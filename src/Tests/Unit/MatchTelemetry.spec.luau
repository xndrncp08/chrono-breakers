--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local MatchTelemetry = require(ServerScriptService.Server.Core.MatchTelemetry)

local CLASSES: { [number]: string } = { [1] = "Ghost", [2] = "Medic", [3] = "Ghost" }

local function play(): MatchTelemetry.MatchTelemetry
	local m = MatchTelemetry.new("Foundry", function(userId)
		return CLASSES[userId]
	end, "Entropy")
	m:chase(1, true, 5) -- before the match: ignored
	m:observe("ConditionChanged", { userId = 1, cause = "Strike", condition = "Injured" }, 5)
	m:observe("MatchStarted", {
		roles = { [1] = "Infiltrator", [2] = "Infiltrator", [3] = "Infiltrator", [9] = "TimeKeeper" },
	}, 10)
	m:chase(1, true, 20)
	m:observe("ConditionChanged", { userId = 1, cause = "Strike", condition = "Injured" }, 24)
	m:observe("ConditionChanged", { userId = 1, cause = "Strike", condition = "Downed" }, 30)
	m:chase(1, false, 30)
	m:observe("PlayerContained", { userId = 1, by = 9 }, 32)
	m:observe("PlayerRescued", { userId = 1, by = 2, cause = "Rescue" }, 50)
	m:observe("ConditionChanged", { userId = 1, cause = "Endured", condition = "Injured" }, 58) -- tunnel
	m:observe("PlayerRescued", { userId = 3, cause = "Feedback" }, 60)
	m:observe("TerminalCompleted", { userId = 2 }, 70)
	m:observe("CalibrationResult", { grade = "Great" }, 71)
	m:observe("CalibrationResult", { grade = "Miss" }, 72)
	m:observe("CalibrationResult", { grade = "Bogus" }, 72)
	m:ability("Afterimage")
	m:chase(2, true, 80)
	m:observe("PlayerExtracted", { userId = 2 }, 90)
	m:observe("PlayerEliminated", { userId = 1 }, 95)
	m:observe("ParticipantLeft", { userId = 3, role = "Infiltrator" }, 96)
	m:observe("MatchResolved", { winner = "TimeKeeper", reason = "AllGone" }, 100)
	m:observe("ConditionChanged", { userId = 2, cause = "Strike", condition = "Injured" }, 101) -- after: ignored
	return m
end

local function hasKey(value: any, key: string): boolean
	if type(value) ~= "table" then
		return false
	end
	for k, v in value do
		if k == key or hasKey(v, key) then
			return true
		end
	end
	return false
end

return function(t: any)
	t.describe("MatchTelemetry", function()
		t.it("summarises a match with anonymous counts only", function()
			local s = play():summary(100) :: MatchTelemetry.Summary
			t.expect(s.mapId).toBe("Foundry")
			t.expect(s.condition).toBe("Entropy")
			t.expect(s.squad).toBe(3)
			t.expect(s.durationSec).toBe(90)
			t.expect(s.winner).toBe("TimeKeeper")
			t.expect(s.hits).toBe(3)
			t.expect(s.downs).toBe(1)
			t.expect(s.tunnelHits).toBe(1)
			t.expect(s.containments).toBe(1)
			t.expect(s.rescues).toBe(1)
			t.expect(s.campReleases).toBe(1)
			t.expect(s.firstTerminalSec).toBe(60)
			t.expect(s.calibration.Great).toBe(1)
			t.expect(s.calibration.Miss).toBe(1)
			t.expect(s.abilities.Afterimage).toBe(1)
			t.expect(s.chases).toBe(2)
			t.expect(s.maxChaseSec).toBe(10)
			t.expect(s.classes.Ghost.picked).toBe(2)
			t.expect(s.classes.Ghost.erased).toBe(1)
			t.expect(s.classes.Medic.extracted).toBe(1)
			t.expect(s.disconnects.Infiltrator).toBe(1)
			-- No user ids leak into the summary.
			t.expect(hasKey(s, "userId")).toBe(false)
		end)

		t.it("returns nothing before a match starts", function()
			local m = MatchTelemetry.new("Foundry", function()
				return nil
			end)
			t.expect(m:summary(10)).toBeNil()
		end)

		t.it("aggregates headline balance numbers", function()
			local a = play():summary(100) :: MatchTelemetry.Summary
			local b = table.clone(a)
			b.winner, b.mapId, b.durationSec = "Infiltrators", "Archive", 110
			local agg = MatchTelemetry.aggregate({ a, b })
			t.expect(agg.matches).toBe(2)
			t.expect(agg.keeperWinRate).toBe(0.5)
			t.expect(agg.avgDurationSec).toBe(100)
			t.expect(agg.tunnelHitShare).toBeNear(1 / 3, 0.001)
			t.expect(agg.byMap.Foundry.keeperWins).toBe(1)
			t.expect(agg.byMap.Archive.matches).toBe(1)
			t.expect(agg.byCondition.Entropy.matches).toBe(2)
			t.expect(MatchTelemetry.aggregate({}).keeperWinRate).toBe(0)
		end)
	end)
end
