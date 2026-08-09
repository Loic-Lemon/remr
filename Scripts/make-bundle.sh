#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Debug/remr.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/debug/remr" "$APP/Contents/MacOS/remr"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --entitlements "$ROOT/Support/entitlements.plist" "$APP"
