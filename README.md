# Chrono Breakers: Temporal Heist

Asymmetrical Roblox multiplayer game: **1 Time-Keeper vs. up to 4 Infiltrators**. Infiltrators hack
three vault terminals, then race to the extraction pad; the Time-Keeper hunts them with Chrono Strike,
Time-Freeze Zones, and Temporal Traps. Built with Luau (`--!strict`), Rojo, and a small
service/controller architecture with a pure, offline-tested gameplay core.

> Working title — configurable in `src/Shared/Config/GameConfig.luau`.

## Status (honest summary)

| Area | State |
| --- | --- |
| Match flow, roles, terminals, extraction, results | Implemented; Lune tests + **verified in Roblox Studio** (solo 102/102, 2-player 69/69 E2E) |
| Time-Keeper kit + Infiltrator gadgets | Implemented; exercised through real remotes in a 2-player Studio session |
| Persistence, shop/loadout, rewards | Implemented; shop/rewards verified in Studio with the in-memory store. **Real DataStores not yet verified** (needs a published test experience) |
| Client UI (lobby, HUD, reveal, results, loadout, settings) | Implemented; screen visibility/state verified in Studio. **Visual layout, touch and gamepad not yet reviewed** |
| Studio validation details | [docs/TEST_PLAN.md](docs/TEST_PLAN.md), raw logs in [docs/evidence/](docs/evidence/) |

## Requirements

Installed and verified on macOS (arm64) during development:

| Tool | Version | Install |
| --- | --- | --- |
| Rojo | 7.7.1 | `brew install rojo` |
| Lune (test runner) | 0.10.5 | `brew install lune` |
| StyLua | 2.5.2 | `brew install stylua` |
| Selene | 0.32.0 | `brew install selene` |
| luau-lsp (type checking) | 1.70.1 | download `luau-lsp-macos.zip` from the [luau-lsp releases](https://github.com/JohnnyMorganz/luau-lsp/releases) into `~/.local/bin` |
| Roblox Studio | 0.742 used | [create.roblox.com](https://create.roblox.com) |

No Wally/Aftman/Rokit packages are used; the project has **no third-party runtime dependencies**.

## Commands

```bash
# Run all automated tests (builds build/test.rbxl, runs specs under Lune)
./tools/test.sh            # optional filter: ./tools/test.sh Hacking

# Static checks: StyLua format check, Selene lint, luau-lsp strict type analysis
./tools/analyze.sh

# Format sources
stylua src tools/run-tests.luau

# Build the production place file
rojo build default.project.json -o build/game.rbxl

# Live-sync into an open Studio place (requires the Rojo Studio plugin)
rojo serve default.project.json
```

## Playing in Roblox Studio

1. `rojo build default.project.json -o build/game.rbxl` and open `build/game.rbxl` in Studio
   (or open any place and connect via `rojo serve` + the Rojo plugin).
2. **Solo:** Play (F5), press **Join Queue**. In Studio a single queued player may start a
   keeperless match (Infiltrator only) to exercise hacking → extraction (`GameConfig.Studio`).
3. **Full match:** Test → Clients and Servers → 2–5 players, queue on each client.
4. DataStores: Studio uses an **in-memory fallback** unless the place is published and
   "Enable Studio Access to API Services" is on. The UI shows "Unsaved session" when data
   cannot persist.
5. In-Studio test run: open `build/test.rbxl` (built by `./tools/test.sh`) and press Run;
   `TestRunner` prints `[Tests] N passed, M failed` to Output.

## Controls

| Action | Keyboard/Mouse | Gamepad | Touch |
| --- | --- | --- | --- |
| Hack terminal | E (prompt) | X | tap prompt |
| Cancel hack | C | B | Cancel button |
| Chrono Strike (Keeper) | LMB | R2 | ability button |
| Time-Freeze Zone (Keeper) | Q to aim, click to place, RMB cancel | L1, press again/R2, B cancel | button → Confirm |
| Temporal Trap (Keeper) | F (aim/confirm like above) | Y | button → Confirm |
| Gadget (Infiltrator) | Q | L1 | ability button |

## Repository layout

```
default.project.json   production Rojo tree       test.project.json  adds src/Tests
src/Shared/            replicated: Config, Types, Network registry, Modules (Signal, Cleanup, Safe…)
src/Server/            ServerScriptService: Bootstrap, Services, Core (pure rules), Components, World
src/Client/            StarterPlayerScripts: Bootstrap, Controllers, UI (Components, Screens)
src/Tests/             TestKit, Unit/, Integration/, Helpers/, Studio TestRunner
tools/                 test.sh, analyze.sh, run-tests.luau (Lune harness)
docs/                  design, architecture, network, data, tests, balance, build, release
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) to orient, and
[docs/IMPLEMENTATION_CHECKLIST.md](docs/IMPLEMENTATION_CHECKLIST.md) for progress.
