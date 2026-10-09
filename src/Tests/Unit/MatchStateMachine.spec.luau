--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local MatchStateMachine = require(ServerScriptService.Server.Core.MatchStateMachine)

return function(t: any)
	t.describe("MatchStateMachine", function()
		t.it("starts in WaitingForPlayers", function()
			local m = MatchStateMachine.new(0)
			t.expect(m.phase).toBe("WaitingForPlayers")
			t.expect(m:isInMatch()).toBe(false)
		end)

		t.it("walks the full legal cycle", function()
			local m = MatchStateMachine.new(0)
			local path = {
				"Intermission",
				"RoleAssignment",
				"Intro",
				"Active",
				"Extraction",
				"Resolving",
				"ReturningToLobby",
				"WaitingForPlayers",
			}
			for i, phase in path do
				t.expect(m:transition(phase :: any, i)).toBe(true)
				t.expect(m.phase).toBe(phase)
			end
			t.expect(#m.history).toBe(#path)
		end)

		t.it("rejects illegal transitions and keeps state", function()
			local m = MatchStateMachine.new(0)
			t.expect(m:transition("Active", 1)).toBe(false)
			t.expect(m:transition("Resolving", 1)).toBe(false)
			t.expect(m:transition("WaitingForPlayers", 1)).toBe(false) -- no self-transition
			t.expect(m.phase).toBe("WaitingForPlayers")
			m:transition("Intermission", 2)
			t.expect(m:transition("Extraction", 3)).toBe(false)
			t.expect(m.phase).toBe("Intermission")
		end)

		t.it("does not allow skipping straight from Active back to the lobby", function()
			t.expect(MatchStateMachine.isLegal("Active", "ReturningToLobby")).toBe(false)
			t.expect(MatchStateMachine.isLegal("Active", "WaitingForPlayers")).toBe(false)
			t.expect(MatchStateMachine.isLegal("Extraction", "Active")).toBe(false)
		end)

		t.it("reports in-match phases", function()
			t.expect(MatchStateMachine.isInMatchPhase("Intro")).toBe(true)
			t.expect(MatchStateMachine.isInMatchPhase("Active")).toBe(true)
			t.expect(MatchStateMachine.isInMatchPhase("Extraction")).toBe(true)
			t.expect(MatchStateMachine.isInMatchPhase("Resolving")).toBe(false)
			t.expect(MatchStateMachine.isInMatchPhase("Intermission")).toBe(false)
		end)

		t.it("bounds its transition history", function()
			local m = MatchStateMachine.new(0)
			for i = 1, 200 do
				m:transition(if i % 2 == 1 then "Intermission" else "WaitingForPlayers", i)
			end
			t.expect(#m.history).toBe(MatchStateMachine.HISTORY_LIMIT)
		end)
	end)
end
