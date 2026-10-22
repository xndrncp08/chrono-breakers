# Survival Protocol — design

Chrono Breakers becomes a 1v4 survival-horror heist: one Time-Keeper hunts four Infiltrators who
breach terminals, survive pursuit, rescue each other and escape a collapsing timeline. The design
borrows the *principles* of the asymmetric chase genre (readable threat, short loops with finite
resources, recoverable mistakes, progressive elimination, built-in anti-camping) and expresses them
in original mechanics, names and visuals. Every value below lives in `src/Shared/Config/SurvivalConfig.luau`.

## Vocabulary

| Concept | Name in game |
| --- | --- |
| Healthy / injured / downed | **Stable / Fractured / Desynced** |
| Containment chamber | **Stasis Pod** |
| Contained / eliminated | **In Stasis / Erased** |
| Revive a downed ally / heal an injured one | **Re-sync / Patch** |
| Keeper puts a downed Infiltrator in a pod | **Phase-Lock** |
| Proximity warning | **Temporal Resonance** |
| Chase escalation | **Hunt Momentum** |
| Skill check | **Calibration Pulse** |
| Keeper terminal regression | **Overload** |
| Vaultable low wall / droppable barricade | **Breach Rail / Stasis Barrier** |
| Hiding spot / door | **Phase Locker / Blast Door** |
| Endgame / gate consoles / last-survivor exit | **Temporal Collapse / Gate Relays / Slip Rift** |
| Infiltrator perks / Keeper perks | **Protocols / Edicts** |

## Integrity ladder (replaces instant elimination)

`Stable → Fractured → Desynced → In Stasis → Erased`. A Chrono Strike moves a target one step.
Health bars mirror the step (server-owned; Humanoids are never killed by gameplay).

* **Fractured** Infiltrators leave sparks and are audible. Allies **Patch** them (12 s, progress kept
  on the target, up to two helpers; each extra helper works at 80%).
* **Desynced** Infiltrators crawl at 20% speed, cannot jump, hack, vault or use gadgets. Allies
  **Re-sync** them (8 s). After 90 s unattended they are auto Phase-Locked (no benefit from slugging).
* The Keeper **Phase-Locks** a Desynced target within 7 studs (1 s channel, Keeper rooted; any
  barrier, Disruption Pulse or rescue-break interrupts it). The target appears in the nearest free
  Stasis Pod.
* **Stasis stages:** 1st containment — 60 s pod timer; 2nd — 30 s; 3rd — Erased immediately. A
  pod timer reaching zero Erases the captive.
* **Rescue:** an ally within 7 studs channels 1.5 s. The captive returns Fractured with
  **Endurance** (12 s: the next hit that would Desync them is absorbed) and a 2.5 s speed burst.
* **Anti-camping:** while the Keeper stays within 18 studs of an occupied pod, the timer drains at
  half speed and *temporal feedback* builds; 15 s of camping releases the captive automatically.
* **Anti-tunnelling:** Endurance after rescue, rescue speed burst, and Hunt Momentum resetting on
  every hit, so focusing one target is never free.
* If no Infiltrator remains free (all Desynced or In Stasis), the remaining ones are Erased and the
  match resolves at once — no stalling.

## Pursuit

* **Temporal Resonance:** within 52 studs of the Keeper a heartbeat and vignette scale with
  distance (presentation from replicated positions; never authoritative).
* **Chase:** the server opens a chase when the Keeper has line of sight to an Infiltrator within 26
  studs for 0.8 s and closes it after 5 s without sight or beyond 46 studs. Chases drive the
  escalating chase music and the pursuit warning on the victim's HUD.
* **Hunt Momentum:** every 12 s of uninterrupted chase gives the Keeper +5% speed (max +15%).
  Landing a hit, being stunned by a barrier or losing the chase resets it — loops always end.
* **Stamina:** Infiltrators sprint (+32%) for ~3.6 s, regenerate after 1.2 s; emptying the bar
  exhausts them until it refills to 35%. Keepers do not sprint but move 15% faster than a running
  Infiltrator. Jumps are a small hop in matches so obstacles matter.
* **Chrono Strike:** 0.2 s telegraphed wind-up. A hit gives the victim a 1.8 s escape burst and
  the Keeper a 1.8 s recoil slow; a whiff costs a 0.9 s recovery slow. Hits interrupt hacks and
  every channel.

* **Fair hits under latency:** the server keeps a 1 s trail of free Infiltrators and also judges a
  swing against where the Keeper saw the target (Keeper round trip + 0.1 s replication buffer,
  capped at 0.25 s). Line of sight is always judged at the target's *current* position and the
  target must still be within range + 3 studs, so nobody is hit through a corner they already
  rounded or from far behind them.
* **Threat direction:** while Resonance or a chase is active and the Keeper is off-screen, a chevron
  on the screen edge points at them (a visual twin of the spatial audio for players who cannot
  hear it); it turns solid when a strike winds up within 16 studs.
* **Afterimage (gadget, 200 Scrap, 40 s):** pay 35 stamina to shed a ghost of yourself that keeps
  running your heading for 3 s and leaves Keeper residue, while your own residue goes quiet.
  Counterplay: the cast chimes and rings at the cast point; the echo stops at walls, shimmers up
  close, shatters on a Chrono Strike (the Keeper still pays the whiff recovery) and inside any
  Chrono Pulse. It is strongest right after breaking line of sight — a prediction tool, not speed.

## Environment

Per map (authored in `MapLayout`, checked by `MapValidator`): five terminals (four required),
four Stasis Pods, Breach Rails (vault 0.65 s, Keeper 1.6 s), Stasis Barriers (drop to block a gap and
stun a Keeper standing in it for 2 s; Infiltrators can vault a dropped barrier; the Keeper breaks it
in 2.2 s — permanently), Blast Doors (toggle; block sight), Phase Lockers (hidden from scans and
Resonance; the Keeper can search, ejecting and Fracturing the occupant) and two Gate Relays.
**Rail fatigue:** the same rail vaulted three times inside 40 s seals for Infiltrators for 20 s,
which ends infinite loops while keeping short loops strong.

## Hacking

* Up to three hackers per terminal (each extra at 80%). Squad scaling keeps small lobbies viable
  (hack time ×0.5 / 0.7 / 0.85 / 1.0 for 1–4 Infiltrators). Each finished terminal makes the rest
  10% slower and shrinks calibration zones.
* **Calibration Pulses** arrive at random 5–10 s intervals for every hacker independently: a needle
  sweeps a ring and the player presses in the marked arc. Great: +2.5% progress. Miss or timeout:
  −7% progress and the Keeper sees a trace at the terminal. Three terminal "flavours" vary needle
  speed, direction and arc width. Server time judges every press (bounded latency allowance).
* **Overload:** the Keeper spends 1.2 s at an idle terminal with progress to make it regress
  (−4% at once, then 0.6%/s) until an Infiltrator resumes it.

## Endgame — Temporal Collapse

When four terminals are breached the remaining one locks and the 120 s Collapse begins. A Gate
Relay must be powered (10 s channel, progress kept) to open the Breach Gate; standing on the pad
for 3 s extracts. Instability rises with the timer: at 50% pods drain 1.5× faster; at 80% a
shockwave every 10 s reveals free Infiltrators to the Keeper. When the timer ends everyone still
inside is Erased. If a single Infiltrator is left in play before the Collapse, a **Slip Rift** opens
at a far anomaly site: a 2 s channel escapes; the Keeper can seal it (1.5 s), which starts the
Collapse early. Outcomes play short camera sequences (escape lift, erasure glitch, Keeper victory).

## Timeline Conditions

Each match rolls one condition (`ConditionConfig`, weights in the file; disable with
`ServerConfig.TimelineConditions.Enabled`). It is shown on the deployment card and under the HUD
objectives. Every condition gives one side something and the other side something back, reusing
perk modifier keys so the owning systems apply it with no special cases:

| Condition | Effect |
| --- | --- |
| Stable Timeline (weight 4) | none |
| Accelerated Entropy | hacks +15% speed; pods drain +20% |
| Overcharged Pulses | calibration arcs +20%; misses cost +40% |
| Brittle Seconds | barrier stuns +25%; Keeper hit recoil −20% |
| Mending Loop | Re-sync/Patch +20%; Overload regression +50% |
| Restless Echoes | stamina regen +20%; calibration traces last +50% |

`ForceTimelineCondition` (server attribute on ServerScriptService) pins one; the E2E driver pins
Stable.

## Progression (no pay-to-win)

Two perk slots per role. Class Protocols unlock through class mastery, shared Protocols through
account level, Edicts through Keeper mastery — never with Scrap or money. Mastery tiers grant
cosmetic titles/accents; survival contracts (rescues, re-syncs, great calibrations, Phase-Locks)
join the daily/weekly rotation. Scrap still buys only cosmetics and side-grade gadgets.

## Server authority

Every interaction is a request (`InteractRequest`, `SprintRequest`, calibration presses) validated
for match id, phase, role, condition, range, line of sight, rate limit and object state. Pure rules
live in `Core` (`SurvivalModel`, `ChaseModel`, `StaminaModel`, `WorldObjects`, `EndgameModel`,
`HackChallenge`, `TerminalModel`) with Lune specs; services adapt them to Instances.
