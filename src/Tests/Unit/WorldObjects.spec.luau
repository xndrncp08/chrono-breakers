--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local WorldObjects = require(ServerScriptService.Server.Core.WorldObjects)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

local SPECS = {
	{ id = "V1", kind = "Rail" },
	{ id = "B1", kind = "Barrier" },
	{ id = "D1", kind = "Door" },
}

return function(t: any)
	t.describe("WorldObjects", function()
		t.it("seals an over-used rail for Infiltrators only, then reopens it", function()
			local config = SurvivalConfig.World
			local objects = WorldObjects.new(SPECS, {})
			for i = 1, config.FatigueVaults - 1 do
				t.expect(objects:recordVault("V1", false, i)).toBe(false)
			end
			t.expect(objects:recordVault("V1", true, 3)).toBe(false) -- Keeper vaults never count
			t.expect(objects:recordVault("V1", false, 4)).toBe(true)
			t.expect(select(2, objects:canVault("V1", false, 5))).toBe("Locked")
			t.expect((objects:canVault("V1", true, 5))).toBe(true)
			t.expect((objects:canVault("V1", false, 4 + config.FatigueSeal))).toBe(true)
		end)

		t.it("forgets vaults that fall outside the fatigue window", function()
			local config = SurvivalConfig.World
			local objects = WorldObjects.new(SPECS, {})
			objects:recordVault("V1", false, 0)
			objects:recordVault("V1", false, 1)
			t.expect(objects:recordVault("V1", false, config.FatigueWindow + 2)).toBe(false)
		end)

		t.it("drops a barrier once, lets only Infiltrators vault it and only the Keeper break it", function()
			local objects = WorldObjects.new(SPECS, {})
			t.expect((objects:canVault("B1", false, 0))).toBe(false)
			t.expect(objects:breakBarrier("B1")).toBe(false)
			t.expect(objects:dropBarrier("B1")).toBe(true)
			t.expect(objects:dropBarrier("B1")).toBe(false)
			t.expect((objects:canVault("B1", false, 0))).toBe(true)
			t.expect(select(2, objects:canVault("B1", true, 0))).toBe("WrongRole")
			t.expect(objects:breakBarrier("B1")).toBe(true)
			t.expect(objects.barriers.B1).toBe("Broken")
			t.expect((objects:canVault("B1", false, 0))).toBe(false)
		end)

		t.it("toggles doors with a cooldown", function()
			local objects = WorldObjects.new(SPECS, {})
			local ok, open = objects:toggleDoor("D1", 0)
			t.expect(ok).toBe(true)
			t.expect(open).toBe(false)
			t.expect((objects:toggleDoor("D1", 0.5))).toBe(false)
			t.expect(select(2, objects:toggleDoor("D1", SurvivalConfig.World.DoorCooldown))).toBe(true)
			t.expect((objects:toggleDoor("Nope", 99))).toBe(false)
		end)

		t.it("holds one occupant per locker and one locker per player", function()
			local objects = WorldObjects.new({}, { "L1", "L2" })
			t.expect((objects:enterLocker("L1", 1))).toBe(true)
			t.expect(select(2, objects:enterLocker("L1", 2))).toBe("Busy")
			t.expect(select(2, objects:enterLocker("L2", 1))).toBe("AlreadyHacking")
			t.expect(select(2, objects:enterLocker("L9", 2))).toBe("UnknownTarget")
			t.expect(objects:leaveLocker(1)).toBe("L1")
			t.expect(objects:leaveLocker(1)).toBeNil()
		end)

		t.it("lands vaults on the far side, clamped inside the obstacle", function()
			local center = Vector3.new(0, 0, 0)
			local landing = WorldObjects.landing("X", center, Vector3.new(30, 3, 2), 3, 10)
			t.expect(landing.Z).toBeNear(-SurvivalConfig.World.VaultClearance)
			t.expect(landing.X).toBeNear(4.25)
			local back = WorldObjects.landing("Z", center, Vector3.new(-2, 3, 1), 3, 8)
			t.expect(back.X).toBeNear(SurvivalConfig.World.VaultClearance)
			t.expect(back.Z).toBeNear(1)
		end)
	end)
end
