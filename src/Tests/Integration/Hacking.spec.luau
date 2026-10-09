--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Harness = require(ServerScriptService.Tests.Helpers.DirectorHarness)

return function(t: any)
	t.describe("Hacking rules", function()
		t.it("rejects hacks outside the Active phase", function()
			local h = Harness.new()
			h:queueAll({ 1, 2 })
			h:advance(10.3)
			t.expect(h.director:getPhase()).toBe("Intro")
			local ok, code = h.director:requestHackStart(1, "T1", h.now)
			t.expect(ok).toBe(false)
			t.expect(code).toBe("WrongPhase")
		end)

		t.it("validates role, participation, target, and range", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local keeper, a = h:keeper(), h:infiltrators()[1]
			h:placeAt(keeper, "T1")
			t.expect(select(2, h.director:requestHackStart(keeper, "T1", h.now))).toBe("WrongRole")
			t.expect(select(2, h.director:requestHackStart(999, "T1", h.now))).toBe("NotParticipant")
			h:placeAt(a, "T1")
			t.expect(select(2, h.director:requestHackStart(a, "ForgedTerminal", h.now))).toBe("UnknownTarget")
			h.distance[a] = { T1 = 12.5 }
			t.expect(select(2, h.director:requestHackStart(a, "T1", h.now))).toBe("OutOfRange")
			h.distance[a] = { T1 = 0 / 0 }
			t.expect(select(2, h.director:requestHackStart(a, "T1", h.now))).toBe("OutOfRange")
			h.distance[a] = { T1 = 12 }
			t.expect((h.director:requestHackStart(a, "T1", h.now))).toBe(true)
		end)

		t.it("rejects dead and restrained hackers", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:placeAt(a, "T1")
			h.alive[a] = false
			t.expect(select(2, h.director:requestHackStart(a, "T1", h.now))).toBe("NotAlive")
			h.alive[a] = true
			h.restrained[a] = true
			t.expect(select(2, h.director:requestHackStart(a, "T1", h.now))).toBe("Restrained")
		end)

		t.it("allows one hacker per terminal and one terminal per hacker", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local a, b = h:infiltrators()[1], h:infiltrators()[2]
			h.distance[a] = { T1 = 5, T2 = 5 }
			h.distance[b] = { T1 = 5 }
			t.expect((h.director:requestHackStart(a, "T1", h.now))).toBe(true)
			t.expect(select(2, h.director:requestHackStart(b, "T1", h.now))).toBe("Busy")
			t.expect(select(2, h.director:requestHackStart(a, "T1", h.now))).toBe("AlreadyHacking")
			t.expect(select(2, h.director:requestHackStart(a, "T2", h.now))).toBe("AlreadyHacking")
		end)

		t.it("interrupts when the hacker walks out of range and retains progress", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:placeAt(a, "T1")
			h.director:requestHackStart(a, "T1", h.now)
			h:advance(6)
			h.distance[a] = { T1 = 20 }
			h:advance(0.2)
			local interrupted = h:last("HackInterrupted")
			t.expect(interrupted.reason).toBe("OutOfRange")
			local terminal = h.director:publicTerminal("T1") :: any
			t.expect(terminal.state).toBe("Interrupted")
			t.expect(terminal.progress).toBeGreaterThan(0.35)
			h:advance(1.6)
			t.expect((h.director:publicTerminal("T1") :: any).state).toBe("Available")
		end)

		t.it("interrupts on damage, death, restraint, and disconnect", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3, 4 })
			local a, b, c = h:infiltrators()[1], h:infiltrators()[2], h:infiltrators()[3]
			h:placeAt(a, "T1")
			h:placeAt(b, "T2")
			h:placeAt(c, "T3")
			h.director:requestHackStart(a, "T1", h.now)
			h.director:requestHackStart(b, "T2", h.now)
			h.director:requestHackStart(c, "T3", h.now)
			h.director:notifyDamage(a, h.now)
			t.expect(h:last("HackInterrupted").reason).toBe("Damaged")
			h.alive[b] = false
			h:advance(0.1)
			t.expect(h:last("HackInterrupted").reason).toBe("Died")
			h.director:playerRemoving(c, h.now)
			t.expect(h:last("HackInterrupted").reason).toBe("Disconnected")
			t.expect(h:count("HackInterrupted")).toBe(3)
			for _, id in { "T1", "T2", "T3" } do
				t.expect((h.director:publicTerminal(id) :: any).hackerUserId).toBeNil()
			end
		end)

		t.it("lets a teammate resume a partially hacked terminal", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local a, b = h:infiltrators()[1], h:infiltrators()[2]
			h:placeAt(a, "T1")
			h.director:requestHackStart(a, "T1", h.now)
			h:advance(10)
			h.director:cancelHack(a, "Cancelled", h.now)
			h:advance(1.6)
			h:placeAt(b, "T1")
			t.expect((h.director:requestHackStart(b, "T1", h.now))).toBe(true)
			h:advance(5.3)
			t.expect((h.director:publicTerminal("T1") :: any).state).toBe("Completed")
		end)

		t.it("counts each terminal once and rejects re-hacking a completed terminal", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local a, b = h:infiltrators()[1], h:infiltrators()[2]
			h:hack(a, "T1")
			h:placeAt(b, "T1")
			t.expect(select(2, h.director:requestHackStart(b, "T1", h.now))).toBe("AlreadyCompleted")
			t.expect(h:count("TerminalCompleted")).toBe(1)
			t.expect(h.director:snapshot().completedHacks).toBe(1)
		end)

		t.it("throttles progress broadcasts", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:placeAt(a, "T1")
			h.director:requestHackStart(a, "T1", h.now)
			h:advance(5, 0.05) -- 100 ticks
			local progressEvents = h:count("TerminalProgress")
			t.expect(progressEvents).toBeLessThan(22) -- ~4 per second
			t.expect(progressEvents).toBeGreaterThan(15)
		end)

		t.it("locks all terminals when the match resolves mid-hack", function()
			local h = Harness.new({ matchDuration = 8 })
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:placeAt(a, "T1")
			h.director:requestHackStart(a, "T1", h.now)
			h:advance(9)
			t.expect(h.director:getPhase()).toBe("Resolving")
			local terminal = h.director:publicTerminal("T1") :: any
			t.expect(terminal.state).toBe("Locked")
			t.expect(terminal.hackerUserId).toBeNil()
			t.expect(select(2, h.director:requestHackStart(a, "T2", h.now))).toBe("WrongPhase")
		end)

		t.it("does not allow extraction before the objectives are complete", function()
			local h = Harness.new()
			h:startMatch({ 1, 2 })
			local a = h:infiltrators()[1]
			h:hack(a, "T1")
			h:hack(a, "T2")
			h.inZone[a] = true
			h:advance(5)
			t.expect((h.director:getParticipant(a) :: any).status).toBe("Active")
			t.expect(h:count("PlayerExtracted")).toBe(0)
		end)

		t.it("does not extract eliminated or disconnected players and resets channels on exit", function()
			local h = Harness.new()
			h:startMatch({ 1, 2, 3 })
			local a, b = h:infiltrators()[1], h:infiltrators()[2]
			h:hack(a, "T1")
			h:hack(a, "T2")
			h:hack(a, "T3")
			h.inZone[a] = true
			h.inZone[b] = true
			h:advance(2)
			h.director:playerRemoving(b, h.now) -- b leaves mid-channel
			h.inZone[a] = false
			h:advance(0.2)
			h.inZone[a] = true
			h:advance(2)
			t.expect((h.director:getParticipant(a) :: any).status).toBe("Active") -- channel restarted
			h:advance(1.5)
			t.expect((h.director:getParticipant(a) :: any).status).toBe("Extracted")
			t.expect((h.director:getParticipant(b) :: any).status).toBe("Disconnected")
			t.expect(h:count("PlayerExtracted")).toBe(1)
		end)
	end)
end
