--!strict
-- MatchService: the Roblox adapter around the pure MatchDirector.
--   * Supplies the director with real world facts (alive, restrained, distances, extraction zone).
--   * Drives the director on a fixed server tick using workspace:GetServerTimeNow(), so every
--     deadline sent to clients is directly comparable with the client's synchronised clock.
--   * Translates director events into spawns, status effects, world changes, rewards, and network
--     messages. Every delayed task is scoped to the match's Cleanup and re-checks the matchId.
--   * Owns the matchmaking queue remote (QueueService responsibilities live here + QueueModel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local RoleConfig = require(ReplicatedStorage.Shared.Config.RoleConfig)
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Cleanup = require(ReplicatedStorage.Shared.Modules.Cleanup)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

local MatchDirector = require(script.Parent.Parent.Core.MatchDirector)
local Validate = require(script.Parent.Parent.Core.Validate)

local MatchService = {}

local deps: { [string]: any } = {}
local director: MatchDirector.MatchDirector? = nil
local matchCleanup: Cleanup.Cleanup? = nil
local matchLoadouts: { [number]: string } = {} -- userId -> gadget id locked at match start
local spawnIndex: { [number]: number } = {}
local lastSnapshotAt = 0
local studioSolo = false

local IN_MATCH = { Intro = true, Active = true, Extraction = true }

local REASON_TEXT: { [string]: string } = {
	OutOfRange = "Hack interrupted — you moved too far from the terminal.",
	Damaged = "Hack interrupted — you were hit!",
	Died = "Hack interrupted — you were downed.",
	Restrained = "Hack interrupted — temporal snare!",
	Cancelled = "Hack cancelled.",
	Disconnected = "Hack interrupted.",
	Eliminated = "Hack interrupted — you were eliminated.",
}

local RESULT_TEXT: { [string]: string } = {
	Extracted = "The Infiltrators escaped with the Chronos tech!",
	AllEliminated = "Every Infiltrator was caught. The vault holds.",
	TimeExpired = "Time ran out. The Time-Keeper prevails.",
	ExtractionFailed = "The breach closed with no one out.",
	KeeperLeft = "The Time-Keeper abandoned the vault.",
	InfiltratorsLeft = "The Infiltrators abandoned the heist.",
	Aborted = "Match aborted — not enough players.",
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function getDirector(): MatchDirector.MatchDirector
	assert(director, "MatchService used before Init")
	return director :: MatchDirector.MatchDirector
end

local function playerById(userId: number?): Player?
	if userId == nil then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function displayName(userId: number?): string
	local player = playerById(userId)
	if player then
		return TableUtil.truncate(player.DisplayName, 20)
	end
	local d = getDirector()
	local participant = if userId then d:getParticipant(userId) else nil
	return if participant then TableUtil.truncate(participant.name, 20) else "Someone"
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and getRoot(player) ~= nil
end

-- Connected participants of the current match (any status).
function MatchService.GetParticipants(): { Player }
	local list = {}
	local session = getDirector().session
	if session then
		for _, userId in session.order do
			local player = playerById(userId)
			if player and session.participants[userId].connected then
				table.insert(list, player)
			end
		end
	end
	return list
end

function MatchService.GetActiveInfiltrators(): { Player }
	local list = {}
	local session = getDirector().session
	if session then
		for _, userId in session.order do
			local p = session.participants[userId]
			if p.role == "Infiltrator" and p.status == "Active" and p.connected then
				local player = playerById(userId)
				if player then
					table.insert(list, player)
				end
			end
		end
	end
	return list
end

function MatchService.GetKeeper(): Player?
	local session = getDirector().session
	return if session then playerById(session.keeperUserId) else nil
end

function MatchService.GetPhase(): string
	return getDirector():getPhase()
end

function MatchService.CurrentMatchId(): string?
	local session = getDirector().session
	return if session then session.matchId else nil
end

function MatchService.IsCurrentMatch(matchId: string?): boolean
	return getDirector():isCurrentMatch(matchId)
end

function MatchService.GetRole(player: Player): string?
	return getDirector():getRole(player.UserId)
end

function MatchService.IsActiveParticipant(player: Player): boolean
	return getDirector():isActiveParticipant(player.UserId)
end

function MatchService.GetMatchGadget(player: Player): string?
	return matchLoadouts[player.UserId]
end

function MatchService.IsInMatch(player: Player): boolean
	local d = getDirector()
	local p = d:getParticipant(player.UserId)
	return p ~= nil and p.connected and IN_MATCH[d:getPhase()] == true
end

-- Decides where (and as what role) a freshly spawned character should be placed.
function MatchService.ResolveSpawn(player: Player): { cframe: CFrame, role: string? }
	local d = getDirector()
	local p = d:getParticipant(player.UserId)
	if p and p.connected and p.status == "Active" and IN_MATCH[d:getPhase()] then
		if p.role == "TimeKeeper" then
			return { cframe = deps.WorldService.GetKeeperSpawnCFrame(), role = p.role }
		end
		return {
			cframe = deps.WorldService.GetInfiltratorSpawnCFrame(spawnIndex[player.UserId] or 1),
			role = p.role,
		}
	end
	return { cframe = deps.WorldService.GetLobbySpawnCFrame(), role = nil }
end

---------------------------------------------------------------------------
-- Broadcasting
---------------------------------------------------------------------------

function MatchService.BroadcastSnapshot()
	lastSnapshotAt = os.clock()
	deps.NetworkService.FireAll(RemoteNames.MatchState, getDirector():snapshot())
end

local function queueStateFor(player: Player): { [string]: any }
	local d = getDirector()
	local list = d.queue:list()
	local position = table.find(list, player.UserId)
	local minPlayers = d:snapshot().minPlayers
	return {
		queued = position ~= nil,
		position = position,
		count = #list,
		needed = math.max(0, minPlayers - #list),
		minPlayers = minPlayers,
		maxPlayers = GameConfig.MaxPlayers,
		inMatch = MatchService.IsInMatch(player),
	}
end

function MatchService.BroadcastQueue()
	for _, player in Players:GetPlayers() do
		deps.NetworkService.FireClient(RemoteNames.QueueState, player, queueStateFor(player))
	end
end

local function sendRoleAssignment(player: Player)
	local d = getDirector()
	local session = d.session
	local p = d:getParticipant(player.UserId)
	if not session or not p then
		return
	end
	local role = RoleConfig.get(p.role)
	local abilities: { string } = {}
	if p.role == "TimeKeeper" then
		abilities = table.clone(AbilityConfig.KeeperAbilityOrder :: any)
	else
		local gadget = matchLoadouts[player.UserId]
		if gadget then
			abilities = { gadget }
		end
	end
	deps.NetworkService.FireClient(RemoteNames.RoleAssigned, player, {
		matchId = session.matchId,
		role = p.role,
		displayName = if role then role.DisplayName else p.role,
		tagline = if role then role.Tagline else "",
		description = if role then role.Description else "",
		abilities = abilities,
		keeperName = displayName(session.keeperUserId),
		hasKeeper = session.keeperUserId ~= nil,
	})
end

---------------------------------------------------------------------------
-- Director event handling
---------------------------------------------------------------------------

local function participantsAndAll(): { Player }
	-- Announcements go to everyone so lobby players can follow the match too.
	return Players:GetPlayers()
end

local function onMatchStarted(payload: any)
	if matchCleanup then
		matchCleanup:Destroy()
	end
	matchCleanup = Cleanup.new()
	table.clear(matchLoadouts)
	table.clear(spawnIndex)
	local infiltratorIndex = 0
	for _, userId in payload.order do
		local player = playerById(userId)
		if player then
			local role = payload.roles[userId]
			if role == "Infiltrator" then
				infiltratorIndex += 1
				spawnIndex[userId] = infiltratorIndex
				matchLoadouts[userId] = deps.InventoryService.GetEquipped(player, "Gadget") or "Stabilizer"
			end
			deps.StatusEffectService.ClearAll(player)
			deps.StatusEffectService.Apply(player, {
				key = "intro",
				kind = "Root",
				magnitude = 1,
				duration = GameConfig.IntroDuration + 1,
				source = "Intro",
			})
			sendRoleAssignment(player)
			deps.CharacterService.Respawn(player)
		end
	end
	deps.AbilityService.BeginMatch(payload.matchId)
	MatchService.BroadcastQueue()
end

local function onMatchActive(payload: any)
	local d = getDirector()
	local session = d.session
	if not session or session.matchId ~= payload.matchId then
		return
	end
	for _, player in MatchService.GetParticipants() do
		deps.StatusEffectService.Remove(player, "intro")
		local role = d:getRole(player.UserId)
		if role == "TimeKeeper" then
			deps.StatusEffectService.Apply(player, {
				key = "keeperRelease",
				kind = "Root",
				magnitude = 1,
				duration = GameConfig.KeeperReleaseDelay,
				source = "KeeperRelease",
			})
			deps.NetworkService.Notify(
				{ player },
				Protocol.NotifyKinds.Announcement,
				`The vault seals behind you. You are released in {GameConfig.KeeperReleaseDelay}s.`,
				"Temporal",
				4
			)
		else
			deps.StatusEffectService.Apply(player, {
				key = "spawnProtection",
				kind = "Invulnerable",
				magnitude = 1,
				duration = GameConfig.InfiltratorSpawnProtection,
				source = "SpawnProtection",
			})
			deps.NetworkService.Notify(
				{ player },
				Protocol.NotifyKinds.Announcement,
				`Breach the vault: hack {TerminalConfig.RequiredHacks} terminals.`,
				"Stable",
				4
			)
		end
	end
	deps.AbilityService.SendAllStates()
end

local function onTerminalChanged(payload: any)
	local terminal = payload.terminal
	if not terminal then
		return
	end
	deps.ObjectiveService.OnTerminalChanged(terminal)
	deps.NetworkService.FireAll(RemoteNames.TerminalUpdate, {
		matchId = payload.matchId,
		terminal = terminal,
		reason = payload.reason,
	})
end

local function onTerminalProgress(payload: any)
	if payload.terminal then
		deps.NetworkService.FireList(RemoteNames.TerminalUpdate, MatchService.GetParticipants(), {
			matchId = payload.matchId,
			terminal = payload.terminal,
		})
	end
end

local function onHackStarted(payload: any)
	local keeper = MatchService.GetKeeper()
	local terminal = deps.WorldService.GetTerminal(payload.terminalId)
	if keeper and terminal then
		deps.NetworkService.Notify(
			{ keeper },
			Protocol.NotifyKinds.Warning,
			`Breach detected: {terminal.name}`,
			"Temporal",
			3
		)
	end
	local hacker = playerById(payload.userId)
	if hacker then
		deps.NetworkService.Accept(hacker, "HackStart", { terminalId = payload.terminalId })
	end
end

local function onHackInterrupted(payload: any)
	local hacker = playerById(payload.userId)
	if hacker then
		deps.NetworkService.Notify(
			{ hacker },
			Protocol.NotifyKinds.Warning,
			REASON_TEXT[payload.reason] or "Hack interrupted.",
			"Danger",
			3
		)
	end
end

local function onTerminalCompleted(payload: any)
	local terminal = deps.WorldService.GetTerminal(payload.terminalId)
	local name = if terminal then terminal.name else "Terminal"
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Announcement,
		`{name} breached by {displayName(payload.userId)} — {payload.completed}/{payload.required}`,
		"Stable",
		4
	)
	if terminal then
		deps.NetworkService.FireAll(RemoteNames.Effect, {
			kind = Protocol.EffectKinds.TerminalCompleted,
			position = terminal.position,
		})
	end
end

local function onExtractionOpened(payload: any)
	deps.WorldService.SetExtractionOpen(true)
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Announcement,
		"EXTRACTION OPEN — reach the Breach Dock!",
		"Success",
		5
	)
	deps.NetworkService.FireAll(RemoteNames.Effect, {
		kind = Protocol.EffectKinds.ExtractionOpened,
		position = deps.WorldService.GetMap().extractionCenter,
		endsAt = payload.endsAt,
	})
end

local function onExtractionChannel(payload: any)
	local player = playerById(payload.userId)
	if player then
		deps.NetworkService.FireClient(RemoteNames.StatusUpdate, player, {
			kind = "Extraction",
			progress = payload.progress,
		})
	end
end

local function onPlayerExtracted(payload: any)
	local player = playerById(payload.userId)
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Announcement,
		`{displayName(payload.userId)} extracted!`,
		"Success",
		3
	)
	deps.NetworkService.FireAll(RemoteNames.Effect, {
		kind = Protocol.EffectKinds.PlayerExtracted,
		userId = payload.userId,
	})
	if player and matchCleanup then
		local matchId = payload.matchId
		matchCleanup:Add(task.delay(1.2, function()
			if MatchService.IsCurrentMatch(matchId) and player.Parent == Players then
				deps.StatusEffectService.ClearAll(player)
				deps.CharacterService.Respawn(player)
			end
		end))
	end
end

local function onPlayerEliminated(payload: any)
	local byText = if payload.byUserId then ` by {displayName(payload.byUserId)}` else ""
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Toast,
		`{displayName(payload.userId)} was eliminated{byText}.`,
		"Danger",
		3
	)
	deps.NetworkService.FireAll(RemoteNames.Effect, {
		kind = Protocol.EffectKinds.PlayerEliminated,
		userId = payload.userId,
	})
end

local function onParticipantLeft(payload: any)
	local roleText = if payload.role == "TimeKeeper" then "The Time-Keeper" else "An Infiltrator"
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Toast,
		`{roleText} disconnected.`,
		"Warning",
		3
	)
end

local function onMatchResolved(result: MatchDirector.MatchResult)
	deps.AbilityService.EndMatch(result.matchId)
	deps.CombatService.EndMatch()
	deps.WorldService.SetExtractionOpen(false)
	for userId in result.participants do
		local player = playerById(userId)
		if player then
			deps.StatusEffectService.ClearAll(player)
			-- Hold surviving characters in place during the results screen.
			if isAlive(player) and deps.WorldService.IsInsideVault((getRoot(player) :: BasePart).Position) then
				deps.StatusEffectService.Apply(player, {
					key = "results",
					kind = "Root",
					magnitude = 1,
					duration = GameConfig.ResultsDuration + GameConfig.ReturnToLobbyDuration + 1,
					source = "Results",
				})
			end
		end
	end
	deps.NetworkService.Notify(
		participantsAndAll(),
		Protocol.NotifyKinds.Announcement,
		RESULT_TEXT[result.reason] or "Match over.",
		if result.winner == "Infiltrators"
			then "Stable"
			elseif result.winner == "TimeKeeper" then "Temporal"
			else "Warning",
		5
	)
	deps.RewardService.GrantMatchRewards(result)
end

local function onReturnToLobby(payload: any)
	for _, userId in payload.userIds do
		local player = playerById(userId)
		if player then
			deps.StatusEffectService.ClearAll(player)
			local root = getRoot(player)
			if not root or deps.WorldService.IsInsideVault(root.Position) then
				deps.CharacterService.Respawn(player)
			end
		end
	end
end

local function onMatchCleanup(_payload: any)
	if matchCleanup then
		matchCleanup:Destroy()
		matchCleanup = nil
	end
	table.clear(matchLoadouts)
	table.clear(spawnIndex)
	deps.ObjectiveService.ResetVisuals()
	deps.WorldService.SetExtractionOpen(false)
	MatchService.BroadcastQueue()
end

local HANDLERS: { [string]: (any) -> () } = {
	MatchStarted = onMatchStarted,
	MatchActive = onMatchActive,
	TerminalChanged = onTerminalChanged,
	TerminalProgress = onTerminalProgress,
	HackStarted = onHackStarted,
	HackInterrupted = onHackInterrupted,
	TerminalCompleted = onTerminalCompleted,
	ExtractionOpened = onExtractionOpened,
	ExtractionChannel = onExtractionChannel,
	PlayerExtracted = onPlayerExtracted,
	PlayerEliminated = onPlayerEliminated,
	ParticipantLeft = onParticipantLeft,
	MatchResolved = onMatchResolved,
	ReturnToLobby = onReturnToLobby,
	MatchCleanup = onMatchCleanup,
}

-- Events whose handling changes publicly visible state and should push a snapshot immediately.
local SNAPSHOT_EVENTS: { [string]: boolean } = {
	PhaseChanged = true,
	MatchStarted = true,
	TerminalCompleted = true,
	PlayerExtracted = true,
	PlayerEliminated = true,
	ParticipantLeft = true,
	MatchResolved = true,
}

local function onDirectorEvent(name: string, payload: any)
	local handler = HANDLERS[name]
	if handler then
		local ok, err = Safe.call(handler, payload)
		if not ok then
			warn(`[MatchService] handler for {name} failed: {err}`)
		end
	end
	if name == "PhaseChanged" and (payload.phase == "WaitingForPlayers" or payload.phase == "Intermission") then
		MatchService.BroadcastQueue()
	end
	if SNAPSHOT_EVENTS[name] then
		MatchService.BroadcastSnapshot()
	end
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------

function MatchService.RequestHack(player: Player, terminalId: string): (boolean, string)
	return getDirector():requestHackStart(player.UserId, terminalId, now())
end

function MatchService.CancelHack(player: Player, reason: string): boolean
	return getDirector():cancelHack(player.UserId, reason, now())
end

function MatchService.NotifyDamage(player: Player)
	getDirector():notifyDamage(player.UserId, now())
end

function MatchService.OnCharacterDied(player: Player)
	local d = getDirector()
	local p = d:getParticipant(player.UserId)
	if not p or p.role ~= "Infiltrator" or p.status ~= "Active" then
		return
	end
	local by = deps.CombatService.GetAttribution(player)
	d:eliminate(player.UserId, by, now())
end

local function handleQueueRequest(player: Player, action: any, ...: any)
	if select("#", ...) > 0 or not Validate.isOneOf(action, Protocol.QueueActions) then
		deps.SecurityService.Report(player, "InvalidPayload", "QueueRequest")
		deps.NetworkService.Reject(player, "Queue", Protocol.Codes.InvalidPayload)
		return
	end
	local d = getDirector()
	if action == Protocol.QueueActions.Join then
		if MatchService.IsInMatch(player) then
			deps.NetworkService.Reject(player, "Queue", Protocol.Codes.InMatch)
			return
		end
		if not isAlive(player) then
			deps.NetworkService.Reject(player, "Queue", Protocol.Codes.NotAlive)
			return
		end
		local ok, code = d.queue:join(player.UserId)
		if not ok then
			deps.NetworkService.Reject(player, "Queue", code)
			return
		end
		deps.NetworkService.Accept(player, "Queue", { queued = true })
	else
		local ok, code = d.queue:leave(player.UserId)
		if not ok then
			deps.NetworkService.Reject(player, "Queue", code)
			return
		end
		deps.NetworkService.Accept(player, "Queue", { queued = false })
	end
	MatchService.BroadcastQueue()
	MatchService.BroadcastSnapshot()
end

local function handleClientReady(player: Player, ...: any)
	if select("#", ...) > 0 then
		deps.SecurityService.Report(player, "InvalidPayload", "ClientReady")
		return
	end
	deps.NetworkService.FireClient(RemoteNames.MatchState, player, getDirector():snapshot())
	deps.NetworkService.FireClient(RemoteNames.QueueState, player, queueStateFor(player))
	deps.PlayerDataService.SendSnapshot(player)
	if MatchService.IsInMatch(player) then
		sendRoleAssignment(player)
		deps.AbilityService.SendStates(player)
	end
	deps.StatusEffectService.Reapply(player)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function MatchService.Init(injected: { [string]: any })
	deps = injected
	studioSolo = RunService:IsStudio() and GameConfig.Studio.AllowSoloMatch
	local rng = Random.new()
	director = MatchDirector.new({
		config = {
			minPlayers = GameConfig.MinPlayers,
			maxPlayers = GameConfig.MaxPlayers,
			intermissionDuration = GameConfig.IntermissionDuration,
			soloIntermissionDuration = GameConfig.Studio.SoloIntermissionDuration,
			introDuration = GameConfig.IntroDuration,
			matchDuration = GameConfig.MatchDuration,
			extractionWindow = GameConfig.ExtractionWindow,
			extractionChannelTime = GameConfig.ExtractionChannelTime,
			resultsDuration = GameConfig.ResultsDuration,
			returnToLobbyDuration = GameConfig.ReturnToLobbyDuration,
			requiredHacks = TerminalConfig.RequiredHacks,
			hackDuration = TerminalConfig.HackDuration,
			maxInteractionDistance = TerminalConfig.MaxInteractionDistance,
			interruptLockout = TerminalConfig.InterruptLockout,
			retainProgressOnInterrupt = TerminalConfig.RetainProgressOnInterrupt,
			progressBroadcastInterval = TerminalConfig.ProgressBroadcastInterval,
			allowKeeperless = studioSolo,
		},
		terminals = deps.WorldService.GetTerminalSpecs(),
		now = now(),
		newMatchId = function()
			return game:GetService("HttpService"):GenerateGUID(false)
		end,
		randomIndex = function(n: number)
			return rng:NextInteger(1, n)
		end,
		world = {
			isEligibleForMatch = function(userId: number)
				local player = playerById(userId)
				return player ~= nil and player.Parent == Players
			end,
			isAlive = function(userId: number)
				local player = playerById(userId)
				return player ~= nil and isAlive(player)
			end,
			isRestrained = function(userId: number)
				local player = playerById(userId)
				return player ~= nil and deps.StatusEffectService.IsRestrained(player)
			end,
			distanceToTerminal = function(userId: number, terminalId: string): number?
				local player = playerById(userId)
				local terminal = deps.WorldService.GetTerminal(terminalId)
				local root = if player then getRoot(player) else nil
				if not root or not terminal then
					return nil
				end
				return (root.Position - terminal.position).Magnitude
			end,
			isInExtractionZone = function(userId: number)
				local player = playerById(userId)
				local root = if player then getRoot(player) else nil
				return root ~= nil and deps.WorldService.IsInsideExtraction(root.Position)
			end,
			getName = function(userId: number)
				local player = playerById(userId)
				return if player then player.DisplayName else tostring(userId)
			end,
		},
	})
	if studioSolo then
		print("[MatchService] Studio solo matches enabled (a single queued player can start a keeperless match).")
	end
end

function MatchService.GetDirector(): MatchDirector.MatchDirector
	return getDirector()
end

function MatchService.Start()
	local d = getDirector()
	d.events:Connect(onDirectorEvent)

	deps.NetworkService.OnRequest(RemoteNames.QueueRequest, handleQueueRequest)
	deps.NetworkService.OnRequest(RemoteNames.ClientReady, handleClientReady)

	Players.PlayerRemoving:Connect(function(player)
		d:playerRemoving(player.UserId, now())
		matchLoadouts[player.UserId] = nil
		MatchService.BroadcastQueue()
		MatchService.BroadcastSnapshot()
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.DirectorTickInterval)
			-- Studio solo matches only when the player is genuinely alone, so multi-client Studio
			-- tests still get a real Time-Keeper.
			d.config.allowKeeperless = studioSolo and #Players:GetPlayers() == 1
			local ok, err = Safe.call(function()
				d:tick(now())
			end)
			if not ok then
				warn(`[MatchService] director tick failed: {err}`)
			end
			if os.clock() - lastSnapshotAt >= GameConfig.SnapshotInterval then
				MatchService.BroadcastSnapshot()
			end
		end
	end)
end

return MatchService
