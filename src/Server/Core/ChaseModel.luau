--!strict
-- ChaseModel: decides who the Time-Keeper is pursuing and how much Hunt Momentum they have (pure).
-- A chase opens after the Keeper keeps line of sight to a target inside StartRange for StartDwell
-- seconds, and closes after LoseSightGrace seconds without sight or immediately beyond MaxRange.
-- Momentum grows with continuous chase time and resets on a hit, a stun or when every chase ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type Sample = { userId: number, distance: number, visible: boolean }
export type Event = { kind: string, userId: number }

export type ChaseModel = {
	chasing: { [number]: boolean },
	update: (self: ChaseModel, now: number, samples: { Sample }) -> { Event },
	momentum: (self: ChaseModel, now: number) -> number,
	resetMomentum: (self: ChaseModel, now: number) -> (),
	isChased: (self: ChaseModel, userId: number) -> boolean,
	anyChase: (self: ChaseModel) -> boolean,
	chaseStartedAt: (self: ChaseModel) -> number?,
	clear: (self: ChaseModel) -> { Event },
}

local ChaseModel = {}
local config = SurvivalConfig.Chase

function ChaseModel.new(): ChaseModel
	local dwellSince: { [number]: number } = {}
	local lastSeen: { [number]: number } = {}
	local momentumFrom: number? = nil
	local self = { chasing = {} :: { [number]: boolean } } :: any

	local function anyChase(): boolean
		return next(self.chasing) ~= nil
	end

	function self:update(now: number, samples: { Sample }): { Event }
		local events: { Event } = {}
		local present: { [number]: boolean } = {}
		for _, sample in samples do
			local userId = sample.userId
			present[userId] = true
			local inRange = sample.visible and sample.distance <= config.StartRange
			if self.chasing[userId] then
				if sample.visible and sample.distance <= config.MaxRange then
					lastSeen[userId] = now
				end
				local lost = sample.distance > config.MaxRange
					or now - (lastSeen[userId] or now) >= config.LoseSightGrace
				if lost then
					self.chasing[userId] = nil
					dwellSince[userId] = nil
					table.insert(events, { kind = "ChaseEnded", userId = userId })
				end
			elseif inRange then
				dwellSince[userId] = dwellSince[userId] or now
				if now - dwellSince[userId] >= config.StartDwell then
					self.chasing[userId] = true
					lastSeen[userId] = now
					if momentumFrom == nil then
						momentumFrom = now
					end
					table.insert(events, { kind = "ChaseStarted", userId = userId })
				end
			else
				dwellSince[userId] = nil
			end
		end
		-- Targets no longer sampled (downed, contained, hidden, gone) leave the chase.
		for userId in self.chasing do
			if not present[userId] then
				self.chasing[userId] = nil
				table.insert(events, { kind = "ChaseEnded", userId = userId })
			end
		end
		for userId in dwellSince do
			if not present[userId] then
				dwellSince[userId] = nil
			end
		end
		if not anyChase() then
			momentumFrom = nil
		end
		table.sort(events, function(a, b)
			return a.userId < b.userId
		end)
		return events
	end

	function self:momentum(now: number): number
		if momentumFrom == nil then
			return 0
		end
		local steps = math.floor((now - (momentumFrom :: number)) / config.MomentumInterval)
		return math.min(config.MomentumMax, steps * config.MomentumStep)
	end

	function self:resetMomentum(now: number)
		momentumFrom = if anyChase() then now else nil
	end

	function self:isChased(userId: number): boolean
		return self.chasing[userId] == true
	end

	function self:anyChase(): boolean
		return anyChase()
	end

	function self:chaseStartedAt(): number?
		return momentumFrom
	end

	function self:clear(): { Event }
		local events: { Event } = {}
		for userId in self.chasing do
			table.insert(events, { kind = "ChaseEnded", userId = userId })
		end
		table.clear(self.chasing)
		table.clear(dwellSince)
		table.clear(lastSeen)
		momentumFrom = nil
		return events
	end

	return self :: ChaseModel
end

return table.freeze(ChaseModel)
