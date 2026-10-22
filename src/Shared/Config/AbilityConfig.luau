--!strict
-- Ability and gadget tunables. Abilities belong to the Time-Keeper; gadgets are the Infiltrators'
-- counterplay tools and are chosen through the loadout (see ItemConfig).

export type TargetMode = "None" | "Ground" | "Direction"

export type AbilityDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Role: string, -- "TimeKeeper" | "Infiltrator"
	Cooldown: number,
	TargetMode: TargetMode,
	-- Default input bindings (InputController maps these per device).
	KeyboardKey: string,
	GamepadKey: string,
	[string]: any,
}

local AbilityConfig = {}

AbilityConfig.Abilities = table.freeze({
	ChronoStrike = table.freeze({
		Id = "ChronoStrike",
		DisplayName = "Chrono Strike",
		Description = "A short telegraphed temporal blade: Fractures, then Desyncs the nearest Infiltrator in front of you.",
		Role = "TimeKeeper",
		Cooldown = 1,
		TargetMode = "Direction",
		KeyboardKey = "MouseButton1",
		GamepadKey = "ButtonR2",
		Damage = 34,
		Range = 9, -- studs from caster root to target root
		ConeAngleDegrees = 70, -- full cone width centred on the aim direction
	} :: AbilityDefinition),
	TimeFreeze = table.freeze({
		Id = "TimeFreeze",
		DisplayName = "Time-Freeze Zone",
		Description = "Collapse time in an area. After a short telegraph, Infiltrators inside move 70% slower.",
		Role = "TimeKeeper",
		Cooldown = 22,
		TargetMode = "Ground",
		KeyboardKey = "Q",
		GamepadKey = "ButtonL1",
		Radius = 15, -- 30 stud nominal diameter
		Duration = 10,
		TelegraphDelay = 0.75, -- visible warning before the slow begins
		SlowMagnitude = 0.7,
		MaxCastRange = 70,
		MaxActive = 1,
		-- Membership is re-evaluated at this interval; the slow lingers briefly after leaving.
		MembershipInterval = 0.2,
		LingerAfterExit = 0.35,
	} :: AbilityDefinition),
	TemporalTrap = table.freeze({
		Id = "TemporalTrap",
		DisplayName = "Temporal Trap",
		Description = "Plant a faint temporal snare. The first Infiltrator to step on it is stunned, then slowed.",
		Role = "TimeKeeper",
		Cooldown = 12,
		TargetMode = "Ground",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		MaxCastRange = 18,
		MaxActive = 3,
		ArmingTime = 1.5,
		TriggerRadius = 4,
		Lifetime = 90,
		StunDuration = 1.25,
		SlowDuration = 2.5,
		SlowMagnitude = 0.4,
		-- Minimum spacing between traps and from objectives, to prevent unavoidable stacking.
		MinSpacing = 10,
		MinDistanceFromTerminal = 6,
		MinDistanceFromExtraction = 12,
	} :: AbilityDefinition),

	ChronoScan = table.freeze({
		Id = "ChronoScan",
		DisplayName = "Chrono Pulse",
		Description = "Warn nearby breakers, then reveal those still within 48 studs after 1.5s. Veil blocks detection.",
		Role = "TimeKeeper",
		Cooldown = 30,
		TargetMode = "None",
		KeyboardKey = "R",
		GamepadKey = "ButtonL2",
		Radius = 48,
		Duration = 3,
		TelegraphDelay = 1.5,
	} :: AbilityDefinition),
	Veil = table.freeze({
		Id = "Veil",
		DisplayName = "Veil",
		Description = "Fade from sight and block scans. Damage and hacking break stealth.",
		Role = "Infiltrator",
		Cooldown = 30,
		TargetMode = "None",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		Duration = 5,
	} :: AbilityDefinition),
	Overclock = table.freeze({
		Id = "Overclock",
		DisplayName = "Overclock",
		Description = "Accelerate your terminal channel by 50% for 6 seconds.",
		Role = "Infiltrator",
		Cooldown = 30,
		TargetMode = "None",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		Duration = 6,
	} :: AbilityDefinition),
	Mend = table.freeze({
		Id = "Mend",
		DisplayName = "Mend",
		Description = "Surge Patch progress by 50% and Re-sync progress by 25% for allies (and you) within 18 studs in sight.",
		Role = "Infiltrator",
		Cooldown = 40,
		TargetMode = "None",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		Radius = 18,
		HealBoost = 0.5,
		ReviveBoost = 0.25,
	} :: AbilityDefinition),
	Slipstream = table.freeze({
		Id = "Slipstream",
		DisplayName = "Slipstream",
		Description = "Double movement speed for 1.5 seconds; snares still apply.",
		Role = "Infiltrator",
		Cooldown = 26,
		TargetMode = "None",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		Duration = 1.5,
		HasteMagnitude = 1,
	} :: AbilityDefinition),
	EMP = table.freeze({
		Id = "EMP",
		DisplayName = "Disruption Pulse",
		Description = "Disarm traps, cleanse allies and break a Keeper's Phase-Lock within 18 studs.",
		Role = "Infiltrator",
		Cooldown = 36,
		TargetMode = "None",
		KeyboardKey = "F",
		GamepadKey = "ButtonY",
		Radius = 18,
		KeeperSlow = 0.5,
		KeeperSlowDuration = 2,
	} :: AbilityDefinition),

	-- Infiltrator gadgets (one equipped at a time through the loadout).
	Stabilizer = table.freeze({
		Id = "Stabilizer",
		DisplayName = "Chrono Stabilizer",
		Description = "Purge slows and stuns, then become immune to them for a few seconds.",
		Role = "Infiltrator",
		Cooldown = 32,
		TargetMode = "None",
		KeyboardKey = "Q",
		GamepadKey = "ButtonL1",
		ImmunityDuration = 3,
	} :: AbilityDefinition),
	PhaseDash = table.freeze({
		Id = "PhaseDash",
		DisplayName = "Phase Dash",
		Description = "A burst of accelerated time: move much faster for a short duration.",
		Role = "Infiltrator",
		Cooldown = 24,
		TargetMode = "None",
		KeyboardKey = "Q",
		GamepadKey = "ButtonL1",
		HasteMagnitude = 0.6,
		Duration = 2.5,
	} :: AbilityDefinition),
	EchoScanner = table.freeze({
		Id = "EchoScanner",
		DisplayName = "Echo Scanner",
		Description = "Reveal the Time-Keeper and armed Temporal Traps to your whole team.",
		Role = "Infiltrator",
		Cooldown = 38,
		TargetMode = "None",
		KeyboardKey = "Q",
		GamepadKey = "ButtonL1",
		RevealDuration = 4,
	} :: AbilityDefinition),
	Afterimage = table.freeze({
		Id = "Afterimage",
		DisplayName = "Afterimage",
		Description = "Shed a running time-echo that keeps your heading while your own trail goes quiet. Costs stamina; a Chrono Pulse or a strike shatters it.",
		Role = "Infiltrator",
		Cooldown = 40,
		TargetMode = "None",
		KeyboardKey = "Q",
		GamepadKey = "ButtonL1",
		Duration = 3, -- echo lifetime and how long the caster's residue is suppressed
		StaminaCost = 35,
		MinSpeed = 12, -- the echo runs at the caster's speed, clamped to this range
		MaxSpeed = 22,
	} :: AbilityDefinition),
})

AbilityConfig.KeeperAbilityOrder = table.freeze({ "ChronoStrike", "TimeFreeze", "TemporalTrap", "ChronoScan" })
AbilityConfig.GadgetIds = table.freeze({ "Stabilizer", "PhaseDash", "EchoScanner", "Afterimage" })

function AbilityConfig.get(abilityId: string): AbilityDefinition?
	return (AbilityConfig.Abilities :: any)[abilityId]
end

return table.freeze(AbilityConfig)
