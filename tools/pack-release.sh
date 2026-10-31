#!/bin/sh
# Packs a built pastel (bin/) with the framework into dist/ for a release:
#   sh tools/pack-release.sh 0.7.0 linux-x86_64
# dist/pastel-0.7.0-linux-x86_64.tar.gz (or .zip for Windows) contains
# pastel-0.7.0/ with bin/, framework/src/, cli/ (the designer compiles the
# project's own controls with it), docs/, examples/, README.md, LICENSE.
set -e
cd "$(dirname "$0")/.."
VERSION="$1"
PLATFORM="$2"
[ -n "$VERSION" ] && [ -n "$PLATFORM" ] || { echo "use: sh tools/pack-release.sh <version> <platform>" >&2; exit 2; }
NAME="pastel-$VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME/bin" "$STAGE/$NAME/framework" dist
if [ -f bin/pastel.exe ]; then cp bin/pastel.exe "$STAGE/$NAME/bin/"; else cp bin/pastel "$STAGE/$NAME/bin/"; fi
cp -r framework/src "$STAGE/$NAME/framework/"
cp -r cli docs examples README.md ROADMAP.md LICENSE "$STAGE/$NAME/"
find "$STAGE/$NAME" \( -name build -o -name dist -o -name data \) -type d -prune -exec rm -rf {} +
find "$STAGE/$NAME" \( -name '*.o' -o -name '*.ppu' \) -delete
# the version must match the tag
"$STAGE/$NAME/bin/pastel"* version | grep -q "pastel $VERSION$" || {
  echo "bin/pastel is not version $VERSION: $("$STAGE/$NAME/bin/pastel"* version)" >&2; exit 1; }
case "$PLATFORM" in
  windows*) (cd "$STAGE" && if command -v zip >/dev/null; then zip -qr "$OLDPWD/dist/$NAME-$PLATFORM.zip" "$NAME";
             else powershell -Command "Compress-Archive -Path '$NAME' -DestinationPath '$OLDPWD/dist/$NAME-$PLATFORM.zip'"; fi) ;;
  *) tar -C "$STAGE" -czf "dist/$NAME-$PLATFORM.tar.gz" "$NAME" ;;
esac
ls dist/"$NAME-$PLATFORM".*
