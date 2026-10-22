--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ChaseModel = require(ServerScriptService.Server.Core.ChaseModel)
local EndgameModel = require(ServerScriptService.Server.Core.EndgameModel)
local StaminaModel = require(ServerScriptService.Server.Core.StaminaModel)
local SurvivalModel = require(ServerScriptService.Server.Core.SurvivalModel)
local TerminalModel = require(ServerScriptService.Server.Core.TerminalModel)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

local QUIET = {
	isCamped = function(_: string)
		return false
	end,
	drainMultiplier = 1,
}

return function(t: any)
	t.describe("SurvivalModel", function()
		t.it("walks the integrity ladder one step per hit and ignores hits on Desynced players", function()
			local model = SurvivalModel.new({ "P1" })
			model:add(7)
			t.expect(model:hit(7, 0)).toBe("Injured")
			t.expect(model:hit(7, 1)).toBe("Downed")
			t.expect((model:get(7) :: any).bleedoutAt).toBe(1 + SurvivalConfig.Integrity.BleedoutTime)
			t.expect(model:hit(7, 2)).toBe("Ignored")
			t.expect(model:isFree(7)).toBe(false)
		end)

		t.it("keeps Patch and Re-sync progress on the target and completes exactly once", function()
			local model = SurvivalModel.new({})
			model:add(1)
			model:hit(1, 0)
			t.expect(model:recover(1, "Revive", 1)).toBe(false) -- wrong condition
			t.expect(model:recover(1, "Heal", 0.6)).toBe(false)
			t.expect((model:get(1) :: any).heal).toBeNear(0.6)
			t.expect(model:recover(1, "Heal", 0.4)).toBe(true)
			t.expect((model:get(1) :: any).condition).toBe("Healthy")
			model:hit(1, 0)
			model:hit(1, 0)
			t.expect(model:recover(1, "Revive", 0 / 0)).toBe(false)
			t.expect(model:recover(1, "Revive", 1)).toBe(true)
			t.expect((model:get(1) :: any).condition).toBe("Injured")
			t.expect((model:get(1) :: any).bleedoutAt).toBeNil()
		end)

		t.it("contains in stages, erases on the final stage and frees pods on release", function()
			local model = SurvivalModel.new({ "P1", "P2" })
			model:add(1)
			model:hit(1, 0)
			model:hit(1, 0)
			t.expect(model:contain(1, "P1", 0)).toBe("Contained")
			t.expect(model.pods.P1).toBe(1)
			t.expect((model:get(1) :: any).podDuration).toBe(SurvivalConfig.Containment.StageDurations[1])
			model:add(2)
			model:hit(2, 0)
			model:hit(2, 0)
			t.expect(model:contain(2, "P1", 0)).toBe("Ignored") -- occupied pod
			t.expect(model:release(1, 10)).toBe(true)
			t.expect(model.pods.P1).toBeNil()
			local vital = model:get(1) :: any
			t.expect(vital.condition).toBe("Injured")
			t.expect(vital.enduranceUntil).toBe(10 + SurvivalConfig.Containment.EnduranceDuration)
			-- Endurance absorbs the hit that would Desync.
			t.expect(model:hit(1, 11)).toBe("Endured")
			t.expect(model:hit(1, 12)).toBe("Downed")
			t.expect(model:contain(1, "P2", 12)).toBe("Contained")
			t.expect(vital.podDuration).toBe(SurvivalConfig.Containment.StageDurations[2])
			model:release(1, 13)
			model:hit(1, 30)
			model:hit(1, 30)
			t.expect(model:contain(1, "P1", 30)).toBe("Erased")
		end)

		t.it("drains pods, slows them under camping and releases after enough feedback", function()
			local model = SurvivalModel.new({ "P1" })
			model:add(1)
			model:hit(1, 0)
			model:hit(1, 0)
			model:contain(1, "P1", 0)
			local camped = {
				isCamped = function(_: string)
					return true
				end,
				drainMultiplier = 1,
			}
			local events = {}
			local now = 0
			while #events == 0 and now < 100 do
				now += 0.5
				events = model:tick(now, 0.5, camped)
			end
			t.expect(events[1].kind).toBe("Released")
			t.expect(now).toBeNear(SurvivalConfig.Containment.CampReleaseTime, 0.5)
			local vital = model:get(1) :: any
			t.expect(vital.podRemaining)
				.toBeNear(
					SurvivalConfig.Containment.StageDurations[1] - now * SurvivalConfig.Containment.CampDrainMultiplier,
					0.6
				)
			t.expect(vital.condition).toBe("Injured")
		end)

		t.it("erases when a pod timer runs out and reports bleed-out once", function()
			local model = SurvivalModel.new({ "P1" })
			model:add(1)
			model:add(2)
			model:hit(1, 0)
			model:hit(1, 0)
			model:contain(1, "P1", 0)
			model:hit(2, 0)
			model:hit(2, 0)
			local bled, erased = 0, 0
			for step = 1, 1300 do
				for _, event in model:tick(step * 0.1, 0.1, QUIET) do
					if event.kind == "BledOut" then
						bled += 1
					elseif event.kind == "Erased" then
						erased += 1
					end
				end
			end
			t.expect(bled).toBe(1)
			t.expect(erased).toBe(1)
			t.expect(model.pods.P1).toBeNil()
		end)
	end)

	t.describe("ChaseModel", function()
		t.it("opens after the sight dwell, closes after the grace, and builds capped momentum", function()
			local chase = ChaseModel.new()
			local config = SurvivalConfig.Chase
			local sample = { { userId = 1, distance = 10, visible = true } }
			t.expect(#chase:update(0, sample)).toBe(0)
			local events = chase:update(config.StartDwell, sample)
			t.expect(events[1].kind).toBe("ChaseStarted")
			t.expect(chase:momentum(config.StartDwell + config.MomentumInterval * 10)).toBe(config.MomentumMax)
			chase:update(20, sample)
			chase:resetMomentum(20)
			t.expect(chase:momentum(20 + config.MomentumInterval - 0.01)).toBe(0)
			local hidden = { { userId = 1, distance = 10, visible = false } }
			chase:update(21, hidden)
			t.expect(chase:isChased(1)).toBe(true)
			t.expect(chase:update(21 + config.LoseSightGrace, hidden)[1].kind).toBe("ChaseEnded")
			t.expect(chase:anyChase()).toBe(false)
			t.expect(chase:momentum(100)).toBe(0)
		end)

		t.it("ends chases for targets that leave sampling or range", function()
			local chase = ChaseModel.new()
			local near = { { userId = 2, distance = 5, visible = true } }
			chase:update(0, near)
			chase:update(1, near)
			t.expect(chase:isChased(2)).toBe(true)
			t.expect(chase:update(2, {})[1].kind).toBe("ChaseEnded")
			chase:update(3, near)
			chase:update(4, near)
			local far = { { userId = 2, distance = SurvivalConfig.Chase.MaxRange + 1, visible = true } }
			t.expect(chase:update(4.1, far)[1].kind).toBe("ChaseEnded")
		end)
	end)

	t.describe("StaminaModel", function()
		t.it("drains only while moving and sprinting, exhausts at zero and recovers past the threshold", function()
			local config = SurvivalConfig.Stamina
			local stamina = StaminaModel.new()
			stamina:setWanted(true)
			t.expect(stamina:tick(0, 0.1, false, true)).toBe(false)
			t.expect(stamina.value).toBe(config.Max)
			t.expect(stamina:tick(0.1, 0.1, true, true)).toBe(true)
			local now = 0.1
			while not stamina.exhausted and now < 20 do
				now += 0.1
				stamina:tick(now, 0.1, true, true)
			end
			t.expect(now).toBeNear(0.1 + config.Max / config.DrainPerSecond, 0.15)
			t.expect(stamina.sprinting).toBe(false)
			-- No regeneration inside the delay; then exhaustion clears at the recover threshold.
			stamina:tick(now + 0.5, 0.5, true, true)
			t.expect(stamina.value).toBe(0)
			local t0 = now + config.RegenDelay
			stamina:tick(t0, 0.1, true, true)
			local recoverAt = t0
			while stamina.exhausted and recoverAt < t0 + 10 do
				recoverAt += 0.1
				stamina:tick(recoverAt, 0.1, true, true)
			end
			t.expect(stamina.value).toBeGreaterThan(config.RecoverThreshold - 1)
		end)

		t.it("gadget costs are paid up front and pause regeneration", function()
			local config = SurvivalConfig.Stamina
			local stamina = StaminaModel.new()
			t.expect(stamina:spend(0, 35)).toBe(true)
			t.expect(stamina.value).toBe(config.Max - 35)
			stamina:tick(0.5, 0.5, false, true)
			t.expect(stamina.value).toBe(config.Max - 35) -- still inside RegenDelay
			t.expect(stamina:spend(0.5, 70)).toBe(false) -- cannot overdraw
			stamina.exhausted = true
			t.expect(stamina:spend(0.5, 1)).toBe(false)
		end)

		t.it("never sprints when the server disallows it", function()
			local stamina = StaminaModel.new(1.25)
			stamina:setWanted(true)
			stamina:tick(0, 0.1, true, false)
			t.expect(stamina.sprinting).toBe(false)
			t.expect(stamina.max).toBe(SurvivalConfig.Stamina.Max * 1.25)
		end)
	end)

	t.describe("EndgameModel", function()
		t.it("opens the gate from the first fully powered relay and raises instability tiers", function()
			local config = SurvivalConfig.Endgame
			local endgame = EndgameModel.new({ "R1", "R2" })
			t.expect(endgame:power("R1", 1)).toBe(false) -- not begun
			t.expect(endgame:tier(0)).toBe("Dormant")
			endgame:begin(0, 100)
			t.expect(endgame:begin(1, 100)).toBe(false)
			t.expect(endgame:power("R1", 0.5)).toBe(false)
			t.expect(endgame:power("R9", 1)).toBe(false)
			t.expect(endgame:power("R1", 0.5)).toBe(true)
			t.expect(endgame.gateOpen).toBe(true)
			t.expect(endgame:power("R2", 1)).toBe(false)
			t.expect(endgame:tier(100 * config.RisingAt)).toBe("Rising")
			t.expect(endgame:tier(100 * config.CriticalAt)).toBe("Critical")
			t.expect(endgame:shockwaveDue(100 * config.CriticalAt)).toBe(true)
			t.expect(endgame:shockwaveDue(100 * config.CriticalAt + 1)).toBe(false)
			t.expect(endgame:shockwaveDue(100 * config.CriticalAt + config.ShockwaveInterval)).toBe(true)
		end)

		t.it("opens immediately when a map has no relays", function()
			local endgame = EndgameModel.new({})
			endgame:begin(0, 60)
			t.expect(endgame.gateOpen).toBe(true)
		end)
	end)

	t.describe("Terminal overload", function()
		t.it("regresses only idle terminals with progress until hacking resumes", function()
			local terminal = TerminalModel.new("T", "T")
			terminal:unlock()
			t.expect(terminal:overload(0.04)).toBe(false) -- no progress
			terminal:start(1, 0)
			terminal:advance(5, 10)
			t.expect(terminal:overload(0.04)).toBe(false) -- being hacked
			terminal:interrupt("Cancelled", 5, 0, true)
			terminal:tickLockout(5)
			t.expect(terminal:overload(0.04)).toBe(true)
			t.expect(terminal.progress).toBeNear(0.46)
			t.expect(terminal:overload(0.04)).toBe(false)
			terminal:regress(10, 0.01)
			t.expect(terminal.progress).toBeNear(0.36)
			terminal:start(2, 15)
			t.expect(terminal.regressing).toBe(false)
			terminal:interrupt("Cancelled", 15, 0, true)
			terminal:tickLockout(15)
			terminal:overload(0)
			t.expect(terminal:regress(100, 0.01)).toBe(true)
			t.expect(terminal.progress).toBe(0)
		end)
	end)
end
