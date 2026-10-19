# Test Plan and Results

## Current expansion validation

Current offline results, production artifact checks and precise unrun engine/device/persistence
procedures are in [EXPANSION_RELEASE](EXPANSION_RELEASE.md) and
[evidence/expansion-automated.txt](evidence/expansion-automated.txt). The new optional Studio suite
is selected with `ServerScriptService.Tests.RunExpansionE2E = true` before starting 2–5 clients.

Everything below is **historical baseline evidence**. It must not be presented as execution of the
new maps, classes, anomalies, progression or redesigned interfaces.

## Historical automated baseline (Lune, `./tools/test.sh`)
Last run 2026-10-09: **148 passed, 0 failed** (17 spec modules). Specs execute the real
ModuleScripts from the Rojo-built `build/test.rbxl` tree. A deliberately failing canary spec was
used once to confirm the runner reports failures with a non-zero exit code.

| Spec | Tests | Covers (brief §12.2) |
| --- | --- | --- |
| Unit/MatchStateMachine | 6 | legal cycle, illegal transition rejection, bounded history |
| Unit/QueueModel | 7 | join/duplicate, cancel, disconnect removal, FIFO cap, ineligible drop, restore |
| Unit/RoleSelector | 6 | exactly one Keeper, fairness/rotation, tie-break, Studio solo |
| Unit/TerminalModel | 9 | start validation, server-time progress, completion once, concurrency, interruption + lockout, retained progress, locking |
| Unit/ObjectiveAndExtraction | 7 | completion dedup, threshold once, forged ids, extraction activation/channel/once/expiry |
| Unit/StatusEffects | 8 | baseline restore, overlap (strongest), independent expiry, haste×slow, stun/root/immunity, cleanse, hostile magnitudes |
| Unit/Security | 7 | Validate guards (NaN/inf/oversized/forged tables/arg counts), token bucket, cooldowns |
| Unit/PlacementAndAbility | 16 | range, bounds, mid-air, walls, LOS, spacing; role/phase/alive/restrained/cooldown/gadget checks; strike targeting |
| Unit/ProfileSchema | 7 | defaults, v1→v2 migration, future-version refusal, sanitisation |
| Unit/EconomyAndRewards | 11 | non-negative currency, atomic purchase, equip rules, reward calc, idempotent ledger |
| Unit/ProfileStore | 9 | session lock, release, foreign lock backoff, stale takeover, retries, LockLost, future schema, **late autosave never re-locks a released profile** |
| Unit/MapValidator | 5 | authored map passes contract; detects sealed objectives, embedded spawns, bad ids |
| Unit/SignalAndCleanup | 7 | signal semantics, cleanup order, post-destroy adds, thread cancel, truncation |
| Unit/ConfigConsistency | 5 | remote registry uniqueness, messages for codes, brief defaults, ability/item links |
| Unit/Components | 6 | FreezeZone telegraph/membership/re-entry/expiry cleanup; TemporalTrap arming/single trigger/expiry |
| Integration/MatchLifecycle | 20 | **late tick after the deadline does not count hack progress; a hack finishing exactly at the deadline opens extraction**, threshold, intermission fallback, max players, full Infiltrator win, timeout, all eliminated, extraction failed, partial extract, duplicate events, Keeper leave, intro abort, everyone leaves, **4 repeated matches without leaks**, Keeper rotation, Studio solo on/off |
| Integration/Hacking | 12 | wrong phase/role/target/range/NaN, dead/restrained, concurrency, out-of-range interrupt, damage/death/disconnect interrupts, resume by teammate, dedup, throttled progress, lock on resolve, extraction gating |

## Static analysis (`./tools/analyze.sh`)
Last run 2026-10-09: StyLua check clean, Selene 0 errors / 0 warnings, luau-lsp strict analysis
with Roblox definitions: 0 errors across `src/` (server, client, tests).

## Build
`rojo build default.project.json` and `rojo build test.project.json` succeed (Rojo 7.7.1).

## Roblox Studio validation (2026-10-09, Studio 0.742, via Meganugger Roblox Studio MCP)

Setup and the earlier timeout are documented in [BUILD_AND_RUN.md](BUILD_AND_RUN.md#roblox-studio-mcp).
Raw logs for every run are in [`docs/evidence/`](evidence/). Status legend: **Passed** (executed,
evidence attached) · **Failed** · **Blocked** (cannot run in this environment; reason given) ·
**Not run** (could run, not yet executed).

### Engine-level checks
| Check | Status | Evidence |
| --- | --- | --- |
| MCP connected to the real Studio session | Passed | `get_studio_status` (edit peer `test.rbxl`), `ping_studio` 16 ms, `get_project_info`, `run_luau` hierarchy probe |
| Place matches the Rojo build | Passed | 100 scripts in Studio = 100 `.luau` files in `src/`; all expected modules at their Rojo paths |
| All scripts compile in Studio | Passed | `analyze_scripts`: 100 analysed, 0 problems |
| Server boots in the engine | Passed | Run mode output: `[Bootstrap] Chrono Breakers server ready (12 services, 39 ms)`; `get_errors` count 0 |
| Unit + integration suite inside the engine | Passed | `[Tests] 145 passed, 0 failed` (Run mode and every Play session) |
| World built correctly | Passed | 91 static parts, 3 terminals (Locked, prompts off), 17 remotes, gate closed |
| Server boots again after a Run session | **Failed → fixed → Passed** | Defect: boot guard persisted as an attribute (`server already booted`). Fix `33928e7`; two consecutive Run sessions both booted |

### Solo Play suite (E2E driver, one player, keeperless Studio match) — 110 / 110
Evidence: `evidence/studio-e2e-solo-run5.txt` (run 5 adds layout lint and death-while-slowed; run 4,
104/104: `evidence/studio-e2e-solo-run4.txt`, after the UI layering fixes; run 2 was
102/102 before the two UI checks were added: `evidence/studio-e2e-solo-run2.txt`). Run 1 before the character fix: 89 passed, 13 failed
(`evidence/studio-e2e-solo-run1-before-fix.txt`). Run 3 was invalidated by a manual Join Queue click
(`evidence/studio-e2e-solo-run3-manual-input.txt`); the driver now aborts in that case.

| Area | Status | What was verified in the engine |
| --- | --- | --- |
| Character spawn + init | **Failed → fixed → Passed** | Defect: `CharacterAdded` fires before parenting; setup returned early (no role spawn, baseline, trail, or Died hook). Fix `a11e89f` |
| Lobby | Passed | Lobby spawn, speed 16, Health regen replaced, client connected, lobby UI shown, profile received |
| Queue | Passed | Join accepted, duplicate → AlreadyQueued, bad action → InvalidPayload, queue state mirrored |
| Intro / role reveal | Passed | Infiltrator spawn, held at speed 0, role reveal visible, role = Infiltrator |
| Active | Passed | Speed restored, spawn protection, terminals Available, HUD shown, 1 gadget slot |
| Server authority | Passed | WrongRole, NaN target, extra args, unequipped gadget, shop locked in match, server-measured range, forged terminal id |
| Rate limiting | Passed | 20-request burst produced RateLimited |
| Gadget (Stabilizer) | Passed | Accepted, immunity applied, OnCooldown, cooldown mirrored to client |
| Time-Freeze component on a real Humanoid | Passed | No slow during telegraph, 16→4.8, two overlapping zones don't stack, back to exactly 16 |
| Hacking via real ProximityPrompt | Passed | Hack starts, hack panel visible, leaving range interrupts, ~33% progress retained, lockout, resume |
| Temporal Trap component | Passed | Trigger → speed 0 → hack interrupted (Restrained) → 9.6 → 16 |
| Placement vs. real geometry | Passed | Floor OK; behind Chrono Core / through partition → NoLineOfSight; off-map → OutOfBounds; mid-air; beyond range |
| Three terminals → extraction | Passed | All complete, Extraction phase, gate non-colliding |
| Extraction + results + rewards | Passed | Extracted, Infiltrators win, results UI, payout 155, profile credited once, duplicate grant ignored |
| Cleanup / repeated match | Passed | Session cleared, stale id rejected, runtime empty, terminals Locked, gate closed, lobby UI back |
| Match 2: death → elimination | Passed | AllEliminated, defeat result on client, +20 separately, lobby respawn, no lingering effects |

### Multiplayer suite (Test → Clients and Servers, 2 players) — 72 / 72
Evidence: `evidence/studio-e2e-multiplayer-run2.txt` (run 2 adds a live zone + trap at resolution;
run 1, 69/69: `evidence/studio-e2e-multiplayer.txt`).

| Area | Status | What was verified in the engine |
| --- | --- | --- |
| Shop via remotes | Passed | Purchase deducts 250 once, AlreadyOwned, InsufficientFunds with no charge, equip, loadout mirrored |
| Two-player minimum | Passed | One queued player waits; second join → Intermission → Intro |
| Role assignment | Passed | Exactly one Keeper; Keeper in Sanctum, Infiltrator in Spawn Bay; each client's reveal shows its own role |
| Keeper release hold | Passed | Keeper 0 speed and abilities → Restrained; released at 17 after 10 s; Infiltrator protected |
| Replication | Passed | Both clients see both participants; Keeper client sees the terminal being hacked |
| Echo Scanner | Passed | Accepted; Keeper marked Revealed; unequipped Stabilizer rejected (loadout locked) |
| Time-Freeze via remote | Passed | OutOfRange, NoLineOfSight, valid cast, slow to 4.8, client slowed, OnCooldown, leave → 16, expiry cleanup |
| Temporal Trap via remote | Passed | Placed, second → OnCooldown, arming, stun to 0, consumed, back to 16 |
| Chrono Strike via remote | Passed | 34 damage, interrupts hack, cooldown, 3 strikes eliminate, credit to Keeper |
| Results for both players | Passed | Keeper win 90, Infiltrator defeat 20, both clients received results, runtime emptied |
| Disconnect during hacking | Passed | Hack interrupted, InfiltratorsLeft, leaver ineligible, Keeper paid 70, lifecycle recovers |
| Match ending with a live zone + trap | Passed | Keeper casts a Time-Freeze and an armed trap, the Infiltrator leaves → resolution destroys both, runtime folder empty |

### Squad suite (Test → Clients and Servers, 3 players) — 26 / 26
Evidence: `evidence/studio-e2e-squad-3p-run1.txt`. Selected automatically for 3–5 players.

| Area | Status | What was verified in the engine |
| --- | --- | --- |
| Role assignment (3 players) | Passed | Exactly one Keeper, two Infiltrators; every client mirrors its own role and shows the HUD |
| Simultaneous hacks | Passed | Archive and Reactor hacked at the same time via real prompts |
| One terminal per hacker | Passed | Second `RequestHack` while hacking → AlreadyHacking |
| One hacker per terminal | Not run | Needs a third Infiltrator (4+ players) |
| Teammate resume | Passed | Archive resumed from 33 %, Observatory from 20 % by the other Infiltrator |
| Disconnect mid-hack (match continues) | Passed | Leaver's hack interrupted, status Disconnected, phase stays Active |
| Extraction win with 3 players | Passed | All terminals → Extraction → extracted → Infiltrators win; leaver ineligible |
| Reward consistency | Passed | Every remaining client received the same matchId, total = `RewardCalculator`, profile credited exactly that amount |
| Keeper rotation | Passed | Next match's Keeper differs from the previous Keeper |
| Keeper leaves | Passed | KeeperLeft → Infiltrators win; lifecycle recovers; no lingering status effects |

### Remaining matrix (brief §12.3)
| Scenario | Status | Reason / evidence |
| --- | --- | --- |
| Keeper win after timeout | Not run in Studio | 10-minute timer; covered by Lune `TimeExpired` test |
| Disconnect during extraction | Not run in Studio | Covered by Lune Hacking extraction/disconnect test |
| Death while a slow is active | Passed | Solo run 5: 30 s slow at 4.8 → death → lobby respawn at exactly 16 (`evidence/studio-e2e-solo-run5.txt`) |
| Match ending with an active zone/trap | Passed | Multiplayer run 2 (see above) |
| 3–5 player matches | Partly passed | 3 players: squad suite 26/26. 4–5 players not run (Studio client count) |
| DataStore load/save/retry on Roblox servers | **Blocked** | Needs a separate **published test experience** with Studio API access enabled (no production data at risk); unpublished Studio uses the in-memory fallback (observed warning) |
| Real keyboard/mouse key presses | **Blocked** | Inputs were driven by remotes and `ProximityPrompt:InputHoldBegin`; MCP keystroke simulation needs macOS Accessibility for VS Code |
| Layout lint at the Studio viewport | Passed | Solo run 5: lobby, HUD, HUD while hacking, results have no clipped text or off-screen elements (`E2EClient` `lintLayout`) |
| Touch layout / gamepad navigation | **Blocked** | Needs Studio Device Emulator, which needs window automation (System Events lists no Studio windows) or a manual pass |
| Visual review of UI (results/lobby) | **Failed → fixed → Passed** | Full-screen capture (`capture_studio_screenshot fullScreen=true`) showed the previous match's results still open in the next match with the "Breach the vault" banner drawn over its title bar and Close button, and the Roblox PlayerList covering the Squad Status panel (`evidence/ui-results-banner-overlap-before.png`). Fixes: results close when a new match's role arrives; banner ZIndex 15 (beneath modals); core PlayerList disabled. Verified by 2 new E2E checks (run 4) and `evidence/ui-results-lobby-after.png` |
| Visual review of HUD, map, other screens | Not run | Full-screen capture works; window capture and resolution switching still need window automation |
| Reset button disabled in match | Not run | Client-side `SetCore` call; not observable from the server and no client MCP peer registered |
| Missing optional assets | Not run | Audio fallback by code review only |

### Defects found and fixed (2026-10-09 hardening pass)
| Defect | Repro | Root cause | Fix | Regression test |
| --- | --- | --- | --- | --- |
| Results modal lingers into the next match, objective banner drawn over it | Don't press Continue; next match starts | Results never closed on a new match; banner ZIndex 30 > modal 20 | `ResultsScreen` closes when a role for another matchId arrives; banner ZIndex 15 | E2E "match 1 results closed once match 2 role arrived" |
| Roblox PlayerList covers the Squad Status panel / lobby menu | Any multi-player session | Core PlayerList left enabled in the top-right corner | `UIController` disables it (no leaderstats; People tab still in the Roblox menu) | E2E "core PlayerList hidden" |
| Hack progress after the match timer could open extraction | Final hack would finish 0.5 s after the deadline; next tick arrives 1 s late (server hitch) | `processTerminals` advanced with the late `now` before the deadline check | Terminal processing clamps `now` to the deadline while Active | Lune "does not count hack progress earned after the timer expired" |
| A hack finishing exactly at the deadline could miss by float drift | 0.1 s ticks sum to 0.9999999 | Exact `progress >= 1` comparison | 1e-6 completion tolerance | Lune "opens extraction when the final hack completes exactly at the deadline" |
| Profile re-locked after the player left | Autosave in flight when the player leaves; release commits first | Non-release saves re-acquired a missing lock; release didn't wait for the in-flight save | Normal saves require our own lock (else LockLost); release waits for in-flight saves | Lune "does not re-acquire a released lock on a late non-release save" |
| Session lock of an idle player goes stale after 30 min | Player idles with no profile changes | Lock refreshed only by dirty saves | Autosave also saves clean sessions older than LockTimeout/2 | Code review (timing-based; not unit tested) |

### MCP limitations observed
- `start_play_solo` / `stop_play_solo` and window capture fail with "No Roblox Studio window was
  found": System Events lists the Studio processes but zero windows, so Play was pressed manually.
  `capture_studio_screenshot fullScreen=true` works.
- Logs of finished play sessions are not kept by the MCP server; Studio's own log files in
  `~/Library/Logs/Roblox/*_last.log` contain the `[E2E]` lines.
- No **client** peer registered in Play or multi-client sessions, so client state was observed through
  the in-game E2E client agent instead of `eval_client_runtime`.
- `eval_server_runtime` requires `ServerScriptService.LoadStringEnabled`; enabled in `test.project.json`
  only (production place verified `false`). Code evaluated through the plugin gets separate module
  instances from the game's, so live service state is observed by the in-game driver.

### How to rerun
Build `rojo build test.project.json -o build/test.rbxl`, open it in Studio. Solo: F5 and don't touch
anything. Multiplayer: Test → Clients and Servers → 2 players → Start. Squad: same with 3–5 players. Read `[E2E] … passed, … failed`
from Output (or `get_output_logs peer=server` via MCP).
