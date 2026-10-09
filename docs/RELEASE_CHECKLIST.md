# Release Checklist (first playable)

Status legend: [x] verified with evidence · [ ] not yet verified.

## Automated gates
- [x] `./tools/test.sh` — 148/148 passing (2026-10-09)
- [x] `./tools/analyze.sh` — stylua, selene, luau-lsp strict all clean (2026-10-09)
- [x] `rojo build default.project.json` succeeds
- [x] Map contract (bounds, spacing, reachability, gate) validated at startup and in tests

## Studio verification (required before publishing)
- [x] Server log shows `[Bootstrap] Chrono Breakers server ready` with no errors (Studio, 2026-10-09)
- [x] Spawn locations: lobby, Infiltrator spawn, Keeper Sanctum (E2E; 2 of 4 Infiltrator spawns used)
- [x] Terminals: three prompts, states Locked→Available→Hacking→Completed (E2E; colours not visually reviewed)
- [x] Extraction: gate opens, extraction completes after 3 s (E2E; visuals not reviewed)
- [x] Time-Freeze/Trap placement rejects walls, out-of-range, and off-map targets (E2E)
- [x] Movement returns to 16/17 after every slow/stun/hold (E2E; Phase Dash haste not exercised live)
- [x] Results screen shows rewards; currency updates; second match pays separately (E2E)
- [x] 3-player match: one Keeper, simultaneous hacks, teammate resume, disconnect, consistent rewards, Keeper rotation (squad E2E 26/26)
- [x] Match end destroys live zones/traps; death while slowed respawns at 16 (E2E)
- [x] UI layout lint clean at the Studio viewport (lobby, HUD, hack panel, results); results/banner and PlayerList overlap fixed
- [ ] 4–5 player session
- [ ] Map reviewed from the player's perspective (terminals, gate, Sanctum, Spawn Bay)
- [ ] UI checked at 1920×1080, 1280×720, phone landscape (Device Emulator), gamepad navigation
- [ ] DataStore round trip in a published test place (rejoin keeps Scrap/items/settings)

## Configuration review
- [x] `GameConfig.Studio.AllowSoloMatch` only affects Studio — `MatchService.Init` sets `studioSolo = RunService:IsStudio() and …`; `allowKeeperless` and `soloIntermissionDuration` are only consulted through it (code review, 2026-10-09)
- [x] `ServerConfig.Security.KickOnFlood` deliberately false (reject + log preferred; documented in `SecurityService`) (code review, 2026-10-09)
- [x] Audio: only verified `rbxasset://sounds` entries; `LobbyMusic`/`MatchMusic` ids are nil (code review, 2026-10-09)

## Publishing (not authorised yet)
Runbook and rollback: [RELEASE_READINESS.md](RELEASE_READINESS.md).
- [ ] Explicit approval from the owner to publish / change experience settings
- [ ] Experience max players ≥ 5; Studio API access settings as desired
