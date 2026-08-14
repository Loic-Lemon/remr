#!/bin/bash
# install.sh — build remr, bundle it, and install it to /Applications.
#
# Usage:
#   ./install.sh              build, install, then relaunch remr
#   ./install.sh --no-launch  build and install without relaunching
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$ROOT/build/Build/Products/Debug/remr.app"
APP_DEST="/Applications/remr.app"

cd "$ROOT"

echo "▸ Building remr…"
swift build

echo "▸ Assembling remr.app…"
Scripts/make-bundle.sh

# Quit the running instance so the bundle can be replaced cleanly. remr is
# menu-bar only (no window to lose); reminders are written to Reminders.app
# as they're created, so quitting is safe.
echo "▸ Quitting running remr…"
pkill -x remr 2>/dev/null || true
sleep 1

echo "▸ Installing to /Applications…"
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

if [[ "${1:-}" != "--no-launch" ]]; then
    echo "▸ Launching remr…"
    open "$APP_DEST"
fi

echo "Done — remr installed at $APP_DEST"
