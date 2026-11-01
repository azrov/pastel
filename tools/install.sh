#!/bin/sh
# Installs the latest Pastel release on Linux:
#   curl -fsSL https://github.com/azrov/pastel/releases/latest/download/install.sh | sh
# into ~/.pastel/<version>/, with ~/.local/bin/pastel pointing at it.
# Needs Free Pascal: sudo apt install fpc (and fpc-source for Windows builds).
set -e
REPO="${PASTEL_REPO:-__REPO__}"     # filled in by the release workflow
case "$(uname -m)" in
  x86_64|amd64) PLATFORM=linux-x86_64 ;;
  aarch64|arm64) PLATFORM=linux-arm64 ;;
  *) echo "error: no ready-made Pastel for $(uname -m); build it from the sources (./build.sh)" >&2; exit 1 ;;
esac
VERSION="${PASTEL_VERSION:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')}"
[ -n "$VERSION" ] || { echo "error: could not find the latest release of $REPO" >&2; exit 1; }
URL="https://github.com/$REPO/releases/download/v$VERSION/pastel-$VERSION-$PLATFORM.tar.gz"
DEST="$HOME/.pastel"
mkdir -p "$DEST" "$HOME/.local/bin"
echo "Downloading $URL"
curl -fsSL "$URL" | tar -xz -C "$DEST"
ln -sf "$DEST/pastel-$VERSION/bin/pastel" "$HOME/.local/bin/pastel"
echo "Installed Pastel $VERSION: $HOME/.local/bin/pastel"
command -v fpc >/dev/null || echo "Next: install Free Pascal (sudo apt install fpc), then run: pastel doctor"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH to run pastel." ;; esac
