--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local MemoryDataStore = require(ServerScriptService.Server.Core.MemoryDataStore)
local ProfileSchema = require(ServerScriptService.Server.Core.ProfileSchema)
local ProfileStore = require(ServerScriptService.Server.Core.ProfileStore)

local function makeStore(adapter: any, jobId: string, clock: { now: number }, sleeps: { number }?)
	return ProfileStore.new({
		adapter = adapter,
		jobId = jobId,
		now = function()
			return clock.now
		end,
		sleep = function(seconds: number)
			if sleeps then
				table.insert(sleeps, seconds)
			end
			clock.now += seconds
		end,
		maxAttempts = 4,
		baseBackoff = 1,
		maxBackoff = 4,
		lockTimeout = 600,
	})
end

return function(t: any)
	t.describe("ProfileStore", function()
		t.it("creates a default profile and acquires the session lock", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 0 }
			local store = makeStore(ds, "jobA", clock)
			local status, profile = store:load(1)
			t.expect(status).toBe("Loaded")
			t.expect((profile :: any).ChronosScrap).toBe(0)
			t.expect(ds:GetRaw("Player_1").Lock.JobId).toBe("jobA")
		end)

		t.it("round-trips saved data and releases the lock", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 0 }
			local store = makeStore(ds, "jobA", clock)
			local _, profile = store:load(1)
			local p = profile :: ProfileSchema.Profile
			p.ChronosScrap = 77
			t.expect(store:save(1, p, true)).toBe("Saved")
			local raw = ds:GetRaw("Player_1")
			t.expect(raw.Lock).toBeNil()
			t.expect(raw.Data.ChronosScrap).toBe(77)
			local other = makeStore(ds, "jobB", clock)
			local status, again = other:load(1)
			t.expect(status).toBe("Loaded")
			t.expect((again :: any).ChronosScrap).toBe(77)
		end)

		t.it("waits on a fresh foreign lock and reports Locked with bounded backoff", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 0 }
			ds:SetRaw("Player_1", { Data = { ChronosScrap = 5 }, Lock = { JobId = "jobOther", Time = 0 } })
			local sleeps = {}
			local store = makeStore(ds, "jobA", clock, sleeps)
			local status, profile = store:load(1)
			t.expect(status).toBe("Locked")
			t.expect(profile).toBeNil()
			t.expect(sleeps).toEqual({ 1, 2, 4 })
			t.expect(ds:GetRaw("Player_1").Lock.JobId).toBe("jobOther")
		end)

		t.it("takes over a stale lock left by a crashed server", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 10_000 }
			ds:SetRaw("Player_1", { Data = { ChronosScrap = 5 }, Lock = { JobId = "jobDead", Time = 0 } })
			local store = makeStore(ds, "jobA", clock)
			local status, profile = store:load(1)
			t.expect(status).toBe("Loaded")
			t.expect((profile :: any).ChronosScrap).toBe(5)
			t.expect(ds:GetRaw("Player_1").Lock.JobId).toBe("jobA")
		end)

		t.it("retries transient errors and then succeeds", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 0 }
			ds:FailNext(2)
			local sleeps = {}
			local store = makeStore(ds, "jobA", clock, sleeps)
			local status = store:load(1)
			t.expect(status).toBe("Loaded")
			t.expect(#sleeps).toBe(2)
		end)

		t.it("reports Error when every attempt fails", function()
			local ds = MemoryDataStore.new()
			ds:FailNext(10)
			local store = makeStore(ds, "jobA", { now = 0 })
			t.expect((store:load(1))).toBe("Error")
		end)

		t.it("refuses to save when another server has taken the lock", function()
			local ds = MemoryDataStore.new()
			local clock = { now = 0 }
			local store = makeStore(ds, "jobA", clock)
			local _, profile = store:load(1)
			ds:SetRaw("Player_1", { Data = { ChronosScrap = 999 }, Lock = { JobId = "jobB", Time = 0 } })
			t.expect(store:save(1, profile :: any, true)).toBe("LockLost")
			t.expect(ds:GetRaw("Player_1").Data.ChronosScrap).toBe(999)
		end)

		t.it("does not overwrite profiles from a newer schema and releases the lock", function()
			local ds = MemoryDataStore.new()
			ds:SetRaw("Player_1", { Data = { SchemaVersion = 50, ChronosScrap = 3 } })
			local store = makeStore(ds, "jobA", { now = 0 })
			local status = store:load(1)
			t.expect(status).toBe("FutureVersion")
			local raw = ds:GetRaw("Player_1")
			t.expect(raw.Data.SchemaVersion).toBe(50)
			t.expect(raw.Lock).toBeNil()
		end)
	end)
end
