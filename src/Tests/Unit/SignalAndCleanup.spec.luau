--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cleanup = require(ReplicatedStorage.Shared.Modules.Cleanup)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

return function(t: any)
	t.describe("Signal", function()
		t.it("fires connected handlers with arguments and supports disconnect", function()
			local s = Signal.new()
			local got = {}
			local c = s:Connect(function(a: number, b: number)
				table.insert(got, a + b)
			end)
			s:Fire(1, 2)
			c:Disconnect()
			s:Fire(5, 5)
			t.expect(got).toEqual({ 3 })
			t.expect(s:GetConnectionCount()).toBe(0)
		end)

		t.it("Once handlers run a single time", function()
			local s = Signal.new()
			local count = 0
			s:Once(function()
				count += 1
			end)
			s:Fire()
			s:Fire()
			t.expect(count).toBe(1)
		end)

		t.it("tolerates disconnecting during dispatch", function()
			local s = Signal.new()
			local calls = 0
			local second
			s:Connect(function()
				calls += 1
				second:Disconnect()
			end)
			second = s:Connect(function()
				calls += 100
			end)
			s:Fire()
			t.expect(calls).toBe(1)
		end)
	end)

	t.describe("Cleanup", function()
		t.it("releases functions, signal connections, and nested cleanups in reverse order", function()
			local order = {}
			local c = Cleanup.new()
			local s = Signal.new()
			c:Add(function()
				table.insert(order, "first")
			end)
			c:Add(s:Connect(function() end))
			local nested = Cleanup.new()
			nested:Add(function()
				table.insert(order, "nested")
			end)
			c:Add(nested)
			c:Add(function()
				table.insert(order, "last")
			end)
			t.expect(c:Count()).toBe(4)
			c:Clean()
			t.expect(order).toEqual({ "last", "nested", "first" })
			t.expect(s:GetConnectionCount()).toBe(0)
			t.expect(c:Count()).toBe(0)
		end)

		t.it("cleans items added after destruction immediately", function()
			local c = Cleanup.new()
			c:Destroy()
			local ran = false
			c:Add(function()
				ran = true
			end)
			t.expect(ran).toBe(true)
			t.expect(c:IsDestroyed()).toBe(true)
		end)

		t.it("cancels pending threads", function()
			local c = Cleanup.new()
			local fired = false
			c:Add(task.delay(0.05, function()
				fired = true
			end))
			c:Clean()
			task.wait(0.1)
			t.expect(fired).toBe(false)
		end)
	end)

	t.describe("TableUtil", function()
		t.it("deep copies and truncates long names safely", function()
			local src = { a = { b = 1 } }
			local copy = TableUtil.deepCopy(src)
			copy.a.b = 2
			t.expect(src.a.b).toBe(1)
			t.expect(TableUtil.truncate("Short", 10)).toBe("Short")
			t.expect(TableUtil.truncate("AVeryLongPlayerName_123", 10)).toBe("AVeryLong…")
		end)
	end)
end
