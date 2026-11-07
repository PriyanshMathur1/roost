#!/bin/bash
# Builds a universal, signed Roost.app and zips it for a GitHub release:
#   VERSION=0.2.0 ./scripts/release.sh   →  dist/Roost-0.2.0.zip
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.3.0}"
STAGE="$(mktemp -d)"
ROOST_APP_DIR="$STAGE" VERSION="$VERSION" UNIVERSAL=1 ./scripts/bundle.sh
mkdir -p dist
rm -f "dist/Roost-$VERSION.zip"
ditto -c -k --keepParent "$STAGE/Roost.app" "dist/Roost-$VERSION.zip"
# A version-free copy, so links to releases/latest/download/Roost.zip always work.
cp "dist/Roost-$VERSION.zip" dist/Roost.zip
lipo -info "$STAGE/Roost.app/Contents/MacOS/Roost"
shasum -a 256 "dist/Roost-$VERSION.zip"
