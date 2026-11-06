#!/bin/bash
# Regenerates Resources/AppIcon.icns (and a 512 px preview PNG) from Sources/Roost/Brand.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swiftc -O Sources/Roost/Brand.swift scripts/make-icon/main.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_256x256@2x.png" docs/icon.png
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
