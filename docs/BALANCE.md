# Balance Sheet

All values live in `src/Shared/Config/` (server-only values in `src/Server/ServerConfig.luau`).
Defaults follow the design brief; none have been playtested with real players yet.

| Value | Default | File |
| --- | --- | --- |
| Min / max players | 2 / 5 | GameConfig |
| Intermission / intro | 15 s / 8 s | GameConfig |
| Match timer | 600 s | GameConfig |
| Extraction window / channel | 60 s / 3 s | GameConfig |
| Results / return | 12 s / 3 s | GameConfig |
| Keeper release delay | 10 s | GameConfig |
| Infiltrator spawn protection | 8 s | GameConfig |
| Required hacks | 3 | TerminalConfig |
| Hack duration | 15 s | TerminalConfig |
| Max hack distance / prompt range | 12 / 10 studs | TerminalConfig |
| Interrupt lockout | 1.5 s (progress retained) | TerminalConfig |
| Walk speed Keeper / Infiltrator | 17 / 16 | RoleConfig |
| Chrono Strike | 34 dmg, 9 studs, 70° cone, 1.2 s | AbilityConfig |
| Time-Freeze | r=15 (30 dia), 10 s, 70% slow, 0.75 s telegraph, 70 range, 22 s CD, 1 active | AbilityConfig |
| Temporal Trap | 1.25 s stun + 40% slow 2.5 s, r=4, 1.5 s arm, 18 range, 12 s CD, max 3, 90 s life | AbilityConfig |
| Stabilizer | 3 s immunity, 32 s CD | AbilityConfig |
| Phase Dash | +60% for 2.5 s, 24 s CD | AbilityConfig |
| Echo Scanner | 4 s reveal, 38 s CD | AbilityConfig |
| Rewards | 20 participation, 50 win, 15/terminal, 40 extract, 20/elimination | RewardConfig |
| Item costs | Phase Dash 150, Echo 250, Magenta 100, Gold 400 | ItemConfig |

## Design notes / things to watch in playtests
- Three strikes eliminate an Infiltrator; spawn protection and the Keeper release delay prevent
  instant spawn kills.
- Hacking is loud: the Keeper is notified when a breach starts and sees active-breach markers.
  If this proves too punishing, delay the marker or remove it after N seconds.
- Disconnect wins (`KeeperLeft`, `InfiltratorsLeft`) pay the normal win bonus; consider reducing
  if win-trading with alt accounts appears.
- Freeze zones never stack; traps cannot be clustered on objectives, extraction, or spawns.

## Playtest observations
None yet — no multi-player session has been run (see TEST_PLAN.md).

## Expansion tuning (not live-playtested)

See ClassConfig, ProgressionConfig and AnomalyConfig for the canonical values. Ghost: 17 speed/80 HP;
Engineer: 15/100 and ×1.15 hack; Medic: 16/95; Phantom: 16.5/85 and ×0.9 hack; Disruptor: 16/100
and ×0.95 hack. Skills: Veil 5s/30s CD, Overclock ×1.5 for 6s/30s CD, Mend 28 HP/18 studs/40s CD,
Slipstream ×2 for 1.5s/26s CD, EMP 18 studs/36s CD. Pulse: 48 studs, 1.5s warning, 3s reveal/30s CD.

Anomalies: first warning after 30s Active, warning 3s, radius 13, duration 6–12s, next warning 35s
after expiry. One at a time; protected spawns/objectives are excluded by map validation. Progression
never modifies these values. Real match balance and low-end performance remain release gates.

## Survival Protocol values

Source of truth: `SurvivalConfig.luau`, `PerkConfig.luau`, `ClassConfig.luau`. Key relationships
(also enforced by `ConfigConsistency.spec`): the Keeper (17.25) outruns every running class by >8%,
every sprinting class (×1.32) outruns the Keeper, full Hunt Momentum (+15%) never makes sprint
pointless, and Desynced crawl stays under 4 studs/s. Two hits Desync; stages last 60 s / 30 s /
erase; camping releases a captive after 15 s; rails seal after 3 vaults in 40 s; four of five
terminals at 40 s (solo, four-player squad) with ×0.5/0.7/0.85 scaling for 1–3 Infiltrators;
Collapse 120 s. Perk modifiers are bounded to ≤×2 and unlock only through play. All of these need
1v4 playtests before release (see SURVIVAL_RELEASE).
