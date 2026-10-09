# Release Checklist (first playable)

Status legend: [x] verified with evidence · [ ] not yet verified.

## Automated gates
- [x] `./tools/test.sh` — 145/145 passing (2026-10-09)
- [x] `./tools/analyze.sh` — stylua, selene, luau-lsp strict all clean (2026-10-09)
- [x] `rojo build default.project.json` succeeds
- [x] Map contract (bounds, spacing, reachability, gate) validated at startup and in tests

## Studio verification (required before publishing)
- [ ] Server log shows `[Bootstrap] Chrono Breakers server ready` with no errors
- [ ] Spawn locations: lobby, 4 Infiltrator spawns, Keeper Sanctum
- [ ] Terminals: three prompts, colours change Locked→Available→Hacking→Completed
- [ ] Extraction: gate opens, pad/beacon visible, extraction completes after 3 s
- [ ] Time-Freeze/Trap placement rejects walls, out-of-range, and off-map clicks
- [ ] Movement returns to 16/17 after every slow/stun/haste
- [ ] Results screen shows rewards; currency updates; second match pays separately
- [ ] UI checked at 1920×1080, 1280×720, phone landscape (Device Emulator), gamepad navigation
- [ ] DataStore round trip in a published test place (rejoin keeps Scrap/items/settings)

## Configuration review
- [ ] `GameConfig.Studio.AllowSoloMatch` only affects Studio (`RunService:IsStudio()` gate)
- [ ] `ServerConfig.Security.KickOnFlood` deliberately false
- [ ] Audio: only verified `rbxasset://sounds` entries; music unconfigured

## Publishing (not authorised yet)
- [ ] Explicit approval from the owner to publish / change experience settings
- [ ] Experience max players ≥ 5; Studio API access settings as desired
