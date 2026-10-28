#!/bin/sh
# Builds the pastel command-line tool into bin/pastel.
#   ./build.sh          build
#   ./build.sh test     build and run the tests
set -e
cd "$(dirname "$0")"

FPC="${PASTEL_FPC:-fpc}"

if ! command -v "$FPC" >/dev/null 2>&1; then
  echo "error: the Free Pascal compiler (fpc) was not found" >&2
  echo "hint: on Linux Mint / Ubuntu / Debian: sudo apt install fpc" >&2
  echo "      other systems: https://www.freepascal.org/download.html" >&2
  exit 1
fi

mkdir -p bin build/cli

"$FPC" -Mobjfpc -Sh -O2 -Xs -XX -vewn \
  -FUbuild/cli -Fucli/src -Fuframework/src -FEbin -opastel \
  cli/pastel.pas

echo "Built bin/pastel"

if [ "$1" = "test" ]; then
  sh tests/run.sh
fi
