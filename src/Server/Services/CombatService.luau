--!strict
-- CombatService: the Time-Keeper's Chrono Strike. A strike is telegraphed for a short wind-up, then
-- resolved against the server's current positions. A hit moves the target one step down the
-- integrity ladder through MatchDirector (no remote can set health or declare a hit), gives the
-- victim an escape burst and the Keeper a recoil; a whiff costs a short recovery. Striking a target
-- slowed by a Time-Freeze Zone or Temporal Trap also reveals them to the Keeper (ability combo).
-- Damage attribution is bounded (DamageAttributionWindow) and cleared at match end.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

local AbilityRules = require(script.Parent.Parent.Core.AbilityRules)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

local CombatService = {}

local deps: { [string]: any } = {}
local attribution: { [Player]: { by: number, at: number } } = {}

local strike = SurvivalConfig.Strike

local function now(): number
	return Workspace:GetServerTimeNow()
end

function CombatService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		attribution[player] = nil
	end)
end

function CombatService.GetAttribution(victim: Player): number?
	local record = attribution[victim]
	if record and now() - record.at <= GameConfig.DamageAttributionWindow then
		return record.by
	end
	return nil
end

function CombatService.EndMatch()
	table.clear(attribution)
end

local function selfSlow(caster: Player, key: string, magnitude: number, duration: number, source: string)
	deps.StatusEffectService.Apply(caster, {
		key = key,
		kind = "Slow",
		magnitude = magnitude,
		duration = duration,
		source = source,
	})
end

-- Resolves a strike after its wind-up using the caster's current position and the original aim.
local function resolve(caster: Player, aim: Vector3, matchId: string?)
	if not deps.MatchService.IsCurrentMatch(matchId) or not deps.MatchService.IsActiveParticipant(caster) then
		return
	end
	if deps.StatusEffectService.IsRestrained(caster) then
		return -- stunned during the wind-up (e.g. a Stasis Barrier): the swing is lost
	end
	local definition = AbilityConfig.Abilities.ChronoStrike
	local character = caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local origin = root.Position
	local eye = origin + Vector3.new(0, ServerConfig.Combat.EyeHeight, 0)

	local candidates: { AbilityRules.StrikeCandidate } = {}
	local byUserId: { [number]: Player } = {}
	for _, target in deps.MatchService.GetFreeInfiltrators() do
		local targetCharacter = target.Character
		local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		if targetRoot and humanoid and humanoid.Health > 0 and not deps.InteractionService.IsHidden(target) then
			table.insert(candidates, { userId = target.UserId, position = targetRoot.Position })
			byUserId[target.UserId] = target
		end
	end

	local targetId = AbilityRules.selectStrikeTarget(
		origin,
		aim,
		candidates,
		definition.Range,
		definition.ConeAngleDegrees,
		function(c)
			return deps.WorldService.HasLineOfSight(eye, c.position)
		end
	)

	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.Strike,
		userId = caster.UserId,
		position = origin,
		direction = aim,
	})

	local victim = if targetId then byUserId[targetId] else nil
	if victim == nil then
		selfSlow(caster, "strikeMiss", strike.MissSlow, strike.MissDuration, "StrikeMiss")
		return
	end
	if deps.StatusEffectService.IsInvulnerable(victim) then
		selfSlow(caster, "strikeMiss", strike.MissSlow, strike.MissDuration, "StrikeMiss")
		return
	end
	local combo = deps.StatusEffectService.HasSource(victim, "Slow", { "TimeFreeze", "TemporalTrap" })
	attribution[victim] = { by = caster.UserId, at = now() }
	deps.MatchService.NotifyDamage(victim)
	local outcome = deps.MatchService.GetDirector():strike(victim.UserId, caster.UserId, now())
	if outcome == "Ignored" then
		return
	end
	selfSlow(caster, "strikeRecoil", strike.RecoilSlow, strike.RecoilDuration, "StrikeRecoil")
	deps.HuntService.OnKeeperHit(caster)
	if combo then
		deps.NetworkService.FireClient(
			RemoteNames.Effect,
			caster,
			{ kind = "Tracking", userId = victim.UserId, duration = strike.FractureRevealDuration }
		)
		deps.NetworkService.Notify(
			{ caster },
			Protocol.NotifyKinds.Toast,
			"Temporal Fracture — target revealed!",
			"Temporal",
			2
		)
	end
	local victimRoot = (victim.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.Hit,
		userId = victim.UserId,
		byUserId = caster.UserId,
		position = if victimRoot then victimRoot.Position else origin,
		outcome = outcome,
		condition = deps.MatchService.GetDirector():getCondition(victim.UserId),
	})
end

-- Starts a validated Chrono Strike (the caster passed AbilityRules.checkCaster). The wind-up is
-- telegraphed to everyone; a swing that finds no target still uses the cooldown.
function CombatService.Strike(caster: Player, aim: Vector3): (boolean, string)
	local flatAim = Vector3.new(aim.X, 0, aim.Z)
	if flatAim.Magnitude < 1e-3 then
		return false, Protocol.Codes.InvalidPayload
	end
	local direction = flatAim.Unit
	local root = caster.Character and caster.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false, Protocol.Codes.NotAlive
	end
	local matchId = deps.MatchService.CurrentMatchId()
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = "StrikeWindup",
		userId = caster.UserId,
		position = root.Position,
		direction = direction,
		duration = strike.Windup,
	})
	task.delay(strike.Windup, function()
		local ok, err = Safe.call(resolve, caster, direction, matchId)
		if not ok then
			warn(`[CombatService] strike resolution failed: {err}`)
		end
	end)
	return true, Protocol.Codes.Ok
end

return CombatService
