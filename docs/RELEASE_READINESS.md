# Release Readiness (2026-10-09)

**Verdict: ready for a controlled test release in a separate test experience; not yet ready for a
broad public release.** Core gameplay, server authority, lifecycle and cleanup are verified in the
Roblox engine with 1, 2 and 3 players. Real DataStore persistence, touch/gamepad input and a
player-perspective visual review of the map have not been verified; publishing has not been
authorised. Evidence for every claim is in [TEST_PLAN.md](TEST_PLAN.md) and [`evidence/`](evidence/).

## Gate status
| Gate | Status | Evidence / what is missing |
| --- | --- | --- |
| A — Automated integrity | **Passed** | `./tools/test.sh` 148/148, `./tools/analyze.sh` clean, both Rojo builds succeed |
| B — Studio integration | **Passed** | Meganugger Studio MCP connected to `test.rbxl`; hierarchy inspected; script sync verified (103 scripts identical); runtime output read per session. Limitation: Studio windows are invisible to macOS automation, so Play/Stop are manual |
| C — Core gameplay | **Passed** | Solo 110/110 (twice), 2-player 72/72, 3-player 26/26: queue → roles → abilities → hacking → extraction/defeat → results → cleanup → next match |
| D — Security and data | **Partly passed** | Server-authority and exploit paths verified live; reward/purchase integrity verified live (in-memory store). **Blocked:** real DataStore round trip, needs a published test experience with API access |
| E — Player experience | **Partly passed** | UI layout lint clean on lobby, HUD, hack panel, results; two UI defects found by screenshot and fixed. **Not run:** player-height map review, Device Emulator (phone), gamepad navigation, real key presses |
| F — Release preparation | **Passed (pending approval)** | This document, [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md), [BUILD_AND_RUN.md](BUILD_AND_RUN.md); runbook and rollback below. Publishing needs explicit owner approval |

## Open issues (prioritised)
| # | Priority | Issue | Next step |
| --- | --- | --- | --- |
| 1 | P1 | DataStore load/save/session-lock not verified on Roblox servers | Publish to a **separate test experience**, enable Studio API access, run the round trip below |
| 2 | P1 | Touch and gamepad not verified | Device Emulator pass (phone landscape, tablet) + a real gamepad; record in TEST_PLAN |
| 3 | P1 | Map not reviewed from the player's perspective | Walk each route in Play; screenshots of terminals, gate, Sanctum, Spawn Bay |
| 4 | P2 | 4–5 player sessions not run ("one hacker per terminal" live check needs 4+) | Clients and Servers with 4–5 players; the squad suite runs automatically |
| 5 | P2 | Keeper win on the 10-minute timer not run live | Lune-tested (incl. the deadline race); optionally a Studio run with a shortened duration |
| 6 | P2 | Reset-button disable and audio fallback verified by code review only | Manual check during the Device Emulator pass |
| 7 | P3 | Studio automation: `start_play_solo`, window capture and shortcuts fail ("No Roblox Studio window was found") | Grant Accessibility to the MCP host app and restart it; until then press Play manually |

## Security audit summary
- Every client→server remote (`QueueRequest`, `ObjectiveRequest`, `AbilityRequest`, `ShopRequest`,
  `SettingsUpdate`, `ClientReady`) goes through `NetworkService.OnRequest`: per-player token-bucket
  rate limit, exact argument counts, type/enum/size validation, errors contained.
- Abilities check role, match membership, phase, alive, restrained, cooldown and equipped gadget
  before casting; placement re-checks range, bounds, ground and line of sight on the server.
- Hacking is server-timed; prompts are only requests. One hacker per terminal, one terminal per
  hacker, interrupts on range/damage/death/restraint/disconnect; progress after the match deadline
  no longer counts (fixed this pass).
- Purchases are atomic through `PlayerDataService.Mutate`; rewards are idempotent per match and player
  (in-memory guard + profile ledger). Clients never send currency, roles or results.
- Persistence: a profile is never written without holding its session lock; a late autosave can no
  longer re-lock a released profile (fixed this pass); failed loads give an unsaved session, never
  defaults written over real data.
- Not verified: behaviour under real DataStore throttling; `KickOnFlood` deliberately off (reject + log).

## Performance summary
Measured in Studio on the development Mac (2026-10-09, solo, server peer):
- Server heartbeat: mean 16.6 ms, p99 17.5 ms, max 17.8 ms in the lobby and in an active match (no
  hitches); server send ≈ 1 KB/s in a solo match.
- By design: all loops bounded (10 Hz director tick, 10 Hz status pruning, zone membership every
  0.2 s against ≤ 4 Infiltrators, no Workspace scans); terminal progress broadcasts throttled.
- Not measured: live servers, 5-player load, low-end mobile client frame rate. Studio memory numbers
  include Studio itself and are not meaningful.

## Deployment runbook
1. Clean checkout of `main`; `./tools/test.sh && ./tools/analyze.sh` must both pass.
2. `rojo build default.project.json -o build/game.rbxl`. Never publish `test.project.json` output:
   it contains the E2E driver/agent and enables `LoadStringEnabled`.
3. Open `build/game.rbxl` and confirm: no `ServerScriptService.Tests`, no `E2EClient`,
   `ServerScriptService.LoadStringEnabled = false`.
4. **Test experience first** (separate universe): File → Publish to Roblox as a new experience;
   Game Settings → Security → enable Studio Access to API Services; max players 5.
5. DataStore round trip there: join, earn Scrap, buy/equip an item, change a setting, leave, rejoin
   from another server → everything kept; join from two servers at once → second gets the unsaved
   notice; Output shows no `[ProfileStore]` errors.
6. Run a 2–5 player private-server match end to end (queue → results), on PC, phone and gamepad.
7. With explicit owner approval only: publish to the production experience, note the place version
   number, then follow [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

## Rollback and recovery
- **Code rollback:** Creator Dashboard → the place → Version History → restore the previous version,
  then "Shut down all servers" (or migrate to latest update) so players land on it.
- **Data:** profiles live in `ChronoBreakersProfiles_v1`, schema v2. Migrations are forward-only and
  older code refuses a newer schema (`FutureVersion`) instead of overwriting it, so a rollback across
  a schema bump leaves those players in unsaved sessions until the newer code returns. Don't ship a
  schema bump together with risky gameplay changes.
- **Server shutdown:** `BindToClose` saves and releases every loaded profile (25 s budget). Locks left
  by a crashed server count as stale after 30 minutes; affected players play unsaved until then.
- **Incident signals:** `[PlayerDataService] save … returned`, `[ProfileStore] … failed`,
  `[MatchService] director tick failed`, `[NetworkService] handler … errored` in server logs.
