--!strict
-- Timeline Conditions: one match-wide modifier rolled at match start for variety. Every condition
-- trades a benefit for one side against a benefit for the other, and reuses the perk modifier keys
-- (PerkConfig) so the systems that own each rule apply it without special cases. Values multiply
-- with perks. Weights are relative; "Stable" is the unmodified baseline.

export type Condition = {
	Id: string,
	Name: string,
	Description: string,
	Weight: number,
	Modifiers: { [string]: number },
}

local ConditionConfig = {}

local function condition(id: string, name: string, description: string, weight: number, modifiers): Condition
	return table.freeze({
		Id = id,
		Name = name,
		Description = description,
		Weight = weight,
		Modifiers = table.freeze(modifiers),
	})
end

ConditionConfig.Conditions = table.freeze({
	Stable = condition("Stable", "Stable Timeline", "No distortions this run.", 4, {}),
	Entropy = condition(
		"Entropy",
		"Accelerated Entropy",
		"Terminals breach 15% faster, but Stasis Pods drain 20% faster.",
		2,
		{ HackSpeed = 1.15, PodDrain = 1.2 }
	),
	Overcharge = condition(
		"Overcharge",
		"Overcharged Pulses",
		"Calibration arcs are 20% wider, but a miss costs 40% more progress.",
		2,
		{ CalibrationArc = 1.2, MissPenalty = 1.4 }
	),
	Brittle = condition(
		"Brittle",
		"Brittle Seconds",
		"Stasis Barriers stun the Keeper 25% longer, but the Keeper recovers from hits 20% faster.",
		2,
		{ BarrierStun = 1.25, Recoil = 0.8 }
	),
	Mending = condition(
		"Mending",
		"Mending Loop",
		"Re-sync and Patch run 20% faster, but Overloaded terminals regress 50% faster.",
		2,
		{ Revive = 1.2, Heal = 1.2, Regression = 1.5 }
	),
	Restless = condition(
		"Restless",
		"Restless Echoes",
		"Stamina recovers 20% faster, but calibration traces stay on the Keeper's screen 50% longer.",
		2,
		{ StaminaRegen = 1.2, TraceDuration = 1.5 }
	),
})

-- Stable roll order (dictionary iteration order is not defined).
ConditionConfig.Order = table.freeze({ "Stable", "Entropy", "Overcharge", "Brittle", "Mending", "Restless" })

function ConditionConfig.get(id: string?): Condition?
	return if id then (ConditionConfig.Conditions :: any)[id] else nil
end

-- Weighted pick from a uniform `r` in [0, 1).
function ConditionConfig.roll(r: number): string
	local total = 0
	for _, id in ConditionConfig.Order do
		total += (ConditionConfig.Conditions :: any)[id].Weight
	end
	local pick = math.clamp(r, 0, 0.999999) * total
	for _, id in ConditionConfig.Order do
		pick -= (ConditionConfig.Conditions :: any)[id].Weight
		if pick < 0 then
			return id
		end
	end
	return "Stable"
end

function ConditionConfig.modifier(id: string?, key: string): number
	local entry = ConditionConfig.get(id)
	return if entry then entry.Modifiers[key] or 1 else 1
end

return table.freeze(ConditionConfig)
