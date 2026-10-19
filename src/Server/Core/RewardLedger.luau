--!strict
-- Applies a reward breakdown to a profile exactly once per match id. The profile keeps a bounded
-- list of recently paid match ids, so duplicate resolution events (or a duplicate call after a
-- reconnect within the same server) can never pay twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)

local Progression = require(script.Parent.Progression)
local Economy = require(script.Parent.Economy)
local ProfileSchema = require(script.Parent.ProfileSchema)
local RewardCalculator = require(script.Parent.RewardCalculator)

local RewardLedger = {}

function RewardLedger.hasPaid(profile: ProfileSchema.Profile, matchId: string): boolean
	return table.find(profile.RecentMatchIds, matchId) ~= nil
end

-- Returns (applied, amountGranted). Ineligible breakdowns are recorded as paid with 0 so that a
-- later duplicate cannot be treated as new.
function RewardLedger.apply(
	profile: ProfileSchema.Profile,
	matchId: string,
	breakdown: RewardCalculator.Breakdown
): (boolean, number, { string }?)
	if type(matchId) ~= "string" or #matchId == 0 then
		return false, 0
	end
	if RewardLedger.hasPaid(profile, matchId) then
		return false, 0
	end
	table.insert(profile.RecentMatchIds, matchId)
	while #profile.RecentMatchIds > RewardConfig.RecentMatchHistorySize do
		table.remove(profile.RecentMatchIds, 1)
	end
	if not breakdown.eligible then
		return true, 0
	end
	local granted = Economy.grant(profile, breakdown.total)
	local stats = profile.Stats :: any
	for key, delta in breakdown.statDeltas do
		if stats[key] ~= nil and delta > 0 then
			stats[key] += math.floor(delta)
		end
	end
	local bonus, notifications = Progression.apply(profile, breakdown)
	return true, granted + bonus, notifications
end

return table.freeze(RewardLedger)
