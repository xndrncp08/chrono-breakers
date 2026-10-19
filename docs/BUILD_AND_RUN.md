# Build and Run

Exact commands for the current toolchain (verified on macOS arm64, 2026-10-09).

```bash
brew install rojo lune stylua selene        # rojo 7.7.1, lune 0.10.5, stylua 2.5.2, selene 0.32.0
# luau-lsp 1.70.1: download luau-lsp-macos.zip from GitHub releases → ~/.local/bin/luau-lsp

./tools/test.sh          # build test place + run all Lune specs (exit 1 on failure)
./tools/analyze.sh       # stylua --check, selene, luau-lsp strict analysis
rojo build default.project.json -o build/game.rbxl     # production place
rojo build test.project.json -o build/test.rbxl        # place incl. Studio TestRunner
rojo serve default.project.json                        # live sync to Studio (Rojo plugin)
```

`analyze.sh` downloads the Roblox API definitions (`globalTypes.d.luau`) from the luau-lsp
repository into `.cache/` on first run (network required once). `sourcemap.json` and `build/` are
generated and git-ignored.

## Studio
- Open `build/game.rbxl`, press Play for solo (keeperless Studio match after queueing) or use
  Test → Clients and Servers for 2–5 players.
- `Workspace.StreamingEnabled` is set to false in the project file (small map; all objective
  instances must exist on clients).
- To test real DataStores: publish the place, enable Studio access to API services.

## Publishing
Not performed. To publish: open the built place in Studio → File → Publish to Roblox, configure
the experience (max players ≥ 5 recommended), then follow RELEASE_CHECKLIST.md. Do not publish
without verifying the Studio scenarios in TEST_PLAN.md.

## Roblox Studio MCP

Studio validation uses **Meganugger's Roblox Studio MCP**
(<https://github.com/Meganugger/roblox-studio-mcp>, v4.0.0).

### Why the first attempt timed out
The project was originally registered with a different server (npm `robloxstudio-mcp`). That server
was running (`/health` → `"pluginConnected": false, "instanceCount": 0`), but **no Studio plugin was
ever installed** (`~/Documents/Roblox/Plugins` did not exist), so nothing in Studio ever connected.

### Setup (as performed 2026-10-09, macOS)
```bash
git clone https://github.com/Meganugger/roblox-studio-mcp.git ~/tools/roblox-studio-mcp
cd ~/tools/roblox-studio-mcp && npm install && npm run build && npm test   # 214 passed, 8 skipped
node server/dist/index.js --install-plugin      # -> ~/Documents/Roblox/Plugins/RobloxStudioMCP.rbxmx
# register with your MCP client as server "roblox-studio": node ~/tools/roblox-studio-mcp/server/dist/index.js
```
Then **restart Studio** (plugins load at startup), open a place, click **Plugins → MCP**, paste the
token from `~/.roblox-studio-mcp/token`, and press **Connect**. The token is saved; later sessions
(including Play sessions) reconnect automatically.

Notes:
- One MCP server per Studio session; the bridge listens on `127.0.0.1:3667`.
- `start_play_solo` presses F5 via macOS automation: grant **Accessibility** to the app running
  the server (here: Visual Studio Code). `capture_studio_screenshot` needs **Screen Recording**.
- Runtime evaluation on the play server needs `LoadStringEnabled`; it is set **only** in
  `test.project.json`. Never enable it in `default.project.json`.

## In-engine E2E suites
`test.project.json` adds `ServerScriptService.Tests.E2E.E2EDriver` (enabled by the `RunE2E`
attribute) and `StarterPlayerScripts.E2EClient`. Open `build/test.rbxl` in Studio, then:
- **Solo:** press F5 and do not interact (two full matches, ~2.5 min).
- **Multiplayer:** Test → Clients and Servers → 2 players → Start (~4 min; one client is kicked
  at the end on purpose).
- **Squad:** same with 3–5 players (~3 min; one Infiltrator and later the Keeper are kicked on purpose).
The summary prints as `[E2E] <mode>: N passed, M failed` and is stored in the ReplicatedStorage
attribute `E2ESummary`. Logs of finished sessions are also in `~/Library/Logs/Roblox/*_last.log`.
To push local edits into an open Studio without Rojo, use `tools/studio-sync.py` (see tools/README.md).

## Expansion validation

After the normal tests/analysis, run `rojo build default.project.json -o build/game.rbxl` then
`lune run tools/verify-build.luau`. This inspects the built artifact for test-script leakage,
LoadStringEnabled, required services and syntax compilation of every shipped script.

For the new Studio suite, build test.project.json, open test.rbxl, set the boolean attribute
`ServerScriptService.Tests.RunExpansionE2E=true` in edit mode and start 2–5 test clients. It is
written but unrun in the current environment; Studio window access was denied. Exact steps and
published DataStore/device/performance gates are in [EXPANSION_RELEASE](EXPANSION_RELEASE.md).
