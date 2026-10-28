#!/bin/sh
# Builds the pastel command-line tool into bin/pastel.
#   ./build.sh          build
#   ./build.sh test     build and run the tests
set -e
cd "$(dirname "$0")"

FPC="${PASTEL_FPC:-fpc}"
mkdir -p bin build/cli

"$FPC" -Mobjfpc -Sh -O2 -Xs -XX -vewn \
  -FUbuild/cli -Fucli/src -FEbin -opastel \
  cli/pastel.pas

echo "Built bin/pastel"

if [ "$1" = "test" ]; then
  sh tests/run.sh
fi
