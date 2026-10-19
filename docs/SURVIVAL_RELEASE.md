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

Studio validation could not run in this session: the required Studio MCP server failed to connect,
and the fallback server has no plugin (connection timeout). Studio was open on a different place.

1. In-engine E2E (`build/test.rbxl`): solo F5, 2-player and 3–5 player squad runs. The driver was
   updated for the new rules (calibration answering, four terminals, relay-gated extraction,
   strike → Fractured → erased, Mend boosts, calibration press through the remote) but has **not**
   been executed; expect first-run fixes.
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
