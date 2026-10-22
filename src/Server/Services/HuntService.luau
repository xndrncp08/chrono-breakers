--!strict
-- HuntService: pursuit pacing.
--   * Sprint: SprintRequest(wanted, matchId) only states intent; StaminaModel decides on the server
--     whether the Infiltrator actually sprints (moving, free, not hidden/vaulting/restrained).
--   * Chase: ChaseModel samples the Keeper's line of sight to free, visible Infiltrators at 5 Hz.
--     Chase state drives the victim's pursuit warning and both sides' chase music.
--   * Hunt Momentum: Keeper speed grows with continuous chase time and resets on hits and stuns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

local ChaseModel = require(script.Parent.Parent.Core.ChaseModel)
local StaminaModel = require(script.Parent.Parent.Core.StaminaModel)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

local HuntService = {}

type StaminaEntry = { model: StaminaModel.StaminaModel, sent: string, sentAt: number }

local deps: { [string]: any } = {}
local stamina: { [Player]: StaminaEntry } = {}
local chase = ChaseModel.new()
local momentumApplied = 0
local chaseAccumulator = 0
local TICK = 0.1
local CHASE_INTERVAL = 0.2

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function inPursuitPhase(): boolean
	local phase = deps.MatchService.GetPhase()
	return phase == "Active" or phase == "Extraction"
end

local function setSprinting(player: Player, sprinting: boolean)
	if sprinting then
		deps.StatusEffectService.Apply(player, {
			key = "sprint",
			kind = "Haste",
			magnitude = SurvivalConfig.Stamina.SprintHaste,
			duration = 600,
			source = "Sprint",
		})
	else
		deps.StatusEffectService.Remove(player, "sprint")
	end
end

local function sendStamina(player: Player, entry: StaminaEntry, force: boolean)
	local model = entry.model
	local signature = `{math.floor(model:fraction() * 50)}|{model.sprinting}|{model.exhausted}`
	local t = os.clock()
	if not force and (signature == entry.sent or t - entry.sentAt < 0.2) then
		return
	end
	entry.sent, entry.sentAt = signature, t
	deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
		kind = "Stamina",
		value = math.floor(model:fraction() * 100 + 0.5) / 100,
		sprinting = model.sprinting,
		exhausted = model.exhausted,
	})
end

local function applyMomentum()
	local keeper = deps.MatchService.GetKeeper()
	local momentum = chase:momentum(now())
	if momentum == momentumApplied or not keeper then
		return
	end
	momentumApplied = momentum
	if momentum > 0 then
		deps.StatusEffectService.Apply(keeper, {
			key = "momentum",
			kind = "Haste",
			magnitude = momentum,
			duration = 600,
			source = "HuntMomentum",
		})
		deps.NetworkService.Notify(
			{ keeper },
			Protocol.NotifyKinds.Toast,
			`Hunt Momentum +{math.floor(momentum * 100 + 0.5)}%`,
			"Temporal",
			1.5
		)
	else
		deps.StatusEffectService.Remove(keeper, "momentum")
	end
	deps.NetworkService.FireClient(RemoteNames.StatusUpdate, keeper, { kind = "Momentum", value = momentum })
end

local function sendChase(userId: number, chased: boolean)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
			kind = "Chase",
			chased = chased,
			matchId = deps.MatchService.CurrentMatchId(),
		})
	end
	local keeper = deps.MatchService.GetKeeper()
	if keeper then
		local targets = {}
		for id in chase.chasing do
			table.insert(targets, id)
		end
		deps.NetworkService.FireClient(RemoteNames.StatusUpdate, keeper, {
			kind = "Hunt",
			targets = targets,
			matchId = deps.MatchService.CurrentMatchId(),
		})
	end
end

local function updateChase()
	local keeper = deps.MatchService.GetKeeper()
	local keeperRoot = rootOf(keeper)
	local samples: { ChaseModel.Sample } = {}
	if keeperRoot and keeper and deps.MatchService.IsActiveParticipant(keeper) then
		local eye = keeperRoot.Position + Vector3.new(0, ServerConfig.Combat.EyeHeight, 0)
		for _, target in deps.MatchService.GetFreeInfiltrators() do
			local root = rootOf(target)
			if root and not deps.InteractionService.IsHidden(target) then
				local distance = (root.Position - keeperRoot.Position).Magnitude
				local visible = distance <= SurvivalConfig.Chase.MaxRange
					and not deps.StatusEffectService.Has(target, "Cloaked")
					and deps.WorldService.HasLineOfSight(eye, root.Position + Vector3.new(0, 1, 0))
				table.insert(samples, { userId = target.UserId, distance = distance, visible = visible })
			end
		end
	end
	for _, event in chase:update(now(), samples) do
		sendChase(event.userId, event.kind == "ChaseStarted")
		deps.TelemetryService.Chase(event.userId, event.kind == "ChaseStarted")
	end
	applyMomentum()
end

local function tick(dt: number)
	if not inPursuitPhase() then
		if next(stamina) or chase:anyChase() or momentumApplied > 0 then
			HuntService.EndMatch()
		end
		return
	end
	local director = deps.MatchService.GetDirector()
	local t = now()
	for _, player in deps.MatchService.GetActiveInfiltrators() do
		local entry = stamina[player]
		if not entry then
			local class = ClassConfig.get(deps.MatchService.GetMatchClass(player))
			entry = {
				model = StaminaModel.new(
					if class then class.StaminaScale else 1,
					deps.PerkService.Value(player, "StaminaRegen")
				),
				sent = "",
				sentAt = 0,
			}
			stamina[player] = entry
		end
		local current = entry :: StaminaEntry
		local root = rootOf(player)
		local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > SurvivalConfig.Stamina.MovingSpeed
		local allowed = director:isFree(player.UserId)
			and not deps.InteractionService.IsHidden(player)
			and not deps.InteractionService.IsBusy(player)
			and not deps.StatusEffectService.IsRestrained(player)
		if current.model:tick(t, dt, moving, allowed) then
			setSprinting(player, current.model.sprinting)
			sendStamina(player, current, true)
		else
			sendStamina(player, current, false)
		end
	end
	chaseAccumulator += dt
	if chaseAccumulator >= CHASE_INTERVAL then
		chaseAccumulator = 0
		updateChase()
	end
end

-- Pays a gadget's stamina cost; false while exhausted, short, or outside a match.
function HuntService.SpendStamina(player: Player, amount: number): boolean
	local entry = stamina[player]
	if not entry or not entry.model:spend(now(), amount) then
		return false
	end
	sendStamina(player, entry, true)
	return true
end

function HuntService.IsChased(player: Player): boolean
	return chase:isChased(player.UserId)
end

function HuntService.OnKeeperHit(_keeper: Player)
	chase:resetMomentum(now())
	applyMomentum()
end

function HuntService.OnKeeperStunned(_keeper: Player)
	chase:resetMomentum(now())
	applyMomentum()
end

function HuntService.EndMatch()
	for player, entry in stamina do
		if entry.model.sprinting then
			setSprinting(player, false)
		end
	end
	table.clear(stamina)
	for _, event in chase:clear() do
		sendChase(event.userId, false)
	end
	local keeper = deps.MatchService.GetKeeper()
	if keeper then
		deps.StatusEffectService.Remove(keeper, "momentum")
	end
	momentumApplied = 0
end

local function handleSprint(player: Player, wanted: any, ...: any)
	if select("#", ...) > 0 or type(wanted) ~= "boolean" then
		deps.SecurityService.Report(player, "InvalidPayload", "SprintRequest")
		return
	end
	local entry = stamina[player]
	if entry then
		entry.model:setWanted(wanted)
	end
end

function HuntService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		stamina[player] = nil
	end)
end

function HuntService.Start()
	deps.NetworkService.OnRequest(RemoteNames.SprintRequest, handleSprint)
	task.spawn(function()
		while true do
			local dt = task.wait(TICK)
			local ok, err = Safe.call(tick, dt)
			if not ok then
				warn(`[HuntService] tick failed: {err}`)
			end
		end
	end)
end

return HuntService
