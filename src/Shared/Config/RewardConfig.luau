--!strict
-- Chronos Scrap rewards. Rewards are computed and granted only on the server, once per match.

local RewardConfig = {
	CurrencyName = "Chronos Scrap",
	CurrencyShort = "Scrap",
	MaxCurrency = 1_000_000_000, -- hard cap to keep values sane

	Participation = 20,
	Win = 50,

	-- Infiltrator
	PerTerminalHacked = 15,
	Extracted = 40,

	-- Survival teamwork
	PerRescue = 12,
	PerResync = 8,

	-- Time-Keeper
	PerElimination = 20,
	PerContainment = 10,

	-- Participants who disconnect before resolution receive nothing (they are not eligible).
	-- Keeps a short history of paid match ids in the profile to make payouts idempotent.
	RecentMatchHistorySize = 20,
}

return table.freeze(RewardConfig)
