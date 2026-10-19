# Chrono Breakers: Temporal Heist

Asymmetrical survival-horror heist for Roblox: **1 Time-Keeper vs. up to 4 Infiltrators**.
Infiltrators breach four of five terminals under Calibration Pulses, break chases with sprints,
vaults, Stasis Barriers and lockers, Re-sync and rescue each other from Stasis Pods, then power a
Gate Relay and escape the Temporal Collapse. The Time-Keeper hunts with a telegraphed Chrono Strike,
Phase-Locks the fallen, Overloads terminals and controls space with Freeze Zones, Traps and Pulses.
Design: [SURVIVAL_DESIGN](docs/SURVIVAL_DESIGN.md). Built with Luau (`--!strict`), Rojo, and a small
service/controller architecture with a pure, offline-tested gameplay core.

> Working title — configurable in `src/Shared/Config/GameConfig.luau`.

## Status

**Survival Protocol** implemented on top of the temporal expansion (integrity ladder, containment,
pursuit, interactive hacking, environmental play, Collapse endgame, perks, survival HUD, atmosphere).
Offline gates pass; Studio E2E, balance and device validation are pending —
[SURVIVAL_RELEASE](docs/SURVIVAL_RELEASE.md).

Temporal expansion implemented: four maps/voting, five free classes, co-op and interactive hacking,
eight anomalies, Keeper tracking, XP/mastery/calendar contracts/cosmetics, team pings and refreshed
presentation. The existing authoritative architecture and runtime dependency policy are preserved.

Automated verification and limitations: [EXPANSION_RELEASE](docs/EXPANSION_RELEASE.md).
**Release sign-off is pending** new Studio/five-client, real DataStore, device, visual and profiling
checks. Historical Studio evidence verifies the earlier build only. Nothing has been published.

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
lune run tools/verify-build.luau

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
| Hack / interact (Re-sync, Patch, Rescue, Vault, Barrier, Door, Locker, Relay) | E (prompt) | X | tap prompt |
| Cancel hack or channel | C | B | Cancel button |
| Sprint (Infiltrator) | hold Left Shift | hold L3 | hold SPRINT |
| Calibration Pulse | Space | A | tap the ring |
| Phase-Lock / Overload / Break / Search (Keeper) | E (prompt) | X | tap prompt |
| Chrono Strike (Keeper) | LMB | R2 | ability button |
| Time-Freeze Zone (Keeper) | Q to aim, click to place, RMB cancel | L1, press again/R2, B cancel | button → Confirm |
| Temporal Trap (Keeper) | F (aim/confirm like above) | Y | button → Confirm |
| Gadget (Infiltrator) | Q | L1 | ability button |
| Class skill (Infiltrator) | F | Y | class button |
| Chrono Pulse (Keeper) | R | L2 | pulse button |
| Team ping | G | R1 | Team ping button |

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
