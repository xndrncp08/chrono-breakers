--!strict
local MapConfig = {}
MapConfig.Order = table.freeze({ "Vault", "Metropolis", "Laboratory", "Nexus" })
MapConfig.Maps = table.freeze({
	Vault = { Name = "The Chronos Vault", Description = "Shelving lanes, reactor cover, and the original vault heist." },
	Metropolis = {
		Name = "Fractured Metropolis",
		Description = "Cross neon streets, flank city blocks, and breach the transit dock.",
	},
	Laboratory = {
		Name = "The Forgotten Laboratory",
		Description = "Parallel research wings and a hazardous central test chamber.",
	},
	Nexus = {
		Name = "Temporal Nexus",
		Description = "Four pylons surround a fractured core with broad rotation routes.",
	},
})
return table.freeze(MapConfig)
