--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Harness = require(ServerScriptService.Tests.Helpers.DirectorHarness)

return function(t: any)
	t.describe("Match lifecycle", function()
		t.it("waits for the minimum player threshold", function()
			local h = Harness.new()
			h:queueAll({ 1 })
			h:advance(30)
			t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
			h:queueAll({ 2 })
			h:advance(0.1)
			t.expect(h.director:getPhase()).toBe("Intermission")
		end)

		t.it("returns to waiting if the queue drops below the threshold during intermission", function()
			local h = Harness.new()
			h:queueAll({ 1, 2 })
			h:advance(1)
			t.expect(h.director:getPhase()).toBe("Intermission")
			h.director.queue:leave(2)
			h:advance(0.1)
			t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
			t.expect(h.director.session).toBeNil()
		end)

		t.it("starts with exactly one Keeper and caps participants at MaxPlayers", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3, 4, 5, 6, 7 })
			t.expect(#h:infiltrators()).toBe(4)
			t.expect(h:keeper()).toBeGreaterThan(0)
			t.expect(h.director.queue:list()).toEqual({ 6, 7 })
			t.expect(h:count("MatchStarted")).toBe(1)
		end)

		t.it("skips ineligible queued players at role assignment", function()
			local h = Harness.new()
			h:queueAll({ 1, 2, 3 })
			h:advance(0.1)
			h.eligible[3] = false
			h:advance(11)
			t.expect(h.director:getParticipant(3)).toBeNil()
			t.expect(h.director:getPhase()).toBe("Intro")
		end)

		t.it("plays a complete Infiltrator victory: hack x3, extract, resolve, return, cleanup", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local infiltrators = h:infiltrators()
			local a, b = infiltrators[1], infiltrators[2]
			h:hack(a, "T1")
			t.expect(h.director:getPhase()).toBe("Active")
			h:hack(b, "T2")
			h:hack(a, "T3")
			t.expect(h.director:getPhase()).toBe("Extraction")
			t.expect(h:count("TerminalCompleted")).toBe(3)
			t.expect(h:count("ExtractionOpened")).toBe(1)
			h.inZone[a] = true
			h:advance(3.5)
			t.expect((h.director:getParticipant(a) :: any).status).toBe("Extracted")
			-- b is still active, so the match continues until b extracts or the window ends.
			t.expect(h.director:getPhase()).toBe("Extraction")
			h.inZone[b] = true
			h:advance(3.5)
			t.expect(h.director:getPhase()).toBe("Resolving")
			local result = h:last("MatchResolved")
			t.expect(result.winner).toBe("Infiltrators")
			t.expect(result.reason).toBe("Extracted")
			t.expect(result.participants[a].hacks).toBe(2)
			t.expect(result.participants[b].hacks).toBe(1)
			h:advance(10.2)
			t.expect(h.director:getPhase()).toBe("ReturningToLobby")
			t.expect(#h:last("ReturnToLobby").userIds).toBe(3)
			h:advance(3.2)
			t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
			t.expect(h.director.session).toBeNil()
			t.expect(h:count("MatchResolved")).toBe(1)
			t.expect(h:count("MatchCleanup")).toBe(1)
		end)

		t.it("awards the Keeper a win when the match timer expires", function()
			local h = Harness.new({ matchDuration = 30 })
			h:startMatch({ 1, 2 })
			h:advance(31)
			local result = h:last("MatchResolved")
			t.expect(result.winner).toBe("TimeKeeper")
			t.expect(result.reason).toBe("TimeExpired")
		end)

		-- Drives the last hack so it would finish `overrun` seconds after the deadline, then delivers
		-- one (possibly late) tick at `tickAt` seconds after the deadline.
		local function finalHackAroundDeadline(overrun: number, tickAt: number)
			local h = Harness.new({ matchDuration = 60 })
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:hack(a, "T1")
			h:hack(a, "T2")
			local deadline = (h.director.session :: any).deadline
			local startAt = deadline + overrun - h.director.config.hackDuration
			h:advance(startAt - h.now)
			h:placeAt(a, "T3")
			t.expect((h.director:requestHackStart(a, "T3", h.now))).toBe(true)
			h:advance(deadline - 0.2 - h.now)
			h.now = deadline + tickAt
			h.director:tick(h.now)
			return h
		end

		t.it("does not count hack progress earned after the timer expired (late tick)", function()
			local h = finalHackAroundDeadline(0.5, 1)
			t.expect(h:count("ExtractionOpened")).toBe(0)
			t.expect(h:last("MatchResolved").reason).toBe("TimeExpired")
		end)

		t.it("opens extraction when the final hack completes exactly at the deadline", function()
			local h = finalHackAroundDeadline(0, 0)
			t.expect(h:count("ExtractionOpened")).toBe(1)
			t.expect(h.director:getPhase()).toBe("Extraction")
			t.expect(h:count("MatchResolved")).toBe(0)
		end)

		t.it("awards the Keeper a win when all Infiltrators are eliminated", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local keeper = h:keeper()
			for _, userId in h:infiltrators() do
				t.expect(h.director:eliminate(userId, keeper, h.now)).toBe(true)
			end
			local result = h:last("MatchResolved")
			t.expect(result.reason).toBe("AllEliminated")
			t.expect(result.participants[keeper].eliminations).toBe(2)
		end)

		t.it("awards the Keeper a win when extraction closes with nobody out", function()
			local h = Harness.new({ extractionWindow = 10 })
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:hack(a, "T1")
			h:hack(a, "T2")
			h:hack(a, "T3")
			t.expect(h.director:getPhase()).toBe("Extraction")
			h:advance(10.5)
			t.expect(h:last("MatchResolved").reason).toBe("ExtractionFailed")
		end)

		t.it("still counts the team win if one Infiltrator extracts and the other is eliminated", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local a, b = h:infiltrators()[1], h:infiltrators()[2]
			h:hack(a, "T1")
			h:hack(a, "T2")
			h:hack(a, "T3")
			h.inZone[a] = true
			h:advance(3.5)
			h.director:eliminate(b, h:keeper(), h.now)
			local result = h:last("MatchResolved")
			t.expect(result.winner).toBe("Infiltrators")
			t.expect(result.reason).toBe("Extracted")
		end)

		t.it("resolves exactly once even with duplicate elimination events", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			t.expect(h.director:eliminate(a, h:keeper(), h.now)).toBe(true)
			t.expect(h.director:eliminate(a, h:keeper(), h.now)).toBe(false)
			h.director:playerRemoving(a, h.now)
			h:advance(1)
			t.expect(h:count("MatchResolved")).toBe(1)
			t.expect(h:count("PlayerEliminated")).toBe(1)
		end)

		t.it("gives the Infiltrators the win when the Keeper disconnects mid-match", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			h.director:playerRemoving(h:keeper(), h.now)
			t.expect(h:last("MatchResolved").reason).toBe("KeeperLeft")
			t.expect(h:last("MatchResolved").winner).toBe("Infiltrators")
		end)

		t.it("aborts (no winner) when someone leaves during the intro", function()
			local h = Harness.new()
			h:queueAll({ 1, 2 })
			h:advance(10.3)
			t.expect(h.director:getPhase()).toBe("Intro")
			h.director:playerRemoving((h.director.session :: any).keeperUserId, h.now)
			local result = h:last("MatchResolved")
			t.expect(result.reason).toBe("Aborted")
			t.expect(result.winner).toBeNil()
		end)

		t.it("awards the Keeper when every Infiltrator disconnects", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			for _, userId in h:infiltrators() do
				h.director:playerRemoving(userId, h.now)
			end
			t.expect(h:last("MatchResolved").reason).toBe("InfiltratorsLeft")
		end)

		t.it("never gets stuck when everyone leaves", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			for _, userId in { 1, 2, 3 } do
				h.director:playerRemoving(userId, h.now)
			end
			t.expect(h:count("MatchResolved")).toBe(1)
			h:advance(15)
			t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
			t.expect(h.director.session).toBeNil()
		end)

		t.it("runs repeated matches without leaking state, listeners, or stale ids", function()
			local h = Harness.new({ matchDuration = 5 })
			local ids: { [string]: boolean } = {}
			local listeners = h.director.events:GetConnectionCount()
			for round = 1, 4 do
				h:startMatch({ 1, 2, 3 })
				local matchId = (h.director.session :: any).matchId
				t.expect(ids[matchId]).toBeNil()
				ids[matchId] = true
				h:advance(6)
				t.expect(h.director:getPhase()).toBe("Resolving")
				h:advance(14)
				t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
				t.expect(h.director.session).toBeNil()
				t.expect(h.director:isCurrentMatch(matchId)).toBe(false)
				t.expect(h:count("MatchResolved")).toBe(round)
			end
			t.expect(h.director.events:GetConnectionCount()).toBe(listeners)
			t.expect(h.director.queue:count()).toBe(0)
		end)

		t.it("rotates the Time-Keeper between consecutive matches", function()
			local h = Harness.new({ matchDuration = 5 })
			local keepers = {}
			for _ = 1, 3 do
				h:startMatch({ 1, 2, 3 })
				table.insert(keepers, h:keeper())
				h:advance(20)
			end
			t.expect(keepers[1] ~= keepers[2] and keepers[2] ~= keepers[3] and keepers[1] ~= keepers[3]).toBe(true)
		end)

		t.it("requires the normal threshold once keeperless mode is switched off at runtime", function()
			local h = Harness.new({ allowKeeperless = true })
			h.director.config.allowKeeperless = false -- e.g. a second player joined the Studio server
			h:queueAll({ 9 })
			h:advance(10)
			t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
		end)

		t.it("supports a Studio-only keeperless solo match when enabled", function()
			local h = Harness.new({ allowKeeperless = true })
			h:startMatch({ 9 })
			t.expect(h:keeper()).toBeNil()
			h:hack(9, "T1")
			h:hack(9, "T2")
			h:hack(9, "T3")
			h.inZone[9] = true
			h:advance(3.5)
			t.expect(h:last("MatchResolved").reason).toBe("Extracted")
		end)
	end)
end
