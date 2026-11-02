#!/bin/sh
# Builds framework/android/classes.dex from framework/android/java (Pastel's
# Android activity). Needs javac, an android.jar and dx (on Ubuntu:
# sudo apt install default-jdk-headless android-sdk-platform-23 dalvik-exchange).
# The .dex is kept in the repository, so apps do not need these tools.
set -e
cd "$(dirname "$0")/.."
JAR="${ANDROID_JAR:-$(ls /usr/lib/android-sdk/platforms/android-*/android.jar 2>/dev/null | tail -1)}"
[ -f "$JAR" ] || { echo "error: no android.jar (set ANDROID_JAR)" >&2; exit 1; }
DX="$(command -v dx || command -v dalvik-exchange)"
WORK="$(mktemp -d)"
javac -source 8 -target 8 -nowarn -Xlint:-options -bootclasspath "$JAR" -d "$WORK" framework/android/java/dev/pastel/*.java
"$DX" --dex --min-sdk-version=23 --output=framework/android/classes.dex "$WORK"
rm -rf "$WORK"
echo "built framework/android/classes.dex"
