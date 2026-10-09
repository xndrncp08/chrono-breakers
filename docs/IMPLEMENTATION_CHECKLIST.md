# Implementation Checklist (resumable progress log)

This file is the persistent progress log for the autonomous build. If a session is
interrupted, resume from the first unchecked item. Only tick items that were verified.

## Phase 0 — Audit
- [x] Repository audited (only the master prompt existed; remote `origin` is empty)
- [x] Toolchain installed via Homebrew: rojo 7.7.1, stylua 2.5.2, selene 0.32.0, luau 0.741, lune 0.10.5
- [x] luau-lsp 1.70.1 installed to `~/.local/bin` (official GitHub release) for Roblox-aware type checking
- [x] Lune harness prototype verified (Rojo-built place -> Lune deserialize -> ModuleScript loading)
- [x] Roblox Studio MCP connected (Meganugger v4.0.0); root cause of earlier timeout: no plugin installed for the old server

## Phase 1 — Foundation
- [x] Rojo projects (`default.project.json`, `test.project.json`)
- [x] Tool configs (stylua, selene, .luaurc), analysis script
- [x] Shared config, types, Signal, Cleanup, Result, TableUtil
- [x] Remote registry + network contract
- [x] Server/client bootstraps

## Phase 2–4 — Gameplay core (pure, tested)
- [x] MatchStateMachine, QueueModel, RoleSelector
- [x] TerminalModel, ObjectiveTracker, ExtractionModel, MatchDirector
- [x] StatusEffects, CooldownTracker, PlacementRules, AbilityRules
- [x] RateLimiter, Validate

Status 2026-10-09: full server+client implemented; 133 Lune tests green; analyze.sh clean (stylua/selene/luau-lsp strict). Next: Studio playtest if plugin connects, docs, hardening review.

## Phase 2–4 — Roblox services
- [x] World builder (lobby + vault map) and MapValidator
- [x] Network/Security/Queue/Role/Match/Character services
- [x] Objective (terminals) + extraction binding
- [x] Ability/StatusEffect/Combat services, FreezeZone + TemporalTrap components

## Phase 5 — Persistence/economy
- [x] ProfileSchema + migrations, ProfileStore (session lock, retry), MemoryDataStore
- [x] PlayerDataService, InventoryService, RewardService (idempotent)

## Phase 6 — Client
- [x] Theme tokens, UI components
- [x] Lobby/queue, role reveal, HUD, terminal panel, ability bar, gadgets, announcements
- [x] Results, loadout/shop, settings, toasts/errors, spectate
- [x] Input (KBM/touch/gamepad), camera, effects, audio, interaction

## Phase 7–8 — Validation & docs
- [x] Unit + integration tests passing under Lune (148)
- [x] stylua --check, selene, luau-lsp analyze clean
- [x] rojo build succeeds
- [x] Studio validation via MCP: engine boot + 145 in-engine tests; solo E2E 110/110; 2-player E2E 72/72; 3-player squad E2E 26/26
- [x] Fixed (found in Studio): boot guard persisted into place (`33928e7`); CharacterAdded parenting (`a11e89f`)
- [ ] BLOCKED: real DataStore verification (needs a published test experience with API access)
- [x] Fixed (found by screenshot): results modal lingering into the next match under the objective banner; PlayerList over the squad panel
- [x] Hardening pass: deadline race, float drift at completion, profile re-lock after leave, idle lock refresh (TEST_PLAN defect log)
- [x] Squad E2E suite (3–5 players), layout lint, `tools/studio-sync.py`; [RELEASE_READINESS.md](RELEASE_READINESS.md)
- [ ] Player-perspective map review, touch + gamepad (window automation still fails: System Events lists no Studio windows)
- [ ] 4–5 player session
- [x] Docs: README, GAME_DESIGN, ARCHITECTURE, NETWORK_CONTRACT, DATA_SCHEMA, TEST_PLAN, BALANCE, BUILD_AND_RUN, RELEASE_CHECKLIST

## Next actions (if resuming)
Follow the open-issue table in [RELEASE_READINESS.md](RELEASE_READINESS.md): DataStore round trip in a
separate test experience, Device Emulator + gamepad pass, player-perspective map review, a 4–5
player session.
