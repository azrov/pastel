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
