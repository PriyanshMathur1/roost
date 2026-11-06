#!/bin/bash
# Builds Tessera in release mode and wraps it in build/Tessera.app.
#
# Signing is ad-hoc ("-"). macOS ties the Accessibility grant of an ad-hoc signed app
# to this exact build, so after every rebuild you have to switch Tessera off and on
# again in System Settings › Privacy & Security › Accessibility. A Developer ID
# certificate (paid Apple developer account) removes that step.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Tessera.app"

swift build -c release --product Tessera
BIN="$(swift build -c release --show-bin-path)/Tessera"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tessera"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.priyansh.tessera</string>
    <key>CFBundleName</key><string>Tessera</string>
    <key>CFBundleDisplayName</key><string>Tessera</string>
    <key>CFBundleExecutable</key><string>Tessera</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Priyansh Mathur</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.priyansh.tessera --options runtime "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)"
