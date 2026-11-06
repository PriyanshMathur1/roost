#!/bin/bash
# Builds Tessera in release mode and wraps it in build/Tessera.app.
#
# Signing: if a code-signing certificate named "Tessera Dev" (or $SIGN_IDENTITY) is in
# your keychain, the app is signed with it. macOS then ties the Accessibility grant to
# that certificate and the bundle ID, so the grant survives rebuilds. Without one the
# app is signed ad-hoc, and every rebuild needs the grant again. See README › Signing.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# The app is assembled outside the project: iCloud Drive (the Desktop and Documents
# folders, when synced) adds Finder and file-provider attributes to bundles, which breaks
# their code signature.
APP_DIR="${TESSERA_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Tessera.app"
mkdir -p "$APP_DIR"

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

IDENTITY="${SIGN_IDENTITY:-Tessera Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    SIGN_WITH="$IDENTITY"
else
    SIGN_WITH="-"
    echo "No \"$IDENTITY\" certificate found: signing ad-hoc (the Accessibility grant won't survive the next rebuild)."
fi
# Extended attributes (Finder info, quarantine, provenance) make codesign refuse the bundle.
xattr -cr "$APP"
codesign --force --sign "$SIGN_WITH" --identifier com.priyansh.tessera --options runtime "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER, signed: ${SIGN_WITH/#-/ad-hoc})"
