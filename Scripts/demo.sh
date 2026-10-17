#!/bin/bash
# Prepare or launch the isolated demo. Never installs over /Applications/remr.app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Demo/remr Demo.app"
case "${1:-prepare}" in
    prepare)
        swift build --package-path "$ROOT" -c release
        mkdir -p "$APP/Contents/MacOS"
        cp "$ROOT/.build/release/remr" "$APP/Contents/MacOS/remr-demo"
        cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable remr-demo' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.remr.demo' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleName remr Demo' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName remr Demo' "$APP/Contents/Info.plist"
        # The demo must not register the production URL scheme or text service.
        /usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Delete :NSServices' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Delete :NSRemindersUsageDescription' "$APP/Contents/Info.plist"
        printf 'APPL????' > "$APP/Contents/PkgInfo"
        codesign --force --sign - "$APP"
        echo "Demo prepared: $APP"
        echo "When ready: Scripts/demo.sh start"
        ;;
    start|reset)
        [[ -x "$APP/Contents/MacOS/remr-demo" ]] || { echo 'Run Scripts/demo.sh prepare first.' >&2; exit 1; }
        # Both instances use the same global shortcuts; only run one at a time.
        pkill -x remr 2>/dev/null || true
        pkill -x remr-demo 2>/dev/null || true
        sleep 1
        open -n "$APP"
        sleep 2
        pgrep -x remr-demo >/dev/null || { echo 'Demo failed to stay running; inspect the latest remr-demo crash report.' >&2; exit 1; }
        echo 'Demo launched with fresh fictional data. No recording has started.'
        ;;
    stop)
        pkill -x remr-demo 2>/dev/null || true
        open /Applications/remr.app
        ;;
    *) echo 'Usage: Scripts/demo.sh [prepare|start|reset|stop]' >&2; exit 1 ;;
esac
