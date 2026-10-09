--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local Economy = require(ServerScriptService.Server.Core.Economy)
local ProfileSchema = require(ServerScriptService.Server.Core.ProfileSchema)
local RewardCalculator = require(ServerScriptService.Server.Core.RewardCalculator)
local RewardLedger = require(ServerScriptService.Server.Core.RewardLedger)

local function participant(overrides: { [string]: any }): RewardCalculator.ParticipantLike
	local base: any = {
		userId = 1,
		role = "Infiltrator",
		status = "Active",
		connected = true,
		hacks = 0,
		eliminations = 0,
		extracted = false,
	}
	for k, v in overrides do
		base[k] = v
	end
	return base
end

return function(t: any)
	t.describe("Economy", function()
		t.it("never lets currency go negative", function()
			local p = ProfileSchema.defaults()
			p.ChronosScrap = 10
			t.expect(Economy.spend(p, 20)).toBe(false)
			t.expect(p.ChronosScrap).toBe(10)
			t.expect(Economy.spend(p, -5)).toBe(false)
			t.expect(Economy.spend(p, 0 / 0)).toBe(false)
			t.expect(Economy.spend(p, 2.5)).toBe(false)
			t.expect(Economy.spend(p, 10)).toBe(true)
			t.expect(p.ChronosScrap).toBe(0)
		end)

		t.it("grants only positive whole amounts and caps the total", function()
			local p = ProfileSchema.defaults()
			t.expect(Economy.grant(p, -10)).toBe(0)
			t.expect(Economy.grant(p, math.huge)).toBe(0)
			t.expect(Economy.grant(p, 12.9)).toBe(12)
			p.ChronosScrap = RewardConfig.MaxCurrency - 1
			t.expect(Economy.grant(p, 100)).toBe(1)
		end)

		t.it("purchases atomically and does not consume currency on failure", function()
			local p = ProfileSchema.defaults()
			p.ChronosScrap = 100
			local ok, code = Economy.purchase(p, "PhaseDash") -- costs 150
			t.expect(ok).toBe(false)
			t.expect(code).toBe("InsufficientFunds")
			t.expect(p.ChronosScrap).toBe(100)
			t.expect(p.OwnedItems.PhaseDash).toBeNil()
			p.ChronosScrap = 160
			t.expect((Economy.purchase(p, "PhaseDash"))).toBe(true)
			t.expect(p.ChronosScrap).toBe(10)
			local again, againCode = Economy.purchase(p, "PhaseDash")
			t.expect(again).toBe(false)
			t.expect(againCode).toBe("AlreadyOwned")
			t.expect(p.ChronosScrap).toBe(10)
		end)

		t.it("rejects unknown and malformed items", function()
			local p = ProfileSchema.defaults()
			t.expect(select(2, Economy.purchase(p, "FreeMoney"))).toBe("UnknownItem")
			t.expect(select(2, Economy.purchase(p, { "PhaseDash" }))).toBe("InvalidPayload")
		end)

		t.it("equips only owned items into their own slot", function()
			local p = ProfileSchema.defaults()
			t.expect(select(2, Economy.equip(p, "EchoScanner"))).toBe("NotOwned")
			p.OwnedItems.EchoScanner = true
			t.expect((Economy.equip(p, "EchoScanner"))).toBe(true)
			t.expect(p.Equipped.Gadget).toBe("EchoScanner")
			t.expect(p.Equipped.Trail).toBe("TrailCyan")
		end)
	end)

	t.describe("RewardCalculator", function()
		local win = { matchId = "m1", winner = "Infiltrators", reason = "Extracted" } :: any

		t.it("rewards an extracting Infiltrator from central config", function()
			local b = RewardCalculator.compute(win, participant({ hacks = 2, extracted = true }))
			t.expect(b.eligible).toBe(true)
			t.expect(b.won).toBe(true)
			local expected = RewardConfig.Participation
				+ RewardConfig.Win
				+ 2 * RewardConfig.PerTerminalHacked
				+ RewardConfig.Extracted
			t.expect(b.total).toBe(expected)
			t.expect(b.statDeltas.Wins).toBe(1)
			t.expect(b.statDeltas.Extractions).toBe(1)
		end)

		t.it("rewards the Time-Keeper for eliminations", function()
			local keeperWin = { matchId = "m2", winner = "TimeKeeper", reason = "AllEliminated" } :: any
			local b = RewardCalculator.compute(keeperWin, participant({ role = "TimeKeeper", eliminations = 3 }))
			t.expect(b.total).toBe(RewardConfig.Participation + RewardConfig.Win + 3 * RewardConfig.PerElimination)
			t.expect(b.statDeltas.KeeperMatches).toBe(1)
		end)

		t.it("pays nothing for aborted matches or departed players", function()
			local aborted = { matchId = "m3", winner = nil, reason = "Aborted" } :: any
			t.expect(RewardCalculator.compute(aborted, participant({})).eligible).toBe(false)
			t.expect(RewardCalculator.compute(win, participant({ connected = false })).total).toBe(0)
		end)
	end)

	t.describe("RewardLedger", function()
		t.it("applies a match reward exactly once", function()
			local p = ProfileSchema.defaults()
			local b = RewardCalculator.compute(
				{ matchId = "m1", winner = "Infiltrators", reason = "Extracted" } :: any,
				participant({ hacks = 1 })
			)
			local applied, granted = RewardLedger.apply(p, "m1", b)
			t.expect(applied).toBe(true)
			t.expect(granted).toBe(b.total)
			local applied2, granted2 = RewardLedger.apply(p, "m1", b)
			t.expect(applied2).toBe(false)
			t.expect(granted2).toBe(0)
			t.expect(p.ChronosScrap).toBe(b.total)
			t.expect(p.Stats.MatchesPlayed).toBe(1)
		end)

		t.it("bounds the paid-match history", function()
			local p = ProfileSchema.defaults()
			local b =
				RewardCalculator.compute({ matchId = "x", winner = nil, reason = "Aborted" } :: any, participant({}))
			for i = 1, RewardConfig.RecentMatchHistorySize + 5 do
				RewardLedger.apply(p, `m{i}`, b)
			end
			t.expect(#p.RecentMatchIds).toBe(RewardConfig.RecentMatchHistorySize)
		end)

		t.it("rejects empty match ids", function()
			local p = ProfileSchema.defaults()
			local b =
				RewardCalculator.compute({ matchId = "", winner = nil, reason = "Aborted" } :: any, participant({}))
			t.expect((RewardLedger.apply(p, "", b))).toBe(false)
		end)
	end)
end
