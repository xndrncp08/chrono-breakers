# Temporal expansion — implementation and verification

This expansion retains the original pure-core/service/controller architecture, native Roblox assets,
server-owned outcomes and dependency-free runtime. It does **not** constitute a production sign-off.
Historical Studio logs describe the earlier build, not this expansion.

## Implemented vertical slices

| Area | Shipped implementation |
| --- | --- |
| Maps | Vault plus authored Metropolis, Laboratory and Nexus layouts; participant-only ballots; rotating ties; between-match rebuilding; renewed prompts/markers; atmosphere palettes and wayfinding |
| Validation | Every spawn and terminal reachable with the gate closed; extraction sealed until open; anomaly sites away from protected areas; routes remain usable around every possible fracture |
| Classes | Five free classes, independent of Scrap/XP; fixed match loadouts; class speed/health/hack trade-offs; Veil, Overclock, Mend, Slipstream and EMP |
| Keeper | Chrono Pulse added to Strike/Freeze/Trap; 1.5-second warning, 48-stud range, sight/distance/Veil counterplay; traps disarmable by EMP; cosmetic trails/titles usable by either role |
| Hacking | One primary plus one assistant; exclusive terminal participation; assisted speed and assist credit; randomized Sequence/Cipher/Timing challenges; server nonce/time/identity checks; optional +8% progress versus −6% and a trace on failure; later objectives take longer |
| Anomalies | One event at a time: distortion, local gravity, stasis, route fracture, paired portals, rewinding sight-blocking cover, reactor damage and acceleration; 3-second warnings; synchronized deadlines; centralized expiry/phase/departure cleanup |
| Career | Schema v3, XP/levels, five class masteries and Keeper mastery, career stats, two rotating daily and two weekly contracts, automatic rewards, milestones, unlockable cosmetic titles and a violet trail |
| Team play | Contextual team-only pings, teammate health markers, class HUD identity, assistant participation, teammate-only eliminated-player spectating |
| Presentation | Deployment and career dashboards; shared glass gradients; refreshed reveal and HUD; cached rows; larger controls, touch ability grid, modal focus/input ownership, reduced-motion support; intro and safe post-extraction camera transitions |
| Security | Movement checks at gameplay boundaries and periodic sampling; illegal displacement correction; hack sight checks; match-bound abilities/cancel/challenges/pings; bounded flood telemetry/replies; per-load profile lock tokens; stale release protection; current-result reward identity guard |
| Build | Explicit production LoadStringEnabled=false; artifact verifier compiles all shipped scripts and rejects test drivers |

No new runtime dependency, uploaded asset, purchase with Robux, live experience setting change or
publication is included. Character locomotion retains Roblox's existing animation system; combat
feedback uses native geometry, highlights, camera effects and the existing verified sound manifest.
Music tracks remain unconfigured. These are not custom character animation clips or uploaded music.

## Architecture and limits

- `MatchDirector` remains the only owner of objectives, roles, extraction and results. Map preparation
  is an injected callback; a failed preparation restores the queue without consuming role fairness.
- `MapVote`, `HackChallenge`, `MovementRules`, `AnomalyModel` and `Progression` are pure rules tested
  with the existing Lune runner. Roblox services own Instances, physics, persistence and networking.
- `AnomalyService` runs from the existing match tick. Membership runs at 5 Hz against at most five
  participants; no additional Workspace scan loop. Gravity attachments, tweens, portal connections,
  temporary geometry and status keys are destroyed at event/end/phase cleanup.
- Fractures only become solid when the volume is clear. Moving rewind cover blocks queries but
  cannot collide with, crush or carry characters. Ground abilities cannot land on that hologram.
- Hacking challenges accelerate a safe timed channel. Latency-sensitive timing challenges are
  optional and use server receive time; physical-device/network playtests must assess that trade-off.
- Class/mastery/level progress never increases combat power. Titles are in-game profile cosmetics;
  no external Roblox badge provisioning is performed.
- Progression and automatic calendar rewards execute inside the existing non-yielding profile reward
  mutation after its idempotency check. No claim/reward endpoint exists. Only the director's current
  result object can enter RewardService. The persistent match ledger remains bounded at 20 ids;
  it is not an archive accepting arbitrary historical payout requests.
- Movement enforcement checks finite coordinates, bounds and displacement with prior/current speed
  tolerance. It is **not** complete server simulation or a guarantee against all physics/noclip cheats.
  Calibration under real latency, slopes, jumps, portals and low gravity is a release gate.
- Cosmetic trails remain the existing side-grade economy. Custom uploaded music/animation assets,
  ranked matchmaking and cross-server reconnect/resume are not added. A disconnect retains the
  existing authoritative departure outcome; reconnecting players receive fresh server snapshots.

## Current automated evidence

Run `./tools/test.sh`, `./tools/analyze.sh`, `rojo build default.project.json -o build/game.rbxl`,
and `lune run tools/verify-build.luau`. Exact final output is in
[`evidence/expansion-automated.txt`](evidence/expansion-automated.txt).

Coverage includes concurrent hacking and assistants, challenge replay/timing/failure, all map
contracts and fracture placements, anomaly scheduling/portal eligibility, class ownership/cooldowns,
XP/calendar rewards/migration, old-session releases, movement rejection and twenty consecutive
five-player **model** matches. These model matches do not exercise live physics or networking.

## Studio expansion suite — written, not run

1. Run `./tools/test.sh` to rebuild `build/test.rbxl`. Open that local file in Studio.
2. In **edit mode**, set the boolean attribute `ServerScriptService.Tests.RunExpansionE2E = true`.
   Keep `RunE2E = true`. Never make these changes to a published production place.
3. Test → Clients and Servers → start **five clients**. Use two clients first for a smoke run.
   Do not manually queue or move players while the driver runs.
4. The test driver equips all five classes over five rounds, votes across the four maps, exercises
   real class remotes, cooldowns, stale ids, hacking challenges/assistants, displacement correction,
   and real anomaly creation/cleanup. It uses server-only, Studio-gated anomaly fixtures to avoid
   waiting minutes for random events. It accelerates the results/return timers in this test run.
5. Save server Output and the final `[E2E] expansion: ... passed, ... failed` summary to a new
   evidence file. Inspect each FAIL; do not relabel historical logs as this run's results.
6. For the legacy solo/two-player/squad suites, remove/disable `RunExpansionE2E`. Those suites now
   explicitly vote Vault so their geometry fixtures stay deterministic; anomaly scheduling is paused
   only by the Studio test driver. Build the production project for manual gameplay afterward.

The current session could see Studio in the application inventory, but the computer-use tool returned
`Computer Use was not approved to use Roblox Studio`. No expansion engine result or screenshot
has therefore been claimed. No connected Studio execution tool was available in this session.

## Published test DataStore procedure — requires owner-managed publication

Use a **separate test universe**, never production data. Publishing is not authorized by this task.
After its owner publishes and enables the required API access:

1. Join server A. Confirm the lobby no longer says UNSAVED. Record Scrap, XP, mastery, equipped
   class/gadget/trail/title, settings and career stats. Complete a match and a contract; buy/equip a
   cosmetic and change a setting. Leave normally, join server B, and compare all recorded fields.
2. In two controlled server sessions, attempt to load the same test user while A owns its lock.
   B must refuse ownership and display the unsaved warning, without changing A's profile. After
   A leaves, a fresh session must load successfully. Do not run against another person's account.
3. Rapidly leave/rejoin on the same server and across servers while a save is delayed/throttled.
   Confirm the old lock token cannot release or overwrite the newer session. Repeat the release
   once the newer session has itself released. Use server logs and test DataStore records as evidence.
4. Migrate a test v2 record with known currency/items/stats/settings to v3; compare existing fields.
   Test future-version refusal on an isolated test key. Never deliberately corrupt production keys.
5. Trigger a duplicate current match payout in a controlled server test: currency, XP, mastery,
   contracts and unlocks must remain unchanged. Replay a stale result: no award at all.
6. Test autosave, server shutdown, API throttling and failure recovery. A lock-lost server must stop
   writing and update its UI to UNSAVED. Crash locks expire after 30 minutes; do not shorten live
   lock policy merely to speed up a test.

## Device, latency and performance acceptance

| Test | Required evidence / acceptance |
| --- | --- |
| Desktop | 1920×1080 and 1280×720; lobby, every modal, reveal, HUD/challenge, results and connection failure readable; no clipped controls |
| Mobile | Phone landscape and portrait, tablet and a physical low-end phone; touch prompts, all class/Keeper buttons, portal use, cancel/confirm, settings and challenge buttons work |
| Gamepad | Initial lobby selection, scrolling deployment/career/shop/settings, Close/B, contextual X prompts, L1 gadget, Y class skill, L2 Keeper pulse, R2 strike, R1 ping and D-pad challenge answers |
| Accessibility | Reduced motion toggled during reveal/modal/camera/effects; no stuck camera; critical rings, progress, text and sounds remain; test smallest/largest interface settings |
| Network | Five real clients, simulated latency and packet loss, co-op range/damage/restraint/departure races, late ClientReady, cooldown rejects and extraction deadline races |
| Portals/gravity | Both roles; cooldown, restraint, death and phase rejection; clear forces on leaving, death, respawn, disconnect and match resolution |
| Repeated matches | Twenty engine matches; runtime folders empty between matches, no accumulating trail attachments/markers/statuses/tweens/connections; compare client/server memory after warm-up |
| Budgets | Target 60 FPS desktop, ≥30 FPS low-end phone; server tick p95 <10 ms at five players; snapshot 1 Hz, terminal updates ≤4 Hz/terminal, anomaly membership 5 Hz; measure MicroProfiler and network stats |

These budgets are **targets**, not measured expansion results. The only older measured heartbeat and
bandwidth figures remain in the historical test evidence. Do not infer low-end mobile or five-client
performance from a passing offline test.

## Rollout and rollback

Run the release checklist, then obtain explicit owner authorization for any publication. Build only
`default.project.json` for the published artifact. Record the source commit and Roblox place version.
Start with private test servers; widen access only after the new engine/device/persistence gates pass.

Schema v3 remains in `ChronoBreakersProfiles_v1`; do not change the live store name. The previous
schema-v2 build deliberately refuses v3 records. A rollback to it therefore puts migrated players in
unsaved sessions. Prefer rolling gameplay back while retaining the v3 schema/session fencing, or
roll forward a fix. Never lower SchemaVersion or overwrite v3 with defaults. Restore a previous
Roblox place version only with that data consequence understood, and replace/drain old servers.
