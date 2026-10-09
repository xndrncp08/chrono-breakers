# Network Contract

All remotes are `RemoteEvent`s created by the server under `ReplicatedStorage.Remotes` from
`src/Shared/Network/RemoteNames.luau`. Clients only wait for them. Times are
`workspace:GetServerTimeNow()` seconds. Every client→server handler is wrapped by
`NetworkService.OnRequest`: per-player token bucket (limits from `ServerConfig.RateLimits`),
error boundary, and SecurityService reporting. Extra arguments are rejected.

## Client → Server

| Remote | Payload | Validation | Rate limit (burst / per s) | Response |
| --- | --- | --- | --- | --- |
| `QueueRequest` | `action: "Join" \| "Leave"` | enum; ≤1 arg; Join requires alive + not in a match; duplicate join/leave rejected | 4 / 1 | `ActionResult{action="Queue"}`, `QueueState` to all |
| `ObjectiveRequest` | `action: "Cancel"` | enum; ≤1 arg; must currently be hacking | 4 / 2 | interruption via `TerminalUpdate`/`Notify`, or `ActionResult` reject |
| `AbilityRequest` | `abilityId: string, target: Vector3?, aim: Vector3?` | ≤3 args; id ≤32 chars & known; finite Vector3 (|coord| ≤ 100000); aim non-zero; phase Active/Extraction; participant; role; equipped gadget; alive; not stunned/held; server cooldown; ability-specific placement (range, bounds, walkable, LOS, limits, spacing) | 6 / 4 | `ActionResult{action="Ability"}` + `AbilityState`; effects via `Effect` |
| `ShopRequest` | `action: "Purchase" \| "Equip", itemId: string` | ≤2 args; enum; id ≤32 & known; not in a live match; atomic economy op on server profile | 4 / 1 | `ActionResult{action="Shop"}` + `ProfileSnapshot` |
| `SettingsUpdate` | `{ [settingKey]: value }` | plain table, no metatable, ≤8 keys, keys from `ProfileSchema.SETTINGS`, each value type/range checked (whole request rejected if any invalid) | 3 / 0.5 | `ActionResult{action="Settings"}` + `ProfileSnapshot` |
| `ClientReady` | none | 0 args | 2 / 0.2 | `MatchState`, `QueueState`, `ProfileSnapshot`, and if in a match `RoleAssigned` + `AbilityState` |
| *(ProximityPrompt)* `HackPrompt` | engine `Triggered(player)` | rate key `HackPrompt` 4 / 2; then full hack validation in `MatchDirector:requestHackStart` (phase, participant, role, alive, restrained, registered terminal, concurrency, distance ≤ 12) | — | `ActionResult{action="HackStart"}` |

Never accepted from clients: progress, rewards, currency, damage, health, roles, cooldown state,
match outcome, profile data, instance references, or remote names.

## Server → Client

| Remote | Audience | Payload (public unless noted) |
| --- | --- | --- |
| `MatchState` | all (1 Hz + on change) | `MatchSnapshot`: version, matchId, phase, phaseEndsAt, required/completed hacks, participants {userId,name,role,status}, terminals {id,name,state,progress,hackerUserId}, extractionActive, queueCount, min/max players |
| `QueueState` | each player (private) | queued, position, count, needed, minPlayers, maxPlayers, inMatch |
| `RoleAssigned` | each participant (private) | matchId, role, displayName, tagline, description, abilities[], keeperName, hasKeeper |
| `TerminalUpdate` | state changes → all; progress ticks → participants | matchId, terminal (PublicTerminal), reason? (≤4/s per terminal) |
| `AbilityState` | owner (private) | matchId, abilities[{abilityId, readyAt, cooldown, active, maxActive}] |
| `StatusUpdate` | owner (private) | `{kind="Movement", slowed, stunned, rooted, hasted, slowImmune, invulnerable, effects[{kind,expiresAt,source}]}` (sent only when it changes) or `{kind="Extraction", progress}` |
| `Notify` | targeted lists | kind (Toast/Announcement/Warning), text, severity, duration |
| `Effect` | participants or all | kind (`Protocol.EffectKinds`) + position/radius/userId/timing — cosmetic only. `TrapPlaced` goes only to the Keeper; `Reveal` only to Infiltrators |
| `MatchResult` | each participant (private) | matchId, winner, reason, yourRole, yourStatus, won, rewards[{label,amount}], rewardTotal, rewardsSaved, stats, participants |
| `ProfileSnapshot` | owner (private) | loaded, persistent, currency, owned, equipped, stats, settings |
| `ActionResult` | requester (private) | action, ok, code, message, extra fields |

Rejection codes and their player-facing text live in `src/Shared/Network/Protocol.luau`.
