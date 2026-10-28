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
"$FPC" -Mobjfpc -Sh -vew -FU"$WORK/units" -Fucli/src -o"$WORK/toml_test" tests/toml_test.pas >/dev/null
"$WORK/toml_test"
"$FPC" -Mobjfpc -Sh -vew -FU"$WORK/units" -Fucli/src -Fuframework/src -o"$WORK/pform_test" tests/pform_test.pas >/dev/null
"$WORK/pform_test"

echo "== end-to-end tests"
cd "$WORK"

"$PASTEL" new console demo-app >/dev/null
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

# --- editor tools ---
out="$("$PASTEL" check --json)"
expect "check --json reports no problems" '[ "$out" = "[]" ]'
out="$(sed 's/Bold = True/Bold = Yes/' src/forms/Home.pform | "$PASTEL" check src/forms/Home.pform --stdin --json || true)"
expect "check --stdin reads unsaved text" 'echo "$out" | grep -q "\"line\":11,\"severity\":\"error\",\"message\":\"Bold expects True or False\""'
expect "schema lists TButton"             '"$PASTEL" schema | grep -q "\"name\":\"TButton\""'
"$PASTEL" preview src/forms/Home.pform -o preview.png >/dev/null
expect "preview writes a PNG"             'head -c 4 preview.png | grep -q PNG'
cd "$WORK"

echo "e2e: $pass passed, $fail failed"
[ "$fail" = 0 ]
