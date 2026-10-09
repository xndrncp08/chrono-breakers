--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local RoleSelector = require(ServerScriptService.Server.Core.RoleSelector)

local function first(_: number): number
	return 1
end

return function(t: any)
	t.describe("RoleSelector", function()
		t.it("assigns exactly one Time-Keeper and the rest Infiltrators", function()
			for n = 2, 5 do
				local candidates = {}
				for i = 1, n do
					table.insert(candidates, i)
				end
				local roles = RoleSelector.assign(candidates, {}, first)
				local keepers, infiltrators = 0, 0
				for _, role in roles do
					if role == "TimeKeeper" then
						keepers += 1
					else
						infiltrators += 1
					end
				end
				t.expect(keepers).toBe(1)
				t.expect(infiltrators).toBe(n - 1)
			end
		end)

		t.it("prefers the player who waited longest to be Keeper", function()
			local history = { [1] = 0, [2] = 3, [3] = 1 }
			t.expect(RoleSelector.selectKeeper({ 1, 2, 3 }, history, first)).toBe(2)
		end)

		t.it("breaks ties with the injected random index", function()
			local history = { [1] = 2, [2] = 2, [3] = 0 }
			t.expect(RoleSelector.selectKeeper({ 1, 2, 3 }, history, function(n)
				return n
			end)).toBe(2)
		end)

		t.it("rotates the Keeper across consecutive matches", function()
			local history = {}
			local players = { 10, 20, 30 }
			local seen: { [number]: boolean } = {}
			for _ = 1, 3 do
				local roles = RoleSelector.assign(players, history, first)
				for userId, role in roles do
					if role == "TimeKeeper" then
						t.expect(seen[userId]).toBeNil()
						seen[userId] = true
					end
				end
				RoleSelector.recordMatch(history, roles)
			end
		end)

		t.it("allows a keeperless solo match only when explicitly requested", function()
			local solo = RoleSelector.assign({ 7 }, {}, first, true)
			t.expect(solo[7]).toBe("Infiltrator")
			local normal = RoleSelector.assign({ 7 }, {}, first, false)
			t.expect(normal[7]).toBe("TimeKeeper")
			local duo = RoleSelector.assign({ 7, 8 }, {}, first, true)
			local keepers = 0
			for _, role in duo do
				if role == "TimeKeeper" then
					keepers += 1
				end
			end
			t.expect(keepers).toBe(1)
		end)

		t.it("clamps out-of-range random indices", function()
			t.expect(RoleSelector.selectKeeper({ 4, 5 }, {}, function()
				return 99
			end)).toBe(5)
		end)
	end)
end
