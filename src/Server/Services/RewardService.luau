--!strict
-- RewardService: turns an authoritative MatchResult into per-player rewards and a results payload.
-- Payouts are idempotent at two levels: an in-memory (matchId, userId) ledger for this server, and the
-- profile's RecentMatchIds (RewardLedger). Only participants still connected at resolution are
-- eligible; aborted matches pay nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local RewardCalculator = require(script.Parent.Parent.Core.RewardCalculator)
local RewardLedger = require(script.Parent.Parent.Core.RewardLedger)

local RewardService = {}

local deps: { [string]: any } = {}
local paid: { [string]: boolean } = {}
local paidOrder: { string } = {}
local PAID_MEMORY = 500

local function remember(key: string)
	paid[key] = true
	table.insert(paidOrder, key)
	if #paidOrder > PAID_MEMORY then
		paid[table.remove(paidOrder, 1) :: string] = nil
	end
end

function RewardService.Init(injected: { [string]: any })
	deps = injected
end

function RewardService.HasPaid(matchId: string, userId: number): boolean
	return paid[`{matchId}:{userId}`] == true
end

function RewardService.GrantMatchRewards(result: any)
	local publicParticipants: { GameTypes.PublicParticipant } = {}
	for userId, p in result.participants do
		table.insert(publicParticipants, { userId = userId, name = p.name, role = p.role, status = p.status })
	end
	table.sort(publicParticipants, function(a, b)
		if a.role ~= b.role then
			return a.role == "TimeKeeper"
		end
		return a.userId < b.userId
	end)

	for userId, participant in result.participants do
		local key = `{result.matchId}:{userId}`
		if paid[key] then
			continue -- duplicate resolution for this player: never pay twice
		end
		remember(key)
		local player = Players:GetPlayerByUserId(userId)
		local breakdown = RewardCalculator.compute(result, participant)
		local saved = false
		local granted = 0
		if player and breakdown.eligible then
			local applied, amount = deps.PlayerDataService.Mutate(player, function(profile)
				local didApply, got = RewardLedger.apply(profile, result.matchId, breakdown)
				return if didApply then got else -1
			end)
			if applied and amount ~= nil and amount >= 0 then
				granted = amount
				saved = deps.PlayerDataService.IsPersistent(player)
				deps.PlayerDataService.SaveSoon(player)
			elseif not applied then
				warn(`[RewardService] could not apply rewards for user {userId} in match {result.matchId}`)
			end
		end
		if player then
			local payload: GameTypes.MatchResultPayload = {
				matchId = result.matchId,
				winner = result.winner,
				reason = result.reason,
				yourRole = participant.role,
				yourStatus = participant.status,
				won = breakdown.won,
				rewards = breakdown.lines,
				rewardTotal = granted,
				rewardsSaved = saved,
				stats = {
					hacks = participant.hacks,
					eliminations = participant.eliminations,
					extracted = participant.extracted,
				},
				participants = publicParticipants,
			}
			deps.NetworkService.FireClient(RemoteNames.MatchResult, player, payload)
		end
	end
end

return RewardService
