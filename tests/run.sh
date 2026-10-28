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

echo "e2e: $pass passed, $fail failed"
[ "$fail" = 0 ]
