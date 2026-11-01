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
"$PASTEL" fmt --check cli framework tests examples >/dev/null || { "$PASTEL" fmt --check cli framework tests examples; exit 1; }
echo "fmt: Pastel's own code is formatted"

if [ -f vscode/out/lang/apidoc.js ] && command -v node >/dev/null; then
  echo "== API reference is up to date"
  node vscode/out/lang/apidoc.js framework/src "$WORK/api" >/dev/null
  if ! diff -rq -x stable.txt docs/api "$WORK/api" >/dev/null; then
    echo "docs/api is out of date: run \"npm run apidoc\" in vscode/"; diff -r -x stable.txt docs/api "$WORK/api" | head -20; exit 1
  fi
  if [ -d tools/site/node_modules ]; then
    echo "== the documentation's links"
    node tools/site/build.mjs --check || exit 1
  fi
  echo "== the stable API is still there"
  node vscode/out/lang/apidoc.js --check-stable framework/src docs/api || exit 1
fi
echo "== every feature is documented"
PASTEL="$PASTEL" sh tests/docs-coverage.sh || exit 1
echo "== framework tests"
(cd framework/tests && PASTEL_ARGS_TEST_TOKEN=secret FWTEST_SERVER_PORT=9090 FWTEST_FEATURES="a, b" \
  "$PASTEL" test >"$WORK/framework.log" 2>&1) || { cat "$WORK/framework.log"; exit 1; }
tail -1 "$WORK/framework.log"


echo "== examples"
for ex in dupfinder weather notes-api contacts notepad components salon-core salon-api; do
  rm -rf "$WORK/ex-$ex" && cp -r "examples/$ex" "$WORK/ex-$ex" && rm -rf "$WORK/ex-$ex/build"
  # libraries next to it (path = "../x") are the ones in examples/
  sed -i "s|path = \"\.\./\([a-z-]*\)\"|path = \"$ROOT/examples/\1\"|" "$WORK/ex-$ex/pastel.toml"
  out="$(cd "$WORK/ex-$ex" && "$PASTEL" test 2>&1)" || { echo "$out"; exit 1; }
  echo "$ex: $(echo "$out" | grep "Tests:" | tail -1)"
done
mkdir -p "$WORK/dups/sub" && echo same > "$WORK/dups/a.txt" && echo same > "$WORK/dups/sub/b.txt" && echo other > "$WORK/dups/c.txt"
out="$(cd "$WORK/ex-dupfinder" && "$PASTEL" run -- "$WORK/dups" 2>&1)"
expect "dupfinder finds the copy"        'echo "$out" | grep -q "1 group(s) of duplicates"'
out="$(cd "$WORK/ex-dupfinder" && ./build/*/debug/dupfinder --json "$WORK/dups")"
expect "dupfinder writes JSON"           'echo "$out" | grep -q "\"wasted\" : 5"'
set +e; out="$(cd "$WORK/ex-weather" && "$PASTEL" run 2>&1)"; code=$?; set -e
expect "weather asks for a place"        '[ "$code" = 2 ] && echo "$out" | grep -q "which place?"'
port=$((20000 + $$ % 20000))
(cd "$WORK/ex-notes-api" && "$PASTEL" build >/dev/null && NOTES_API_SERVER_PORT=$port ./build/*/debug/notes-api > "$WORK/notes.log" 2>&1) &
for i in $(seq 100); do grep -q "is running" "$WORK/notes.log" 2>/dev/null && break; sleep 0.1; done
out="$(curl -s "localhost:$port/api/notes" -H 'Content-Type: application/json' -d '{"title": "Alışveriş", "text": "süt"}')"
expect "notes-api creates a note"        'echo "$out" | grep -q "\"id\":1,\"title\":\"Alışveriş\""'
out="$(curl -s -w ' %{http_code}' "localhost:$port/api/notes/1")"
expect "notes-api finds it"              'echo "$out" | grep -q "süt.* 200$"'
out="$(curl -s -w ' %{http_code}' "localhost:$port/api/notes" -d '{}')"
expect "notes-api validates"             'echo "$out" | grep -q "title is required.* 422$"'
out="$(curl -s -w ' %{http_code}' "localhost:$port/api/notes/abc")"
expect "notes-api rejects bad ids"       'echo "$out" | grep -q " 400$"'
expect "notes-api serves the page"       'curl -s "localhost:$port/" | grep -q "<title>Notes</title>"'
expect "notes-api reports health"        'curl -s "localhost:$port/health" | grep -q "\"status\":\"ok\""'
pkill -TERM -x notes-api || true
for i in $(seq 50); do grep -q "notes-api stopped" "$WORK/notes.log" && break; sleep 0.1; done
expect "notes-api stops cleanly"         'grep -q "notes-api stopped" "$WORK/notes.log"'
expect "notes-api keeps the notes"       'grep -q "Alışveriş" "$WORK/ex-notes-api/data/notes.json"'
(cd "$WORK/ex-contacts" && "$PASTEL" build >/dev/null)
rm -f "$WORK/contacts.db"
set +e; out="$(cd "$WORK/ex-contacts" && PASTEL_CHECK_REPAINT=1 PASTEL_LANG=en CONTACTS_DB="$WORK/contacts.db" PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/*/debug/contacts 2>&1)"; code=$?; set -e
expect "contacts adds, finds and deletes" '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
[ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head
expect "contacts keeps them in SQLite"   '[ -s "$WORK/contacts.db" ]'
(cd "$WORK/ex-notepad" && "$PASTEL" build >/dev/null)
rm -rf "$WORK/np" && mkdir "$WORK/np"
set +e; out="$(cd "$WORK/np" && PASTEL_LANG=en PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT="$WORK/ex-notepad/tests/ui.txt" "$WORK"/ex-notepad/build/*/debug/notepad 2>&1)"; code=$?; set -e
expect "notepad saves, opens, asks"      '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
[ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head
expect "notepad wrote the file"          'grep -q "second line" "$WORK/np/hello.txt"'
mkdir -p "$WORK/ex-notepad/assets" && printf 'accent = "#0E9F6E"\nmystery = "1"\n[dark]\naccent = "#34D399"\n' > "$WORK/ex-notepad/assets/theme.toml"
(cd "$WORK/ex-notepad" && "$PASTEL" build >/dev/null)
set +e; out="$(cd "$WORK/np" && printf 'quit\n' > q.txt && PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=q.txt "$WORK"/ex-notepad/build/*/debug/notepad 2>&1)"; code=$?; set -e
expect "assets/theme.toml is read"       '[ "$code" = 0 ] && echo "$out" | grep -q "\"mystery = 1\" is not a theme value"'
# a library of components, used by an app (examples/components, components-demo)
rm -rf "$WORK/ex-components-demo" && cp -r examples/components-demo "$WORK/ex-components-demo" && rm -rf "$WORK/ex-components-demo/build"
sed -i "s|path = \"../components\"|path = \"$WORK/ex-components\"|" "$WORK/ex-components-demo/pastel.toml"
(cd "$WORK/ex-components-demo" && "$PASTEL" build >/dev/null 2>&1)
rm -rf "$WORK/cfg"
for t in ui ui-memory; do
  set +e; out="$(cd "$WORK/ex-components-demo" && XDG_CONFIG_HOME="$WORK/cfg" PASTEL_LANG=en PASTEL_CHECK_REPAINT=1 PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/$t.txt ./build/*/debug/components-demo 2>&1)"; code=$?; set -e
  expect "components-demo: $t.txt"        '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
  [ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head
done
expect "a library's controls are in the toolbox" '(cd "$WORK/ex-components-demo" && "$PASTEL" schema 2>/dev/null) | grep -q "\"name\":\"TStarRating\",\"container\":false,\"form\":false,\"nonvisual\":false,\"project\":true"'
expect "and its non-visual components"     '(cd "$WORK/ex-components-demo" && "$PASTEL" schema 2>/dev/null) | grep -q "\"name\":\"TFormMemory\",\"container\":false,\"form\":false,\"nonvisual\":true,\"project\":true"'
# the salon system: a desktop app and its server, sharing salon-core
for p in salon-desk salon-api; do
  rm -rf "$WORK/ex-$p" && cp -r "examples/$p" "$WORK/ex-$p" && rm -rf "$WORK/ex-$p/build" "$WORK/ex-$p/data"
  sed -i "s|path = \"../salon-core\"|path = \"$ROOT/examples/salon-core\"|; s|path = \"../components\"|path = \"$ROOT/examples/components\"|" "$WORK/ex-$p/pastel.toml"
  (cd "$WORK/ex-$p" && "$PASTEL" build >/dev/null 2>&1)
done
rm -rf "$WORK/salon" && mkdir -p "$WORK/salon"
set +e; out="$(cd "$WORK/ex-salon-desk" && SALON_DB="$WORK/salon/ui.db" XDG_CONFIG_HOME="$WORK/salon/cfg0" PASTEL_LANG=en PASTEL_CHECK_REPAINT=1 PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/*/debug/salon-desk 2>&1)"; code=$?; set -e
expect "salon: customers, appointments, invoices" '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
[ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head
sport=$((20000 + ($$ + 77) % 20000))
(cd "$WORK/ex-salon-api" && SALON_API_SERVER_PORT=$sport SALON_API_DATABASE_URL="sqlite:$WORK/salon/server.db" ./build/*/debug/salon-api > "$WORK/salon/api.log" 2>&1) &
for i in $(seq 100); do grep -q "is running" "$WORK/salon/api.log" 2>/dev/null && break; sleep 0.1; done
for n in 1 2; do
  f=sync.txt; [ $n = 2 ] && f=sync-2.txt
  sed "s|SERVER|http://127.0.0.1:$sport|" "$WORK/ex-salon-desk/tests/$f" > "$WORK/salon/$f"
  set +e; out="$(cd "$WORK/ex-salon-desk" && SALON_DB="$WORK/salon/desk$n.db" XDG_CONFIG_HOME="$WORK/salon/cfg$n" PASTEL_LANG=en PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT="$WORK/salon/$f" ./build/*/debug/salon-desk 2>&1)"; code=$?; set -e
  expect "salon: computer $n syncs with the server" '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
  [ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head
done
expect "salon: the server has the customer"  'curl -s "localhost:$sport/api/customers?q=zeynep" | grep -q "\"name\":\"Zeynep Kaya\""'
pkill -TERM -x salon-api || true
echo "== end-to-end tests"
# --- desktop packages ---
(cd "$WORK/ex-notepad" && "$PASTEL" package deb >/dev/null)
expect "a desktop .deb has a menu entry"  'dpkg-deb --fsys-tarfile "$WORK"/ex-notepad/dist/notepad_1.0.0_amd64.deb | tar -xO ./usr/share/applications/notepad.desktop | grep -q "^Name=Notepad"'
expect "and an icon"                      'dpkg-deb -c "$WORK"/ex-notepad/dist/notepad_1.0.0_amd64.deb | grep -q "hicolor/256x256/apps/notepad.png"'
expect "and needs SDL2"                   'dpkg-deb -f "$WORK"/ex-notepad/dist/notepad_1.0.0_amd64.deb Depends | grep -q libsdl2'
if command -v makensis >/dev/null && "$PASTEL" doctor 2>/dev/null | grep -q "✓ windows "; then
  (cd "$WORK/ex-notepad" && "$PASTEL" package installer --target windows >/dev/null 2>&1)
  expect "a Windows installer"            '[ -s "$WORK"/ex-notepad/dist/notepad-1.0.0-windows-setup.exe ]'
  expect "the app for Windows was built"  '[ -s "$WORK"/ex-notepad/build/windows/release/notepad.exe ]'
fi
# --- translations ---
rm -rf "$WORK/tr-demo" && cp -r "$ROOT/examples/notepad" "$WORK/tr-demo" && rm -rf "$WORK/tr-demo/build" "$WORK/tr-demo/assets/lang"
cd "$WORK/tr-demo"
out="$("$PASTEL" lang)"
expect "lang without languages says how"  'echo "$out" | grep -q "pastel lang add tr"'
"$PASTEL" lang add tr >/dev/null
expect "lang add collects the .pform texts" 'grep -q "\"Word wrap\": \"\"" assets/lang/tr.json && grep -q "\"Start typing...\"" assets/lang/tr.json'
sed -i 's/"File": ""/"File": "Dosya"/; s/"Word wrap": ""/"Word wrap": "Satır kaydır"/' assets/lang/tr.json
out="$("$PASTEL" lang)"
expect "lang counts what is missing"      'echo "$out" | grep -q "tr.json: 25 of 27 text(s) not translated"'
expect "lang keeps translations"          'grep -q "Satır kaydır" assets/lang/tr.json'
"$PASTEL" build >/dev/null
printf 'expect FileMenu.Caption Dosya\nexpect WrapItem.Caption Satır kaydır\ntype Editor x\nkey ctrl+n\nexpect NoButton Hayır\nclick NoButton\nquit\n' > tr.txt
set +e; out="$(PASTEL_LANG=tr PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tr.txt ./build/*/debug/notepad 2>&1)"; code=$?; set -e
expect "the app speaks Turkish"           '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
[ "$code" = 0 ] || echo "$out" | grep -v "^ok"
cd "$WORK"
# --- Windows program icon (when this computer can build for Windows) ---
if "$PASTEL" doctor 2>/dev/null | grep -q "✓ windows "; then
  rm -rf "$WORK/winicon" && (cd "$WORK" && "$PASTEL" new console winicon >/dev/null)
  mkdir -p "$WORK/winicon/assets" && cp "$ROOT/tests/apps/controls/assets/logo.png" "$WORK/winicon/assets/icon.png"
  (cd "$WORK/winicon" && "$PASTEL" build -t windows >/dev/null)
  expect "the .exe carries the icon in 4 sizes" '[ "$(LC_ALL=C grep -a -o IHDR "$WORK"/winicon/build/windows/debug/winicon.exe | wc -l)" -ge 4 ]'
fi
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

# --- packages: a registry, git repositories, versions, pastel.lock ---
PK="$WORK/pk" && rm -rf "$PK" && mkdir -p "$PK" && cd "$PK"
export PASTEL_CACHE="$PK/cache" PASTEL_REGISTRY="$PK/registry"
mkdir extras && cd extras && git init -q && git config user.email t@example.com && git config user.name t
"$PASTEL" new lib serial >/dev/null && "$PASTEL" new lib greet >/dev/null && rm -rf serial/tests greet/tests
printf 'unit Serial;\n{$mode objfpc}{$H+}\ninterface\nconst\n  SerialVersion = %s;\nimplementation\nend.\n' "'0.1.0'" > serial/src/serial.pas
printf 'unit Greet;\n{$mode objfpc}{$H+}\ninterface\nfunction Hello: string;\nimplementation\nuses\n  Serial;\nfunction Hello: string;\nbegin\n  Result := %s + SerialVersion;\nend;\nend.\n' "'hello '" > greet/src/greet.pas
printf '\n[dependencies]\nserial = "^0.1"\n' >> greet/pastel.toml
git add -A && git commit -qm one && git tag v0.1.0
sed -i "s/'0.1.0'/'0.1.5'/" serial/src/serial.pas && git commit -qam two && git tag v0.1.5
sed -i "s/'0.1.5'/'0.2.0'/" serial/src/serial.pas && sed -i 's/serial = "^0.1"/serial = "^0.2"/' greet/pastel.toml && git commit -qam three && git tag v0.2.0
mkdir -p "$PK/registry" && printf '[serial]\ngit = "%s"\npath = "serial"\ndescription = "Serial ports"\n\n[greet]\ngit = "%s"\npath = "greet"\ndescription = "Says hello"\n' "$PK/extras" "$PK/extras" > "$PK/registry/packages.toml"
cd "$PK" && "$PASTEL" new console use-pk >/dev/null && cd use-pk
printf 'program usepk;\n{$mode objfpc}{$H+}\nuses\n  Greet;\nbegin\n  WriteLn(Hello);\nend.\n' > src/main.pas
out="$("$PASTEL" search serial 2>&1)"
expect "search finds a package"            'echo "$out" | grep -q "^serial .*Serial ports"'
out="$("$PASTEL" add greet@^0.1 2>&1)"
expect "add writes pastel.toml"            'grep -q "^greet = \"^0.1\"$" pastel.toml'
expect "and pastel.lock, with theirs"       'grep -q "^\[package.serial\]" pastel.lock && grep -q "^version = \"0.1.5\"" pastel.lock'
out="$("$PASTEL" run 2>&1)"
expect "a package is built"                'echo "$out" | grep -q "^hello 0.1.5$"'
out="$("$PASTEL" deps 2>&1)"
expect "deps shows the tree"               'echo "$out" | grep -q "^  serial 0.1.5"'
set +e; out="$("$PASTEL" add serial@^0.2 2>&1)"; code=$?; set -e
expect "versions that cannot both be used"  '[ "$code" = 1 ] && echo "$out" | grep -q "a library needs ^0.1" && ! grep -q "^serial" pastel.toml && grep -q "0.1.5" pastel.lock'
sed -i 's/^greet = .*/greet = "^0.2"/' pastel.toml
out="$("$PASTEL" run 2>&1)"
expect "a new version is fetched and built" 'echo "$out" | grep -q "^hello 0.2.0$" && grep -q "^version = \"0.2.0\"" pastel.lock'
rm -rf "$PK/cache/src"
out="$(PASTEL_REGISTRY=/nowhere "$PASTEL" run 2>&1)"
expect "pastel.lock builds without the registry" 'echo "$out" | grep -q "^hello 0.2.0$"'
set +e; out="$("$PASTEL" add serial@^9 2>&1)"; code=$?; set -e
expect "no version matches is explained"   '[ "$code" = 1 ] && echo "$out" | grep -q "no version matches \"^9\" (there are: 0.1.0, 0.1.5, 0.2.0)"'
out="$("$PASTEL" remove greet 2>&1)"
expect "remove drops it and its packages"  '! grep -q "^greet" pastel.toml && [ ! -f pastel.lock ]'
out="$("$PASTEL" add hi --git "$PK/extras" --path greet --branch master 2>&1)"
expect "a package from a git branch"       'grep -q "^hi = { git = \".*extras\", path = \"greet\", branch = \"master\" }$" pastel.toml'
unset PASTEL_CACHE PASTEL_REGISTRY

# --- the debugger shows values readably (vscode/gdb/pastel.py) ---
if command -v gdb >/dev/null 2>&1; then
  cd "$WORK" && rm -rf dbg && "$PASTEL" new console dbg >/dev/null && cd dbg
  cat > src/main.pas <<'PAS'
program dbg;
{$mode objfpc}{$H+}
uses
  Classes, SysUtils, fpjson, Pastel.Json;
type
  TCustomer = class
  private
    FName: string;
  public
    Tags: TStringList;
    property Name: string read FName write FName;
  end;
var
  Base: TStrings;
  C: TCustomer;
  J: TJSONData;
begin
  Base := TStringList.Create;
  Base.Add('şeftali');
  C := TCustomer.Create;
  C.Name := 'Ayşe';
  J := GetJSON('{"items": [1, 2.5, true, null, "x"]}');
  WriteLn(Base.Count, C.Name, J.Count);
end.
PAS
  "$PASTEL" build >/dev/null 2>&1
  printf 'source %s/vscode/gdb/pastel.py\nbreak main.pas:24\nrun\nprint Base\nprint C\nprint J\n' "$ROOT" > g.txt
  out="$(gdb -q -batch -x g.txt build/*/debug/dbg 2>&1)"
  expect "gdb: a string list with its items"  'echo "$out" | grep -q "= TStringList (1) = {.şeftali.}"'
  expect "gdb: an object as its class, properties" 'echo "$out" | grep -q "= TCustomer = {Tags = nil, Name = .Ayşe.}"'
  expect "gdb: JSON as JSON"                  'echo "$out" | grep -q "= TJSONObject {\"items\": \[1, 2.5, true, null, \"x\"\]}"'
fi

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


# --- profiles and pastel package ---
cd "$WORK/demo-app"
cp pastel.toml toml.bak; cp src/main.pas main.bak
cat >> pastel.toml <<'TOML'

[profile.release]
defines = ["SHIPPED"]

[package]
include = ["notes"]
TOML
mkdir -p notes && echo "hello" > notes/first.txt
sed -i 's/WriteLn(MakeGreeting(Who));/WriteLn(MakeGreeting(Who)); {$IFDEF SHIPPED}WriteLn('"'"'release only'"'"');{$ENDIF}/' src/main.pas
out="$("$PASTEL" run 2>&1)"
expect "profile defines stay out of debug builds" '! echo "$out" | grep -q "release only"'
out="$("$PASTEL" package 2>&1)"
expect "package reports the archive"        'echo "$out" | grep -q "Packaged dist/demo-app-0.1.0-linux.tar.gz"'
list="$(tar -tvzf dist/demo-app-0.1.0-linux.tar.gz)"
expect "package holds the program, runnable" 'echo "$list" | grep -q "rwxr-xr-x .* demo-app-0.1.0-linux/demo-app$"'
expect "package holds README and included files" 'echo "$list" | grep -q "demo-app-0.1.0-linux/README.md" && echo "$list" | grep -q "demo-app-0.1.0-linux/notes/first.txt"'
expect "package has a correct checksum"     '(cd dist && sha256sum -c demo-app-0.1.0-linux.tar.gz.sha256 >/dev/null)'
mkdir -p unpacked && tar -xzf dist/demo-app-0.1.0-linux.tar.gz -C unpacked
expect "packaged program is a release build with its profile" './unpacked/demo-app-0.1.0-linux/demo-app | grep -q "release only"'
sed -i 's/include = \["notes"\]/include = ["missing.txt"]/' pastel.toml
set +e; out="$("$PASTEL" package 2>&1)"; code=$?; set -e
expect "a missing package file is explained" '[ "$code" = 1 ] && echo "$out" | grep -q "include: \"missing.txt\" not found"'
echo '[profile.fast]' >> pastel.toml
set +e; out="$("$PASTEL" build 2>&1)"; set -e
expect "an unknown profile is explained"    'echo "$out" | grep -q "unknown profile \[profile.fast\]"'
mv toml.bak pastel.toml; mv main.bak src/main.pas; rm -rf notes unpacked dist

# --- services ---
cd "$WORK"
"$PASTEL" new service file-watch >/dev/null
expect "new service writes a systemd unit" 'grep -q "^Type=notify$" file-watch/deploy/file-watch.service && grep -q "FILE_WATCH_CHECK_INTERVAL" file-watch/deploy/file-watch.service'
out="$(cd file-watch && "$PASTEL" test 2>&1)"
expect "service template tests pass"     'echo "$out" | grep -q "4 passed"'
cd file-watch && "$PASTEL" build >/dev/null
python3 - "$WORK/notify.sock" "$WORK/notify.log" <<'PY' &
import socket, sys, os
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(sys.argv[1])
s.settimeout(20)
with open(sys.argv[2], 'w', buffering=1) as out:
    try:
        while True:
            out.write(s.recv(4096).decode().replace('\n', ' ') + '\n')
    except Exception:
        pass
PY
listener=$!
for i in $(seq 50); do [ -S "$WORK/notify.sock" ] && break; sleep 0.1; done
NOTIFY_SOCKET="$WORK/notify.sock" ./build/*/debug/file-watch > service.log 2>&1 &
svc=$!
for i in $(seq 50); do grep -q "is running" service.log && break; sleep 0.1; done
echo hello > inbox/first.txt
for i in $(seq 50); do grep -q "new file file=first.txt" service.log && break; sleep 0.1; done
kill -HUP $svc
for i in $(seq 50); do grep -q "settings reloaded" service.log && break; sleep 0.1; done
kill -TERM $svc; set +e; wait $svc; code=$?; set -e
kill $listener 2>/dev/null || true
expect "service sees new files"          'grep -q "new file file=first.txt size=\"6 B\"" service.log'
expect "SIGHUP reloads the settings"     'grep -q "settings reloaded" service.log'
expect "SIGTERM stops it cleanly"        '[ "$code" = 0 ] && grep -q "file-watch stopped" service.log'
expect "systemd hears ready, reload, stop" 'grep -q "^READY=1" "$WORK/notify.log" && grep -q "^RELOADING=1 MONOTONIC_USEC=" "$WORK/notify.log" && grep -q "^STOPPING=1" "$WORK/notify.log"'
sed -i 's/interval = 2 /interval = "often" /' config.toml
set +e; out="$(./build/*/debug/file-watch 2>&1)"; code=$?; set -e
expect "bad settings stop the start with a reason" '[ "$code" = 1 ] && echo "$out" | grep -q "check.interval"'

# --- web API with a database, migrations ---
cd "$WORK"
"$PASTEL" new api todo-api >/dev/null
# --- compiler errors for unsaved text ---
(cd todo-api
 sed 's/FTasks.Add(Title, Done)/FTasks.Add(Titl, Done)/' src/controllers/taskscontroller.pas > ../edited.pas
 cp src/controllers/taskscontroller.pas ../before.pas)
out="$(cd todo-api && "$PASTEL" check src/controllers/taskscontroller.pas --stdin --json < ../edited.pas)"
expect "check finds an error in unsaved text"  'echo "$out" | grep -q "\"severity\":\"error\"" && echo "$out" | grep -qF "Identifier not found" && echo "$out" | grep -qF "Titl"'
expect "check names the real file"       'echo "$out" | grep -q "todo-api/src/controllers/taskscontroller.pas"'
expect "check leaves the file alone"     'cmp -s before.pas todo-api/src/controllers/taskscontroller.pas'
out="$(cd todo-api && "$PASTEL" check src/controllers/taskscontroller.pas --stdin --json < src/controllers/taskscontroller.pas)"
expect "check of good code is empty"     '[ "$out" = "[]" ]'
out="$(cd todo-api && sed 's/^  Api := /  Apix := /' src/main.pas | "$PASTEL" check src/main.pas --stdin --json)"
expect "check works on the main program" 'echo "$out" | grep -qF "Identifier not found" && echo "$out" | grep -qF "Apix"'
set +e; out="$("$PASTEL" new service inbox 2>&1)"; code=$?; set -e
expect "a name that clashes with a unit is refused" '[ "$code" != 0 ] && echo "$out" | grep -q "also the name of a unit" && [ ! -d inbox ]'
"$PASTEL" new api tasks >/dev/null
expect "an api called tasks builds"      '(cd tasks && "$PASTEL" build >/dev/null)'
cd todo-api
out="$("$PASTEL" test 2>&1)"
expect "api template tests pass"         'echo "$out" | grep -q "5 passed"'
out="$(NO_COLOR=1 "$PASTEL" migrate status)"
expect "migrate status lists pending"    'echo "$out" | grep -q "pending  001_create_tasks"'
out="$(NO_COLOR=1 "$PASTEL" migrate)"
expect "migrate applies"                 'echo "$out" | grep -q "Migrated 001_create_tasks"'
out="$(NO_COLOR=1 "$PASTEL" migrate)"
expect "migrate twice is up to date"     'echo "$out" | grep -q "up to date"'
out="$(NO_COLOR=1 "$PASTEL" migrate new "Add priority")"
expect "migrate new numbers the file"    '[ -f database/migrations/002_add_priority.sql ]'
echo "alter table tasks add column priority integer not null default 0;" >> database/migrations/002_add_priority.sql
out="$(NO_COLOR=1 "$PASTEL" migrate --database sqlite:other.db)"
expect "migrate --database picks the db" 'echo "$out" | grep -q "2 migration(s) on sqlite:other.db"'
echo "broken sql;" > database/migrations/003_broken.sql
set +e; out="$(NO_COLOR=1 "$PASTEL" migrate 2>&1)"; code=$?; set -e
expect "a broken migration fails clearly" '[ "$code" = 1 ] && echo "$out" | grep -q "003_broken.sql"'
rm database/migrations/003_broken.sql
"$PASTEL" build >/dev/null
port=$((20000 + $$ % 20000))
TODO_API_SERVER_PORT=$port ./build/*/debug/todo-api > api.log 2>&1 &
api=$!
for i in $(seq 50); do grep -q "is running" api.log && break; sleep 0.1; done
out="$(curl -s localhost:$port/api/tasks -H 'Content-Type: application/json' -d '{"title": "Süt al"}')"
expect "api creates a task"              'echo "$out" | grep -q "\"title\":\"Süt al\",\"done\":false"'
expect "api lists tasks"                 'curl -s localhost:$port/api/tasks | grep -q "Süt al"'
expect "api answers 422 for bad data"    '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:$port/api/tasks -d "{}")" = 422 ]'
kill $api; wait $api || true

# --- .deb and docker ---
NO_COLOR=1 "$PASTEL" package deb >/dev/null
expect "package deb writes a .deb"       '[ -f dist/todo-api_0.1.0_amd64.deb ] && [ -f dist/todo-api_0.1.0_amd64.deb.sha256 ]'
if command -v dpkg-deb >/dev/null; then
  expect "the .deb is valid"             'dpkg-deb --info dist/todo-api_0.1.0_amd64.deb | grep -q "Depends: libc6, libsqlite3-0"'
  out="$(dpkg-deb --contents dist/todo-api_0.1.0_amd64.deb)"
  expect "the .deb has program, unit, config" 'echo "$out" | grep -q "^-rwxr-xr-x root/root .* ./opt/todo-api/todo-api$" && echo "$out" | grep -q "./usr/lib/systemd/system/todo-api.service$" && echo "$out" | grep -q "./etc/todo-api/config.toml$" && echo "$out" | grep -q "./opt/todo-api/database/migrations/001_create_tasks.sql$"'
  expect "the config is a conffile"      'dpkg-deb --ctrl-tarfile dist/todo-api_0.1.0_amd64.deb | tar -xO ./conffiles | grep -q "^/etc/todo-api/config.toml$"'
fi
NO_COLOR=1 "$PASTEL" package docker --no-build >/dev/null
expect "package docker writes a Dockerfile" 'grep -q "^ENTRYPOINT \[\"/opt/todo-api/todo-api\"\]$" dist/docker-linux/Dockerfile && grep -q "libsqlite3-0" dist/docker-linux/Dockerfile && [ -x dist/docker-linux/app/todo-api ]'
expect "the image does not run as root"  'grep -q "^USER app$" dist/docker-linux/Dockerfile'
cd "$WORK"
"$PASTEL" new console hello-deb >/dev/null
cd hello-deb
NO_COLOR=1 "$PASTEL" package deb >/dev/null
if command -v dpkg-deb >/dev/null; then
  expect "a console .deb links /usr/bin"  'dpkg-deb --contents dist/hello-deb_0.1.0_amd64.deb | grep -q "./usr/bin/hello-deb -> /opt/hello-deb/hello-deb"'
fi
set +e; out="$(NO_COLOR=1 "$PASTEL" package deb --target windows 2>&1)"; code=$?; set -e
expect "a .deb for windows is refused"   '[ "$code" != 0 ] && echo "$out" | grep -q "not a Linux target"'
cd "$WORK/todo-api"
cd "$WORK/demo-app"

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
sed -i 's/object HintLabel: TLabel/object HintLabel: TLable/' src/forms/Home.pform
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

# --- all the controls, menus and dialogs (tests/apps/controls) ---
cd "$WORK"
"$PASTEL" new app controls-demo >/dev/null
cp -r "$ROOT/tests/apps/controls/src" "$ROOT/tests/apps/controls/assets" controls-demo/
cd controls-demo
"$PASTEL" build >/dev/null
set +e; out="$(PASTEL_CHECK_REPAINT=1 PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT="$ROOT/tests/apps/controls/ui.txt" ./build/*/debug/controls-demo 2>&1)"; code=$?; set -e
expect "controls, menus and dialogs work"  '[ "$code" = 0 ] && ! echo "$out" | grep -q FAIL'
expect "only what changed is repainted"  'echo "$out" | grep -qE "partial repaints: [1-9][0-9]* checked, 0 wrong"'
[ "$code" = 0 ] || echo "$out" | grep -v "^ok" | head -20
expect "the dialogs answered"           'echo "$out" | grep -q "ok: Status = \"new my note\"" && echo "$out" | grep -q "ok: MessageText"'
"$PASTEL" build --release >/dev/null
printf 'expect Logo.LoadError \nexpect Logo.Fit ifContain\n' > "$WORK/asset.txt"
set +e; out="$(cd "$WORK" && PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT="$WORK/asset.txt" "$WORK/controls-demo/build/linux/release/controls-demo" 2>&1)"; code=$?; set -e
expect "a release build carries its assets"  '[ "$code" = 0 ] && echo "$out" | grep -q "ok: Logo.LoadError"'
expect "assets are compiled in"         'grep -q "RegisterAsset(.logo.png., @Asset0" build/linux/release/gen/appassets.pas'
cd "$WORK/gui-demo"

# --- running a library; rows that do not fit ---
set +e; out="$(cd "$ROOT/examples/salon-core" && "$PASTEL" run 2>&1)"; code=$?; set -e
expect "run in a library names its programs" '[ "$code" = 2 ] && echo "$out" | grep -q "these programs use it: ../salon-api, ../salon-desk"'
cd "$WORK" && rm -rf narrow && "$PASTEL" new app narrow >/dev/null && cd narrow
sed -i 's/^  Width = 460$/  Width = 200/' src/forms/Home.pform
out="$("$PASTEL" check 2>&1)"
expect "check warns about a row that is cut off" 'echo "$out" | grep -q "Warning: Buttons: its controls need"'
out="$("$PASTEL" build 2>&1)"
expect "but it still builds"               'echo "$out" | grep -q "Output"'

# --- pastel upgrade ---
cd "$WORK"
rm -rf old-app && "$PASTEL" new app old-app >/dev/null && cd old-app
expect "new projects record the version"  'grep -q "^pastel = \"$("$PASTEL" version | sed "s/pastel \([0-9]*\.[0-9]*\).*/\1/")\"" pastel.toml'
expect "and are up to date"               '"$PASTEL" upgrade --check >/dev/null'
sed -i '/^pastel = /d; /^title = /d' pastel.toml
sed -i 's/object HintLabel: TLabel/object Hint: TLabel/' src/forms/Home.pform
printf '*.o\n' > .gitignore
out="$("$PASTEL" build 2>&1 || true)"
expect "a build hints at upgrade"         'echo "$out" | grep -q "pastel upgrade"'
set +e; out="$("$PASTEL" upgrade --check 2>&1)"; code=$?; set -e
expect "upgrade --check lists the changes" '[ "$code" = 1 ] && echo "$out" | grep -q "the control \"Hint\" is now \"HintLabel\""'
"$PASTEL" upgrade >/dev/null
expect "upgrade renames the control"      'grep -q "object HintLabel: TLabel" src/forms/Home.pform'
expect "upgrade sets the version"         'grep -q "^pastel = " pastel.toml && grep -q "^title = \"Old App\"" pastel.toml'
expect "upgrade fixes .gitignore"         'grep -q "^build/" .gitignore'
out="$("$PASTEL" build 2>&1)"
expect "the upgraded project builds"      'echo "$out" | grep -q "Output" && ! echo "$out" | grep -q "pastel upgrade"'
printf '[biuld]\nmain = "x"\n' >> pastel.toml
out="$("$PASTEL" build 2>&1)"
expect "a typo in pastel.toml is reported" 'echo "$out" | grep -q "unknown setting \"biuld.main\""'
sed -i '/^\[biuld\]/,$d' pastel.toml
sed -i 's/^pastel = .*/pastel = "9.0"/' pastel.toml
out="$("$PASTEL" build 2>&1)"
expect "a project for a newer Pastel warns" 'echo "$out" | grep -q "made for Pastel 9.0"'

# --- the project's own controls (src/controls/) ---
cd "$WORK"
rm -rf own-controls && "$PASTEL" new app own-controls >/dev/null && cd own-controls
"$PASTEL" new control Badge >/dev/null
expect "new control writes a unit"        'grep -q "RegisterControl(TBadge)" src/controls/badge.pas'
sed -i "s/^  object Card: TCard$/  object NewBadge: TBadge\n    Text = 'New'\n    OnClick = BadgeClick\n  end\n  object Card: TCard/" src/forms/Home.pform
sed -i 's/^    procedure SendClick(Sender: TObject);/    procedure SendClick(Sender: TObject);\n    procedure BadgeClick(Sender: TObject);/' src/forms/Home.pas
printf '\nprocedure THomeForm.BadgeClick(Sender: TObject);\nbegin\n  Greeting.Text := NewBadge.Text + '"'"' clicked'"'"';\nend;\n' > extra.inc
sed -i '/^implementation$/r extra.inc' src/forms/Home.pas
"$PASTEL" build >/dev/null 2>&1
expect "an app uses its own control"      '[ -x build/linux/debug/own-controls ]'
printf 'click NewBadge\nexpect Greeting New clicked\nquit\n' > ui.txt
set +e; out="$(PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=ui.txt ./build/linux/debug/own-controls 2>&1)"; set -e
expect "and it works"                     'echo "$out" | grep -q "ok: Greeting = \"New clicked\""'
expect "schema lists it for the designer" '"$PASTEL" schema 2>/dev/null | grep -q "\"name\":\"TBadge\",\"container\":false,\"form\":false,\"nonvisual\":false,\"project\":true"'
out="$(sed "s/Text = 'New'/Txt = 'New'/" src/forms/Home.pform | "$PASTEL" check src/forms/Home.pform --stdin --json 2>/dev/null || true)"
expect "check knows its properties"       'echo "$out" | grep -q "TBadge has no property"'
"$PASTEL" preview src/forms/Home.pform -o badge.png >/dev/null 2>&1
expect "preview draws it"                 'head -c 4 badge.png | grep -q PNG'
cd "$WORK/gui-demo"

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
