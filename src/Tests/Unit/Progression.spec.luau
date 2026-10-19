--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local Schema = require(ServerScriptService.Server.Core.ProfileSchema)
local Progression = require(ServerScriptService.Server.Core.Progression)
local Calculator = require(ServerScriptService.Server.Core.RewardCalculator)
local Ledger = require(ServerScriptService.Server.Core.RewardLedger)
local Economy = require(ServerScriptService.Server.Core.Economy)
local function award(profile: Schema.Profile, id: string, time: number, overrides: any?): number
	local player: any = {
		userId = 1,
		role = "Infiltrator",
		status = "Active",
		connected = true,
		hacks = 0,
		assists = 0,
		eliminations = 0,
		extracted = false,
		classId = "Engineer",
	}
	for k, v in overrides or {} do
		player[k] = v
	end
	local breakdown =
		Calculator.compute({ matchId = id, winner = "Infiltrators", reason = "Extracted", rewardedAt = time }, player)
	local _, amount = Ledger.apply(profile, id, breakdown)
	return amount
end
return function(t: any)
	t.it("migrates v2 without losing currency, inventory, settings or career stats", function()
		local p, status = Schema.migrate({
			SchemaVersion = 2,
			ChronosScrap = 900,
			OwnedItems = { PhaseDash = true },
			Equipped = { Gadget = "PhaseDash" },
			Stats = { Wins = 12 },
			Settings = { ReducedMotion = true },
			RecentMatchIds = { "paid" },
		})
		t.expect(status).toBe("Ok")
		t.expect(p.SchemaVersion).toBe(3)
		t.expect(p.ChronosScrap).toBe(900)
		t.expect(p.OwnedItems.PhaseDash).toBe(true)
		t.expect(p.Equipped.Gadget).toBe("PhaseDash")
		t.expect(p.Stats.Wins).toBe(12)
		t.expect(p.Settings.ReducedMotion).toBe(true)
		t.expect(p.RecentMatchIds).toContain("paid")
		t.expect(p.Progression.XP).toBe(0)
	end)
	t.it("awards XP, mastery and calendar challenges exactly once in the reward ledger", function()
		local p = Schema.defaults()
		award(p, "m1", 0, { hacks = 1 })
		local xp = p.Progression.XP
		local scrap = p.ChronosScrap
		award(p, "m1", 0, { hacks = 100 })
		t.expect(p.Progression.XP).toBe(xp)
		t.expect(p.ChronosScrap).toBe(scrap)
		local amount = award(p, "m2", 0, { hacks = 2 })
		t.expect(amount).toBe(70 + 30 + 30 + 40) -- match Scrap + daily Deploy and Breach
		t.expect(p.Progression.Daily.Claimed.Deploy).toBe(true)
		t.expect(p.Progression.Daily.Claimed.Breach).toBe(true)
		t.expect(p.Progression.Mastery.Engineer).toBe(140 + 25 + 140 + 50)
		t.expect(p.Progression.XP).toBe(p.Progression.Mastery.Engineer + 100 + 150)
		t.expect(award(p, "m3", 0, {})).toBe(70)
	end)
	t.it("resets periods in UTC, retains weekly counters and cannot reopen an older period", function()
		local p = Schema.defaults()
		award(p, "a", 0, { hacks = 2 })
		award(p, "b", 86400, { hacks = 1, extracted = true })
		t.expect(p.Progression.Daily.Period).toBe(1)
		t.expect(p.Progression.Daily.Progress.Breach).toBe(1)
		t.expect(p.Progression.Weekly.Progress.Veteran).toBe(2)
		award(p, "c", 0, { hacks = 3 })
		t.expect(p.Progression.Daily.Period).toBe(1)
		t.expect(p.Progression.Daily.Progress.Breach).toBe(1)
		award(p, "d", 604800, {})
		t.expect(p.Progression.Weekly.Period).toBe(1)
		t.expect(p.Progression.Weekly.Progress.Veteran).toBeNil()
		t.expect(Config.period("Weekly", 4 * 86400 - 1)).toBe(0)
		t.expect(Config.period("Weekly", 4 * 86400)).toBe(1)
	end)
	t.it("unlocks cosmetics without allowing purchases or equipping locked milestone items", function()
		local p = Schema.defaults()
		t.expect(select(2, Economy.purchase(p, "TitleBreaker"))).toBe("Locked")
		t.expect((Economy.equip(p, "TitleBreaker"))).toBe(false)
		award(p, "extract", 0, { extracted = true })
		t.expect(p.Progression.Milestones.FirstEscape).toBe(true)
		t.expect((Economy.equip(p, "TitleBreaker"))).toBe(true)
		p.Progression.XP = Config.threshold(10)
		Progression.apply(p, { xp = 0, statDeltas = {}, eligible = true })
		t.expect(p.OwnedItems.TrailRift).toBe(true)
	end)
	t.it("sanitizes new fields and caps XP and levels", function()
		local p = Schema.reconcile({
			Progression = {
				XP = math.huge,
				Mastery = { Ghost = -8, Forged = 100 },
				Milestones = { Forged = true },
				Daily = { Period = 0 / 0, Progress = { Deploy = 1e20 }, Claimed = { Deploy = "yes" } },
			},
		})
		t.expect(p.Progression.XP).toBe(0)
		t.expect(p.Progression.Mastery.Ghost).toBe(0)
		t.expect(p.Progression.Mastery.Forged).toBeNil()
		t.expect(p.Progression.Daily.Period).toBe(-1)
		t.expect(p.Progression.Daily.Progress.Deploy).toBe(2)
		t.expect(p.Progression.Daily.Claimed.Deploy).toBeNil()
		t.expect(Config.level(Config.threshold(10))).toBe(10)
		t.expect(Config.level(1e9)).toBe(100)
		t.expect(Progression.snapshot(p.Progression, 0).challenges[1].progress).toBe(0)
	end)
end
