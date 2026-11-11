#!/bin/zsh
# Builds LogoToggle.app into ./build. Pass --install to also copy it to ~/Applications.
# Pass --zip to also make build/LogoToggle.zip for a release.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/LogoToggle.app"
VERSION="${VERSION:-1.0.0}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/LogoToggle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LogoToggle</string>
  <key>CFBundleIdentifier</key><string>io.github.jamesfergus2000.logotoggle</string>
  <key>CFBundleExecutable</key><string>LogoToggle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

for arg in "$@"; do
  case "$arg" in
    --install)
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/LogoToggle.app"
      cp -R "$APP" "$HOME/Applications/"
      echo "Installed to ~/Applications/LogoToggle.app" ;;
    --zip)
      rm -f build/LogoToggle.zip
      ditto -c -k --keepParent "$APP" build/LogoToggle.zip
      echo "Zipped build/LogoToggle.zip" ;;
  esac
done
