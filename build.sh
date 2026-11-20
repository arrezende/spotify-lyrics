#!/bin/bash
# Builds a self-contained .app bundle (no Xcode project needed).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/LetrasPiP.app"
BIN="$APP/Contents/MacOS/LetrasPiP"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -O \
  -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework Combine \
  "$DIR"/Sources/*.swift \
  -o "$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>LetrasPiP</string>
    <key>CFBundleDisplayName</key>
    <string>Letras PiP</string>
    <key>CFBundleIdentifier</key>
    <string>com.arrezende.letraspip</string>
    <key>CFBundleExecutable</key>
    <string>LetrasPiP</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Para ler a faixa e a posição que estão tocando no Spotify e sincronizar a letra.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "aviso: codesign falhou (o app ainda roda)"

echo "OK: $APP"
