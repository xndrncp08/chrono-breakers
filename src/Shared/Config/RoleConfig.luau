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
		Tagline = "Guard the vault. Bend time. Let no one escape.",
		Description = "Hunt the Infiltrators with Chrono Strike, slow them with Time-Freeze Zones, and snare routes with Temporal Traps.",
		WalkSpeed = 17.25,
		JumpPower = 20, -- a small hop in matches; obstacles need vaults (SurvivalConfig.Movement)
		MaxHealth = 100,
		Abilities = { "ChronoStrike", "TimeFreeze", "TemporalTrap", "ChronoScan" },
	} :: RoleDefinition),
	Infiltrator = table.freeze({
		Id = "Infiltrator",
		DisplayName = "Infiltrator",
		Tagline = "Hack three terminals. Reach the breach. Get out.",
		Description = "Hack vault terminals, use your gadget to counter temporal effects, and extract before time runs out.",
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
