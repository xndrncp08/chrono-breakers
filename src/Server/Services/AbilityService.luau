--!strict
-- AbilityService: validates and executes every Time-Keeper ability and Infiltrator gadget.
--
-- Pipeline for AbilityRequest(abilityId, target?, aim?, matchId):
--   1. NetworkService rate limit (per player).
--   2. Payload shape: argument count, string id, finite Vector3 target, non-degenerate aim.
--   3. AbilityRules.checkCaster: known id, phase, participant, role, equipped gadget, alive,
--      not restrained, server cooldown.
--   4. Ability-specific validation (placement rules with server raycasts, range, LOS, limits).
--   5. Execute, then start the cooldown (failed casts never consume a cooldown).
-- Zones/traps are ticked from one bounded loop and destroyed at match end.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local AbilityRules = require(script.Parent.Parent.Core.AbilityRules)
local CooldownTracker = require(script.Parent.Parent.Core.CooldownTracker)
local FreezeZone = require(script.Parent.Parent.Components.FreezeZone)
local PlacementRules = require(script.Parent.Parent.Core.PlacementRules)
local ServerConfig = require(script.Parent.Parent.ServerConfig)
local TemporalTrap = require(script.Parent.Parent.Components.TemporalTrap)
local Validate = require(script.Parent.Parent.Core.Validate)

local AbilityService = {}

local deps: { [string]: any } = {}
local cooldowns = CooldownTracker.new()
local zones: { FreezeZone.FreezeZone } = {}
local traps: { TemporalTrap.TemporalTrap } = {}
local currentMatchId: string? = nil

local pendingScans: { { player: Player, at: number, matchId: string } } = {}
local RUNTIME_TICK = 0.1
local TRAP_MIN_DISTANCE_FROM_SPAWN = 18

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function cooldownKey(player: Player, abilityId: string): string
	return `{player.UserId}:{abilityId}`
end

local function nearestLandmark(position: Vector3): string
	local best, bestDistance = "the vault", math.huge
	for _, landmark in deps.WorldService.GetMap().landmarks do
		local d = PlacementRules.horizontalDistance(position, landmark.position)
		if d < bestDistance then
			best, bestDistance = landmark.name, d
		end
	end
	return best
end

local function abilityIdsFor(player: Player): { string }
	local role = deps.MatchService.GetRole(player)
	if role == "TimeKeeper" then
		return table.clone(AbilityConfig.KeeperAbilityOrder :: any)
	elseif role == "Infiltrator" then
		local gadget = deps.MatchService.GetMatchGadget(player)
		local ids = if gadget then { gadget } else {}
		local skill = deps.MatchService.GetClassAbility(player)
		if skill then
			table.insert(ids, skill)
		end
		return ids
	end
	return {}
end

local function activeCount(abilityId: string): number
	if abilityId == "TimeFreeze" then
		return #zones
	elseif abilityId == "TemporalTrap" then
		return #traps
	end
	return 0
end

function AbilityService.SendStates(player: Player)
	local states = {}
	for _, abilityId in abilityIdsFor(player) do
		local definition = AbilityConfig.get(abilityId)
		if definition then
			table.insert(states, {
				abilityId = abilityId,
				readyAt = cooldowns:readyAt(cooldownKey(player, abilityId)),
				cooldown = definition.Cooldown,
				active = activeCount(abilityId),
				maxActive = definition.MaxActive,
			})
		end
	end
	deps.NetworkService.FireClient(RemoteNames.AbilityState, player, {
		matchId = currentMatchId,
		abilities = states,
	})
end

function AbilityService.SendAllStates()
	for _, player in deps.MatchService.GetParticipants() do
		AbilityService.SendStates(player)
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function validatePlacement(player: Player, target: any, maxRange: number): (boolean, string, Vector3?)
	local root = getRoot(player)
	if not root then
		return false, Protocol.Codes.NotAlive, nil
	end
	local map = deps.WorldService.GetMap()
	return PlacementRules.validateGroundTarget({
		casterPosition = root.Position,
		eyePosition = root.Position + Vector3.new(0, ServerConfig.Combat.EyeHeight, 0),
		target = target,
		maxRange = maxRange,
		boundsMin = map.boundsMin,
		boundsMax = map.boundsMax,
		castDown = deps.WorldService.CastDown,
		lineOfSight = deps.WorldService.HasLineOfSight,
	})
end

local function castTimeFreeze(player: Player, target: any): (boolean, string)
	local definition = AbilityConfig.Abilities.TimeFreeze
	if #zones >= definition.MaxActive then
		return false, Protocol.Codes.LimitReached
	end
	local ok, code, ground = validatePlacement(player, target, definition.MaxCastRange)
	if not ok or ground == nil then
		deps.SecurityService.Report(player, "InvalidPlacement", code)
		return false, code
	end
	local startedAt = now()
	local zone = FreezeZone.new({
		id = HttpService:GenerateGUID(false),
		center = ground,
		radius = definition.Radius,
		telegraph = definition.TelegraphDelay,
		duration = definition.Duration,
		slowMagnitude = definition.SlowMagnitude,
		membershipInterval = definition.MembershipInterval,
		linger = definition.LingerAfterExit,
		startedAt = startedAt,
		parent = deps.WorldService.GetRuntimeFolder(),
		getTargets = deps.MatchService.GetFreeInfiltrators,
		applySlow = function(victim: Player, key: string, magnitude: number, duration: number)
			deps.StatusEffectService.Apply(victim, {
				key = key,
				kind = "Slow",
				magnitude = magnitude,
				duration = duration,
				source = "TimeFreeze",
			})
		end,
		removeKeyFromAll = deps.StatusEffectService.RemoveKeyFromAll,
	})
	table.insert(zones, zone)
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.FreezeTelegraph,
		position = ground,
		radius = definition.Radius,
		activatesAt = zone.activatesAt,
		expiresAt = zone.expiresAt,
	})
	return true, Protocol.Codes.Ok
end

local function onTrapTriggered(trap: TemporalTrap.TemporalTrap, victim: Player)
	local definition = AbilityConfig.Abilities.TemporalTrap
	deps.StatusEffectService.Apply(victim, {
		key = `trap:{trap.id}:stun`,
		kind = "Stun",
		magnitude = 1,
		duration = definition.StunDuration * deps.PerkService.Value(deps.MatchService.GetKeeper(), "TrapStun"),
		source = "TemporalTrap",
	})
	deps.StatusEffectService.Apply(victim, {
		key = `trap:{trap.id}:slow`,
		kind = "Slow",
		magnitude = definition.SlowMagnitude,
		duration = definition.StunDuration + definition.SlowDuration,
		source = "TemporalTrap",
	})
	local keeper = deps.MatchService.GetKeeper()
	if keeper then
		deps.NetworkService.Notify(
			{ keeper },
			Protocol.NotifyKinds.Warning,
			`Trap sprung near {nearestLandmark(trap.position)}!`,
			"Temporal",
			3
		)
	end
	deps.NetworkService.Notify({ victim }, Protocol.NotifyKinds.Warning, "Caught in a Temporal Trap!", "Danger", 2)
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.TrapTriggered,
		position = trap.position,
		userId = victim.UserId,
		duration = definition.StunDuration + definition.SlowDuration,
	})
end

local function castTemporalTrap(player: Player, target: any): (boolean, string)
	local definition = AbilityConfig.Abilities.TemporalTrap
	if #traps >= definition.MaxActive then
		return false, Protocol.Codes.LimitReached
	end
	local ok, code, ground = validatePlacement(player, target, definition.MaxCastRange)
	if not ok or ground == nil then
		deps.SecurityService.Report(player, "InvalidPlacement", code)
		return false, code
	end
	local trapPositions = {}
	for _, existing in traps do
		table.insert(trapPositions, existing.position)
	end
	local map = deps.WorldService.GetMap()
	if
		not PlacementRules.isClearOf(ground, trapPositions, definition.MinSpacing)
		or not PlacementRules.isClearOf(
			ground,
			deps.WorldService.GetTerminalPositions(),
			definition.MinDistanceFromTerminal
		)
		or not PlacementRules.isClearOf(ground, { map.extractionCenter }, definition.MinDistanceFromExtraction)
		or not PlacementRules.isClearOf(ground, map.infiltratorSpawns, TRAP_MIN_DISTANCE_FROM_SPAWN)
	then
		return false, Protocol.Codes.TooClose
	end
	local trap = TemporalTrap.new({
		id = HttpService:GenerateGUID(false),
		position = ground,
		armingTime = definition.ArmingTime,
		triggerRadius = definition.TriggerRadius,
		lifetime = definition.Lifetime,
		placedAt = now(),
		parent = deps.WorldService.GetRuntimeFolder(),
		getTargets = deps.MatchService.GetFreeInfiltrators,
		onTriggered = onTrapTriggered,
	})
	table.insert(traps, trap)
	-- Only the Keeper is told precisely; Infiltrators must notice the faint trap themselves.
	deps.NetworkService.FireClient(RemoteNames.Effect, player, {
		kind = Protocol.EffectKinds.TrapPlaced,
		position = ground,
		radius = definition.TriggerRadius,
	})
	return true, Protocol.Codes.Ok
end

local function castGadget(player: Player, abilityId: string): (boolean, string)
	if abilityId == "Veil" or abilityId == "Overclock" or abilityId == "Slipstream" then
		if abilityId == "Veil" and deps.MatchService.GetDirector():getHackingTerminal(player.UserId) then
			return false, Protocol.Codes.Busy
		end
		local definition = AbilityConfig.get(abilityId) :: AbilityConfig.AbilityDefinition
		deps.StatusEffectService.Apply(player, {
			key = if abilityId == "Veil" then "veil" else abilityId,
			kind = if abilityId == "Veil" then "Cloaked" elseif abilityId == "Overclock" then "Overclock" else "Haste",
			magnitude = definition.HasteMagnitude or 1,
			duration = definition.Duration
				* (if abilityId == "Veil" then deps.PerkService.Value(player, "VeilDuration") else 1),
			source = abilityId,
		})
	elseif abilityId == "Mend" or abilityId == "EMP" then
		local definition = AbilityConfig.get(abilityId) :: AbilityConfig.AbilityDefinition
		local origin = getRoot(player)
		if not origin then
			return false, Protocol.Codes.NotAlive
		end
		local director = deps.MatchService.GetDirector()
		local radius = definition.Radius
			* (if abilityId == "EMP" then deps.PerkService.Value(player, "EmpRadius") else 1)
		local useful = false
		for _, ally in deps.MatchService.GetActiveInfiltrators() do
			local root = getRoot(ally)
			local humanoid = ally.Character and ally.Character:FindFirstChildOfClass("Humanoid")
			if
				root
				and humanoid
				and humanoid.Health > 0
				and (root.Position - origin.Position).Magnitude <= radius
				and deps.WorldService.HasLineOfSight(origin.Position, root.Position)
			then
				if abilityId == "Mend" then
					local healed = director:boost(ally.UserId, "Heal", definition.HealBoost, player.UserId, now())
					local revived = director:boost(ally.UserId, "Revive", definition.ReviveBoost, player.UserId, now())
					useful = useful or healed or revived
				elseif abilityId == "EMP" and director:isFree(ally.UserId) then
					deps.StatusEffectService.Cleanse(ally, { "Slow", "Stun" })
					useful = true
				end
			end
		end
		if abilityId == "EMP" then
			-- Counterplay to Phase-Lock: the pulse breaks the Keeper's channel and staggers them.
			local keeper = deps.MatchService.GetKeeper()
			local keeperRoot = if keeper then getRoot(keeper) else nil
			if
				keeper
				and keeperRoot
				and (keeperRoot.Position - origin.Position).Magnitude <= radius
				and deps.WorldService.HasLineOfSight(origin.Position, keeperRoot.Position)
			then
				local action = director:getAction(keeper.UserId)
				if action and action.kind == "Contain" then
					director:stopAction(keeper.UserId, "Disrupted", now())
					deps.StatusEffectService.Apply(keeper, {
						key = "disrupted",
						kind = "Slow",
						magnitude = definition.KeeperSlow,
						duration = definition.KeeperSlowDuration,
						source = "EMP",
					})
					deps.NetworkService.Notify(
						{ keeper },
						Protocol.NotifyKinds.Warning,
						"Phase-Lock disrupted!",
						"Danger",
						2
					)
					useful = true
				end
			end
		end
		if abilityId == "EMP" then
			for i = #traps, 1, -1 do
				local trap = traps[i]
				if
					(trap.position - origin.Position).Magnitude <= radius
					and deps.WorldService.HasLineOfSight(origin.Position, trap.position + Vector3.new(0, 1, 0))
				then
					trap:destroy()
					table.remove(traps, i)
					useful = true
				end
			end
			local keeper = deps.MatchService.GetKeeper()
			if keeper then
				AbilityService.SendStates(keeper)
			end
		end
		if not useful then
			return false, Protocol.Codes.NoTarget
		end
	elseif abilityId == "Stabilizer" then
		local definition = AbilityConfig.Abilities.Stabilizer
		deps.StatusEffectService.Cleanse(player, { "Slow", "Stun" })
		deps.StatusEffectService.Apply(player, {
			key = "stabilizer",
			kind = "SlowImmunity",
			magnitude = 1,
			duration = definition.ImmunityDuration,
			source = "Stabilizer",
		})
	elseif abilityId == "PhaseDash" then
		local definition = AbilityConfig.Abilities.PhaseDash
		deps.StatusEffectService.Apply(player, {
			key = "phaseDash",
			kind = "Haste",
			magnitude = definition.HasteMagnitude,
			duration = definition.Duration,
			source = "PhaseDash",
		})
	elseif abilityId == "EchoScanner" then
		local definition = AbilityConfig.Abilities.EchoScanner
		local keeper = deps.MatchService.GetKeeper()
		local trapPositions = {}
		for _, trap in traps do
			if trap.state == "Armed" or trap.state == "Arming" then
				table.insert(trapPositions, trap.position)
			end
		end
		local recipients = deps.MatchService.GetActiveInfiltrators()
		deps.NetworkService.FireList(RemoteNames.Effect, recipients, {
			kind = Protocol.EffectKinds.Reveal,
			keeperUserId = if keeper then keeper.UserId else nil,
			traps = trapPositions,
			duration = definition.RevealDuration,
		})
		if keeper then
			deps.StatusEffectService.Apply(keeper, {
				key = "echoReveal",
				kind = "Revealed",
				magnitude = 1,
				duration = definition.RevealDuration,
				source = "EchoScanner",
			})
			deps.NetworkService.Notify({ keeper }, Protocol.NotifyKinds.Warning, "You've been scanned!", "Warning", 2)
		end
	else
		return false, Protocol.Codes.InvalidPayload
	end
	local root = getRoot(player)
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), {
		kind = Protocol.EffectKinds.GadgetUsed,
		abilityId = abilityId,
		userId = player.UserId,
		position = if root then root.Position else nil,
	})
	return true, Protocol.Codes.Ok
end

local function handleAbilityRequest(player: Player, abilityId: any, target: any, aim: any, matchId: any, ...: any)
	if select("#", ...) > 0 or not Validate.isShortString(abilityId, 32) or not Validate.isShortString(matchId, 64) then
		deps.SecurityService.Report(player, "InvalidPayload", "AbilityRequest")
		deps.NetworkService.Reject(player, "Ability", Protocol.Codes.InvalidPayload)
		return
	end
	if target ~= nil and not Validate.isFiniteVector3(target) then
		deps.SecurityService.Report(player, "InvalidPayload", "AbilityTarget")
		deps.NetworkService.Reject(player, "Ability", Protocol.Codes.InvalidPayload)
		return
	end
	if aim ~= nil and not Validate.isDirection(aim) then
		deps.SecurityService.Report(player, "InvalidPayload", "AbilityAim")
		deps.NetworkService.Reject(player, "Ability", Protocol.Codes.InvalidPayload)
		return
	end

	if not deps.SecurityService.ValidatePosition(player) then
		deps.NetworkService.Reject(player, "Ability", Protocol.Codes.OutOfRange)
		return
	end
	local matchService = deps.MatchService
	local role = matchService.GetRole(player)
	local key = cooldownKey(player, abilityId)
	local t = now()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local ok, code = AbilityRules.checkCaster({
		abilityId = abilityId,
		matchId = matchId,
		currentMatchId = matchService.CurrentMatchId(),
		phase = matchService.GetPhase(),
		role = role,
		participantActive = matchService.IsActiveParticipant(player),
		alive = humanoid ~= nil and humanoid.Health > 0,
		restrained = deps.StatusEffectService.IsRestrained(player),
		cooldownReady = cooldowns:isReady(key, t),
		equippedGadget = matchService.GetMatchGadget(player),
		classAbility = matchService.GetClassAbility(player),
		free = role ~= "Infiltrator" or matchService.GetDirector():isFree(player.UserId),
	})
	if not ok then
		if code == Protocol.Codes.WrongRole or code == Protocol.Codes.WrongPhase then
			deps.SecurityService.Report(player, "IllegalAbility", code)
		end
		deps.NetworkService.Reject(player, "Ability", code)
		return
	end

	local definition = AbilityConfig.get(abilityId) :: AbilityConfig.AbilityDefinition
	local success, resultCode
	if abilityId == "ChronoStrike" then
		local direction: Vector3
		if aim ~= nil then
			direction = (aim :: Vector3).Unit
		else
			local root = getRoot(player)
			direction = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
		end
		success, resultCode = deps.CombatService.Strike(player, direction)
	elseif abilityId == "ChronoScan" then
		local currentId = matchService.CurrentMatchId()
		if currentId then
			table.insert(pendingScans, { player = player, at = t + definition.TelegraphDelay, matchId = currentId })
			deps.NetworkService.Notify(
				matchService.GetActiveInfiltrators(),
				Protocol.NotifyKinds.Warning,
				"Chrono Pulse charging — break line of sight, leave 48 studs, or use Veil!",
				"Temporal",
				definition.TelegraphDelay + 1
			)
			success, resultCode = true, Protocol.Codes.Ok
		else
			success, resultCode = false, Protocol.Codes.WrongPhase
		end
	elseif abilityId == "TimeFreeze" then
		if target == nil then
			success, resultCode = false, Protocol.Codes.InvalidPayload
		else
			success, resultCode = castTimeFreeze(player, target)
		end
	elseif abilityId == "TemporalTrap" then
		if target == nil then
			success, resultCode = false, Protocol.Codes.InvalidPayload
		else
			success, resultCode = castTemporalTrap(player, target)
		end
	else
		success, resultCode = castGadget(player, abilityId)
	end

	if success then
		local cooldown = definition.Cooldown
			* (if abilityId == "Slipstream" then deps.PerkService.Value(player, "SlipstreamCooldown") else 1)
		cooldowns:start(key, t, cooldown)
		deps.TelemetryService.Ability(abilityId)
		deps.NetworkService.Accept(player, "Ability", { abilityId = abilityId, result = resultCode })
	else
		deps.NetworkService.Reject(player, "Ability", resultCode)
	end
	AbilityService.SendStates(player)
end

local function runtimeTick()
	if #zones == 0 and #traps == 0 and #pendingScans == 0 then
		return
	end
	local t = now()
	local participants = deps.MatchService.GetParticipants()
	for i = #pendingScans, 1, -1 do
		local scan = pendingScans[i]
		if t >= scan.at then
			table.remove(pendingScans, i)
			local origin = getRoot(scan.player)
			if
				deps.MatchService.IsCurrentMatch(scan.matchId)
				and origin
				and deps.MatchService.IsActiveParticipant(scan.player)
			then
				for _, target in deps.MatchService.GetFreeInfiltrators() do
					local root = getRoot(target)
					if
						root
						and not deps.StatusEffectService.Has(target, "Cloaked")
						and not deps.InteractionService.IsHidden(target)
						and (root.Position - origin.Position).Magnitude <= AbilityConfig.Abilities.ChronoScan.Radius
						and deps.WorldService.HasLineOfSight(origin.Position, root.Position)
					then
						deps.NetworkService.FireClient(RemoteNames.Effect, scan.player, {
							kind = "Tracking",
							userId = target.UserId,
							duration = AbilityConfig.Abilities.ChronoScan.Duration,
						})
						deps.NetworkService.Notify(
							{ target },
							Protocol.NotifyKinds.Warning,
							"Chrono Pulse detected you!",
							"Danger",
							2
						)
					end
				end
			end
		end
	end
	for i = #zones, 1, -1 do
		local zone = zones[i]
		local wasActive = zone.state == "Active"
		if zone:update(t) then
			zone:destroy()
			table.remove(zones, i)
			deps.NetworkService.FireList(RemoteNames.Effect, participants, {
				kind = Protocol.EffectKinds.FreezeEnd,
				position = zone.center,
			})
		elseif not wasActive and zone.state == "Active" then
			deps.NetworkService.FireList(RemoteNames.Effect, participants, {
				kind = Protocol.EffectKinds.FreezeActive,
				position = zone.center,
				expiresAt = zone.expiresAt,
			})
		end
	end
	local trapsChanged = false
	for i = #traps, 1, -1 do
		local trap = traps[i]
		if trap:update(t) then
			trap:destroy()
			table.remove(traps, i)
			trapsChanged = true
		end
	end
	if trapsChanged then
		local keeper = deps.MatchService.GetKeeper()
		if keeper then
			AbilityService.SendStates(keeper)
		end
	end
end

function AbilityService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		cooldowns:clearPrefix(`{player.UserId}:`)
	end)
end

function AbilityService.Start()
	deps.NetworkService.OnRequest(RemoteNames.AbilityRequest, handleAbilityRequest)
	task.spawn(function()
		while true do
			task.wait(RUNTIME_TICK)
			local ok, err = Safe.call(runtimeTick)
			if not ok then
				warn(`[AbilityService] runtime tick failed: {err}`)
			end
		end
	end)
end

function AbilityService.BeginMatch(matchId: string)
	AbilityService.EndMatch(currentMatchId)
	currentMatchId = matchId
end

-- Destroys every zone/trap and clears cooldowns. Safe to call repeatedly.
function AbilityService.EndMatch(_matchId: string?)
	for _, zone in zones do
		zone:destroy()
	end
	table.clear(zones)
	table.clear(pendingScans)
	for _, trap in traps do
		trap:destroy()
	end
	table.clear(traps)
	cooldowns:clear()
	currentMatchId = nil
end

function AbilityService.CountRuntime(): (number, number)
	return #zones, #traps
end

return AbilityService
