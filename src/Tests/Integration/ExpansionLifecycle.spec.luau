--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local MapLayout = require(ServerScriptService.Server.World.MapLayout)
local Harness = require(ServerScriptService.Tests.Helpers.DirectorHarness)
local Schema = require(ServerScriptService.Server.Core.ProfileSchema)
local Calculator = require(ServerScriptService.Server.Core.RewardCalculator)
local Ledger = require(ServerScriptService.Server.Core.RewardLedger)
return function(t: any)
	t.it("restores the queue and role fairness after a failed world setup", function()
		local calls = 0
		local h = Harness.new({
			prepareMatch = function()
				calls += 1
				if calls == 1 then
					error("test setup failure")
				end
				return Harness.TERMINALS
			end,
		})
		h:queueAll({ 1, 2, 3, 4, 5 })
		h:advance(10.2)
		t.expect(h.director.session).toBeNil()
		t.expect(h.director.queue:count()).toBe(5)
		t.expect(next(h.director.roleHistory)).toBeNil()
		h:advance(16)
		t.expect(h.director:getPhase()).toBe("Active")
		t.expect(h.director.matchesStarted).toBe(1)
	end)
	t.it(
		"runs twenty five-player matches across all maps with fair roles, co-op, extraction and idempotent progression",
		function()
			local prepared = 0
			local h = Harness.new({
				hackDuration = 5,
				cooperativeHacking = true,
				interactiveChallenges = true,
				prepareMatch = function()
					prepared += 1
					return MapLayout.Maps[MapConfig.Order[(prepared - 1) % 4 + 1]].terminals
				end,
			})
			local profiles: { [number]: Schema.Profile } = {}
			for userId = 1, 5 do
				profiles[userId] = Schema.defaults()
			end
			for round = 1, 20 do
				h:startMatch({ 1, 2, 3, 4, 5 })
				local session = h.director.session :: any
				local team = h:infiltrators()
				local ids = session.terminalOrder
				h:placeAt(team[1], ids[1])
				h:placeAt(team[2], ids[1])
				h.director:requestHackStart(team[1], ids[1], h.now)
				h.director:requestHackStart(team[2], ids[1], h.now)
				h:advance(6)
				t.expect((h.director:publicTerminal(ids[1]) :: any).state).toBe("Completed")
				for index = 2, 3 do
					h:placeAt(team[index + 1], ids[index])
					h.director:requestHackStart(team[index + 1], ids[index], h.now)
				end
				h:advance(7)
				t.expect(h.director:getPhase()).toBe("Extraction")
				for _, userId in team do
					h.inZone[userId] = true
				end
				h:advance(4)
				local result = session.result
				t.expect(result.winner).toBe("Infiltrators")
				result.rewardedAt = round * 86400
				for userId, participant in result.participants do
					participant.classId = ClassConfig.Order[(round - 1) % 5 + 1]
					local reward = Calculator.compute(result, participant)
					t.expect((Ledger.apply(profiles[userId], result.matchId, reward))).toBe(true)
					t.expect((Ledger.apply(profiles[userId], result.matchId, reward))).toBe(false)
				end
				h:advance(14)
				t.expect(h.director.session).toBeNil()
				t.expect(h.director.queue:count()).toBe(0)
				t.expect(h.director:getPhase()).toBe("WaitingForPlayers")
				table.clear(h.inZone)
			end
			t.expect(prepared).toBe(20)
			for _, profile in profiles do
				t.expect(profile.Stats.MatchesPlayed).toBe(20)
				t.expect(profile.Stats.KeeperMatches).toBe(4)
				t.expect(profile.Stats.InfiltratorMatches).toBe(16)
				t.expect(profile.Progression.XP > 0).toBe(true)
			end
			t.expect(#h.director.machine.history <= 64).toBe(true)
		end
	)
end
