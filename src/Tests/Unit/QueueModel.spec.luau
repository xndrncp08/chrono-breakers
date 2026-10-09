--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local QueueModel = require(ServerScriptService.Server.Core.QueueModel)

local function always(_: number): boolean
	return true
end

return function(t: any)
	t.describe("QueueModel", function()
		t.it("joins once and rejects duplicates", function()
			local q = QueueModel.new()
			t.expect((q:join(1))).toBe(true)
			local ok, code = q:join(1)
			t.expect(ok).toBe(false)
			t.expect(code).toBe("AlreadyQueued")
			t.expect(q:count()).toBe(1)
		end)

		t.it("supports cancel (leave) and reports NotQueued", function()
			local q = QueueModel.new()
			q:join(1)
			t.expect((q:leave(1))).toBe(true)
			local ok, code = q:leave(1)
			t.expect(ok).toBe(false)
			t.expect(code).toBe("NotQueued")
		end)

		t.it("removes disconnected players", function()
			local q = QueueModel.new()
			q:join(1)
			q:join(2)
			t.expect(q:remove(1)).toBe(true)
			t.expect(q:remove(1)).toBe(false)
			t.expect(q:list()).toEqual({ 2 })
		end)

		t.it("takes in FIFO order up to the cap and keeps the rest", function()
			local q = QueueModel.new()
			for i = 1, 7 do
				q:join(i)
			end
			local taken = q:take(5, always)
			t.expect(taken).toEqual({ 1, 2, 3, 4, 5 })
			t.expect(q:list()).toEqual({ 6, 7 })
		end)

		t.it("drops ineligible users when taking", function()
			local q = QueueModel.new()
			for i = 1, 4 do
				q:join(i)
			end
			local taken = q:take(5, function(id)
				return id ~= 2
			end)
			t.expect(taken).toEqual({ 1, 3, 4 })
			t.expect(q:count()).toBe(0)
		end)

		t.it("counts only eligible users toward the threshold", function()
			local q = QueueModel.new()
			q:join(1)
			q:join(2)
			t.expect(q:countEligible(function(id)
				return id == 1
			end)).toBe(1)
		end)

		t.it("restores taken users to the front in order", function()
			local q = QueueModel.new()
			q:join(9)
			q:restore({ 1, 2 })
			t.expect(q:list()).toEqual({ 1, 2, 9 })
		end)
	end)
end
