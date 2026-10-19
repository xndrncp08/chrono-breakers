--!strict
-- StaminaModel: server-owned sprint stamina for one Infiltrator (pure).
-- Sprinting drains while the player wants to sprint *and* is moving. Regeneration starts RegenDelay
-- seconds after the last drain. Emptying the bar exhausts the player until it refills to
-- RecoverThreshold, so sprint cannot be feathered indefinitely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type StaminaModel = {
	value: number,
	max: number,
	wanted: boolean,
	exhausted: boolean,
	sprinting: boolean,
	setWanted: (self: StaminaModel, wanted: boolean) -> (),
	-- Returns true when the sprinting state changed.
	tick: (self: StaminaModel, now: number, dt: number, moving: boolean, allowed: boolean) -> boolean,
	fraction: (self: StaminaModel) -> number,
}

local StaminaModel = {}
local config = SurvivalConfig.Stamina

function StaminaModel.new(maxMultiplier: number?, regenMultiplier: number?): StaminaModel
	local max = config.Max * math.clamp(maxMultiplier or 1, 0.5, 2)
	local regen = config.RegenPerSecond * math.clamp(regenMultiplier or 1, 0.5, 2)
	local lastDrainAt = -math.huge
	local self = {
		value = max,
		max = max,
		wanted = false,
		exhausted = false,
		sprinting = false,
	} :: any

	function self:setWanted(wanted: boolean)
		self.wanted = wanted
	end

	function self:tick(now: number, dt: number, moving: boolean, allowed: boolean): boolean
		local was = self.sprinting
		local sprint = self.wanted and moving and allowed and not self.exhausted and self.value > 0
		if sprint then
			self.value = math.max(0, self.value - config.DrainPerSecond * dt)
			lastDrainAt = now
			if self.value <= 0 then
				self.exhausted = true
				sprint = false
			end
		elseif now - lastDrainAt >= config.RegenDelay then
			self.value = math.min(self.max, self.value + regen * dt)
			if self.exhausted and self.value >= config.RecoverThreshold * self.max / config.Max then
				self.exhausted = false
			end
		end
		self.sprinting = sprint
		return was ~= sprint
	end

	function self:fraction(): number
		return self.value / self.max
	end

	return self :: StaminaModel
end

return table.freeze(StaminaModel)
