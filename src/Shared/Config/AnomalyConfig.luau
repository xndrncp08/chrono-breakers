--!strict
local AnomalyConfig = {}
AnomalyConfig.FirstDelay = 30
AnomalyConfig.Interval = 35
AnomalyConfig.Warning = 3
AnomalyConfig.Radius = 13
AnomalyConfig.MembershipInterval = 0.2
AnomalyConfig.PortalCooldown = 4
AnomalyConfig.Order =
	table.freeze({ "Distortion", "Gravity", "Stasis", "Fracture", "Portal", "Rewind", "Pulse", "Surge" })
AnomalyConfig.Events = table.freeze({
	Distortion = {
		Name = "TIME DISTORTION",
		Description = "Local time slows movement by 35%. Leave the cyan boundary.",
		Duration = 9,
	},
	Gravity = {
		Name = "GRAVITY FLUX",
		Description = "Local gravity drops to 45%. Jump carefully; effect ends outside the zone.",
		Duration = 10,
	},
	Stasis = {
		Name = "ENVIRONMENTAL STASIS",
		Description = "Frozen fragments pulse a brief stun every 2s. Stabilizer counters it.",
		Duration = 6,
	},
	Fracture = {
		Name = "TIMELINE FRACTURE",
		Description = "A temporary wall splits this route. Flank around either edge.",
		Duration = 10,
	},
	Portal = {
		Name = "TEMPORAL PORTALS",
		Description = "Use a portal prompt for a shortcut. Both teams can travel; 4s reuse delay.",
		Duration = 12,
	},
	Rewind = {
		Name = "OBJECT REWIND",
		Description = "A shifting holographic block rewinds, blocking scans and attacks through it.",
		Duration = 10,
	},
	Pulse = {
		Name = "UNSTABLE REACTOR",
		Description = "Inside: Infiltrators take 8 damage every 1.5s; the Keeper is slowed 35%.",
		Duration = 8,
	},
	Surge = {
		Name = "ACCELERATION SURGE",
		Description = "Local movement accelerates by 50% for both teams. Risk the faster route.",
		Duration = 8,
	},
})
return table.freeze(AnomalyConfig)
