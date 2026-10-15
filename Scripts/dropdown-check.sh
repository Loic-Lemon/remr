#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remr-dropdown-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc "$ROOT/Sources/remr/Core/DropdownGeometry.swift" "$ROOT/Scripts/DropdownCheckMain.swift" -o "$CHECK_DIR/dropdown-check"
"$CHECK_DIR/dropdown-check"
