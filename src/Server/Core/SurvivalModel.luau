--!strict
-- SurvivalModel: the integrity ladder and Stasis Pod containment for every Infiltrator (pure).
--
--   Healthy --hit--> Injured --hit--> Downed --Phase-Lock/bleed-out--> Contained --timer--> Erased
--   Injured --Patch--> Healthy   Downed --Re-sync--> Injured   Contained --rescue/feedback--> Injured
--
-- Stage = how many times the player has been contained. Stage n uses StageDurations[n]; a stage past
-- the list erases immediately. Endurance (granted on rescue) absorbs one hit that would Desync.
-- The model never decides *who* may act; MatchDirector validates actors, ranges and phases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type Condition = "Healthy" | "Injured" | "Downed" | "Contained"

export type Vital = {
	userId: number,
	condition: Condition,
	stage: number,
	heal: number,
	revive: number,
	bleedoutAt: number?,
	podId: string?,
	podRemaining: number,
	podDuration: number,
	feedback: number,
	enduranceUntil: number,
}

export type Event = { kind: string, userId: number, podId: string? }

export type TickQuery = {
	isCamped: (podId: string) -> boolean,
	drainMultiplier: number,
}

export type SurvivalModel = {
	vitals: { [number]: Vital },
	pods: { [string]: number },
	podOrder: { string },
	add: (self: SurvivalModel, userId: number) -> Vital,
	get: (self: SurvivalModel, userId: number) -> Vital?,
	remove: (self: SurvivalModel, userId: number) -> (),
	isFree: (self: SurvivalModel, userId: number) -> boolean,
	hit: (self: SurvivalModel, userId: number, now: number) -> string,
	recover: (self: SurvivalModel, userId: number, kind: string, amount: number) -> boolean,
	contain: (self: SurvivalModel, userId: number, podId: string, now: number) -> string,
	release: (self: SurvivalModel, userId: number, now: number, enduranceScale: number?) -> boolean,
	occupied: (self: SurvivalModel) -> { [string]: boolean },
	tick: (self: SurvivalModel, now: number, dt: number, query: TickQuery) -> { Event },
}

local SurvivalModel = {}

local integrity = SurvivalConfig.Integrity
local containment = SurvivalConfig.Containment

function SurvivalModel.isFreeCondition(condition: string?): boolean
	return condition == "Healthy" or condition == "Injured"
end

function SurvivalModel.new(podIds: { string }): SurvivalModel
	local self = {
		vitals = {} :: { [number]: Vital },
		pods = {} :: { [string]: number },
		podOrder = table.clone(podIds),
	} :: any

	function self:add(userId: number): Vital
		local vital: Vital = {
			userId = userId,
			condition = "Healthy",
			stage = 0,
			heal = 0,
			revive = 0,
			bleedoutAt = nil,
			podId = nil,
			podRemaining = 0,
			podDuration = 0,
			feedback = 0,
			enduranceUntil = -math.huge,
		}
		self.vitals[userId] = vital
		return vital
	end

	function self:get(userId: number): Vital?
		return self.vitals[userId]
	end

	local function vacate(vital: Vital)
		if vital.podId and self.pods[vital.podId] == vital.userId then
			self.pods[vital.podId] = nil
		end
		vital.podId = nil
		vital.feedback = 0
	end

	-- Removes a player from play (erased, extracted, disconnected); frees their pod.
	function self:remove(userId: number)
		local vital = self.vitals[userId]
		if vital then
			vacate(vital)
			vital.bleedoutAt = nil
		end
	end

	function self:isFree(userId: number): boolean
		local vital = self.vitals[userId]
		return vital ~= nil and SurvivalModel.isFreeCondition(vital.condition)
	end

	-- Returns "Injured", "Downed", "Endured" or "Ignored".
	function self:hit(userId: number, now: number): string
		local vital = self.vitals[userId]
		if not vital then
			return "Ignored"
		end
		if vital.condition == "Healthy" then
			vital.condition = "Injured"
			vital.heal = 0
			return "Injured"
		elseif vital.condition == "Injured" then
			if now < vital.enduranceUntil then
				vital.enduranceUntil = -math.huge
				return "Endured"
			end
			vital.condition = "Downed"
			vital.revive = 0
			vital.heal = 0
			vital.bleedoutAt = now + integrity.BleedoutTime
			return "Downed"
		end
		return "Ignored"
	end

	-- Adds Patch ("Heal") or Re-sync ("Revive") progress. Returns true on the completing call.
	function self:recover(userId: number, kind: string, amount: number): boolean
		local vital = self.vitals[userId]
		if not vital or amount ~= amount or amount <= 0 then
			return false
		end
		if kind == "Heal" and vital.condition == "Injured" then
			vital.heal = math.min(1, vital.heal + amount)
			if vital.heal >= 1 - 1e-6 then
				vital.heal = 0
				vital.condition = "Healthy"
				return true
			end
		elseif kind == "Revive" and vital.condition == "Downed" then
			vital.revive = math.min(1, vital.revive + amount)
			if vital.revive >= 1 - 1e-6 then
				vital.revive = 0
				vital.bleedoutAt = nil
				vital.condition = "Injured"
				vital.heal = 0
				return true
			end
		end
		return false
	end

	-- Places a Downed player in a free pod. Returns "Contained", "Erased" (final stage) or "Ignored".
	function self:contain(userId: number, podId: string, _now: number): string
		local vital = self.vitals[userId]
		if not vital or vital.condition ~= "Downed" or self.pods[podId] ~= nil then
			return "Ignored"
		end
		vital.stage += 1
		vital.bleedoutAt = nil
		vital.revive = 0
		local duration = containment.StageDurations[vital.stage]
		if duration == nil then
			return "Erased"
		end
		vital.condition = "Contained"
		vital.podId = podId
		vital.podDuration = duration
		vital.podRemaining = duration
		vital.feedback = 0
		self.pods[podId] = userId
		return "Contained"
	end

	-- Frees a captive (rescue or feedback release). The captive returns Injured with Endurance.
	function self:release(userId: number, now: number, enduranceScale: number?): boolean
		local vital = self.vitals[userId]
		if not vital or vital.condition ~= "Contained" then
			return false
		end
		vacate(vital)
		vital.condition = "Injured"
		vital.heal = 0
		vital.enduranceUntil = now + containment.EnduranceDuration * (enduranceScale or 1)
		return true
	end

	function self:occupied(): { [string]: boolean }
		local map: { [string]: boolean } = {}
		for podId in self.pods do
			map[podId] = true
		end
		return map
	end

	-- Advances bleed-out and pod timers. Emits BledOut (caller Phase-Locks), Erased (pod expired)
	-- and Released (camping feedback freed the captive).
	function self:tick(now: number, dt: number, query: TickQuery): { Event }
		local events: { Event } = {}
		for userId, vital in self.vitals do
			if vital.condition == "Downed" and vital.bleedoutAt and now >= vital.bleedoutAt then
				vital.bleedoutAt = nil
				table.insert(events, { kind = "BledOut", userId = userId })
			elseif vital.condition == "Contained" and vital.podId then
				local podId = vital.podId :: string
				local camped = query.isCamped(podId)
				local rate = query.drainMultiplier * (if camped then containment.CampDrainMultiplier else 1)
				vital.podRemaining = math.max(0, vital.podRemaining - dt * rate)
				if camped then
					vital.feedback = math.min(1, vital.feedback + dt / containment.CampReleaseTime)
				else
					vital.feedback = math.max(0, vital.feedback - dt / containment.CampDecayTime)
				end
				if vital.feedback >= 1 then
					self:release(userId, now)
					table.insert(events, { kind = "Released", userId = userId, podId = podId })
				elseif vital.podRemaining <= 0 then
					vacate(vital)
					table.insert(events, { kind = "Erased", userId = userId, podId = podId })
				end
			end
		end
		table.sort(events, function(a, b)
			return a.userId < b.userId
		end)
		return events
	end

	return self :: SurvivalModel
end

return table.freeze(SurvivalModel)
