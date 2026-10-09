# Data Schema and Persistence

## Profile (schema version 2) — `src/Server/Core/ProfileSchema.luau`
| Field | Type | Default | Validation |
| --- | --- | --- | --- |
| SchemaVersion | number | 2 | migrations bring older data up; newer data → not loaded |
| ChronosScrap | integer | 0 | finite, floored, clamped to [0, 1e9] |
| OwnedItems | {[itemId]=true} | default-owned items | only known ids with `true`; defaults always present |
| Equipped | {Gadget, Trail} | Stabilizer, TrailCyan | must exist, match slot, and be owned; else default |
| Stats | MatchesPlayed, Wins, Losses, TerminalsHacked, Extractions, Eliminations, KeeperMatches, InfiltratorMatches | 0 | non-negative integers |
| Settings | SfxVolume, UiVolume, MusicVolume (0–1), ReducedMotion, ShowControlHints (bool), UIScale (0.8–1.25) | 0.8, 0.7, 0.5, false, true, 1 | per-key type/range |
| RecentMatchIds | {string} | {} | ≤20 entries, ≤64 chars; reward idempotency ledger |

### Migrations
- v1 → v2: `Scrap` → `ChronosScrap`, `Volume` → `Settings.SfxVolume`, `Items` array → `OwnedItems`
  map. (v1 is the prototype format; kept as the documented migration path.)
- Data with `SchemaVersion` greater than the server's is **not** loaded or overwritten: the server
  releases its lock and the player gets an unsaved session.

## DataStore record (`ProfileStore`)
Key `Player_<userId>` in DataStore `ChronoBreakersProfiles_v1`:
`{ Data = Profile, Lock = { JobId, Time }? }` — written only via `UpdateAsync`.

| Operation | Behaviour |
| --- | --- |
| load | Atomically takes the session lock. Fresh foreign lock (<1800 s) → cancel write, back off (1, 2, 4, 8 s), retry up to 5 attempts → `Locked`. Stale lock → taken over. Errors → retried → `Error`. |
| save | Writes only if this server owns the lock (else `LockLost`, nothing written; session becomes unsaved). Autosave every 120 s if dirty; immediately after purchases/rewards (`SaveSoon`). |
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
