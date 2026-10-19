--!strict
-- Server-only tunables: rate limits, persistence, security thresholds. Never replicated.

local ServerConfig = {}

-- Token-bucket limits per remote (see docs/NETWORK_CONTRACT.md).
ServerConfig.RateLimits = table.freeze({
	HackChallengeRequest = table.freeze({ capacity = 3, refillPerSecond = 1 }),
	PingRequest = table.freeze({ capacity = 2, refillPerSecond = 0.25 }),
	MapVoteRequest = table.freeze({ capacity = 3, refillPerSecond = 0.5 }),
	QueueRequest = table.freeze({ capacity = 4, refillPerSecond = 1 }),
	ObjectiveRequest = table.freeze({ capacity = 4, refillPerSecond = 2 }),
	AbilityRequest = table.freeze({ capacity = 6, refillPerSecond = 4 }),
	ShopRequest = table.freeze({ capacity = 4, refillPerSecond = 1 }),
	SettingsUpdate = table.freeze({ capacity = 3, refillPerSecond = 0.5 }),
	RateNotice = table.freeze({ capacity = 2, refillPerSecond = 0.2 }),
	ClientReady = table.freeze({ capacity = 2, refillPerSecond = 0.2 }),
	PortalPrompt = table.freeze({ capacity = 2, refillPerSecond = 0.5 }),
	HackPrompt = table.freeze({ capacity = 4, refillPerSecond = 2 }),
})

ServerConfig.Persistence = table.freeze({
	DataStoreName = "ChronoBreakersProfiles_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 120,
	MaxAttempts = 5,
	BaseBackoff = 1,
	MaxBackoff = 8,
	LockTimeout = 1800, -- seconds before another server's lock counts as stale
	ShutdownTimeout = 25,
	-- In Studio without API access, fall back to an in-memory store (data is not persisted).
	StudioMemoryFallback = true,
})

ServerConfig.Security = table.freeze({
	ViolationWindow = 60, -- seconds
	ViolationLogThreshold = 10, -- log a summary once a player exceeds this many in the window
	-- Disabled by default: rejection + diagnostics are preferred over automatic punishment.
	KickOnFlood = false,
	FloodKickThreshold = 400,
	MovementCheckInterval = 0.5,
	MovementTolerance = 1.6, -- multiplier on the expected max speed
	MovementSlack = 6, -- studs of slack per sample (knockback, physics)
})

ServerConfig.Combat = table.freeze({
	EyeHeight = 1.5,
})

return table.freeze(ServerConfig)
