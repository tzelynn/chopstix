#!/bin/bash
# Builds a release binary and wraps it in build/Chopstix.app (with icon).
#   scripts/build_app.sh            # build
#   scripts/build_app.sh --install  # build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Chopstix"

APP=build/Chopstix.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Chopstix"
cp Sources/Chopstix/Resources/AppIcon.svg "$APP/Contents/Resources/"

ICONSET=build/Chopstix.iconset
rm -rf "$ICONSET"
"$BIN" --export-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Chopstix.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>chopstix</string>
    <key>CFBundleDisplayName</key><string>chopstix</string>
    <key>CFBundleIdentifier</key><string>app.chopstix</string>
    <key>CFBundleExecutable</key><string>Chopstix</string>
    <key>CFBundleIconFile</key><string>Chopstix</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>made to order</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper treats it as a coherent bundle when run locally.
codesign --force --deep --sign - "$APP" >/dev/null

echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Chopstix.app
    cp -R "$APP" /Applications/
    echo "installed to /Applications/Chopstix.app"
fi
