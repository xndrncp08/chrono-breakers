--!strict
-- EndgameModel: Temporal Collapse state (pure). Gate Relays keep their power progress; the first
-- relay to reach full power opens the Breach Gate. Instability rises with the collapse timer:
-- Rising accelerates pods, Critical emits a shockwave every ShockwaveInterval seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type EndgameModel = {
	relays: { [string]: number },
	relayOrder: { string },
	gateOpen: boolean,
	startedAt: number?,
	endsAt: number?,
	begin: (self: EndgameModel, now: number, duration: number) -> boolean,
	power: (self: EndgameModel, relayId: string, amount: number) -> boolean,
	instability: (self: EndgameModel, now: number) -> number,
	tier: (self: EndgameModel, now: number) -> string,
	shockwaveDue: (self: EndgameModel, now: number) -> boolean,
}

local EndgameModel = {}
local config = SurvivalConfig.Endgame

function EndgameModel.new(relayIds: { string }): EndgameModel
	local nextShockwave = math.huge
	local self = {
		relays = {} :: { [string]: number },
		relayOrder = table.clone(relayIds),
		gateOpen = false,
		startedAt = nil :: number?,
		endsAt = nil :: number?,
	} :: any
	for _, id in relayIds do
		self.relays[id] = 0
	end

	function self:begin(now: number, duration: number): boolean
		if self.startedAt ~= nil then
			return false
		end
		self.startedAt = now
		self.endsAt = now + duration
		nextShockwave = now + duration * config.CriticalAt
		-- A map without relays has nothing to power: the gate opens with the collapse.
		if #self.relayOrder == 0 then
			self.gateOpen = true
		end
		return true
	end

	-- Adds power to a relay. Returns true on the call that opens the gate.
	function self:power(relayId: string, amount: number): boolean
		local current = self.relays[relayId]
		if current == nil or self.gateOpen or self.startedAt == nil or amount ~= amount or amount <= 0 then
			return false
		end
		self.relays[relayId] = math.min(1, current + amount)
		if self.relays[relayId] >= 1 - 1e-6 then
			self.relays[relayId] = 1
			self.gateOpen = true
			return true
		end
		return false
	end

	function self:instability(now: number): number
		if self.startedAt == nil or self.endsAt == nil then
			return 0
		end
		local total = (self.endsAt :: number) - (self.startedAt :: number)
		return if total <= 0 then 1 else math.clamp((now - (self.startedAt :: number)) / total, 0, 1)
	end

	function self:tier(now: number): string
		local value = self:instability(now)
		if self.startedAt == nil then
			return "Dormant"
		elseif value >= config.CriticalAt then
			return "Critical"
		elseif value >= config.RisingAt then
			return "Rising"
		end
		return "Stable"
	end

	function self:shockwaveDue(now: number): boolean
		if now >= nextShockwave and self.endsAt and now < self.endsAt then
			nextShockwave = now + config.ShockwaveInterval
			return true
		end
		return false
	end

	return self :: EndgameModel
end

return table.freeze(EndgameModel)
