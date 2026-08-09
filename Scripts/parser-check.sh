#!/bin/bash
# Runs the parser verification harness (XCTest-free — CommandLineTools ships no
# XCTest.framework, so `swift test` cannot compile the XCTest suite here).
# Compiles the parser sources + Scripts/ParserCheckMain.swift and asserts the
# plan's parser cases. Exit 0 = all pass.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(mktemp -t parser-check.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
swiftc -o "$BIN" \
    "$ROOT/Sources/remr/Core/Parser/NaturalLanguageParser.swift" \
    "$ROOT/Sources/remr/Core/Parser/SearchParser.swift" \
    "$ROOT/Scripts/ParserCheckMain.swift"
"$BIN"
