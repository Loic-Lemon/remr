#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
    debug) BUNDLE_CONFIGURATION="Debug" ;;
    release) BUNDLE_CONFIGURATION="Release" ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
APP="$ROOT/build/Build/Products/$BUNDLE_CONFIGURATION/remr.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/$CONFIGURATION/remr" "$APP/Contents/MacOS/remr"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --entitlements "$ROOT/Support/entitlements.plist" "$APP"
