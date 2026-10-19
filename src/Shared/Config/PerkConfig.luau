--!strict
-- Perks: Infiltrator Protocols and Keeper Edicts. Two slots per loadout (one loadout per class plus
-- one for the Time-Keeper). Perks unlock only through play — account level or mastery — and can
-- never be bought, so they are side-grades rather than pay-to-win. Each perk is a set of
-- multiplicative modifiers read by the systems that own the rule (default 1).
--
-- Modifier keys: SurgeDuration, CalibrationArc, MissPenalty, SelfHeal (flag), VaultSpeed,
-- StaminaRegen, VeilDuration, LockerEnter, Relay, Revive, Heal, Endurance (granted to the rescued),
-- SlipstreamCooldown, EmpRadius, BarrierStun, LandingHaste (flag), Recoil, Regression,
-- RevealRescuer (flag), PodDrain, TraceDuration, TrapStun.

local ProgressionConfig = require(script.Parent.ProgressionConfig)

export type Unlock = { Kind: "Level" | "Mastery", Value: number }
export type Perk = {
	Id: string,
	Name: string,
	Description: string,
	Role: "Infiltrator" | "TimeKeeper",
	Class: string?, -- class-specific Protocols only work for that class
	Unlock: Unlock,
	Modifiers: { [string]: number },
	SortOrder: number,
}

local PerkConfig = {}
PerkConfig.Slots = 2

local function perk(
	id: string,
	name: string,
	description: string,
	role: "Infiltrator" | "TimeKeeper",
	class: string?,
	unlock: Unlock,
	modifiers: { [string]: number },
	order: number
): Perk
	return table.freeze({
		Id = id,
		Name = name,
		Description = description,
		Role = role,
		Class = class,
		Unlock = table.freeze(unlock),
		Modifiers = table.freeze(modifiers),
		SortOrder = order,
	}) :: Perk
end

local level = function(value: number): Unlock
	return { Kind = "Level", Value = value }
end
local mastery = function(value: number): Unlock
	return { Kind = "Mastery", Value = value }
end

PerkConfig.Perks = table.freeze({
	-- Shared Protocols (account level)
	SecondWind = perk(
		"SecondWind",
		"Second Wind",
		"Stamina regenerates 30% faster.",
		"Infiltrator",
		nil,
		level(1),
		{ StaminaRegen = 1.3 },
		1
	),
	AdrenalEcho = perk(
		"AdrenalEcho",
		"Adrenal Echo",
		"The escape burst after being hit lasts 50% longer.",
		"Infiltrator",
		nil,
		level(3),
		{ SurgeDuration = 1.5 },
		2
	),
	SteadyHands = perk(
		"SteadyHands",
		"Steady Hands",
		"Calibration arcs are 20% wider.",
		"Infiltrator",
		nil,
		level(5),
		{ CalibrationArc = 1.2 },
		3
	),
	FieldPatch = perk(
		"FieldPatch",
		"Field Patch",
		"You can Patch yourself at half speed.",
		"Infiltrator",
		nil,
		level(7),
		{ SelfHeal = 1 },
		4
	),
	QuickHands = perk(
		"QuickHands",
		"Quick Hands",
		"Vault 15% faster.",
		"Infiltrator",
		nil,
		level(9),
		{ VaultSpeed = 1.15 },
		5
	),

	-- Class Protocols (class mastery)
	ShadowLag = perk(
		"ShadowLag",
		"Shadow Lag",
		"Veil lasts 40% longer.",
		"Infiltrator",
		"Ghost",
		mastery(3),
		{ VeilDuration = 1.4 },
		10
	),
	SilentLocker = perk(
		"SilentLocker",
		"Silent Locker",
		"Slip into Phase Lockers almost instantly.",
		"Infiltrator",
		"Ghost",
		mastery(6),
		{ LockerEnter = 0.2 },
		11
	),
	Failsafe = perk(
		"Failsafe",
		"Failsafe",
		"Missed calibrations cost half as much progress.",
		"Infiltrator",
		"Engineer",
		mastery(3),
		{ MissPenalty = 0.5 },
		12
	),
	RelayTap = perk(
		"RelayTap",
		"Relay Tap",
		"Power Gate Relays 25% faster.",
		"Infiltrator",
		"Engineer",
		mastery(6),
		{ Relay = 1.25 },
		13
	),
	RapidResync = perk(
		"RapidResync",
		"Rapid Re-sync",
		"Re-sync Desynced allies 20% faster.",
		"Infiltrator",
		"ChronoMedic",
		mastery(3),
		{ Revive = 1.2 },
		14
	),
	StasisWard = perk(
		"StasisWard",
		"Stasis Ward",
		"Allies you rescue keep Endurance 33% longer.",
		"Infiltrator",
		"ChronoMedic",
		mastery(6),
		{ Endurance = 1.33 },
		15
	),
	SlipstreamEcho = perk(
		"SlipstreamEcho",
		"Slipstream Echo",
		"Slipstream recharges 23% faster.",
		"Infiltrator",
		"Phantom",
		mastery(3),
		{ SlipstreamCooldown = 0.77 },
		16
	),
	FeatherFall = perk(
		"FeatherFall",
		"Feather Fall",
		"Landing a vault gives a brief burst of speed.",
		"Infiltrator",
		"Phantom",
		mastery(6),
		{ LandingHaste = 1 },
		17
	),
	OverchargePulse = perk(
		"OverchargePulse",
		"Overcharge Pulse",
		"Disruption Pulse reaches 22% further.",
		"Infiltrator",
		"Disruptor",
		mastery(3),
		{ EmpRadius = 1.22 },
		18
	),
	ShockBarrier = perk(
		"ShockBarrier",
		"Shock Barrier",
		"Barriers you drop stun 25% longer.",
		"Infiltrator",
		"Disruptor",
		mastery(6),
		{ BarrierStun = 1.25 },
		19
	),

	-- Keeper Edicts (Time-Keeper mastery)
	Relentless = perk(
		"Relentless",
		"Relentless",
		"Recover from a landed strike 25% faster.",
		"TimeKeeper",
		nil,
		mastery(1),
		{ Recoil = 0.75 },
		30
	),
	TrackersEye = perk(
		"TrackersEye",
		"Tracker's Eye",
		"Missed calibrations reveal the hacker 60% longer.",
		"TimeKeeper",
		nil,
		mastery(2),
		{ TraceDuration = 1.6 },
		31
	),
	Overseer = perk(
		"Overseer",
		"Overseer",
		"Overloaded terminals regress 30% faster.",
		"TimeKeeper",
		nil,
		mastery(4),
		{ Regression = 1.3 },
		32
	),
	PodSentinel = perk(
		"PodSentinel",
		"Pod Sentinel",
		"Rescuers are revealed to you for 4 seconds.",
		"TimeKeeper",
		nil,
		mastery(6),
		{ RevealRescuer = 1 },
		33
	),
	DeepStasis = perk(
		"DeepStasis",
		"Deep Stasis",
		"Stasis Pods drain 15% faster.",
		"TimeKeeper",
		nil,
		mastery(8),
		{ PodDrain = 1.15 },
		34
	),
	FractureLock = perk(
		"FractureLock",
		"Fracture Lock",
		"Temporal Trap stuns last 40% longer.",
		"TimeKeeper",
		nil,
		mastery(10),
		{ TrapStun = 1.4 },
		35
	),
} :: { [string]: Perk })

-- Loadout key for a perk: its class, the Keeper, or (shared Protocols) the equipping class.
function PerkConfig.get(id: string?): Perk?
	return if id then PerkConfig.Perks[id] else nil
end

export type Progress = { xp: number, mastery: { [string]: number } }

-- True when the perk is unlocked for `loadoutKey` (a class id or "TimeKeeper").
function PerkConfig.isUnlocked(definition: Perk, loadoutKey: string, progress: Progress): boolean
	if definition.Role == "TimeKeeper" then
		if loadoutKey ~= "TimeKeeper" then
			return false
		end
	elseif loadoutKey == "TimeKeeper" or (definition.Class ~= nil and definition.Class ~= loadoutKey) then
		return false
	end
	if definition.Unlock.Kind == "Level" then
		return ProgressionConfig.level(progress.xp) >= definition.Unlock.Value
	end
	local masteryKey = if definition.Role == "TimeKeeper" then "TimeKeeper" else loadoutKey
	return ProgressionConfig.level(progress.mastery[masteryKey] or 0) >= definition.Unlock.Value
end

-- Combined modifier for a set of equipped perk ids (multiplicative, default 1).
function PerkConfig.modifier(perkIds: { string }, key: string): number
	local value = 1
	for _, id in perkIds do
		local definition = PerkConfig.Perks[id]
		local m = definition and definition.Modifiers[key]
		if m then
			value *= m
		end
	end
	return value
end

function PerkConfig.list(): { Perk }
	local list = {}
	for _, definition in PerkConfig.Perks do
		table.insert(list, definition)
	end
	table.sort(list, function(a, b)
		return a.SortOrder < b.SortOrder
	end)
	return list
end

return table.freeze(PerkConfig)
