#!/usr/bin/env bash
# Static analysis: StyLua formatting check, Selene lint, and luau-lsp strict type analysis with the
# Roblox API definitions. Downloads the definitions file into .cache/ on first run.
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU_LSP="${LUAU_LSP:-$(command -v luau-lsp || echo "$HOME/.local/bin/luau-lsp")}"
mkdir -p .cache
DEFS=.cache/globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
	curl -sSfL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== stylua --check"
stylua --check src tools/run-tests.luau tools/verify-build.luau

echo "== selene"
selene src

echo "== luau-lsp analyze"
rojo sourcemap test.project.json -o sourcemap.json >/dev/null
"$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$DEFS" --flag:LuauSolverV2=false src
echo "All static checks passed."
