#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp -t remr-notch-calendar-check.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
swift build --package-path "$ROOT"
OBJECTS=()
for object in "$ROOT"/.build/debug/remr.build/*.swift.o; do
    [[ "$object" == */RemrApp.swift.o ]] || OBJECTS+=("$object")
done
swiftc -parse-as-library -I "$ROOT/.build/debug/Modules" \
    "$ROOT/Scripts/NotchCalendarCheckMain.swift" "${OBJECTS[@]}" -o "$BIN"
"$BIN"
