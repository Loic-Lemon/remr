#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp -t remr-review-nudge-check.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
swiftc -o "$BIN" \
    "$ROOT/Sources/remr/Core/KeyBindings.swift" \
    "$ROOT/Sources/remr/Core/ReviewNudgeSchedule.swift" \
    "$ROOT/Sources/remr/Core/SettingsStore.swift" \
    "$ROOT/Scripts/ReviewNudgeCheckMain.swift"
"$BIN"
