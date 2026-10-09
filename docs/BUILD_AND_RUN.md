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
