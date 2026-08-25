#!/bin/bash
# Builds a patched wvkbd-deskintl (fixes an upstream touch-motion bug: the
# key highlight flickers off and key-repeat never engages, because
# kbd_motion_key() unconditionally unpresses the current key on every touch
# motion event -- including the sub-pixel jitter any real touchscreen
# reports while a finger is held still) and installs it to ~/.local/bin,
# ahead of /usr/bin on PATH, so it's picked up instead of the unpatched AUR
# build.
#
# See keyboard.c.patch and README.md for the actual fix and why it's needed.
set -euo pipefail

VERSION="0.19.4"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Fetching wvkbd v$VERSION source"
curl -sL "https://git.sr.ht/~proycon/wvkbd/archive/v$VERSION.tar.gz" -o "$BUILD_DIR/wvkbd.tar.gz"
tar xzf "$BUILD_DIR/wvkbd.tar.gz" -C "$BUILD_DIR"
SRC_DIR="$BUILD_DIR/wvkbd-v$VERSION"

echo "==> Applying flicker/no-repeat fix"
patch -p1 -d "$SRC_DIR" < "$SCRIPT_DIR/keyboard.c.patch"

echo "==> Building (LAYOUT=deskintl)"
# scdoc (man page) is optional -- ignore its failure if not installed.
make -C "$SRC_DIR" LAYOUT=deskintl || true
if [[ ! -x "$SRC_DIR/wvkbd-deskintl" ]]; then
  echo "Build failed: wvkbd-deskintl binary was not produced." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
install -m 755 "$SRC_DIR/wvkbd-deskintl" "$INSTALL_DIR/wvkbd-deskintl"
echo "==> Installed patched binary to $INSTALL_DIR/wvkbd-deskintl"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "WARNING: $INSTALL_DIR is not on your PATH ahead of /usr/bin -- add it or the unpatched AUR build will run instead." >&2 ;;
esac
