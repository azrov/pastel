#!/bin/sh
# Builds framework/android/classes.dex from framework/android/java (Pastel's
# Android activity) and framework/src/pastel.javaproxy.inc (PastelProxy for
# computers). Needs javac, an android.jar and dx (on Ubuntu:
# sudo apt install default-jdk-headless android-sdk-platform-23 dalvik-exchange).
# The .dex is kept in the repository, so apps do not need these tools.
set -e
cd "$(dirname "$0")/.."
JAR="${ANDROID_JAR:-$(ls /usr/lib/android-sdk/platforms/android-*/android.jar 2>/dev/null | tail -1)}"
[ -f "$JAR" ] || { echo "error: no android.jar (set ANDROID_JAR)" >&2; exit 1; }
DX="$(command -v dx || command -v dalvik-exchange)"
WORK="$(mktemp -d)"
# classes of newer Androids, to compile against only (framework/android/stubs.jar; not in the app)
mkdir -p "$WORK/stubs"
javac -source 8 -target 8 -nowarn -Xlint:-options -bootclasspath "$JAR" -d "$WORK/stubs" $(find framework/android/stubs -name '*.java')
(cd "$WORK/stubs" && jar cf "$OLDPWD/framework/android/stubs.jar" .)
javac -source 8 -target 8 -nowarn -Xlint:-options -bootclasspath "$JAR" -classpath framework/android/stubs.jar -d "$WORK/classes" framework/android/java/dev/pastel/*.java
"$DX" --dex --min-sdk-version=19 --output=framework/android/classes.dex "$WORK/classes"
# PastelProxy for the Java VM of computers (Pastel.Java gives it to the VM itself)
CLS="$WORK/classes/dev/pastel/PastelProxy.class"
{
  echo "{ dev/pastel/PastelProxy.class (framework/android/java) for the Java VM of computers."
  echo "  Written by tools/android-dex.sh: do not change it. }"
  echo "const"
  echo "  PastelProxyClass: array[0..$(($(wc -c < "$CLS") - 1))] of Byte = ("
  od -An -tu1 -v "$CLS" | tr -s ' ' '\n' | grep -v '^$' |
    awk '{ a[NR] = $1 } END { for (i = 1; i <= NR; i++) { if ((i - 1) % 20 == 0) printf "    "; printf "%s", a[i]; if (i < NR) printf ","; if (i % 20 == 0 || i == NR) printf "\n"; else printf " " } }'
  echo "  );"
} > framework/src/pastel.javaproxy.inc
rm -rf "$WORK"
echo "built framework/android/classes.dex and framework/src/pastel.javaproxy.inc"
