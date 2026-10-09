--!strict
-- CombatService: the Time-Keeper's Chrono Strike. Damage is computed and applied only here; no remote
-- can set health or declare a kill. Elimination is processed exactly once by the MatchDirector when
-- the Humanoid dies (CharacterService forwards Died -> MatchService.OnCharacterDied).
-- Damage attribution is bounded (DamageAttributionWindow) and cleared at match end.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local AbilityRules = require(script.Parent.Parent.Core.AbilityRules)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

local CombatService = {}

local deps: { [string]: any } = {}
local attribution: { [Player]: { by: number, at: number } } = {}

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

-- Executes a validated Chrono Strike. The caster has already passed AbilityRules.checkCaster.
-- Returns (ok, code). A swing with no valid target is still a swing (cooldown applies).
function CombatService.Strike(caster: Player, aim: Vector3): (boolean, string)
	local definition = AbilityConfig.Abilities.ChronoStrike
	local character = caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false, Protocol.Codes.NotAlive
	end
	local origin = root.Position
	local eye = origin + Vector3.new(0, ServerConfig.Combat.EyeHeight, 0)

	local candidates: { AbilityRules.StrikeCandidate } = {}
	local byUserId: { [number]: Player } = {}
	for _, target in deps.MatchService.GetActiveInfiltrators() do
		local targetCharacter = target.Character
		local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		if targetRoot and humanoid and humanoid.Health > 0 then
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
		direction = Vector3.new(aim.X, 0, aim.Z).Unit,
	})

	if targetId == nil then
		return true, Protocol.Codes.NoTarget
	end
	local victim = byUserId[targetId]
	if deps.StatusEffectService.IsInvulnerable(victim) then
		return true, "Protected"
	end
	local victimCharacter = victim.Character :: Model
	local humanoid = victimCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid
	attribution[victim] = { by = caster.UserId, at = now() }
	deps.MatchService.NotifyDamage(victim)
	humanoid:TakeDamage(definition.Damage)
	local victimRoot = victimCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.Hit,
		userId = victim.UserId,
		byUserId = caster.UserId,
		position = if victimRoot then victimRoot.Position else origin,
		health = math.max(0, humanoid.Health),
	})
	return true, Protocol.Codes.Ok
end

return CombatService
