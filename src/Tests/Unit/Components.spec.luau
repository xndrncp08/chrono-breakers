--!strict
-- Exercises the real FreezeZone / TemporalTrap components with Instances created by the runtime and
-- fake player records (only `.Character` is read by the components).
local ServerScriptService = game:GetService("ServerScriptService")
local FreezeZone = require(ServerScriptService.Server.Components.FreezeZone)
local TemporalTrap = require(ServerScriptService.Server.Components.TemporalTrap)

local function fakePlayer(position: Vector3): any
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = position
	root.Parent = model
	return { Character = model, root = root }
end

local function makeZone(targets: { any }, log: { any }, removed: { string }, parent: Instance)
	return FreezeZone.new({
		id = "z1",
		center = Vector3.new(0, 0, 0),
		radius = 15,
		telegraph = 0.75,
		duration = 10,
		slowMagnitude = 0.7,
		membershipInterval = 0.2,
		linger = 0.35,
		startedAt = 0,
		parent = parent,
		getTargets = function()
			return targets :: any
		end,
		applySlow = function(player, key, magnitude, duration)
			table.insert(log, { player = player, key = key, magnitude = magnitude, duration = duration })
		end,
		removeKeyFromAll = function(key)
			table.insert(removed, key)
		end,
	})
end

return function(t: any)
	t.describe("FreezeZone", function()
		t.it("telegraphs before slowing, then slows only targets inside the radius", function()
			local inside = fakePlayer(Vector3.new(5, 3, 5))
			local outside = fakePlayer(Vector3.new(40, 3, 0))
			local log, removed = {}, {}
			local folder = Instance.new("Folder")
			local zone = makeZone({ inside, outside }, log, removed, folder)
			t.expect(zone:update(0.5)).toBe(false)
			t.expect(#log).toBe(0) -- telegraph: no slow yet
			t.expect(zone:update(0.8)).toBe(false)
			t.expect(zone.state).toBe("Active")
			t.expect(#log).toBe(1)
			t.expect(log[1].player).toBe(inside)
			t.expect(log[1].magnitude).toBe(0.7)
			t.expect(log[1].key).toBe("freeze:z1")
		end)

		t.it("re-evaluates membership at a bounded interval and handles leaving/re-entering", function()
			local p = fakePlayer(Vector3.new(0, 3, 0))
			local log, removed = {}, {}
			local zone = makeZone({ p }, log, removed, Instance.new("Folder"))
			zone:update(1)
			zone:update(1.05) -- within the membership interval: no extra refresh
			t.expect(#log).toBe(1)
			p.root.Position = Vector3.new(30, 3, 0)
			zone:update(1.3)
			t.expect(#log).toBe(1) -- left the zone: no refresh (existing slow lapses after linger)
			p.root.Position = Vector3.new(2, 3, 0)
			zone:update(1.6)
			t.expect(#log).toBe(2) -- re-entered
		end)

		t.it("expires on time and removes its own slow key from everyone on destroy", function()
			local log, removed = {}, {}
			local folder = Instance.new("Folder")
			local zone = makeZone({}, log, removed, folder)
			t.expect(#folder:GetChildren()).toBe(1)
			t.expect(zone:update(10.75)).toBe(true)
			zone:destroy()
			zone:destroy() -- idempotent
			t.expect(removed).toEqual({ "freeze:z1" })
			t.expect(#folder:GetChildren()).toBe(0)
		end)
	end)

	t.describe("TemporalTrap", function()
		local function makeTrap(targets: { any }, triggered: { any }, folder: Instance)
			return TemporalTrap.new({
				id = "t1",
				position = Vector3.new(0, 0, 0),
				armingTime = 1.5,
				triggerRadius = 4,
				lifetime = 90,
				placedAt = 0,
				parent = folder,
				getTargets = function()
					return targets :: any
				end,
				onTriggered = function(trap, victim)
					table.insert(triggered, { trap = trap, victim = victim })
				end,
			})
		end

		t.it("does not trigger while arming", function()
			local p = fakePlayer(Vector3.new(1, 3, 1))
			local triggered = {}
			local trap = makeTrap({ p }, triggered, Instance.new("Folder"))
			t.expect(trap:update(1)).toBe(false)
			t.expect(#triggered).toBe(0)
		end)

		t.it("triggers exactly once for the first target in range, then finishes", function()
			local far = fakePlayer(Vector3.new(20, 3, 0))
			local near = fakePlayer(Vector3.new(2, 3, 0))
			local triggered = {}
			local folder = Instance.new("Folder")
			local trap = makeTrap({ far, near }, triggered, folder)
			t.expect(trap:update(2)).toBe(true)
			t.expect(#triggered).toBe(1)
			t.expect(triggered[1].victim).toBe(near)
			t.expect(trap.state).toBe("Triggered")
			trap:destroy()
			t.expect(#folder:GetChildren()).toBe(0)
		end)

		t.it("expires after its lifetime without triggering", function()
			local triggered = {}
			local trap = makeTrap({}, triggered, Instance.new("Folder"))
			t.expect(trap:update(89)).toBe(false)
			t.expect(trap:update(90)).toBe(true)
			t.expect(trap.state).toBe("Expired")
			t.expect(#triggered).toBe(0)
		end)
	end)
end
