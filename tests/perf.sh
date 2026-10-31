#!/bin/sh
# Pastel's performance checks: start-up time, memory, requests per second and
# drawing speed. Prints a table (Markdown) and fails when a number is far off
# the limits below, which are generous: they catch mistakes, not small changes.
#   sh tests/perf.sh            (after ./build.sh)
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PASTEL="$ROOT/bin/pastel"
WORK="$(mktemp -d)"
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$WORK"' EXIT
SERVER=""
fails=0

ms() { date +%s%N | cut -b1-13; }
rss_kb() { awk '/VmRSS/ { print $2 }' "/proc/$1/status"; }
check() { # name value op limit unit
  bad=0
  if [ "$3" = "<" ]; then [ "$2" -lt "$4" ] || bad=1; else [ "$2" -gt "$4" ] || bad=1; fi
  if [ "$bad" = 1 ]; then
    echo "| $1 | **$2 $5** | $3 $4 $5 | **not met** |"; fails=$((fails + 1))
  else
    echo "| $1 | $2 $5 | $3 $4 $5 | ok |"
  fi
}

# --- build what is measured (release builds) ---
(cd tests/perf && "$PASTEL" build --release >/dev/null)
PERF="$ROOT/tests/perf/build/linux/release/pastel-perf"
cd "$WORK"
"$PASTEL" new console hello >/dev/null
(cd hello && "$PASTEL" build --release >/dev/null)
cp -r "$ROOT/examples/notes-api" api && rm -rf api/build api/data
(cd api && "$PASTEL" build --release >/dev/null)
cp -r "$ROOT/examples/notepad" pad && rm -rf pad/build
(cd pad && "$PASTEL" build --release >/dev/null)

echo "| What | Measured | Limit | |"
echo "|---|---|---|---|"

# --- start-up ---
t0=$(ms); for i in $(seq 20); do ./hello/build/linux/release/hello >/dev/null; done; t1=$(ms)
check "Console program: start and exit" $(( (t1 - t0) / 20 )) "<" 100 ms
printf 'quit\n' > quit.txt
t0=$(ms); for i in $(seq 5); do PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=quit.txt ./pad/build/linux/release/notepad >/dev/null; done; t1=$(ms)
check "Desktop app: start, first frame, exit" $(( (t1 - t0) / 5 )) "<" 500 ms
check "Console program size" $(( $(stat -c %s hello/build/linux/release/hello) / 1024 )) "<" 3072 KB
check "Desktop app size" $(( $(stat -c %s pad/build/linux/release/notepad) / 1024 )) "<" 8192 KB

# --- a desktop app's memory ---
printf 'type Editor Merhaba\nwait 800\nquit\n' > idle.txt
PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=idle.txt ./pad/build/linux/release/notepad >/dev/null &
PAD=$!; sleep 0.5
check "Desktop app memory" $(( $(rss_kb $PAD) / 1024 )) "<" 80 MB
wait $PAD

# --- the web service ---
PORT=$((20000 + $$ % 20000))
(cd api && NOTES_API_SERVER_PORT=$PORT NOTES_API_LOG_LEVEL=warn ./build/linux/release/notes-api >/dev/null 2>&1) &
SERVER=$!
for i in $(seq 50); do curl -s "localhost:$PORT/health" >/dev/null 2>&1 && break; sleep 0.1; done
PID=$(pgrep -n -x notes-api)
check "Web service memory, idle" $(( $(rss_kb $PID) / 1024 )) "<" 40 MB
out="$("$PERF" load $PORT 3 8)"
rps=$(echo "$out" | awk '/requests_per_second/ { print $2 }')
failed=$(echo "$out" | awk '/failed/ { print $2 }')
check "Requests per second (GET /health, new connection each)" "$rps" ">" 1000 ""
check "Failed requests under load" "$failed" "<" 1 ""
check "Web service memory, after the load" $(( $(rss_kb $PID) / 1024 )) "<" 80 MB
kill $SERVER 2>/dev/null || true; pkill -x notes-api 2>/dev/null || true

# --- drawing ---
out="$("$PERF" draw 40)"
check "Drawing a full 1024x768 window (frames per second)" "$(echo "$out" | awk '/^full/ { print $2 }')" ">" 25 ""
check "Drawing a changed control (frames per second)" "$(echo "$out" | awk '/^partial/ { print $2 }')" ">" 200 ""

echo
echo "$(nproc) CPU(s), $(uname -m), $(date +%Y-%m-%d)"
[ "$fails" = 0 ] || { echo "$fails check(s) failed"; exit 1; }
