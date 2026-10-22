--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoachConfig = require(ReplicatedStorage.Shared.Config.CoachConfig)

return function(t: any)
	t.describe("Field Guide", function()
		t.it("guides only the first matches of each role", function()
			local stats = { KeeperMatches = 0, InfiltratorMatches = CoachConfig.GuidedMatches }
			t.expect(CoachConfig.isGuided(stats, "TimeKeeper")).toBe(true)
			t.expect(CoachConfig.isGuided(stats, "Infiltrator")).toBe(false)
			t.expect(CoachConfig.isGuided(nil, "TimeKeeper")).toBe(false)
			t.expect(CoachConfig.isGuided(stats, nil)).toBe(false)
		end)

		t.it("has a well-formed tip set per role", function()
			for _, set in { CoachConfig.Infiltrator :: any, CoachConfig.TimeKeeper :: any } do
				t.expect(set.Start ~= nil and set.Collapse ~= nil).toBe(true)
				for id, tip in set :: any do
					t.expect(tip.Id).toBe(id)
					t.expect(#tip.Title > 0 and #tip.Text > 0 and #tip.Text <= 160).toBe(true)
				end
			end
			t.expect(CoachConfig.tip("Infiltrator", "AllyPod") ~= nil).toBe(true)
			t.expect(CoachConfig.tip("TimeKeeper", "AllyPod")).toBeNil()
			t.expect(CoachConfig.tip(nil, "Start")).toBeNil()
		end)
	end)
end
