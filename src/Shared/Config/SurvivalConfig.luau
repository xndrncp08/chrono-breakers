--!strict
-- Survival Protocol tunables: integrity ladder, containment, pursuit, stamina, world interactables
-- and the Temporal Collapse endgame. See docs/SURVIVAL_DESIGN.md for the reasoning behind each value.

local SurvivalConfig = {}

SurvivalConfig.ConditionNames = table.freeze({
	Healthy = "Stable",
	Injured = "Fractured",
	Downed = "Desynced",
	Contained = "In Stasis",
})

SurvivalConfig.Integrity = table.freeze({
	InjuredHealthFraction = 0.5, -- humanoid health mirrors the ladder (presentation only)
	DownedHealthFraction = 0.12,
	CrawlSlow = 0.8, -- Desynced move at 20% speed
	BleedoutTime = 90, -- unattended Desynced players are auto Phase-Locked
	ReviveTime = 8,
	HealTime = 12,
	HelperRange = 6,
	MaxHelpers = 2,
	ExtraHelperEfficiency = 0.8,
	SelfHealRate = 0.5, -- only with the Field Patch protocol
})

SurvivalConfig.Containment = table.freeze({
	ContainTime = 1,
	ContainRange = 7,
	-- Pod timer per containment stage; the stage after the last entry Erases immediately.
	StageDurations = table.freeze({ 60, 30 }),
	RescueTime = 1.5,
	RescueRange = 7,
	CampRadius = 18,
	CampDrainMultiplier = 0.5,
	CampReleaseTime = 15, -- seconds of camping until temporal feedback frees the captive
	CampDecayTime = 30, -- seconds for a full feedback meter to decay when the Keeper leaves
	EnduranceDuration = 12,
	RescueHasteDuration = 2.5,
	RescueHaste = 0.35,
})

SurvivalConfig.Strike = table.freeze({
	Windup = 0.2,
	RecoilDuration = 1.8,
	RecoilSlow = 0.45,
	MissDuration = 0.9,
	MissSlow = 0.35,
	SurgeDuration = 1.8,
	SurgeHaste = 0.45,
	FractureRevealDuration = 5, -- combo: striking a time-slowed target reveals them
	-- Lag compensation: the server also judges a swing against where the Keeper saw the target
	-- (Keeper round trip + replication buffer, capped) while the target's current position must stay
	-- in sight and within Range + RewindSlack.
	InterpolationDelay = 0.1,
	MaxRewind = 0.25,
	RewindSlack = 3,
	HistoryWindow = 1,
})

SurvivalConfig.Chase = table.freeze({
	StartRange = 26,
	StartDwell = 0.8,
	LoseSightGrace = 5,
	MaxRange = 46,
	MomentumInterval = 12,
	MomentumStep = 0.05,
	MomentumMax = 0.15,
	ResonanceRadius = 52, -- client presentation radius
})

SurvivalConfig.Stamina = table.freeze({
	Max = 100,
	DrainPerSecond = 28,
	RegenPerSecond = 20,
	RegenDelay = 1.2,
	RecoverThreshold = 35,
	SprintHaste = 0.32,
	MovingSpeed = 3, -- studs/s of horizontal velocity that counts as moving
})

SurvivalConfig.Movement = table.freeze({
	MatchJumpPower = 20, -- a small hop; obstacles taller than ~1 stud need a vault
})

SurvivalConfig.World = table.freeze({
	InteractRange = 6,
	VaultTime = 0.65,
	KeeperVaultTime = 1.6,
	VaultClearance = 3.5, -- studs past the obstacle centre where a vault lands
	FatigueWindow = 40,
	FatigueVaults = 3,
	FatigueSeal = 20,
	BarrierStunRadius = 5,
	BarrierStun = 2,
	BarrierBreakTime = 2.2,
	DoorCooldown = 1.2,
	LockerEnterTime = 0.5,
	SearchTime = 0.9,
	SearchStun = 1,
})

SurvivalConfig.Objectives = table.freeze({
	MaxHackers = 3,
	ExtraHackerEfficiency = 0.8,
	-- Hack-time multiplier by Infiltrator count (index = count).
	SquadScaling = table.freeze({ 0.5, 0.7, 0.85, 1 }),
	OverloadTime = 1.2,
	OverloadRange = 8,
	OverloadInstantLoss = 0.04,
	RegressionPerSecond = 0.006,
})

SurvivalConfig.Calibration = table.freeze({
	MinInterval = 5,
	MaxInterval = 10,
	Warning = 0.6, -- audible cue before the needle starts
	GreatFraction = 0.3, -- leading share of the arc that counts as Great
	GreatBonus = 0.025,
	MissPenalty = 0.07,
	BaseArc = 50, -- degrees
	ArcShrinkPerTerminal = 6,
	MinArc = 26,
	LatencyAllowance = 0.35, -- how far back a claimed press time may reach
	-- Terminal flavours: needle sweep seconds, direction and arc scale.
	Flavours = table.freeze({
		Timing = table.freeze({ Name = "Phase Lock", Sweep = 1.1, Direction = 1, ArcScale = 1 }),
		Sequence = table.freeze({ Name = "Cascade", Sweep = 0.9, Direction = -1, ArcScale = 1.25 }),
		Cipher = table.freeze({ Name = "Cipher Ring", Sweep = 1.4, Direction = 1, ArcScale = 0.8 }),
	}),
})

SurvivalConfig.Endgame = table.freeze({
	CollapseDuration = 120,
	RelayTime = 10,
	RelayRange = 7,
	RisingAt = 0.5,
	CriticalAt = 0.8,
	RisingPodDrain = 1.5,
	ShockwaveInterval = 10,
	ShockwaveReveal = 2,
	RiftChannel = 2,
	RiftSealTime = 1.5,
	RiftRange = 6,
})

return table.freeze(SurvivalConfig)
