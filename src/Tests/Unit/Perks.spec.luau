--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PerkConfig = require(ReplicatedStorage.Shared.Config.PerkConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Schema = require(ServerScriptService.Server.Core.ProfileSchema)
local Economy = require(ServerScriptService.Server.Core.Economy)
local Progression = require(ServerScriptService.Server.Core.Progression)
local Calculator = require(ServerScriptService.Server.Core.RewardCalculator)

return function(t: any)
	t.describe("Perks and survival progression", function()
		t.it("unlocks only through level or mastery and never through an item purchase", function()
			for id, definition in PerkConfig.Perks do
				t.expect(ItemConfig.get(id)).toBeNil()
				t.expect(definition.Unlock.Kind == "Level" or definition.Unlock.Kind == "Mastery").toBe(true)
				for key, value in definition.Modifiers do
					assert(value > 0 and value <= 2, `{id}.{key} out of side-grade bounds`)
				end
			end
			local fresh = { xp = 0, mastery = {} }
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.SecondWind, "Ghost", fresh)).toBe(true)
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.SteadyHands, "Ghost", fresh)).toBe(false)
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.Relentless, "TimeKeeper", fresh)).toBe(true)
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.Relentless, "Ghost", fresh)).toBe(false)
			local veteran = { xp = 0, mastery = { Ghost = ProgressionConfig.threshold(6) } }
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.SilentLocker, "Ghost", veteran)).toBe(true)
			t.expect(PerkConfig.isUnlocked(PerkConfig.Perks.SilentLocker, "Phantom", veteran)).toBe(false)
		end)

		t.it("toggles perks into the right loadout and enforces locks and the slot limit", function()
			local profile = Schema.defaults()
			profile.Equipped.Class = "Phantom"
			t.expect(select(2, Economy.togglePerk(profile, "Nope"))).toBe("UnknownItem")
			t.expect(select(2, Economy.togglePerk(profile, "QuickHands"))).toBe("Locked")
			t.expect((Economy.togglePerk(profile, "SecondWind"))).toBe(true)
			t.expect(profile.Perks.Phantom).toEqual({ "SecondWind" })
			profile.Progression.XP = ProgressionConfig.threshold(9)
			profile.Progression.Mastery.Phantom = ProgressionConfig.threshold(6)
			t.expect((Economy.togglePerk(profile, "QuickHands"))).toBe(true)
			t.expect(select(2, Economy.togglePerk(profile, "FeatherFall"))).toBe("LimitReached")
			t.expect((Economy.togglePerk(profile, "SecondWind"))).toBe(true) -- unequip
			t.expect((Economy.togglePerk(profile, "FeatherFall"))).toBe(true)
			t.expect(profile.Perks.Phantom).toEqual({ "QuickHands", "FeatherFall" })
			t.expect((Economy.togglePerk(profile, "Relentless"))).toBe(true)
			t.expect(profile.Perks.TimeKeeper).toEqual({ "Relentless" })
		end)

		t.it("migrates v3 profiles and strips perks that are locked, duplicated, misplaced or excess", function()
			local p, status = Schema.migrate({
				SchemaVersion = 3,
				ChronosScrap = 40,
				Progression = { XP = ProgressionConfig.threshold(5), Mastery = { Ghost = 0 } },
				Perks = {
					Ghost = { "SecondWind", "SecondWind", "ShadowLag", "SteadyHands", "AdrenalEcho" },
					TimeKeeper = { "SecondWind", "Relentless" },
					Hacker = { "SecondWind" },
				},
			})
			t.expect(status).toBe("Ok")
			t.expect(p.SchemaVersion).toBe(4)
			t.expect(p.ChronosScrap).toBe(40)
			t.expect(p.Perks.Ghost).toEqual({ "SecondWind", "SteadyHands" })
			t.expect(p.Perks.TimeKeeper).toEqual({ "Relentless" })
			t.expect((p.Perks :: any).Hacker).toBeNil()
		end)

		t.it("combines modifiers multiplicatively", function()
			t.expect(PerkConfig.modifier({ "SecondWind" }, "StaminaRegen")).toBeNear(1.3)
			t.expect(PerkConfig.modifier({ "SecondWind", "QuickHands" }, "VaultSpeed")).toBeNear(1.15)
			t.expect(PerkConfig.modifier({}, "Recoil")).toBe(1)
		end)

		t.it("pays survival teamwork, records survival stats and grants mastery cosmetics", function()
			local breakdown = Calculator.compute({ matchId = "m", winner = "Infiltrators", reason = "Extracted" }, {
				userId = 1,
				role = "Infiltrator",
				status = "Extracted",
				connected = true,
				hacks = 1,
				eliminations = 0,
				extracted = true,
				rescues = 2,
				revives = 1,
				greats = 3,
				classId = "Ghost",
			})
			t.expect(breakdown.statDeltas.Rescues).toBe(2)
			t.expect(breakdown.statDeltas.GreatCalibrations).toBe(3)
			local labels = {}
			for _, line in breakdown.lines do
				labels[line.label] = line.amount
			end
			t.expect(labels["Rescues ×2"]).toBe(24)
			local profile = Schema.defaults()
			profile.Progression.Mastery.Ghost = ProgressionConfig.threshold(5) - 10
			Progression.apply(profile, { xp = 50, masteryId = "Ghost", statDeltas = {}, eligible = true })
			t.expect(profile.OwnedItems.TitleGhostAdept).toBe(true)
			t.expect(profile.OwnedItems.TrailGhost).toBeNil()
			t.expect(Economy.purchase(profile, "TrailGhost")).toBe(false)
		end)
	end)
end
