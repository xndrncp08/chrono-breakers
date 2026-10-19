--!strict
-- SurvivalService: the Roblox adapter for the Survival Protocol rules owned by MatchDirector.
--   * Answers the director's world queries (distances, pod choice, camping, rift site, class speeds).
--   * Turns director events into world effects: integrity visuals and movement, Stasis Pod holds and
--     releases, Keeper channel slows, Gate Relays, the Slip Rift, shockwaves and calibration routing.
--   * Owns the survival ProximityPrompts (characters, pods, relays, rift, terminal Overload). Prompt
--     triggers are only requests; MatchDirector validates role, condition, range and phase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

local SurvivalService = {}

local deps: { [string]: any } = {}
local podOf: { [number]: string } = {} -- captive userId -> podId
local characterPrompts: { [Player]: { [string]: ProximityPrompt } } = {}

local integrity = SurvivalConfig.Integrity
local containment = SurvivalConfig.Containment

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function director(): any
	return deps.MatchService.GetDirector()
end

local function playerById(userId: number?): Player?
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function rootOf(player: Player?): BasePart?
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nameOf(userId: number?): string
	local player = playerById(userId)
	return if player then TableUtil.truncate(player.DisplayName, 20) else "An Infiltrator"
end

local function infiltrators(): { Player }
	local list = {}
	for _, player in deps.MatchService.GetParticipants() do
		if deps.MatchService.GetRole(player) == "Infiltrator" then
			table.insert(list, player)
		end
	end
	return list
end

local function horizontal(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

---------------------------------------------------------------------------
-- World queries for MatchDirector
---------------------------------------------------------------------------

function SurvivalService.DistanceTo(userId: number, kind: string, id: any): number?
	local root = rootOf(playerById(userId))
	if not root then
		return nil
	end
	local point: Vector3? = nil
	if kind == "Player" then
		local other = rootOf(playerById(id))
		point = if other then other.Position else nil
	elseif kind == "Pod" then
		local pod = if type(id) == "string" then deps.WorldService.GetPod(id) else nil
		point = if pod then pod.exitCFrame.Position else nil
	elseif kind == "Terminal" then
		local terminal = if type(id) == "string" then deps.WorldService.GetTerminal(id) else nil
		point = if terminal then terminal.position else nil
	elseif kind == "Relay" then
		local relay = if type(id) == "string" then deps.WorldService.GetRelay(id) else nil
		point = if relay then relay.position else nil
	elseif kind == "Rift" then
		point = if type(id) == "string" then deps.WorldService.GetRiftSitePosition(id) else nil
	end
	if point == nil then
		return nil
	end
	-- Generous vertical tolerance (crawling, pods) but strict horizontal range.
	if math.abs(root.Position.Y - (point :: Vector3).Y) > 8 then
		return nil
	end
	return horizontal(root.Position, point :: Vector3)
end

function SurvivalService.ChoosePod(userId: number, occupied: { [string]: boolean }): string?
	local root = rootOf(playerById(userId))
	local best, bestDistance = nil, math.huge
	for id, pod in deps.WorldService.GetPods() do
		if not occupied[id] then
			local d = if root then horizontal(root.Position, pod.position) else 0
			if d < bestDistance then
				best, bestDistance = id, d
			end
		end
	end
	return best
end

function SurvivalService.IsKeeperNear(podId: string): boolean
	local pod = deps.WorldService.GetPod(podId)
	local keeper = rootOf(deps.MatchService.GetKeeper())
	return pod ~= nil and keeper ~= nil and horizontal(keeper.Position, pod.position) <= containment.CampRadius
end

-- Helper speed for pooled actions: class passive x perk modifier.
function SurvivalService.ActionSpeed(userId: number, kind: string): number
	local player = playerById(userId)
	local class = if player then ClassConfig.get(deps.MatchService.GetMatchClass(player)) else nil
	local base = if not class then 1 elseif kind == "Relay" then class.HackSpeed else class.HealSpeed
	return base * deps.PerkService.ValueFor(userId, kind)
end

-- The rift opens at the anomaly site farthest from the Keeper.
function SurvivalService.RiftSite(): string?
	local keeper = rootOf(deps.MatchService.GetKeeper())
	local best, bestDistance = nil, -1
	for _, site in deps.WorldService.GetRiftSites() do
		local position = deps.WorldService.GetRiftSitePosition(site) :: Vector3
		local d = if keeper then horizontal(keeper.Position, position) else 0
		if d > bestDistance then
			best, bestDistance = site, d
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Presentation helpers
---------------------------------------------------------------------------

local function mirrorHealth(player: Player, condition: string?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local fraction = if condition == "Injured"
		then integrity.InjuredHealthFraction
		elseif condition == "Downed" or condition == "Contained" then integrity.DownedHealthFraction
		else 1
	humanoid.Health = math.max(1, humanoid.MaxHealth * fraction)
	if character then
		character:SetAttribute("Condition", condition)
	end
end

local function refreshPrompts(player: Player)
	local prompts = characterPrompts[player]
	if not prompts then
		return
	end
	local condition = director():getCondition(player.UserId)
	local live = deps.MatchService.IsActiveParticipant(player)
	prompts.Resync.Enabled = live and condition == "Downed"
	prompts.Patch.Enabled = live and condition == "Injured"
	prompts.PhaseLock.Enabled = live and condition == "Downed"
end

local function setHeld(player: Player, cframe: CFrame?)
	local root = rootOf(player)
	if not root then
		return
	end
	if cframe then
		root.Anchored = true
		(player.Character :: Model):PivotTo(cframe)
	else
		root.Anchored = false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	deps.SecurityService.ResetMovement(player)
end

local function effect(payload: { [string]: any })
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), payload)
end

local function notify(players: { Player }, text: string, severity: string, duration: number?)
	deps.NetworkService.Notify(players, Protocol.NotifyKinds.Toast, text, severity, duration or 3)
end

---------------------------------------------------------------------------
-- Director events
---------------------------------------------------------------------------

local function onCondition(payload: any)
	local player = playerById(payload.userId)
	if not player then
		return
	end
	local condition = payload.condition
	mirrorHealth(player, condition)
	refreshPrompts(player)
	local strike = SurvivalConfig.Strike
	if condition == "Downed" then
		deps.StatusEffectService.Cleanse(player, { "Haste" })
		deps.StatusEffectService.Apply(player, {
			key = "downed",
			kind = "Crawl",
			magnitude = integrity.CrawlSlow,
			duration = integrity.BleedoutTime + 30,
			source = "Desynced",
		})
		notify({ player }, "DESYNCED — crawl to cover. Allies can Re-sync you.", "Danger", 4)
		notify(infiltrators(), `{nameOf(payload.userId)} is Desynced!`, "Danger")
	elseif payload.cause == "Strike" or payload.cause == "Endured" then
		deps.StatusEffectService.Apply(player, {
			key = "surge",
			kind = "Haste",
			magnitude = strike.SurgeHaste,
			duration = strike.SurgeDuration * deps.PerkService.Value(player, "SurgeDuration"),
			source = "Surge",
		})
		if payload.cause == "Endured" then
			notify({ player }, "Endurance absorbed the hit — run!", "Warning")
		end
	elseif payload.cause == "Revive" then
		deps.StatusEffectService.Remove(player, "downed")
		notify({ player }, `Re-synced by {nameOf(payload.by)}.`, "Success")
	elseif payload.cause == "Heal" then
		notify({ player }, "Patched — integrity Stable.", "Success")
	end
	effect({ kind = "Condition", userId = payload.userId, condition = condition, cause = payload.cause })
end

local function onContained(payload: any)
	local player = playerById(payload.userId)
	local pod = deps.WorldService.GetPod(payload.podId)
	podOf[payload.userId] = payload.podId
	deps.WorldService.SetPodState(payload.podId, payload.userId, payload.stage)
	if player and pod then
		deps.StatusEffectService.Remove(player, "downed")
		deps.StatusEffectService.Apply(player, {
			key = "stasis",
			kind = "Root",
			magnitude = 1,
			duration = 600,
			source = "Stasis",
		})
		setHeld(player, pod.holdCFrame)
		mirrorHealth(player, "Contained")
		refreshPrompts(player)
	end
	local last = #containment.StageDurations
	notify(
		deps.MatchService.GetParticipants(),
		if payload.stage > last
			then `{nameOf(payload.userId)} is in final Stasis!`
			else `{nameOf(payload.userId)} is in Stasis ({payload.stage}/{last + 1}).`,
		"Temporal"
	)
	effect({ kind = "Contained", userId = payload.userId, position = if pod then pod.position else nil })
end

-- mode: "Rescue" steps the captive out of the pod; "Erase" leaves the body for the erasure effect
-- until the lobby respawn; "Reset" only frees the pod (match over, character may already be new).
local function releaseFromPod(userId: number, mode: string): Player?
	local podId = podOf[userId]
	podOf[userId] = nil
	if podId then
		deps.WorldService.SetPodState(podId, nil, nil)
	end
	local player = playerById(userId)
	if not player or not podId then
		return player
	end
	deps.StatusEffectService.Remove(player, "stasis")
	if mode == "Rescue" then
		local pod = deps.WorldService.GetPod(podId)
		setHeld(player, nil)
		if pod and player.Character then
			(player.Character :: Model):PivotTo(pod.exitCFrame)
			deps.SecurityService.ResetMovement(player)
		end
	elseif mode == "Reset" then
		setHeld(player, nil)
	end
	return player
end

local function onRescued(payload: any)
	local player = releaseFromPod(payload.userId, "Rescue")
	if player then
		deps.StatusEffectService.Apply(player, {
			key = "rescued",
			kind = "Haste",
			magnitude = containment.RescueHaste,
			duration = containment.RescueHasteDuration,
			source = "Rescue",
		})
		mirrorHealth(player, "Injured")
		refreshPrompts(player)
	end
	local keeper = deps.MatchService.GetKeeper()
	local rescuer = playerById(payload.by)
	if keeper and rescuer and deps.PerkService.Has(keeper, "RevealRescuer") then
		deps.NetworkService.FireClient(
			RemoteNames.Effect,
			keeper,
			{ kind = "Tracking", userId = rescuer.UserId, duration = 4 }
		)
	end
	local text = if payload.cause == "Feedback"
		then `Temporal feedback freed {nameOf(payload.userId)}!`
		else `{nameOf(payload.by)} rescued {nameOf(payload.userId)}!`
	notify(deps.MatchService.GetParticipants(), text, "Success")
	effect({ kind = "Rescued", userId = payload.userId })
end

local function onEliminated(payload: any)
	releaseFromPod(payload.userId, "Erase")
	local player = playerById(payload.userId)
	if player then
		refreshPrompts(player)
		deps.StatusEffectService.ClearAll(player)
	end
end

local function onActionStarted(payload: any)
	local player = playerById(payload.userId)
	if not player then
		return
	end
	if payload.kind == "Contain" or payload.kind == "Overload" or payload.kind == "Rift" then
		if deps.MatchService.GetRole(player) == "TimeKeeper" then
			deps.StatusEffectService.Apply(player, {
				key = "channel",
				kind = "Slow",
				magnitude = 0.9,
				duration = (payload.duration or 2) + 0.5,
				source = "Channel",
			})
		end
	end
	if payload.kind == "Contain" then
		local victim = playerById(payload.target)
		if victim then
			notify({ victim }, "The Time-Keeper is Phase-Locking you!", "Danger", 2)
		end
	end
	deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
		kind = "Action",
		matchId = payload.matchId,
		action = payload.kind,
		target = payload.target,
		startedAt = now(),
		duration = payload.duration,
		active = true,
	})
	effect({ kind = "ActionStarted", userId = payload.userId, action = payload.kind, target = payload.target })
end

local function onActionEnded(payload: any)
	local player = playerById(payload.userId)
	if not player then
		return
	end
	deps.StatusEffectService.Remove(player, "channel")
	deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
		kind = "Action",
		matchId = payload.matchId,
		action = payload.kind,
		active = false,
		completed = payload.completed,
		reason = payload.reason,
	})
end

local function onGateOpened(_payload: any)
	deps.WorldService.SetExtractionOpen(true)
	for id in deps.WorldService.GetRelays() do
		deps.WorldService.SetRelayState(id, 1, false)
	end
	deps.NetworkService.Notify(
		Players:GetPlayers(),
		Protocol.NotifyKinds.Announcement,
		"BREACH GATE OPEN — reach the extraction pad!",
		"Success",
		4
	)
end

local function bindRift(handle: any)
	if not handle then
		return
	end
	handle.escape.Triggered:Connect(function(player: Player)
		SurvivalService.Request(player, "Rift", handle.site)
	end)
	handle.seal.Triggered:Connect(function(player: Player)
		SurvivalService.Request(player, "Rift", handle.site)
	end)
end

local function onRiftOpened(payload: any)
	bindRift(deps.WorldService.SetRift(payload.site))
	local last = infiltrators()
	notify(last, "A Slip Rift has opened — find it and slip through!", "Success", 5)
	local keeper = deps.MatchService.GetKeeper()
	if keeper then
		notify({ keeper }, "A Slip Rift tore open. Seal it before they escape!", "Temporal", 5)
	end
	effect({ kind = "RiftOpened", position = deps.WorldService.GetRiftSitePosition(payload.site) })
end

local function onShockwave(payload: any)
	local keeper = deps.MatchService.GetKeeper()
	if keeper then
		for _, player in deps.MatchService.GetFreeInfiltrators() do
			deps.NetworkService.FireClient(
				RemoteNames.Effect,
				keeper,
				{ kind = "Tracking", userId = player.UserId, duration = payload.duration }
			)
		end
	end
	effect({ kind = "Shockwave" })
end

local TIER_TEXT: { [string]: string } = {
	Rising = "Temporal instability rising — Stasis Pods accelerate.",
	Critical = "CRITICAL COLLAPSE — shockwaves reveal survivors!",
}

local HANDLERS: { [string]: (any) -> () } = {
	ConditionChanged = onCondition,
	PlayerContained = onContained,
	PlayerRescued = onRescued,
	PlayerEliminated = onEliminated,
	PlayerExtracted = function(payload: any)
		releaseFromPod(payload.userId, "Reset")
	end,
	ActionStarted = onActionStarted,
	ActionEnded = onActionEnded,
	GateOpened = onGateOpened,
	RiftOpened = onRiftOpened,
	RiftClosed = function(_: any)
		deps.WorldService.SetRift(nil)
	end,
	RiftSealed = function(_: any)
		deps.WorldService.SetRift(nil)
		notify(deps.MatchService.GetParticipants(), "The Slip Rift was sealed — the Collapse begins!", "Temporal", 4)
	end,
	Shockwave = onShockwave,
	CollapseTier = function(payload: any)
		local text = TIER_TEXT[payload.tier]
		if text then
			deps.NetworkService.Notify(Players:GetPlayers(), Protocol.NotifyKinds.Warning, text, "Temporal", 4)
		end
	end,
	ExtractionOpened = function(_: any)
		for id in deps.WorldService.GetRelays() do
			deps.WorldService.SetRelayState(id, 0, true)
		end
	end,
	CalibrationIssued = function(payload: any)
		local player = playerById(payload.userId)
		if player then
			deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
				kind = "Calibration",
				matchId = payload.matchId,
				terminalId = payload.terminalId,
				challenge = payload.challenge,
			})
		end
	end,
	CalibrationResult = function(payload: any)
		local player = playerById(payload.userId)
		if player then
			deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
				kind = "CalibrationResult",
				matchId = payload.matchId,
				terminalId = payload.terminalId,
				grade = payload.grade,
			})
		end
		if payload.grade == "Miss" then
			local terminal = deps.WorldService.GetTerminal(payload.terminalId)
			effect({ kind = "CalibrationMiss", position = if terminal then terminal.position else nil })
		end
	end,
	TerminalOverloaded = function(payload: any)
		local terminal = deps.WorldService.GetTerminal(payload.terminalId)
		effect({ kind = "Overloaded", position = if terminal then terminal.position else nil })
	end,
	MatchResolved = function(_: any)
		for userId in table.clone(podOf) do
			releaseFromPod(userId, "Reset")
		end
		deps.WorldService.SetRift(nil)
	end,
}

---------------------------------------------------------------------------
-- Requests (prompt triggers)
---------------------------------------------------------------------------

-- Starts the action, or stops it when the player triggers the same action again.
function SurvivalService.Request(player: Player, kind: string, target: any)
	if not deps.NetworkService.Allow(player, "SurvivalPrompt") then
		return
	end
	if not deps.SecurityService.ValidatePosition(player) then
		deps.NetworkService.Reject(player, "Survival", Protocol.Codes.OutOfRange)
		return
	end
	local d = director()
	local current = d:getAction(player.UserId)
	if current and current.kind == kind and current.target == target then
		d:stopAction(player.UserId, "Cancelled", now())
		return
	end
	if current then
		d:stopAction(player.UserId, "Switched", now())
	end
	local ok, code = d:beginAction(player.UserId, kind, target, now())
	if not ok then
		if code == Protocol.Codes.WrongRole then
			deps.SecurityService.Report(player, "IllegalSurvivalAction", kind)
		end
		deps.NetworkService.Reject(player, "Survival", code)
	end
end

function SurvivalService.StopAction(player: Player, reason: string): boolean
	return director():stopAction(player.UserId, reason, now())
end

-- Character prompts are created once per character; MatchService.ResolveSpawn decides the role.
function SurvivalService.SetupCharacter(player: Player, character: Model, roleId: string?)
	local existing = characterPrompts[player]
	if existing then
		for _, prompt in existing do
			prompt:Destroy()
		end
		characterPrompts[player] = nil
	end
	if roleId ~= "Infiltrator" then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SurvivalPrompts"
	attachment.Parent = root
	local function make(name: string, action: string, range: number, kind: string): ProximityPrompt
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = 0
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = range
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Enabled = false
		prompt:SetAttribute("SurvivalKind", kind)
		prompt:SetAttribute("TargetUserId", player.UserId)
		prompt.Parent = attachment
		prompt.Triggered:Connect(function(by: Player)
			if by ~= player then
				SurvivalService.Request(by, kind, player.UserId)
			end
		end)
		return prompt
	end
	characterPrompts[player] = {
		Resync = make("ResyncPrompt", "Re-sync", integrity.HelperRange - 0.5, "Revive"),
		Patch = make("PatchPrompt", "Patch", integrity.HelperRange - 0.5, "Heal"),
		PhaseLock = make("PhaseLockPrompt", "Phase-Lock", containment.ContainRange - 0.5, "Contain"),
	}
	mirrorHealth(player, director():getCondition(player.UserId))
	refreshPrompts(player)
end

-- Binds pod/relay/terminal Overload prompts for the freshly built world.
function SurvivalService.BindWorld()
	for id, pod in deps.WorldService.GetPods() do
		pod.prompt.Triggered:Connect(function(player: Player)
			local occupant = pod.model:GetAttribute("Occupant")
			if type(occupant) == "number" then
				SurvivalService.Request(player, "Rescue", occupant)
			end
		end)
		deps.WorldService.SetPodState(id, nil, nil)
	end
	for id, relay in deps.WorldService.GetRelays() do
		relay.prompt.Triggered:Connect(function(player: Player)
			SurvivalService.Request(player, "Relay", id)
		end)
		deps.WorldService.SetRelayState(id, 0, false)
	end
	for _, terminal in deps.WorldService.GetTerminals() do
		local terminalId = terminal.id
		local prompt = terminal.overloadPrompt
		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				SurvivalService.Request(player, "Overload", terminalId)
			end)
		end
	end
end

function SurvivalService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		characterPrompts[player] = nil
		local podId = podOf[player.UserId]
		if podId then
			podOf[player.UserId] = nil
			deps.WorldService.SetPodState(podId, nil, nil)
		end
	end)
end

function SurvivalService.Start()
	SurvivalService.BindWorld()
	director().events:Connect(function(name: string, payload: any)
		local handler = HANDLERS[name]
		if handler then
			local ok, err = Safe.call(handler, payload)
			if not ok then
				warn(`[SurvivalService] {name} failed: {err}`)
			end
		end
	end)
	-- Relay screens follow pooled power while the Collapse runs (cheap: two relays at 2 Hz).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local session = director().session
			if session and session.endgame.startedAt and not session.endgame.gateOpen then
				for id, power in session.endgame.relays do
					deps.WorldService.SetRelayState(id, power, true)
				end
			end
		end
	end)
end

return SurvivalService
