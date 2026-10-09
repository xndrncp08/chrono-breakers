#!/usr/bin/env bash
# Builds the test place with Rojo and runs every spec under Lune.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build test.project.json -o build/test.rbxl >/dev/null
lune run tools/run-tests.luau build/test.rbxl "${1:-}"
