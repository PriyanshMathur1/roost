#!/bin/bash
# Builds Roost in release mode and wraps it in build/Roost.app.
#
# Signing: if a code-signing certificate named "Roost Dev" (or $SIGN_IDENTITY) is in
# your keychain, the app is signed with it. macOS then ties the Accessibility grant to
# that certificate and the bundle ID, so the grant survives rebuilds. Without one the
# app is signed ad-hoc, and every rebuild needs the grant again. See README › Signing.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# The app is assembled outside the project: iCloud Drive (the Desktop and Documents
# folders, when synced) adds Finder and file-provider attributes to bundles, which breaks
# their code signature.
APP_DIR="${ROOST_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Roost.app"
mkdir -p "$APP_DIR"

# A universal binary (Apple Silicon + Intel). `swift build --arch a --arch b` needs full Xcode,
# so build each architecture on its own and join them. UNIVERSAL=0 builds for this Mac only.
if [ "${UNIVERSAL:-1}" = "1" ]; then
    for ARCH in arm64 x86_64; do
        swift build -c release --product Roost --triple "$ARCH-apple-macosx14.0"
    done
    BIN="$(mktemp -d)/Roost"
    lipo -create .build/arm64-apple-macosx/release/Roost .build/x86_64-apple-macosx/release/Roost -output "$BIN"
else
    swift build -c release --product Roost
    BIN="$(swift build -c release --show-bin-path)/Roost"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Roost"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.priyansh.roost</string>
    <key>CFBundleName</key><string>Roost</string>
    <key>CFBundleDisplayName</key><string>Roost</string>
    <key>CFBundleExecutable</key><string>Roost</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

IDENTITY="${SIGN_IDENTITY:-Roost Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    SIGN_WITH="$IDENTITY"
else
    SIGN_WITH="-"
    echo "No \"$IDENTITY\" certificate found: signing ad-hoc (the Accessibility grant won't survive the next rebuild)."
fi
# Extended attributes (Finder info, quarantine, provenance) make codesign refuse the bundle.
xattr -cr "$APP"
codesign --force --sign "$SIGN_WITH" --identifier com.priyansh.roost --options runtime "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER, signed: ${SIGN_WITH/#-/ad-hoc})"
