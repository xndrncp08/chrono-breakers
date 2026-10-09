--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local AbilityRules = require(ServerScriptService.Server.Core.AbilityRules)
local PlacementRules = require(ServerScriptService.Server.Core.PlacementRules)

local BOUNDS_MIN = Vector3.new(-90, -5, -90)
local BOUNDS_MAX = Vector3.new(90, 40, 90)

local function flatGround(from: Vector3, depth: number): PlacementRules.GroundHit?
	if from.Y - depth <= 0 and from.Y >= 0 then
		return { position = Vector3.new(from.X, 0, from.Z), normal = Vector3.new(0, 1, 0) }
	end
	return nil
end

local function clearSight(_: Vector3, _: Vector3): boolean
	return true
end

local function input(target: any, overrides: { [string]: any }?): PlacementRules.PlacementInput
	local base: any = {
		casterPosition = Vector3.new(0, 3, 0),
		eyePosition = Vector3.new(0, 4.5, 0),
		target = target,
		maxRange = 70,
		boundsMin = BOUNDS_MIN,
		boundsMax = BOUNDS_MAX,
		castDown = flatGround,
		lineOfSight = clearSight,
	}
	if overrides then
		for k, v in overrides do
			base[k] = v
		end
	end
	return base
end

local function ctx(overrides: { [string]: any }?): AbilityRules.CasterContext
	local base: any = {
		abilityId = "TimeFreeze",
		phase = "Active",
		role = "TimeKeeper",
		participantActive = true,
		alive = true,
		restrained = false,
		cooldownReady = true,
		equippedGadget = nil,
	}
	if overrides then
		for k, v in overrides do
			base[k] = v
		end
	end
	return base
end

return function(t: any)
	t.describe("PlacementRules", function()
		t.it("accepts a valid ground target and returns the server-derived ground point", function()
			local ok, code, ground = PlacementRules.validateGroundTarget(input(Vector3.new(20, 0.4, 10)))
			t.expect(ok).toBe(true)
			t.expect(code).toBe("Ok")
			t.expect((ground :: Vector3).Y).toBe(0)
		end)

		t.it("rejects non-Vector3, NaN, and infinite targets", function()
			t.expect((PlacementRules.validateGroundTarget(input("here")))).toBe(false)
			t.expect((PlacementRules.validateGroundTarget(input(Vector3.new(0 / 0, 0, 0))))).toBe(false)
			local ok, code = PlacementRules.validateGroundTarget(input(Vector3.new(math.huge, 0, 0)))
			t.expect(ok).toBe(false)
			t.expect(code).toBe("InvalidPayload")
		end)

		t.it("rejects targets beyond the cast range", function()
			local ok, code = PlacementRules.validateGroundTarget(input(Vector3.new(80, 0, 0)))
			t.expect(ok).toBe(false)
			t.expect(code).toBe("OutOfRange")
		end)

		t.it("rejects targets outside the playable bounds", function()
			local ok, code = PlacementRules.validateGroundTarget(
				input(Vector3.new(0, 0, -95), { casterPosition = Vector3.new(0, 3, -80) })
			)
			t.expect(ok).toBe(false)
			t.expect(code).toBe("OutOfBounds")
		end)

		t.it("rejects mid-air targets with no ground below", function()
			local ok, code = PlacementRules.validateGroundTarget(input(Vector3.new(10, 30, 10)))
			t.expect(ok).toBe(false)
			t.expect(code).toBe("InvalidPlacement")
		end)

		t.it("rejects walls (non-walkable normals)", function()
			local ok, code = PlacementRules.validateGroundTarget(input(Vector3.new(10, 0, 0), {
				castDown = function(from: Vector3)
					return { position = Vector3.new(from.X, 0, from.Z), normal = Vector3.new(1, 0, 0) }
				end,
			}))
			t.expect(ok).toBe(false)
			t.expect(code).toBe("InvalidPlacement")
		end)

		t.it("rejects placement through walls (no line of sight)", function()
			local ok, code = PlacementRules.validateGroundTarget(input(Vector3.new(10, 0, 0), {
				lineOfSight = function()
					return false
				end,
			}))
			t.expect(ok).toBe(false)
			t.expect(code).toBe("NoLineOfSight")
		end)

		t.it("measures spacing and cylinder membership", function()
			t.expect(PlacementRules.isClearOf(Vector3.new(0, 0, 0), { Vector3.new(5, 0, 0) }, 10)).toBe(false)
			t.expect(PlacementRules.isClearOf(Vector3.new(0, 0, 0), { Vector3.new(15, 0, 0) }, 10)).toBe(true)
			t.expect(PlacementRules.isInsideCylinder(Vector3.zero, 15, 8, Vector3.new(14, 3, 0))).toBe(true)
			t.expect(PlacementRules.isInsideCylinder(Vector3.zero, 15, 8, Vector3.new(16, 3, 0))).toBe(false)
			t.expect(PlacementRules.isInsideCylinder(Vector3.zero, 15, 8, Vector3.new(0, 12, 0))).toBe(false)
		end)
	end)

	t.describe("AbilityRules.checkCaster", function()
		t.it("accepts a valid Time-Keeper cast", function()
			t.expect((AbilityRules.checkCaster(ctx()))).toBe(true)
		end)

		t.it("rejects unknown or malformed ability ids", function()
			local _, code = AbilityRules.checkCaster(ctx({ abilityId = "GodMode" }))
			t.expect(code).toBe("InvalidPayload")
			local _, code2 = AbilityRules.checkCaster(ctx({ abilityId = 42 }))
			t.expect(code2).toBe("InvalidPayload")
		end)

		t.it("rejects the wrong role", function()
			local _, code = AbilityRules.checkCaster(ctx({ role = "Infiltrator" }))
			t.expect(code).toBe("WrongRole")
			local noRole = ctx()
			noRole.role = nil -- (a nil value in an overrides table literal would be a no-op)
			local _, code2 = AbilityRules.checkCaster(noRole)
			t.expect(code2).toBe("NotParticipant")
		end)

		t.it("rejects casts outside active phases", function()
			for _, phase in { "WaitingForPlayers", "Intro", "Resolving", "ReturningToLobby" } do
				local _, code = AbilityRules.checkCaster(ctx({ phase = phase }))
				t.expect(code).toBe("WrongPhase")
			end
			t.expect((AbilityRules.checkCaster(ctx({ phase = "Extraction" })))).toBe(true)
		end)

		t.it("rejects dead, restrained, or cooling-down casters", function()
			t.expect(select(2, AbilityRules.checkCaster(ctx({ alive = false })))).toBe("NotAlive")
			t.expect(select(2, AbilityRules.checkCaster(ctx({ restrained = true })))).toBe("Restrained")
			t.expect(select(2, AbilityRules.checkCaster(ctx({ cooldownReady = false })))).toBe("OnCooldown")
		end)

		t.it("only allows the equipped gadget for Infiltrators", function()
			local base = { role = "Infiltrator", abilityId = "PhaseDash" }
			t.expect(select(2, AbilityRules.checkCaster(ctx(base)))).toBe("NotOwned")
			local equipped = { role = "Infiltrator", abilityId = "PhaseDash", equippedGadget = "PhaseDash" }
			t.expect((AbilityRules.checkCaster(ctx(equipped)))).toBe(true)
		end)
	end)

	t.describe("AbilityRules.selectStrikeTarget", function()
		local origin = Vector3.new(0, 3, 0)
		local aim = Vector3.new(0, 0, -1)
		local always = function()
			return true
		end

		t.it("picks the nearest target inside range and cone", function()
			local target = AbilityRules.selectStrikeTarget(origin, aim, {
				{ userId = 1, position = Vector3.new(0, 3, -8) },
				{ userId = 2, position = Vector3.new(0, 3, -4) },
				{ userId = 3, position = Vector3.new(0, 3, 4) }, -- behind
			}, 9, 70, always)
			t.expect(target).toBe(2)
		end)

		t.it("ignores targets out of range, outside the cone, or not visible", function()
			t.expect(AbilityRules.selectStrikeTarget(origin, aim, {
				{ userId = 1, position = Vector3.new(0, 3, -20) },
				{ userId = 2, position = Vector3.new(8, 3, -2) },
			}, 9, 70, always)).toBeNil()
			t.expect(AbilityRules.selectStrikeTarget(
				origin,
				aim,
				{
					{ userId = 1, position = Vector3.new(0, 3, -5) },
				},
				9,
				70,
				function()
					return false
				end
			)).toBeNil()
		end)
	end)
end
