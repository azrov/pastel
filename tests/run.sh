#!/bin/sh
# Pastel test suite: unit tests + end-to-end tests of the pastel CLI.
# Usage: sh tests/run.sh   (expects bin/pastel, see build.sh)
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PASTEL="$ROOT/bin/pastel"
FPC="${PASTEL_FPC:-fpc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); echo "FAIL: $1"; }
expect() { if eval "$2"; then ok; else bad "$1"; fi; }

echo "== unit tests"
mkdir -p "$WORK/units"
"$FPC" -Mobjfpc -Sh -vew -FU"$WORK/units" -Fucli/src -Fuframework/src -o"$WORK/toml_test" tests/toml_test.pas >/dev/null
"$WORK/toml_test"
"$FPC" -Mobjfpc -Sh -vew -FU"$WORK/units" -Fucli/src -Fuframework/src -o"$WORK/pform_test" tests/pform_test.pas >/dev/null
"$WORK/pform_test"
"$FPC" -Mobjfpc -Sh -vew -FU"$WORK/units" -Fucli/src -Fuframework/src -o"$WORK/format_test" tests/format_test.pas >/dev/null
"$WORK/format_test"
"$PASTEL" fmt --check cli framework tests >/dev/null || { "$PASTEL" fmt --check cli framework tests; exit 1; }
echo "fmt: Pastel's own code is formatted"

echo "== framework tests"
(cd framework/tests && PASTEL_ARGS_TEST_TOKEN=secret FWTEST_SERVER_PORT=9090 FWTEST_FEATURES="a, b" \
  "$PASTEL" test >"$WORK/framework.log" 2>&1) || { cat "$WORK/framework.log"; exit 1; }
tail -1 "$WORK/framework.log"

echo "== end-to-end tests"
cd "$WORK"

"$PASTEL" new console demo-app >/dev/null
out="$(cd demo-app && "$PASTEL" build 2>&1)"
expect "build reports what it did" 'echo "$out" | grep -q "Compiling demo-app" && echo "$out" | grep -q "Finished debug"'
expect "new creates pastel.toml"   '[ -f demo-app/pastel.toml ]'
expect "new creates main.pas"      '[ -f demo-app/src/main.pas ]'
expect "new creates service unit"  '[ -f demo-app/src/services/greeting.pas ]'
expect "new refuses existing dir"  '! "$PASTEL" new console demo-app 2>/dev/null'
expect "new rejects bad names"     '! "$PASTEL" new console 1bad 2>/dev/null'

cd demo-app
out="$("$PASTEL" run 2>&1)"
expect "run prints greeting"       'echo "$out" | grep -q "Hello, world! This is demo-app"'
out="$("$PASTEL" run -- Ayla 2>&1)"
expect "run passes arguments"      'echo "$out" | grep -q "Hello, Ayla!"'
out="$("$PASTEL" run -- --shout ayşe 2>&1)"
expect "template uses Pastel.Args and Pastel.Text" 'echo "$out" | grep -q "Hello, AYŞE!"'
out="$(./build/*/debug/demo-app --version)"
expect "--version comes from pastel.toml" '[ "$out" = "demo-app 0.1.0" ]'
set +e; out="$(./build/*/debug/demo-app --shuot 2>&1)"; code=$?; set -e
expect "typos get a suggestion and exit code 2" '[ "$code" = 2 ] && echo "$out" | grep -q "did you mean --shout?"'

cd src/services
out="$("$PASTEL" run 2>&1)"
expect "run works from a subfolder" 'echo "$out" | grep -q "Hello, world!"'
cd ../..

"$PASTEL" build --release >/dev/null
expect "release build exists"      '[ -x build/*/release/demo-app ]'

sed -i.bak 's/WriteLn(MakeGreeting(Who));/WriteLn(MakeGreeting(Who)); Halt(7);/' src/main.pas
set +e; "$PASTEL" run >/dev/null 2>&1; code=$?; set -e
expect "run returns the program's exit code" '[ "$code" = 7 ]'

sed -i 's/Halt(7);/Undefined;/' src/main.pas
set +e; out="$("$PASTEL" build 2>&1)"; code=$?; set -e
expect "compile error fails the build"      '[ "$code" = 1 ]'
expect "compile error shows relative path"  'echo "$out" | grep -q "src/main.pas(.*) Error: Identifier not found"'
mv src/main.pas.bak src/main.pas

echo 'name = oops' >> pastel.toml
set +e; out="$("$PASTEL" build 2>&1)"; code=$?; set -e
expect "bad pastel.toml is reported" 'echo "$out" | grep -q "pastel.toml: line"'
sed -i '$d' pastel.toml

expect "unknown target is rejected" '! "$PASTEL" build --target amiga 2>/dev/null'
expect "targets lists rpi alias"    '"$PASTEL" targets | grep -q "rpi "'

# --- files, processes and HTTPS from a program ---
cd "$WORK"
"$PASTEL" new console fetch >/dev/null
cat > fetch/src/main.pas <<'PAS'
program fetch;
{$mode objfpc}{$H+}
uses SysUtils, Pastel.Http, Pastel.Files, Pastel.Process;
begin
  try
    WriteText('out/page.html', HttpGetText(ParamStr(1)));
    WriteLn('saved ', FormatSize(FileSize('out/page.html')));
    WriteLn('echo says ', RunOutput('echo', ['ağaç']));
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'error: ', E.Message);
      Halt(1);
    end;
  end;
end.
PAS
cd fetch && "$PASTEL" build >/dev/null
if command -v openssl >/dev/null; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 \
    -subj /CN=localhost -addext subjectAltName=DNS:localhost >/dev/null 2>&1
  port=$((30000 + $$ % 20000))
  openssl s_server -accept $port -cert cert.pem -key key.pem -www -quiet >/dev/null 2>&1 &
  server=$!
  sleep 1
  set +e; out="$(./build/*/debug/fetch https://localhost:$port/ 2>&1)"; code=$?; set -e
  expect "HTTPS refuses an untrusted certificate" '[ "$code" = 1 ] && echo "$out" | grep -q "certificate of \"localhost\" is not trusted: self-signed certificate"'
  out="$(SSL_CERT_FILE=cert.pem ./build/*/debug/fetch https://localhost:$port/ 2>&1)"
  expect "HTTPS works with a trusted certificate" 'echo "$out" | grep -q "^saved .* KB$"'
  expect "file was written"                       'grep -q "s_server" out/page.html'
  expect "process output is captured"             'echo "$out" | grep -q "^echo says ağaç$"'
  kill $server 2>/dev/null || true
fi
cd "$WORK/demo-app"

# --- libraries and dependencies ---
cd "$WORK"
"$PASTEL" new lib text-tools >/dev/null
expect "new lib creates a unit"          '[ -f text-tools/src/texttools.pas ] && grep -q "^unit TextTools;" text-tools/src/texttools.pas'
out="$(cd text-tools && "$PASTEL" build 2>&1)"
expect "building a library compiles its units" 'echo "$out" | grep -q "1 unit(s) of the library compile"'
out="$(cd text-tools && "$PASTEL" test 2>&1)"
expect "library tests pass"              'echo "$out" | grep -q "2 passed"'
set +e; out="$(cd text-tools && "$PASTEL" run 2>&1)"; code=$?; set -e
expect "a library cannot be run"         '[ "$code" = 2 ] && echo "$out" | grep -q "a library has no program to run"'
"$PASTEL" new lib base-tools >/dev/null
cat > base-tools/src/basetools.pas <<'PAS'
unit BaseTools;
{$mode objfpc}{$H+}
interface
function Twice(const S: string): string;
implementation
function Twice(const S: string): string;
begin
  Result := S + S;
end;
end.
PAS
cat >> text-tools/pastel.toml <<'TOML'

[dependencies]
base-tools = { path = "../base-tools" }
TOML
cat > text-tools/src/texttools.pas <<'PAS'
unit TextTools;
{$mode objfpc}{$H+}
interface
function Repeated(const S: string; Count: Integer): string;
function Shout(const S: string): string;
implementation
uses SysUtils, BaseTools;
function Repeated(const S: string; Count: Integer): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to Count do Result := Result + S;
end;
function Shout(const S: string): string;
begin
  Result := Twice(UpperCase(S));
end;
end.
PAS
"$PASTEL" new console use-tools >/dev/null
cat >> use-tools/pastel.toml <<'TOML'

[dependencies]
text-tools = { path = "../text-tools" }
TOML
cat > use-tools/src/main.pas <<'PAS'
program use_tools;
{$mode objfpc}{$H+}
uses TextTools;
begin
  WriteLn(Shout('hey'), ' ', Repeated('ab', 2));
end.
PAS
out="$(cd use-tools && "$PASTEL" run 2>&1)"
expect "dependencies (and theirs) are found" 'echo "$out" | grep -q "^HEYHEY abab$"'
sed -i 's/Twice(UpperCase(S))/Twice(UpperCase(S)) + "!"/; s/"!"/'"'"'!'"'"'/' text-tools/src/texttools.pas
out="$(cd use-tools && "$PASTEL" run 2>&1)"
expect "changes in a dependency are compiled" 'echo "$out" | grep -q "^HEYHEY! abab$"'
sed -i 's#path = "../text-tools"#path = "../missing"#' use-tools/pastel.toml
set +e; out="$(cd use-tools && "$PASTEL" build 2>&1)"; set -e
expect "a missing dependency is explained" 'echo "$out" | grep -q "dependency \"text-tools\": no pastel.toml in \"../missing\""'

# --- pastel fmt ---
cd "$WORK/demo-app"
cat > src/messy.pas <<'PAS'
unit Messy;
{$mode objfpc}{$H+}
interface
function Sign(X:Integer):Integer;
implementation
function Sign(X:Integer):Integer;
BEGIN
if X>0 then
Result:=1
else if X<0 then
Result:=-1
else
Result:=0;
END;
end.
PAS
set +e; out="$("$PASTEL" fmt --check 2>&1)"; code=$?; set -e
expect "fmt --check finds unformatted files" '[ "$code" = 1 ] && echo "$out" | grep -q "src/messy.pas"'
"$PASTEL" fmt >/dev/null
expect "fmt indents the code"            'grep -q "^    Result := 1$" src/messy.pas && grep -q "^  else if X<0 then$" src/messy.pas'
expect "fmt writes keywords in lower case" 'grep -q "^begin$" src/messy.pas'
expect "fmt --check passes afterwards"   '"$PASTEL" fmt --check >/dev/null'
out="$(printf 'begin\nX:=1;\nend.\n' | "$PASTEL" fmt --stdin)"
expect "fmt --stdin formats for editors" '[ "$out" = "$(printf "begin\n  X := 1;\nend.")" ]'
set +e; out="$(printf 'begin\nif A then begin\nend.\n' | "$PASTEL" fmt --stdin 2>&1)"; code=$?; set -e
expect "fmt refuses broken code"         '[ "$code" = 1 ] && echo "$out" | grep -q "no matching \"end\""'
rm src/messy.pas

# --- pastel run --watch ---
cp src/main.pas main.bak
NO_COLOR=1 "$PASTEL" run --watch -- Watcher > watch.log 2>&1 &
watcher=$!
for i in $(seq 50); do grep -q "Hello, Watcher" watch.log && break; sleep 0.1; done
sed -i 's/WriteLn(MakeGreeting(Who));/WriteLn(MakeGreeting(Who)); WriteLn('"'"'second build'"'"');/' src/main.pas
for i in $(seq 80); do grep -q "second build" watch.log && break; sleep 0.1; done
kill $watcher; wait $watcher 2>/dev/null || true
expect "watch builds and runs again after a save" 'grep -q "src/main.pas changed" watch.log && grep -q "^second build$" watch.log'
expect "watch reports the end of the program"     'grep -q "Exited with code 0" watch.log'
mv main.bak src/main.pas

# --- pastel test ---
out="$("$PASTEL" test 2>&1)"
expect "template tests pass"          'echo "$out" | grep -q "Tests: 2 passed, 2 total"'
cat > tests/library_test.pas <<'EOS'
unit Library_Test;
{$mode objfpc}{$H+}
interface
uses SysUtils, Pastel.Testing;
type
  TLibraryTests = class(TTestSuite)
  private
    FValue: Integer;
    procedure Boom;
  public
    procedure SetUp; override;
  published
    procedure SetUpRunsFirst;
    procedure ComparesText;
    procedure CatchesExpectedErrors;
    procedure SkipsWithReason;
    procedure ReportsUnexpectedErrors;
  end;
implementation
procedure TLibraryTests.SetUp; begin FValue := 41; end;
procedure TLibraryTests.Boom; begin raise EConvertError.Create('bad'); end;
procedure TLibraryTests.SetUpRunsFirst; begin AssertEquals(42, FValue + 1); end;
procedure TLibraryTests.ComparesText;
begin
  AssertEquals('abc', 'abd');
end;
procedure TLibraryTests.CatchesExpectedErrors; begin AssertRaises(EConvertError, @Boom); end;
procedure TLibraryTests.SkipsWithReason; begin Skip('later'); end;
procedure TLibraryTests.ReportsUnexpectedErrors; begin raise EInOutError.Create('disk'); end;
procedure PlainTest; begin AssertTrue(True); end;
initialization
  RegisterTests(TLibraryTests);
  Test('plain procedure test', @PlainTest);
end.
EOS
set +e; out="$("$PASTEL" test 2>&1)"; code=$?; set -e
expect "failing tests give exit code 1"   '[ "$code" = 1 ]'
expect "summary counts every outcome"      'echo "$out" | grep -q "Tests: 2 failed, 5 passed, 1 skipped, 8 total"'
expect "failure shows expected and actual" 'echo "$out" | grep -q "expected \"abc\" but got \"abd\""'
expect "failure shows file and line"       'echo "$out" | grep -q "at tests/library_test.pas:25"'
expect "errors show the exception"         'echo "$out" | grep -q "EInOutError: disk"'
expect "names are readable"                'echo "$out" | grep -q "PASS set up runs first"'
out="$("$PASTEL" test greeting 2>&1)"
expect "filter runs matching tests only"   'echo "$out" | grep -q "Tests: 2 passed, 2 total"'
set +e; out="$("$PASTEL" test --json 2>/dev/null)"; set -e
expect "json output for editors"           'echo "$out" | grep -q "\"name\":\"skips with reason\",\"method\":\"SkipsWithReason\",\"outcome\":\"skipped\""'
rm tests/library_test.pas

# --- logging and settings in a real program ---
cat > src/main.pas <<'EOS'
program demo_app;
{$mode objfpc}{$H+}
uses Pastel.Log, Pastel.Config;
var C: TConfig;
begin
  C := TConfig.Create('demo-app');
  C.SetDefault('server.port', '80');
  C.LoadStandard;
  Log.Debug('debug line');
  Log.Fields(['port', C.GetInt('server.port')]).Info('started');
  Log.Error('boom');
  C.Free;
end.
EOS
printf '[server]\nport = 8080\n' > config.toml
"$PASTEL" build >/dev/null
out="$(./build/*/debug/demo-app 2>&1)"
expect "log text format with fields"     'echo "$out" | grep -q "INFO  started port=8080"'
expect "debug hidden by default"         '! echo "$out" | grep -q "debug line"'
out="$(LOG_LEVEL=debug DEMO_APP_SERVER_PORT=9000 ./build/*/debug/demo-app 2>&1)"
expect "LOG_LEVEL and env settings"      'echo "$out" | grep -q "debug line" && echo "$out" | grep -q "port=9000"'
out="$(JOURNAL_STREAM=8:1 ./build/*/debug/demo-app 2>&1)"
expect "journald format under systemd"   'echo "$out" | grep -q "^<6>started port=8080" && echo "$out" | grep -q "^<3>boom"'
rm config.toml

"$PASTEL" clean >/dev/null
expect "clean removes build folder" '[ ! -d build ]'

cd "$WORK"
expect "build outside a project fails" '! "$PASTEL" build 2>/dev/null'

# --- GUI apps (run headless: no window, drawing in memory) ---
"$PASTEL" new app gui-demo >/dev/null
expect "new app creates Home.pform" '[ -f gui-demo/src/forms/Home.pform ]'
expect "new app creates Home.pas"   '[ -f gui-demo/src/forms/Home.pas ]'
cd gui-demo
"$PASTEL" build >/dev/null
expect "app builds"                 '[ -x build/*/debug/gui-demo ]'
expect "form code is generated"     '[ -f build/*/debug/gen/Home.g.pas ]'
cat > ui.txt <<'EOS'
type NameEdit Ayşe
click SendButton
expect Greeting Hello, Ayşe! Welcome to Pastel.
key tab
click ClearButton
expect NameEdit 
shot shot.png
EOS
set +e; out="$(PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=ui.txt ./build/*/debug/gui-demo 2>&1)"; code=$?; set -e
expect "UI script passes"           '[ "$code" = 0 ]'
expect "screenshot is a PNG"        'head -c 4 shot.png | grep -q PNG'

cp src/forms/Home.pform Home.bak
sed -i 's/object Hint: TLabel/object Hint: TLable/' src/forms/Home.pform
set +e; out="$("$PASTEL" build 2>&1)"; code=$?; set -e
expect "unknown component fails the build" '[ "$code" = 1 ]'
expect "pform error has file and line"     'echo "$out" | grep -q "src/forms/Home.pform(13) Error: unknown component type"'
mv Home.bak src/forms/Home.pform

cp src/forms/Home.pform Home.bak
sed -i 's/OnClick = ClearClick/OnClick = Missing/' src/forms/Home.pform
set +e; out="$("$PASTEL" build 2>&1)"; code=$?; set -e
expect "missing event handler fails the build" '[ "$code" = 1 ]'
expect "missing event handler is explained"    'echo "$out" | grep -q "Home.pform(27) Error: event handler \"Missing\" is not declared in Home.pas"'
mv Home.bak src/forms/Home.pform

# --- window events ---
cp src/forms/Home.pform Home.bak
sed -i 's/^  Height = 340$/  Height = 340\n  OnCloseQuery = AskClose/' src/forms/Home.pform
out="$("$PASTEL" check --json || true)"
expect "close-query handler signature is suggested" 'echo "$out" | grep -q "procedure AskClose(Sender: TObject; var CanClose: Boolean);"'
mv Home.bak src/forms/Home.pform
printf 'close\n' > close.txt
set +e; out="$(PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=close.txt ./build/*/debug/gui-demo 2>&1)"; set -e
expect "close works without a handler" 'echo "$out" | grep -q "^closed"'

# --- editor tools ---
out="$("$PASTEL" check --json)"
expect "check --json reports no problems" '[ "$out" = "[]" ]'
out="$(sed 's/Bold = True/Bold = Yes/' src/forms/Home.pform | "$PASTEL" check src/forms/Home.pform --stdin --json || true)"
expect "check --stdin reads unsaved text" 'echo "$out" | grep -q "\"line\":11,\"severity\":\"error\",\"message\":\"Bold expects True or False\""'
expect "schema lists TButton"             '"$PASTEL" schema | grep -q "\"name\":\"TButton\""'
"$PASTEL" preview src/forms/Home.pform -o preview.png >/dev/null
expect "preview writes a PNG"             'head -c 4 preview.png | grep -q PNG'
"$PASTEL" preview src/forms/Home.pform -o preview.png --layout layout.json --json
expect "preview writes the layout"        'grep -q "\"name\":\"SendButton\",\"class\":\"TButton\",\"parent\":\"Buttons\"" layout.json'
cd "$WORK"

echo "e2e: $pass passed, $fail failed"
[ "$fail" = 0 ]
