--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConditionConfig = require(ReplicatedStorage.Shared.Config.ConditionConfig)

-- Modifier keys that some system actually reads (PerkService.Value/ValueFor or world.modifier).
local KNOWN_KEYS = {
	HackSpeed = true,
	PodDrain = true,
	CalibrationArc = true,
	MissPenalty = true,
	BarrierStun = true,
	Recoil = true,
	Revive = true,
	Heal = true,
	Regression = true,
	StaminaRegen = true,
	TraceDuration = true,
}

return function(t: any)
	t.describe("Timeline Conditions", function()
		t.it("lists every condition once in the roll order", function()
			local seen = {}
			for _, id in ConditionConfig.Order do
				t.expect(seen[id]).toBeNil()
				seen[id] = true
				t.expect(ConditionConfig.get(id) ~= nil).toBe(true)
			end
			for id in ConditionConfig.Conditions :: any do
				t.expect(seen[id]).toBe(true)
			end
		end)

		t.it("trades a benefit for each side using keys the game reads", function()
			for _, id in ConditionConfig.Order do
				local condition = ConditionConfig.get(id) :: ConditionConfig.Condition
				local count = 0
				for key, value in condition.Modifiers do
					count += 1
					t.expect(KNOWN_KEYS[key]).toBe(true)
					t.expect(value >= 0.5 and value <= 2 and value ~= 1).toBe(true)
				end
				t.expect(count == 0 and id == "Stable" or count >= 2).toBe(true)
				t.expect(condition.Weight > 0).toBe(true)
			end
		end)

		t.it("rolls by weight and covers the whole range", function()
			t.expect(ConditionConfig.roll(0)).toBe("Stable")
			t.expect(ConditionConfig.roll(0.9999999)).toBe(ConditionConfig.Order[#ConditionConfig.Order])
			local counts: { [string]: number } = {}
			for i = 0, 999 do
				local id = ConditionConfig.roll(i / 1000)
				counts[id] = (counts[id] or 0) + 1
			end
			for _, id in ConditionConfig.Order do
				t.expect((counts[id] or 0) > 0).toBe(true)
			end
			t.expect(counts.Stable).toBeGreaterThan(counts.Entropy)
		end)

		t.it("defaults unknown conditions and keys to 1", function()
			t.expect(ConditionConfig.modifier(nil, "HackSpeed")).toBe(1)
			t.expect(ConditionConfig.modifier("Nope", "HackSpeed")).toBe(1)
			t.expect(ConditionConfig.modifier("Entropy", "Revive")).toBe(1)
			t.expect(ConditionConfig.modifier("Entropy", "HackSpeed")).toBe(1.15)
		end)
	end)
end
