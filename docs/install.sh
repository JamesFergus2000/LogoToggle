#!/bin/sh
# LogoToggle installer
#   curl -fsSL https://jamesfergus2000.github.io/LogoToggle/install.sh | sh
#
# Downloads the latest release from GitHub, installs LogoToggle.app into
# /Applications (or ~/Applications if /Applications isn't writable) and opens it.
# Source: https://github.com/JamesFergus2000/LogoToggle
set -eu

URL="https://github.com/JamesFergus2000/LogoToggle/releases/latest/download/LogoToggle.zip"
DEST="${LOGOTOGGLE_DIR:-/Applications}"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "LogoToggle only runs on macOS."
[ "$(uname -m)" = "arm64" ] || fail "LogoToggle needs a Mac with Apple silicon."

if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading LogoToggle..."
curl -fsSL "$URL" -o "$TMP/LogoToggle.zip" || fail "Download failed. Check your connection and try again."

say "Unpacking..."
ditto -x -k "$TMP/LogoToggle.zip" "$TMP" || fail "Couldn't unpack the download."
[ -d "$TMP/LogoToggle.app" ] || fail "The download didn't contain LogoToggle.app."

# Quit a running copy before replacing it.
pkill -x LogoToggle 2>/dev/null || true

say "Installing to $DEST..."
rm -rf "$DEST/LogoToggle.app"
mv "$TMP/LogoToggle.app" "$DEST/"

if [ -z "${LOGOTOGGLE_NO_OPEN:-}" ]; then
  say "Opening LogoToggle. Look for it in your menu bar."
  open "$DEST/LogoToggle.app"
fi

say "Done. To remove it later: rm -rf \"$DEST/LogoToggle.app\""
