# Architecture

## Layers
```
Shared (ReplicatedStorage.Shared)  Config · Types · Network registry/Protocol · Signal · Cleanup · Safe · TableUtil
Server Core (pure Luau)            MatchDirector ← MatchStateMachine, QueueModel, RoleSelector, TerminalModel,
                                   ObjectiveTracker, ExtractionModel · StatusEffects · CooldownTracker · RateLimiter
                                   Validate · PlacementRules · AbilityRules · ProfileSchema · ProfileStore
                                   MemoryDataStore · Economy · RewardCalculator · RewardLedger
Server World                       MapLayout (data) · MapValidator (pure) · MatchWorldBuilder (instances)
Server Components                  FreezeZone · TemporalTrap
Server Services (adapters)         see table below
Client                             Net · ClientState · StateSync · Controllers · UI (Components/Screens)
```
Pure Core modules never touch Instances and receive time as an argument, so every rule is
exercised by Lune tests. Services adapt them to Roblox (Players, Humanoids, raycasts, remotes).

## Server bootstrap (`src/Server/Bootstrap.server.luau`)
Requires every service, then runs `Init(registry)` for all, then `Start(registry)` for all, in
this order. Any failure is fatal (`error`) with the service name. `BootGuard` (module state, never
an Instance attribute, so nothing can persist into a saved place) prevents a duplicate boot.

| # | Service | Owns / does | Depends on |
| --- | --- | --- | --- |
| 1 | SecurityService | violation telemetry, movement sanity samples | MatchService, StatusEffectService (runtime) |
| 2 | NetworkService | creates all remotes from `RemoteNames.Specs`; rate-limited, error-bounded handlers; Notify/Accept/Reject | SecurityService |
| 3 | WorldService | validates map contract (fatal on failure), builds world, raycasts, spawn CFrames, gate/terminal visuals | — |
| 4 | StatusEffectService | per-player StatusEffects + role baseline; sole writer of WalkSpeed/JumpPower | NetworkService |
| 5 | PlayerDataService | profile sessions (load/lock/autosave/release/shutdown), snapshots, `Mutate` | NetworkService |
| 6 | InventoryService | Shop and Settings remotes, equipped items | PlayerDataService, MatchService |
| 7 | MatchService | owns `MatchDirector`, queue remote, ClientReady, tick loop, event → effects translation, spawn resolution | most services |
| 8 | CharacterService | character setup, spawn pivot, trails, Died → MatchService | MatchService, StatusEffectService, InventoryService |
| 9 | ObjectiveService | terminal prompts → hack requests, terminal visuals, cancel remote | MatchService, WorldService |
| 10 | CombatService | Chrono Strike damage + attribution | MatchService, WorldService, StatusEffectService |
| 11 | AbilityService | ability remote pipeline, cooldowns, zones/traps lifecycle | most services |
| 12 | RewardService | idempotent payouts and results payloads | PlayerDataService |

Dependencies are passed through the registry; services call each other only through public
functions (no shared mutable tables), which avoids circular `require`s.

## Match lifecycle and cleanup
- `MatchDirector` is the only owner of phase, participants, terminals, objectives, extraction, and
  results. Illegal transitions are rejected (`MatchStateMachine.LEGAL`); resolution is idempotent.
- Each match has a GUID `matchId`; every director event carries it. MatchService keeps a per-match
  `Cleanup` (delayed tasks) destroyed at `MatchCleanup`, and delayed callbacks re-check
  `IsCurrentMatch(matchId)`.
- On `MatchResolved`: AbilityService destroys all zones/traps and clears cooldowns, CombatService
  clears attribution, status effects are cleared, the gate closes, rewards are paid once.
- On `MatchCleanup`: terminal visuals reset, per-match tables cleared. Integration tests run four
  consecutive matches and assert no session, queue, or listener leakage.

## Loops (all bounded)
| Loop | Rate | Work |
| --- | --- | --- |
| MatchService tick | 10 Hz | director tick (≤5 participants, 3 terminals) + 1 Hz snapshot |
| StatusEffectService | 10 Hz | prune expired effects for players with entries |
| AbilityService runtime | 10 Hz, skipped when empty | zones (membership every 0.2 s vs ≤4 Infiltrators), traps |
| SecurityService | 2 Hz | movement samples for active participants |
| PlayerDataService | every 120 s | autosave dirty profiles |
No loop scans the Workspace; area effects check only the active Infiltrators' root positions.

## Client
`Bootstrap.client` → controllers `Init` → `Net.waitForRemotes(30)` (connecting/failed overlay) →
`StateSync` (the only remote → `ClientState` ingestion) → controllers `Start` → `ClientReady`
(server replies with a full state refresh). UI renders from `ClientState`; nothing on the client is
authoritative. Controllers: Audio, Input (KBM/touch/gamepad + ground targeting), Camera (spectate),
UI (routing/scale/modals/toasts), Effects (cosmetic), Interaction (markers, prompt visibility,
reset-button policy).

## Failure behaviour
- Map contract violation or a service `Init` error → server refuses to start (loud error).
- DataStore failure → unsaved session (player can play; UI warns); Studio without API access →
  in-memory store (logged).
- Handler errors are caught at the remote boundary and logged with the remote name and user id.
