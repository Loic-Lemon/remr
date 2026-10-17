#!/bin/bash
# Real native-glass capture and clock regression check; --record also saves
# 12-second light/dark GIFs to build/composer-scene. Uses only its own window.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp -t remr-composer-scene-check.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
swift build --package-path "$ROOT"
OBJECTS=()
for object in "$ROOT"/.build/debug/remr.build/*.swift.o; do
    [[ "$object" == */RemrApp.swift.o ]] || OBJECTS+=("$object")
done
swiftc -parse-as-library -I "$ROOT/.build/debug/Modules" \
    "$ROOT/Scripts/ComposerSceneCheckMain.swift" "${OBJECTS[@]}" -o "$BIN"
COMPOSER_SCENE_OUTPUT="${COMPOSER_SCENE_OUTPUT:-$ROOT/build/composer-scene}" "$BIN" "$@"
