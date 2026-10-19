# Game Design — Chrono Breakers: Temporal Heist

> **Survival Protocol.** Instant elimination, open extraction and optional puzzles were replaced by
> the integrity ladder, Stasis Pods, pursuit systems, Calibration Pulses, the Temporal Collapse and
> perk loadouts described in [SURVIVAL_DESIGN](SURVIVAL_DESIGN.md). Where the sections below
> disagree with that document (terminal count, hack time, damage, elimination, extraction window,
> challenges), SURVIVAL_DESIGN is current; the rest (queue, roles, phases, map contract, economy)
> still applies.

The core loop below is retained. Expansion systems and current verification limits are described in [EXPANSION_RELEASE](EXPANSION_RELEASE.md).

Describes what is implemented. Values are defaults from `src/Shared/Config` (see BALANCE.md).

## Match loop
1. Players spawn in the **lobby** and press **Join Queue** (server-owned FIFO queue; must be alive
   and not already in a match).
2. When `MinPlayers` (2) eligible players are queued → **Intermission** (15 s). Dropping below the
   threshold returns to **WaitingForPlayers**.
3. **RoleAssignment** takes up to `MaxPlayers` (5) in queue order; extra players stay queued.
   Exactly one **Time-Keeper**; everyone else is an **Infiltrator**.
4. **Intro** (8 s): private role reveal; everyone is held in place at their spawn.
5. **Active** (600 s): Infiltrators hack terminals; the Keeper is held in the Sanctum for 10 s
   (anti spawn-camp); Infiltrators are damage-immune for 8 s.
6. Third terminal breached → **Extraction** (60 s): the Breach Gate opens. An Infiltrator must stand
   on the extraction pad for 3 continuous seconds to extract.
7. **Resolving** (12 s): results + rewards; **ReturningToLobby** (3 s); back to waiting.

## Win conditions (resolved exactly once, by `MatchDirector`)
| Situation | Winner | Reason |
| --- | --- | --- |
| No Infiltrator still active and ≥1 extracted | Infiltrators | `Extracted` |
| Extraction window ends with ≥1 extracted | Infiltrators | `Extracted` |
| All Infiltrators eliminated (none extracted) | Time-Keeper | `AllEliminated` |
| Match timer expires during Active | Time-Keeper | `TimeExpired` |
| Extraction window ends with nobody extracted | Time-Keeper | `ExtractionFailed` |
| Time-Keeper disconnects (Active/Extraction) | Infiltrators | `KeeperLeft` |
| Every remaining Infiltrator disconnects | Time-Keeper | `InfiltratorsLeft` |
| Someone leaves during Intro, or nobody is connected | none | `Aborted` (no rewards) |

Once one Infiltrator extracts the team has secured the win, but the match continues until the
remaining Infiltrators extract, are eliminated, or the window closes (so they can earn the
extraction bonus). Entering Extraction replaces the match deadline with the extraction deadline.

## Roles
**Time-Keeper** (17 walk speed): Chrono Strike, Time-Freeze Zone, Temporal Trap. Cannot be damaged
(no Infiltrator weapons exist); if the Keeper dies (fall/reset) they respawn at the Sanctum.
**Infiltrator** (16 walk speed, 100 HP): hacks terminals; one equipped gadget.

### Role fairness
The candidate with the most matches since last being Keeper is chosen; ties broken at random.
History is per server session (`RoleSelector`), so the Keeper rotates across consecutive matches.

## Terminals (HackTerminal)
States: `Locked → Available → Hacking → Completed`, with `Hacking → Interrupted → Available`
(1.5 s lockout). Rules:
- Only an active, alive, unrestrained Infiltrator in the Active phase, within **12 studs**
  (server-measured), may start. The ProximityPrompt (10 studs) is only an input request.
- **One primary plus one optional assistant per terminal; one terminal per player.** Duplicate requests return `Busy` /
  `AlreadyHacking`.
- Progress advances from server time (15 s total) and is broadcast at most 4×/s.
- Interrupted by: leaving range, damage, death, stun/hold (Restrained), disconnect, elimination,
  explicit cancel, match end. **Progress is retained**, so any teammate can resume.
- Each terminal completes once; completion is deduplicated by `ObjectiveTracker`.
- When extraction opens, unfinished terminals lock.

## Time-Keeper abilities
| Ability | Behaviour |
| --- | --- |
| Chrono Strike | 34 damage to the nearest Infiltrator within 9 studs inside a 70° cone with line of sight. 1.2 s cooldown; a whiff still uses the cooldown. Damage interrupts hacking. |
| Time-Freeze Zone | Ground-targeted (≤70 studs, walkable surface, line of sight, inside the vault). 0.75 s telegraph ring, then 10 s of a 70% slow on Infiltrators inside the 15-stud radius. 1 active zone; 22 s cooldown. |
| Temporal Trap | Ground-targeted (≤18 studs). Arms after 1.5 s, faintly visible. First Infiltrator within 4 studs is stunned 1.25 s then slowed 40% (total 3.75 s); Keeper is notified. Max 3; ≥10 studs apart, ≥6 from terminals, ≥12 from extraction, ≥18 from Infiltrator spawns; 90 s lifetime. |

### Placement rule
Client positions are hints only. The server checks: finite Vector3 → horizontal range → vault
bounds → downward probe finds a walkable surface (normal.Y ≥ 0.7) → line of sight from the
caster's eye to the ground point. The server-derived ground point is used.

## Infiltrator gadgets (counterplay, one equipped)
| Gadget | Cost | Effect |
| --- | --- | --- |
| Chrono Stabilizer | free | Removes Slow/Stun; 3 s immunity to Slow/Stun. Cooldown 32 s. |
| Phase Dash | 150 | +60% speed for 2.5 s. Cooldown 24 s. |
| Echo Scanner | 250 | Highlights the Keeper and armed traps for the team (4 s); Keeper is told. Cooldown 38 s. |

The gadget is locked in at match start.

## Status effects (movement)
Speed = role base × (1 − strongest Slow) × (1 + strongest Haste); Stun/Root → 0 speed and jump.
Same source key refreshes rather than stacks; different sources of the same kind do not add
(strongest wins); each expires independently; SlowImmunity suppresses Slow and Stun but not Root.
Overlapping Freeze Zones therefore give 70%, not 140%. Leaving a zone ends its slow ~0.35 s later;
re-entering re-applies it. Effects are cleared on death, at match end, and on departure, and are
always recomputed from the role baseline.

## Combat and elimination
Infiltrators have 100 HP and no regeneration (the default Health script is replaced). Death during
a match = elimination (processed once); eliminated and extracted players respawn in the lobby and
may spectate. The reset button is disabled while you are an active participant.

## Map contract (Chronos Vault)
Authored blockout in `src/Server/World/MapLayout.luau`: seven areas (Archive, Sanctum, Reactor,
central halls, Spawn Bay, Dock, Observatory), each with ≥2 entrances, cover and sight-line
breakers, three terminals ≥40 studs apart, and an extraction pad behind the Breach Gate.
`MapValidator` checks at server start and in tests: everything inside bounds, no spawn or
interaction point inside geometry, every terminal/spawn/extraction reachable on foot (grid flood
fill with character radius), and that the closed gate really blocks extraction.

## Economy
Chronos Scrap is earned only from match results (Participation 20, Victory 50, per terminal 15,
extracted 40, per Keeper elimination 20). Spent on gadgets (side-grades) and cosmetic trails.
No real-money products exist.

## Expansion balance

Class definitions live in ClassConfig; all five are free and available immediately. Ghost trades
health for speed/stealth; Engineer trades movement for hacking; Medic heals living allies; Phantom
trades health/hacking for mobility; Disruptor counters traps/control. Class skills use F/Y separately
from the Q/L1 gadget. Keeper Chrono Pulse uses R/L2, leaving X free for interaction prompts.

Safe hacking remains timed. Optional challenges grant 8% progress; failure removes 6%, interrupts
and traces the hacker. Each completed objective raises remaining channel durations by 10%; an
assistant adds 35% speed. XP, mastery, daily/weekly contracts and titles are cosmetic progression.
Eight telegraphed anomaly modes add temporary routes, hazards and counterplay to all four maps.
These expansion balance choices still need multiplayer playtesting.
