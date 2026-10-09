# Test Plan and Results

## Automated (Lune, `./tools/test.sh`)
Last run 2026-10-09: **145 passed, 0 failed** (17 spec modules). Specs execute the real
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
| Unit/ProfileStore | 8 | session lock, release, foreign lock backoff, stale takeover, retries, LockLost, future schema |
| Unit/MapValidator | 5 | authored map passes contract; detects sealed objectives, embedded spawns, bad ids |
| Unit/SignalAndCleanup | 7 | signal semantics, cleanup order, post-destroy adds, thread cancel, truncation |
| Unit/ConfigConsistency | 5 | remote registry uniqueness, messages for codes, brief defaults, ability/item links |
| Unit/Components | 6 | FreezeZone telegraph/membership/re-entry/expiry cleanup; TemporalTrap arming/single trigger/expiry |
| Integration/MatchLifecycle | 18 | threshold, intermission fallback, max players, full Infiltrator win, timeout, all eliminated, extraction failed, partial extract, duplicate events, Keeper leave, intro abort, everyone leaves, **4 repeated matches without leaks**, Keeper rotation, Studio solo on/off |
| Integration/Hacking | 12 | wrong phase/role/target/range/NaN, dead/restrained, concurrency, out-of-range interrupt, damage/death/disconnect interrupts, resume by teammate, dedup, throttled progress, lock on resolve, extraction gating |

## Static analysis (`./tools/analyze.sh`)
Last run 2026-10-09: StyLua check clean, Selene 0 errors / 0 warnings, luau-lsp strict analysis
with Roblox definitions: 0 errors across `src/` (server, client, tests).

## Build
`rojo build default.project.json` and `rojo build test.project.json` succeed (Rojo 7.7.1).

## Not covered by automation (needs the Roblox engine)
Humanoid movement application, raycast placement against real geometry, ProximityPrompt input,
remote delivery, character spawning, UI layout/rendering, DataStore service behaviour.

## Integration / manual matrix (brief §12.3)
The Roblox Studio MCP plugin never connected during this session (Studio was running and the
place was opened, but the plugin reported "connection timeout"), so **no Studio scenario has
been executed**. Logic-level equivalents run in Lune are noted.

| Scenario | Studio result | Logic-level evidence |
| --- | --- | --- |
| One-player lobby behaviour | Not run (no Studio session) | QueueModel / MatchLifecycle threshold tests |
| Minimum-player threshold | Not run | MatchLifecycle "waits for the minimum…" |
| Full match role assignment | Not run | RoleSelector + MatchLifecycle max-players |
| Successful Infiltrator extraction | Not run | MatchLifecycle complete victory |
| Keeper win after timeout | Not run | MatchLifecycle TimeExpired |
| All Infiltrators eliminated | Not run | MatchLifecycle AllEliminated |
| Disconnect during hacking | Not run | Hacking "interrupts on … disconnect" |
| Disconnect during extraction | Not run | Hacking extraction/disconnect test |
| Death during an active effect | Not run | StatusEffectService clears on Died (code review only) |
| Match ending with timer/trap active | Not run | Hacking "locks all terminals…"; AbilityService.EndMatch (code review) |
| Persistence unavailable/failing | Not run | ProfileStore Error/Locked tests; unsaved-session path (code review) |
| PC keyboard/mouse | Not run | — |
| Mobile layout/touch | Not run | — |
| Gamepad navigation | Not run | — |
| Missing optional assets | Not run | AudioController skips nil ids (code review) |
| Multiple matches in one server | Not run | MatchLifecycle repeated-matches test |

To execute: open `build/test.rbxl` (Output shows `[Tests] …` from the in-Studio runner), then
Test → Clients and Servers with 2–5 players and walk the table above, recording results here.
