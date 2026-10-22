# Survival Protocol — implementation and release status

Design: [SURVIVAL_DESIGN](SURVIVAL_DESIGN.md). Every tunable: `src/Shared/Config/SurvivalConfig.luau`
and `PerkConfig.luau`. Nothing has been published.

## Milestones

| Milestone | Branch | What landed |
| --- | --- | --- |
| Server foundation | `feat/survival-core` | Integrity ladder, Stasis Pods and stages, rescues with Endurance, anti-camp feedback, bleed-out, no-free-survivor resolution, calibration pulses, three-hacker co-op, squad scaling, Overload, gate relays, Temporal Collapse, Slip Rift (`MatchDirector`, `SurvivalModel`, `EndgameModel`, `HackChallenge`, `TerminalModel`); maps with five terminals, pods, relays, lockers, rails, barriers, doors and loop gyms (`MapLayout`, `MapValidator`, `MatchWorldBuilder`); `SurvivalService`, `InteractionService` (`WorldObjects`), `HuntService` (`ChaseModel`, `StaminaModel`); strike wind-up/recoil/escape burst and freeze combo |
| Progression | `feat/survival-progression` | Perk loadouts (2 per class + Keeper) unlocked only by level/mastery, `PerkService` modifiers, schema v4 migration, survival stats, rewards, contracts, mastery titles and trails |
| Presentation | `feat/survival-presentation` | Survival HUD (squad cards, Collapse panel, calibration ring, channel bar, stamina, Endurance, momentum), Resonance heartbeat and vignette, dynamic music layers, chase distortion, Keeper residue, Fractured cues, spatial audio, darker lighting with haze and flickering fixtures, procedural poses, prompt filtering, sprint/calibration on all devices, perk UI, survival results, outcome cinematics; E2E driver updated |

All merged into `integration/survival-protocol`, then `main`.

### Survival Evolution (2026-10-22)

| Milestone | Branch | What landed |
| --- | --- | --- |
| Chase fairness | `feat/chase-fairness` | Lag-compensated Chrono Strike (`PositionHistory`, bounded rewind, line of sight and range judged at the current position), off-screen threat chevron, **Afterimage** decoy gadget |
| Balance telemetry | `feat/balance-telemetry`, `feat/telemetry-conditions` | `MatchTelemetry` anonymous per-match summaries, rolling aggregate, AnalyticsService headline events, target bands and ten repeatable scenarios in BALANCE.md |
| Replayability | `feat/timeline-conditions` | Six weighted, two-sided Timeline Conditions applied through perk modifier keys; shown on deployment and HUD |
| Onboarding | `feat/field-guide` | Field Guide coaching cards for each role's first three matches |
| Runtime validation | `fix/e2e-survival-expectations`, `test/afterimage-e2e` | First in-engine run of the survival build; toast-stack and marker fixes; harden and extend the E2E suites |

Merged into `integration/survival-evolution`, then `main`. In-engine results:
[TEST_PLAN](TEST_PLAN.md#survival-evolution-validation-current-2026-10-22).

## Verified (offline, this build)

Evidence: [evidence/survival-automated.txt](evidence/survival-automated.txt).

* Lune: **215 passed, 0 failed** (29 spec modules) — 41 new or rewritten tests: integrity ladder,
  pooled re-sync/patch, Phase-Lock range/role/interrupts, rescue + Endurance, pod expiry and
  camping release, bleed-out, no-free resolution, Slip Rift escape and seal, relay-gated pad,
  collapse erasure, Overload regression, three-hacker co-op, calibration grading/latency/replay,
  chase/momentum, stamina exhaustion, world objects (fatigue, barriers, doors, lockers, landings),
  map furniture validation on all four maps, perk unlocks/loadouts/migration/modifiers, survival
  rewards and mastery cosmetics, pursuit speed-ladder invariants.
* Static: StyLua, Selene (0/0), luau-lsp strict analysis clean.
* Production build: 109 scripts compile, test code absent, `LoadStringEnabled=false`.

## Not verified — release gates

1. ~~In-engine E2E~~ — **done 2026-10-22**: solo 120/120, 2-player 81/81, 5-player 36/36 (see
   TEST_PLAN). Latency play (BALANCE scenario S3) is still open.
2. Runtime behaviour that only the engine exercises: anchored vault arcs and landing feel, barrier
   push-out, locker hide/search, pod holds, prompt filtering by local activation distance,
   procedural root-joint poses on R15 and R6 avatars, heartbeat timing, residue counts.
3. Balance playtests with 1v4 lobbies: hack time (40 s solo at four Infiltrators), collapse length,
   pod stage timers, momentum cap, rail fatigue, barrier counts per map.
4. Device passes: touch (sprint button, ring tap, prompt density), gamepad (L3 sprint, A on pulses),
   small screens (compact squad cards).
5. Audio: music layers have no verified asset ids (silent until ids are supplied in
   `AssetManifest`); one-shots use the engine's built-in sounds only.
6. Real DataStore round trip of schema v4 (forward-only migration; v3 servers will refuse v4
   profiles as `FutureVersion`, so deploy all servers together).

## Known limitations

* Shift is also Roblox's optional Shift Lock key; players using Shift Lock should sprint with L3 or
  rebind via Roblox settings.
* A Keeper client can read every character position (Roblox replication), so hiding and residue are
  presentation-level information, not secrets; strikes and scans exclude hidden players on the server.
* Pod and locker holds anchor the root; a disconnect mid-hold is cleaned up by `PlayerRemoving`.
