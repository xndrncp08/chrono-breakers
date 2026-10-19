--!strict
-- Role definitions and baseline movement. Baselines are the single source of truth for movement:
-- status effects are always computed from these values, never from a character's current speed.

export type RoleDefinition = {
	Id: string,
	DisplayName: string,
	Tagline: string,
	Description: string,
	WalkSpeed: number,
	JumpPower: number,
	MaxHealth: number,
	Abilities: { string },
}

local RoleConfig = {}

RoleConfig.Lobby = table.freeze({
	WalkSpeed = 16,
	JumpPower = 50,
	MaxHealth = 100,
})

RoleConfig.Roles = table.freeze({
	TimeKeeper = table.freeze({
		Id = "TimeKeeper",
		DisplayName = "Time-Keeper",
		Tagline = "Hunt them down. Phase-Lock the fallen. Let no one escape.",
		Description = "Strike twice to Desync an Infiltrator, Phase-Lock them into a Stasis Pod, Overload terminals and use Freeze Zones, Traps and Pulses to control the hunt. Camping a pod only frees its captive.",
		WalkSpeed = 17.25,
		JumpPower = 20, -- a small hop in matches; obstacles need vaults (SurvivalConfig.Movement)
		MaxHealth = 100,
		Abilities = { "ChronoStrike", "TimeFreeze", "TemporalTrap", "ChronoScan" },
	} :: RoleDefinition),
	Infiltrator = table.freeze({
		Id = "Infiltrator",
		DisplayName = "Infiltrator",
		Tagline = "Breach four terminals. Rescue your squad. Survive the Collapse.",
		Description = "Hack terminals and nail Calibration Pulses, sprint, vault and drop Stasis Barriers to break chases, Re-sync and rescue allies, then power a relay and escape before the timeline collapses.",
		WalkSpeed = 15,
		JumpPower = 20,
		MaxHealth = 100,
		Abilities = {},
	} :: RoleDefinition),
})

function RoleConfig.get(roleId: string): RoleDefinition?
	return (RoleConfig.Roles :: any)[roleId]
end

return table.freeze(RoleConfig)
