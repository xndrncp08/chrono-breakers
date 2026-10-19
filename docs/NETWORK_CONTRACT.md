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
| `ObjectiveRequest` | `action: "Cancel", matchId: string` | enum; ≤2 args; current match id; must currently be hacking | 4 / 2 | interruption via `TerminalUpdate`/`Notify`, or `ActionResult` reject |
| `AbilityRequest` | `abilityId: string, target: Vector3?, aim: Vector3?, matchId: string` | ≤4 args; current match id ≤64 chars; id ≤32 chars & known; finite Vector3 (|coord| ≤ 100000); aim non-zero; phase Active/Extraction; participant; role; equipped gadget; alive; not stunned/held; server cooldown; ability-specific placement (range, bounds, walkable, LOS, limits, spacing) | 6 / 4 | `ActionResult{action="Ability"}` + `AbilityState`; effects via `Effect` |
| `ShopRequest` | `action: "Purchase" \| "Equip" \| "TogglePerk", itemId: string` | ≤2 args; enum; id ≤32 & known item (or perk for TogglePerk); not in a live match; atomic economy op; perks must be unlocked by level/mastery and fit the 2-slot loadout | 4 / 1 | `ActionResult{action="Shop"}` + `ProfileSnapshot` |
| `SprintRequest` | `wanted: boolean` | ≤1 arg; boolean; only an intent — `StaminaModel` sprints only a free, visible, unrestrained, moving Infiltrator with stamina | 10 / 5 | `StatusUpdate{kind="Stamina"}` |
| `HackChallengeRequest` | `matchId, terminalId, nonce: integer, pressTime: number` | ≤4 args; current match; caller is a hacker of that terminal with a pending pulse; nonce one-use; press time bounded to 0.35 s before arrival (else arrival time is used) | 3 / 1 | `ActionResult{action="Challenge"}` + `StatusUpdate{kind="CalibrationResult"}` |
| *(ProximityPrompts)* survival | `Triggered(player)` on Re-sync / Patch / Phase-Lock (characters), Rescue (pods), Power Relay, Overload (terminals), Vault / Drop / Break / Open-Close (furniture), Hide / Search / Leave (lockers), Slip Through / Seal (rift) | rate key `SurvivalPrompt` 6 / 3; movement validation; then `MatchDirector:beginAction` or `InteractionService` checks phase, role, condition, restraint, busy state, server-measured range and object state. Triggering the same action again cancels it; `ObjectiveRequest Cancel` cancels hacks and channels | — | `StatusUpdate{kind="Action"}` or `ActionResult` reject |
| `SettingsUpdate` | `{ [settingKey]: value }` | plain table, no metatable, ≤8 keys, keys from `ProfileSchema.SETTINGS`, each value type/range checked (whole request rejected if any invalid) | 3 / 0.5 | `ActionResult{action="Settings"}` + `ProfileSnapshot` |
| `ClientReady` | none | 0 args | 2 / 0.2 | `MatchState`, `QueueState`, `ProfileSnapshot`, and if in a match `RoleAssigned` + `AbilityState` |
| *(ProximityPrompt)* `HackPrompt` | engine `Triggered(player)` | rate key `HackPrompt` 4 / 2; then full hack validation in `MatchDirector:requestHackStart` (phase, participant, role, alive, restrained, registered terminal, concurrency (primary + one assistant), distance ≤ 12 and sight) | — | `ActionResult{action="HackStart"}` |

Never accepted from clients: progress, rewards, currency, damage, health, roles, cooldown state,
match outcome, profile data, instance references, or remote names.

## Server → Client

| Remote | Audience | Payload (public unless noted) |
| --- | --- | --- |
| `MatchState` | all (1 Hz + on change) | `MatchSnapshot`: version, matchId, phase, phaseEndsAt, required/completed hacks, participants {userId,name,role,status,classId, condition, stage, heal, revive, bleedoutAt, podId, podRemaining, podDuration, feedback, enduranceUntil, action}, terminals {id,name,state,progress,hackerUserId,assistants,regressing,mode}, extractionActive, collapse {endsAt, gateOpen, relays, tier}?, rift {site}?, queueCount, min/max players |
| `QueueState` | each player (private) | queued, position, count, needed, minPlayers, maxPlayers, inMatch |
| `RoleAssigned` | each participant (private) | matchId, role, displayName, tagline, description, abilities[], keeperName, hasKeeper |
| `TerminalUpdate` | state changes → all; progress ticks → participants | matchId, terminal (PublicTerminal), reason? (≤4/s per terminal) |
| `AbilityState` | owner (private) | matchId, abilities[{abilityId, readyAt, cooldown, active, maxActive}] |
| `StatusUpdate` | owner (private) | `{kind="Movement", slowed, stunned, rooted, hasted, slowImmune, invulnerable, crawling, effects[…]}` (on change), `{kind="Extraction", progress}`, `{kind="Calibration", terminalId, challenge{nonce,mode,startAt,sweep,direction,arcStart,arcWidth,greatWidth}}`, `{kind="CalibrationResult", grade}`, `{kind="Action", action, target, startedAt, duration, active}`, `{kind="Stamina", value, sprinting, exhausted}`, `{kind="Chase", chased}`, Keeper-only `{kind="Hunt", targets}` / `{kind="Momentum", value}` |
| `Notify` | targeted lists | kind (Toast/Announcement/Warning), text, severity, duration |
| `Effect` | participants or all | kind (`Protocol.EffectKinds`) + position/radius/userId/timing — cosmetic only. `TrapPlaced` goes only to the Keeper; `Reveal` only to Infiltrators |
| `MatchResult` | each participant (private) | matchId, winner, reason, yourRole, yourStatus, won, rewards[{label,amount}], rewardTotal, rewardsSaved, stats, participants |
| `ProfileSnapshot` | owner (private) | loaded, persistent, currency, owned, equipped, stats, settings |
| `ActionResult` | requester (private) | action, ok, code, message, extra fields |

Rejection codes and their player-facing text live in `src/Shared/Network/Protocol.luau`.

## Expansion remotes and payloads

| Client → server | Validation and cadence |
| --- | --- |
| MapVoteRequest(mapId) | Exact one short known id; queued player; waiting/intermission only; votes count only selected participants; 3 burst / 0.5 per second |
| HackChallengeRequest(matchId, terminalId, nonce, answer) | Exact four fields; short strings; nonce integer 1..1e6; answer 1..3; current Active match before deadline; primary hacker alive/in range/in sight/unrestrained; one-use server challenge/window; 3 / 1 |
| PingRequest(matchId) | Exact short current id; living active Infiltrator; valid movement; 2 / 0.25; server derives position/context and team recipients |

Ability requests also enforce the fixed class skill or gadget and movement validity. Cancel requests
carry matchId. Portal prompts are server-created with fixed endpoints; range ≤6, sight, participant,
alive, restraint, Active phase, current event and a per-player 4s cooldown are checked. PortalPrompt
rate key is 2 / 0.5. Rejection replies themselves are bounded (RateNotice 2 / 0.2) during floods.

MatchState adds mapId/mapName, string-user-id ballots, class ids and the current anomaly's state,
positions and activation/expiry deadlines. PublicTerminal adds assistantUserId, difficulty and an
optional public challenge (nonce/mode/prompt/timing; **never** answer). AbilityState and extraction
StatusUpdate are match-scoped and stale client messages are dropped. ProfileSnapshot adds the
owner's career/contract summary; MatchResult adds XP and progression notifications. TeamPing and
Tracking effects are sent only to the intended team/Keeper. No new reward/claim/damage endpoint.
