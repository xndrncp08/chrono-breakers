# Data Schema and Persistence

## Profile (schema version 4) — `src/Server/Core/ProfileSchema.luau`
| Field | Type | Default | Validation |
| --- | --- | --- | --- |
| SchemaVersion | number | 4 | migrations bring older data up; newer data → not loaded |
| ChronosScrap | integer | 0 | finite, floored, clamped to [0, 1e9] |
| OwnedItems | {[itemId]=true} | default-owned items | only known ids with `true`; defaults always present |
| Equipped | {Gadget, Trail, Class, Title} | Stabilizer, TrailCyan, Ghost, TitleRookie | must exist, match slot, and be owned; else default |
| Stats | HackAssists, KeeperWins, MatchesPlayed, Wins, Losses, TerminalsHacked, Extractions, Eliminations, KeeperMatches, InfiltratorMatches, Rescues, Resyncs, Patches, Containments, Downs, GreatCalibrations | 0 | non-negative integers |
| Perks | {[classId \| "TimeKeeper"] = {perkId}} | {} | known loadout keys only; ≤2 unique known perks; each must be unlocked (level or mastery, judged after progression is reconciled) and match the loadout's role/class |
| Settings | SfxVolume, UiVolume, MusicVolume (0–1), ReducedMotion, ShowControlHints (bool), UIScale (0.8–1.25) | 0.8, 0.7, 0.5, false, true, 1 | per-key type/range |
| RecentMatchIds | {string} | {} | ≤20 entries, ≤64 chars; reward idempotency ledger |

`Progression = {XP, Mastery, Milestones, Daily, Weekly}`. XP and known mastery ids are clamped to
[0,1e9]. Daily/Weekly each hold `{Period, Progress, Claimed}` with only known contract ids and
progress capped at targets. Periods use UTC days and Monday-based UTC weeks. Two rotating
contracts per period auto-award at eligible match resolution; clocks moving backward cannot
reopen an old period. Milestones grant only configured cosmetic items.

### Migrations
- v1 → v2: `Scrap` → `ChronosScrap`, `Volume` → `Settings.SfxVolume`, `Items` array → `OwnedItems`
  map. (v1 is the prototype format; kept as the documented migration path.)
- v2 → v3: additive defaults for classes/titles and progression; existing balance/items/stats/settings preserved.
- v3 → v4: additive `Perks` loadouts and survival stats; everything else preserved. Deploy all
  servers together: a v3 server treats a v4 profile as a future version (unsaved session).
- Data with `SchemaVersion` greater than the server's is **not** loaded or overwritten: the server
  releases its lock and the player gets an unsaved session.

## DataStore record (`ProfileStore`)
Key `Player_<userId>` in DataStore `ChronoBreakersProfiles_v1`:
`{ Data = Profile, Lock = { JobId, Token, Time }? }` — written only via `UpdateAsync`.

| Operation | Behaviour |
| --- | --- |
| load | Atomically takes the session lock. Fresh foreign lock (<1800 s) → cancel write, back off (1, 2, 4, 8 s), retry up to 5 attempts → `Locked`. Stale lock → taken over. Errors → retried → `Error`. |
| save | Writes only if this exact load token owns the lock (else `LockLost`, nothing written; session becomes unsaved). Autosave every 120 s if dirty; immediately after purchases/rewards (`SaveSoon`). |
| release | On leave and in `BindToClose` (bounded 25 s): save with lock cleared. A player who leaves mid-load has the lock released immediately. |

Failure policy: if a profile cannot be loaded the player still plays with defaults in an
**unsaved session**; the lobby and results screens say so. Profile contents are never logged.

## Economy invariants (tested)
- Currency never negative; grants are positive whole numbers; total capped.
- Purchases validate item, ownership, and funds before mutating; failures consume nothing.
- Rewards are computed server-side from the authoritative result and applied once per match id
  (profile `RecentMatchIds` + RewardService in-memory ledger). Disconnected participants and
  aborted matches receive nothing.
- No developer products or game passes exist yet, so no receipt processing is implemented.

## Studio
Without published-place API access, Studio uses `MemoryDataStore` (logged warning); nothing persists.
Live DataStore behaviour has **not** been verified in a published experience.

A missing lock rejects data writes even for a late release. Sessions keep their own token across
save/release retries, preventing same-server rejoin races. Studio's in-memory fallback is explicitly
reported non-persistent. Gameplay rollback to a v2 build makes v3 profiles unsaved; retain v3 schema
support when rolling gameplay back. See [EXPANSION_RELEASE](EXPANSION_RELEASE.md).
