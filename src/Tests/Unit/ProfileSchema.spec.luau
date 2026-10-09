--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local ProfileSchema = require(ServerScriptService.Server.Core.ProfileSchema)

return function(t: any)
	t.describe("ProfileSchema", function()
		t.it("provides complete safe defaults", function()
			local p = ProfileSchema.defaults()
			t.expect(p.SchemaVersion).toBe(ProfileSchema.CURRENT_VERSION)
			t.expect(p.ChronosScrap).toBe(0)
			t.expect(p.OwnedItems.Stabilizer).toBe(true)
			t.expect(p.OwnedItems.TrailCyan).toBe(true)
			t.expect(p.OwnedItems.PhaseDash).toBeNil()
			t.expect(p.Equipped.Gadget).toBe(ItemConfig.DefaultEquipped.Gadget)
			t.expect(p.Stats.MatchesPlayed).toBe(0)
			t.expect(p.Settings.SfxVolume).toBe(0.8)
		end)

		t.it("treats missing data as a new profile", function()
			local p, status = ProfileSchema.migrate(nil)
			t.expect(status).toBe("New")
			t.expect(p.ChronosScrap).toBe(0)
		end)

		t.it("migrates v1 data to the current version", function()
			local p, status = ProfileSchema.migrate({ Scrap = 120, Volume = 0.25, Items = { "PhaseDash", 42 :: any } })
			t.expect(status).toBe("Ok")
			t.expect(p.SchemaVersion).toBe(2)
			t.expect(p.ChronosScrap).toBe(120)
			t.expect(p.Settings.SfxVolume).toBe(0.25)
			t.expect(p.OwnedItems.PhaseDash).toBe(true)
			t.expect((p :: any).Scrap).toBeNil()
		end)

		t.it("refuses to downgrade data written by a newer schema", function()
			local _, status = ProfileSchema.migrate({ SchemaVersion = 99, ChronosScrap = 5 })
			t.expect(status).toBe("FutureVersion")
		end)

		t.it("sanitises malformed and hostile fields", function()
			local p = ProfileSchema.reconcile({
				ChronosScrap = -50,
				OwnedItems = { PhaseDash = true, Hacked = true, EchoScanner = "yes" },
				Equipped = { Gadget = "EchoScanner", Trail = "PhaseDash" },
				Stats = { Wins = -3, MatchesPlayed = 4.7, Extractions = 0 / 0 },
				Settings = { SfxVolume = 7, UIScale = 0.1, ReducedMotion = "true", Unknown = 1 },
				RecentMatchIds = { "a", 5 :: any, string.rep("x", 100) },
			})
			t.expect(p.ChronosScrap).toBe(0)
			t.expect(p.OwnedItems.Hacked).toBeNil()
			t.expect(p.OwnedItems.EchoScanner).toBeNil()
			t.expect(p.OwnedItems.PhaseDash).toBe(true)
			-- Not owned -> default; wrong slot -> default
			t.expect(p.Equipped.Gadget).toBe("Stabilizer")
			t.expect(p.Equipped.Trail).toBe("TrailCyan")
			t.expect(p.Stats.Wins).toBe(0)
			t.expect(p.Stats.MatchesPlayed).toBe(4)
			t.expect(p.Stats.Extractions).toBe(0)
			t.expect(p.Settings.SfxVolume).toBe(1)
			t.expect(p.Settings.UIScale).toBe(0.8)
			t.expect(p.Settings.ReducedMotion).toBe(false)
			t.expect((p.Settings :: any).Unknown).toBeNil()
			t.expect(p.RecentMatchIds).toEqual({ "a" })
		end)

		t.it("always keeps default-owned items", function()
			local p = ProfileSchema.reconcile({ OwnedItems = {} })
			t.expect(p.OwnedItems.Stabilizer).toBe(true)
		end)

		t.it("sanitizeSetting rejects unknown keys and wrong types", function()
			t.expect(ProfileSchema.sanitizeSetting("SfxVolume", 0.5)).toBe(0.5)
			t.expect(ProfileSchema.sanitizeSetting("SfxVolume", "loud")).toBeNil()
			t.expect(ProfileSchema.sanitizeSetting("Admin", true)).toBeNil()
			t.expect(ProfileSchema.sanitizeSetting("ShowControlHints", false)).toBe(false)
		end)
	end)
end
