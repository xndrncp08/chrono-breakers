--!strict
-- MatchDirector: the single authoritative owner of match flow, participants, roles, terminal
-- progress, extraction, and resolution. It is pure Luau (no Instance access): the Roblox-facing
-- MatchService feeds it world facts through the injected WorldQuery and turns its events into
-- world/network effects. This keeps every rule testable offline (see src/Tests).
--
-- Time is always passed in explicitly (`now`, server seconds). Each match has a unique matchId;
-- every event carries it so adapters can drop stale callbacks from a previous match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local EndgameModel = require(script.Parent.EndgameModel)
local HackChallenge = require(script.Parent.HackChallenge)
local ExtractionModel = require(script.Parent.ExtractionModel)
local MatchStateMachine = require(script.Parent.MatchStateMachine)
local ObjectiveTracker = require(script.Parent.ObjectiveTracker)
local QueueModel = require(script.Parent.QueueModel)
local RoleSelector = require(script.Parent.RoleSelector)
local SurvivalModel = require(script.Parent.SurvivalModel)
local TerminalModel = require(script.Parent.TerminalModel)

type Phase = GameTypes.Phase
type Role = GameTypes.Role
type Team = GameTypes.Team
type ParticipantStatus = GameTypes.ParticipantStatus
type ResolutionReason = GameTypes.ResolutionReason

export type WorldQuery = {
	isEligibleForMatch: (userId: number) -> boolean,
	isAlive: (userId: number) -> boolean,
	isRestrained: (userId: number) -> boolean,
	distanceToTerminal: (userId: number, terminalId: string) -> number?,
	isInExtractionZone: (userId: number) -> boolean,
	getName: (userId: number) -> string,
	hackSpeed: ((userId: number) -> number)?,
	-- Survival Protocol queries (optional so older harnesses keep working).
	-- kind: "Player" | "Pod" | "Terminal" | "Relay" | "Rift"
	distanceTo: ((userId: number, kind: string, id: any) -> number?)?,
	choosePod: ((userId: number, occupied: { [string]: boolean }) -> string?)?,
	isKeeperNear: ((podId: string) -> boolean)?,
	actionSpeed: ((userId: number, kind: string) -> number)?, -- Revive / Heal / Relay helpers
	modifier: ((userId: number?, key: string) -> number)?, -- perk modifiers (PerkConfig keys)
	canSelfHeal: ((userId: number) -> boolean)?,
	riftSite: (() -> string?)?,
	podIds: (() -> { string })?,
	relayIds: (() -> { string })?,
}

export type DirectorConfig = {
	minPlayers: number,
	maxPlayers: number,
	intermissionDuration: number,
	soloIntermissionDuration: number,
	introDuration: number,
	matchDuration: number,
	extractionWindow: number,
	extractionChannelTime: number,
	resultsDuration: number,
	returnToLobbyDuration: number,
	requiredHacks: number,
	hackDuration: number,
	maxInteractionDistance: number,
	interruptLockout: number,
	retainProgressOnInterrupt: boolean,
	progressBroadcastInterval: number,
	cooperativeHacking: boolean?,
	interactiveChallenges: boolean?,
	assistantEfficiency: number?,
	maxHackers: number?,
	squadScaling: { number }?,
	allowKeeperless: boolean, -- Studio solo testing only
}

export type TerminalSpec = { id: string, name: string }

export type Participant = {
	userId: number,
	name: string,
	role: Role,
	status: ParticipantStatus,
	connected: boolean,
	hacks: number,
	eliminations: number,
	extracted: boolean,
	lastChannelBroadcast: number,
	assists: number,
	downs: number,
	containments: number,
	rescues: number,
	revives: number,
	heals: number,
	greats: number,
}

export type Action = { kind: string, target: any, startedAt: number, progress: number, duration: number? }

export type ResultParticipant = {
	assists: number?,
	downs: number?,
	containments: number?,
	rescues: number?,
	revives: number?,
	heals: number?,
	greats: number?,
	userId: number,
	name: string,
	role: Role,
	status: ParticipantStatus,
	connected: boolean,
	hacks: number,
	eliminations: number,
	extracted: boolean,
}

export type MatchResult = {
	matchId: string,
	winner: Team?,
	reason: ResolutionReason,
	startedAt: number,
	endedAt: number,
	completedHacks: number,
	participants: { [number]: ResultParticipant },
}

export type Session = {
	matchId: string,
	startedAt: number,
	activeAt: number?,
	deadline: number?,
	keeperUserId: number?,
	participants: { [number]: Participant },
	order: { number },
	terminals: { [string]: TerminalModel.TerminalModel },
	terminalOrder: { string },
	objectives: ObjectiveTracker.ObjectiveTracker,
	extraction: ExtractionModel.ExtractionModel,
	result: MatchResult?,
	challenges: { [number]: { terminalId: string, check: HackChallenge.Challenge } },
	nextCheckAt: { [number]: number },
	challengeSequence: number,
	modes: { [string]: string },
	survival: SurvivalModel.SurvivalModel,
	actions: { [number]: Action },
	endgame: EndgameModel.EndgameModel,
	rift: { open: boolean, site: string?, openedAt: number? },
	lastTickAt: number?,
	squadSize: number,
	collapseTier: string?,
}

export type DirectorEvent = string

export type MatchDirector = {
	config: DirectorConfig,
	world: WorldQuery,
	queue: QueueModel.QueueModel,
	machine: MatchStateMachine.MatchStateMachine,
	session: Session?,
	phaseEndsAt: number?,
	roleHistory: RoleSelector.History,
	events: Signal.Signal<string, any>,
	matchesStarted: number,
	snapshotVersion: number,
	lastNow: number,

	tick: (self: MatchDirector, now: number) -> (),
	getPhase: (self: MatchDirector) -> Phase,
	isCurrentMatch: (self: MatchDirector, matchId: string?) -> boolean,
	getParticipant: (self: MatchDirector, userId: number) -> Participant?,
	isActiveParticipant: (self: MatchDirector, userId: number) -> boolean,
	getRole: (self: MatchDirector, userId: number) -> Role?,
	requestHackStart: (self: MatchDirector, userId: number, terminalId: string, now: number) -> (boolean, string),
	respondChallenge: (
		self: MatchDirector,
		userId: number,
		matchId: string,
		terminalId: string,
		nonce: number,
		pressTime: number,
		now: number
	) -> (boolean, string),
	strike: (self: MatchDirector, victimId: number, byUserId: number?, now: number) -> string,
	beginAction: (self: MatchDirector, userId: number, kind: string, target: any, now: number) -> (boolean, string),
	stopAction: (self: MatchDirector, userId: number, reason: string, now: number) -> boolean,
	getAction: (self: MatchDirector, userId: number) -> Action?,
	isFree: (self: MatchDirector, userId: number) -> boolean,
	boost: (self: MatchDirector, target: number, kind: string, amount: number, by: number?, now: number) -> boolean,
	getCondition: (self: MatchDirector, userId: number) -> string?,
	cancelHack: (self: MatchDirector, userId: number, reason: string, now: number) -> boolean,
	getHackingTerminal: (self: MatchDirector, userId: number) -> string?,
	notifyDamage: (self: MatchDirector, userId: number, now: number) -> (),
	eliminate: (self: MatchDirector, userId: number, byUserId: number?, now: number) -> boolean,
	playerRemoving: (self: MatchDirector, userId: number, now: number) -> (),
	snapshot: (self: MatchDirector) -> GameTypes.MatchSnapshot,
	publicTerminal: (self: MatchDirector, terminalId: string) -> GameTypes.PublicTerminal?,
	publicParticipants: (self: MatchDirector) -> { GameTypes.PublicParticipant },
	destroy: (self: MatchDirector) -> (),
}

local MatchDirector = {}

export type Params = {
	config: DirectorConfig,
	world: WorldQuery,
	queue: QueueModel.QueueModel?,
	terminals: { TerminalSpec },
	prepareMatch: (({ number }) -> { TerminalSpec })?,
	newMatchId: () -> string,
	randomIndex: (n: number) -> number,
	now: number,
}

function MatchDirector.new(params: Params): MatchDirector
	assert(#params.terminals >= params.config.requiredHacks, "MatchDirector: fewer terminals than required hacks")

	local config = params.config
	local world = params.world

	local self = {
		config = config,
		world = world,
		queue = params.queue or QueueModel.new(),
		machine = MatchStateMachine.new(params.now),
		session = nil :: Session?,
		phaseEndsAt = nil :: number?,
		roleHistory = {} :: RoleSelector.History,
		events = Signal.new() :: Signal.Signal<string, any>,
		matchesStarted = 0,
		snapshotVersion = 0,
		lastNow = params.now,
	} :: any

	local function emit(name: string, payload: any)
		self.snapshotVersion += 1
		self.events:Fire(name, payload)
	end

	local function minRequired(): number
		if config.allowKeeperless then
			return 1
		end
		return config.minPlayers
	end

	local function eligibleCount(): number
		return self.queue:countEligible(world.isEligibleForMatch)
	end

	local function setPhase(to: Phase, now: number, endsAt: number?): boolean
		local from = self.machine.phase
		if not self.machine:transition(to, now) then
			warn(`[MatchDirector] rejected illegal transition {from} -> {to}`)
			return false
		end
		self.phaseEndsAt = endsAt
		local session: Session? = self.session
		emit("PhaseChanged", {
			from = from,
			phase = to,
			endsAt = endsAt,
			matchId = if session then session.matchId else nil,
		})
		return true
	end

	function self:getPhase(): Phase
		return self.machine.phase
	end

	function self:isCurrentMatch(matchId: string?): boolean
		local session = self.session
		return session ~= nil and matchId ~= nil and session.matchId == matchId
	end

	function self:getParticipant(userId: number): Participant?
		local session = self.session
		if not session then
			return nil
		end
		return session.participants[userId]
	end

	function self:isActiveParticipant(userId: number): boolean
		local participant = self:getParticipant(userId)
		return participant ~= nil and participant.status == "Active" and self.machine:isInMatch()
	end

	function self:getRole(userId: number): Role?
		local participant = self:getParticipant(userId)
		return if participant then participant.role else nil
	end

	function self:publicTerminal(terminalId: string): GameTypes.PublicTerminal?
		local session = self.session
		if not session then
			return nil
		end
		local terminal = session.terminals[terminalId]
		if not terminal then
			return nil
		end
		return {
			id = terminal.id,
			name = terminal.name,
			state = terminal.state,
			progress = math.floor(terminal.progress * 1000 + 0.5) / 1000,
			hackerUserId = terminal.hackerUserId,
			assistants = table.clone(terminal.assistants),
			regressing = terminal.regressing,
			mode = session.modes[terminalId],
			difficulty = session.objectives:completedCount() + 1,
		}
	end

	function self:publicParticipants(): { GameTypes.PublicParticipant }
		local list: { GameTypes.PublicParticipant } = {}
		local session = self.session
		if not session then
			return list
		end
		for _, userId in session.order do
			local p = session.participants[userId]
			local entry: any = { userId = p.userId, name = p.name, role = p.role, status = p.status }
			local vital = session.survival:get(userId)
			if vital and p.status == "Active" then
				entry.condition = vital.condition
				entry.stage = vital.stage
				entry.heal = math.floor(vital.heal * 100 + 0.5) / 100
				entry.revive = math.floor(vital.revive * 100 + 0.5) / 100
				entry.bleedoutAt = vital.bleedoutAt
				entry.podId = vital.podId
				entry.podRemaining = if vital.podId then math.ceil(vital.podRemaining) else nil
				entry.podDuration = if vital.podId then vital.podDuration else nil
				entry.feedback = if vital.podId then math.floor(vital.feedback * 100 + 0.5) / 100 else nil
				entry.enduranceUntil = if vital.enduranceUntil > -math.huge then vital.enduranceUntil else nil
			elseif vital then
				entry.stage = vital.stage
			end
			local action = session.actions[userId]
			if action then
				entry.action = action.kind
			end
			table.insert(list, entry)
		end
		return list
	end

	function self:snapshot(): GameTypes.MatchSnapshot
		local session = self.session
		local terminals: { GameTypes.PublicTerminal } = {}
		if session then
			for _, id in session.terminalOrder do
				local t = self:publicTerminal(id)
				if t then
					table.insert(terminals, t)
				end
			end
		end
		return {
			version = self.snapshotVersion,
			matchId = if session then session.matchId else nil,
			phase = self.machine.phase,
			phaseEndsAt = self.phaseEndsAt,
			requiredHacks = config.requiredHacks,
			completedHacks = if session then session.objectives:completedCount() else 0,
			participants = self:publicParticipants(),
			terminals = terminals,
			extractionActive = session ~= nil and session.extraction.active,
			collapse = if session and session.endgame.startedAt
				then {
					endsAt = session.endgame.endsAt,
					gateOpen = session.endgame.gateOpen,
					relays = table.clone(session.endgame.relays),
					tier = session.endgame:tier(self.lastNow),
				}
				else nil,
			rift = if session and session.rift.open then { site = session.rift.site } else nil,
			queueCount = self.queue:count(),
			minPlayers = minRequired(),
			maxPlayers = config.maxPlayers,
		}
	end

	local function emitTerminal(session: Session, terminalId: string, reason: string?)
		emit("TerminalChanged", {
			matchId = session.matchId,
			terminal = self:publicTerminal(terminalId),
			reason = reason,
		})
	end

	---------------------------------------------------------------------------
	-- Resolution
	---------------------------------------------------------------------------

	local function resolve(winner: Team?, reason: ResolutionReason, now: number): boolean
		local session = self.session
		if not session or session.result ~= nil then
			return false -- idempotent: a match resolves exactly once
		end
		if not MatchStateMachine.isInMatchPhase(self.machine.phase) then
			return false
		end
		-- Freeze objective interactions before anything else observes the result.
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal:lock() then
				emitTerminal(session, id, "MatchEnded")
			end
		end
		local participants: { [number]: ResultParticipant } = {}
		for userId, p in session.participants do
			participants[userId] = {
				userId = p.userId,
				name = p.name,
				role = p.role,
				status = p.status,
				connected = p.connected,
				hacks = p.hacks,
				eliminations = p.eliminations,
				extracted = p.extracted,
				assists = p.assists,
				downs = p.downs,
				containments = p.containments,
				rescues = p.rescues,
				revives = p.revives,
				heals = p.heals,
				greats = p.greats,
			}
		end
		local result: MatchResult = {
			matchId = session.matchId,
			winner = winner,
			reason = reason,
			startedAt = session.startedAt,
			endedAt = now,
			completedHacks = session.objectives:completedCount(),
			participants = participants,
		}
		session.result = result
		setPhase("Resolving", now, now + config.resultsDuration)
		emit("MatchResolved", result)
		return true
	end

	local function checkOutcome(now: number)
		local session = self.session
		if not session or session.result ~= nil then
			return
		end
		local phase = self.machine.phase
		if not MatchStateMachine.isInMatchPhase(phase) then
			return
		end

		local anyConnected = false
		local keeperGone = false
		local active, extracted, eliminated, total, free = 0, 0, 0, 0, 0
		for _, p in session.participants do
			if p.connected then
				anyConnected = true
			end
			if p.role == "TimeKeeper" then
				if p.status == "Disconnected" then
					keeperGone = true
				end
			else
				total += 1
				if p.status == "Active" then
					active += 1
					if session.survival:isFree(p.userId) then
						free += 1
					end
				elseif p.status == "Extracted" then
					extracted += 1
				elseif p.status == "Eliminated" then
					eliminated += 1
				end
			end
		end

		if not anyConnected or total == 0 then
			resolve(nil, "Aborted", now)
			return
		end

		if phase == "Intro" then
			-- Nothing has been played yet: departures abort instead of awarding a free win.
			if keeperGone or active == 0 then
				resolve(nil, "Aborted", now)
			end
			return
		end

		if keeperGone then
			resolve("Infiltrators", "KeeperLeft", now)
			return
		end

		-- Nobody left who could rescue or re-sync, or the collapse ended: the rest are Erased now.
		local collapsed = phase == "Extraction" and session.extraction:isExpired(now)
		if active > 0 and (free == 0 or collapsed) then
			for _, userId in table.clone(session.order) do
				local p = session.participants[userId]
				if p.role == "Infiltrator" and p.status == "Active" then
					self:eliminate(userId, session.keeperUserId, now)
				end
			end
			return -- eliminate() re-enters checkOutcome with the final counts
		end

		if active == 0 then
			if extracted > 0 then
				resolve("Infiltrators", "Extracted", now)
			elseif collapsed then
				resolve("TimeKeeper", "ExtractionFailed", now)
			elseif eliminated > 0 then
				resolve("TimeKeeper", "AllEliminated", now)
			else
				resolve("TimeKeeper", "InfiltratorsLeft", now)
			end
			return
		end

		if phase == "Active" and session.deadline ~= nil and now >= session.deadline then
			resolve("TimeKeeper", "TimeExpired", now)
		end
	end

	---------------------------------------------------------------------------
	-- Hacking
	---------------------------------------------------------------------------

	local function findHackedTerminal(session: Session, userId: number): TerminalModel.TerminalModel?
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal.state == "Hacking" and terminal:hasParticipant(userId) then
				return terminal
			end
		end
		return nil
	end

	function self:getHackingTerminal(userId: number): string?
		local session = self.session
		if not session then
			return nil
		end
		local terminal = findHackedTerminal(session, userId)
		return if terminal then terminal.id else nil
	end

	local function interruptTerminal(
		session: Session,
		terminal: TerminalModel.TerminalModel,
		reason: string,
		now: number
	)
		local hacker = terminal.hackerUserId
		local everyone = { hacker }
		for _, assistant in terminal.assistants do
			table.insert(everyone, assistant)
		end
		for _, userId in everyone do
			if userId then
				session.challenges[userId] = nil
				session.nextCheckAt[userId] = nil
			end
		end
		if terminal:interrupt(reason, now, config.interruptLockout, config.retainProgressOnInterrupt) then
			emit("HackInterrupted", {
				matchId = session.matchId,
				terminalId = terminal.id,
				userId = hacker,
				reason = reason,
			})
			emitTerminal(session, terminal.id, reason)
		end
	end

	-- Returns nil when the hacker may continue, otherwise the interruption reason.
	local function hackerInvalidReason(
		session: Session,
		terminal: TerminalModel.TerminalModel,
		candidate: number?
	): string?
		local userId = candidate
		if userId == nil then
			return "NoHacker"
		end
		local p = session.participants[userId]
		if not p or not p.connected then
			return "Disconnected"
		end
		if p.status ~= "Active" then
			return "Eliminated"
		end
		if not session.survival:isFree(userId) then
			return "Downed"
		end
		if not world.isAlive(userId) then
			return "Died"
		end
		if world.isRestrained(userId) then
			return "Restrained"
		end
		local distance = world.distanceToTerminal(userId, terminal.id)
		if distance == nil or distance ~= distance or distance > config.maxInteractionDistance then
			return "OutOfRange"
		end
		return nil
	end

	function self:requestHackStart(userId: number, terminalId: string, now: number): (boolean, string)
		local session = self.session
		if not session or self.machine.phase ~= "Active" then
			return false, "WrongPhase"
		end
		local p = session.participants[userId]
		if not p or not p.connected then
			return false, "NotParticipant"
		end
		if p.role ~= "Infiltrator" then
			return false, "WrongRole"
		end
		if p.status ~= "Active" or not world.isAlive(userId) or not session.survival:isFree(userId) then
			return false, "NotAlive"
		end
		if world.isRestrained(userId) then
			return false, "Restrained"
		end
		if session.actions[userId] then
			return false, "Busy"
		end
		local terminal = session.terminals[terminalId]
		if not terminal or not session.objectives:isRegistered(terminalId) then
			return false, "UnknownTarget"
		end
		local current = findHackedTerminal(session, userId)
		if current ~= nil then
			return false, "AlreadyHacking"
		end
		local maxAssistants = (config.maxHackers or SurvivalConfig.Objectives.MaxHackers) - 1
		if config.cooperativeHacking and terminal.state == "Hacking" and #terminal.assistants < maxAssistants then
			local distance = world.distanceToTerminal(userId, terminalId)
			if distance == nil or distance ~= distance or distance > config.maxInteractionDistance then
				return false, "OutOfRange"
			end
			table.insert(terminal.assistants, userId)
			session.nextCheckAt[userId] = nil
			emit(
				"HackStarted",
				{ matchId = session.matchId, terminalId = terminalId, userId = userId, assisting = true }
			)
			emitTerminal(session, terminalId, "Assisting")
			return true, "Ok"
		end
		local canStart, code = terminal:canStart(userId)
		if not canStart then
			return false, code
		end
		local distance = world.distanceToTerminal(userId, terminalId)
		if distance == nil or distance ~= distance or distance > config.maxInteractionDistance then
			return false, "OutOfRange"
		end
		local started, startCode = terminal:start(userId, now)
		if not started then
			return false, startCode
		end
		session.nextCheckAt[userId] = nil
		emit("HackStarted", { matchId = session.matchId, terminalId = terminalId, userId = userId })
		emitTerminal(session, terminalId, nil)
		return true, "Ok"
	end

	function self:cancelHack(userId: number, reason: string, now: number): boolean
		local session = self.session
		if not session then
			return false
		end
		local terminal = findHackedTerminal(session, userId)
		if not terminal then
			return false
		end
		if terminal:removeAssistant(userId) then
			session.challenges[userId] = nil
			emitTerminal(session, terminal.id, "AssistantLeft")
		else
			interruptTerminal(session, terminal, reason, now)
		end
		return true
	end

	---------------------------------------------------------------------------
	-- Calibration Pulses (per hacker)
	---------------------------------------------------------------------------

	local calibration = SurvivalConfig.Calibration

	local function modifier(userId: number?, key: string): number
		return if world.modifier then world.modifier(userId, key) else 1
	end

	local function scheduleNextCheck(session: Session, userId: number, now: number)
		local spread = calibration.MaxInterval - calibration.MinInterval
		session.nextCheckAt[userId] = now + calibration.MinInterval + (params.randomIndex(6) - 1) / 5 * spread
	end

	local function resolveCalibration(
		session: Session,
		terminal: TerminalModel.TerminalModel,
		userId: number,
		grade: string,
		now: number
	)
		session.challenges[userId] = nil
		scheduleNextCheck(session, userId, now)
		local p = session.participants[userId]
		if grade == "Great" then
			terminal.progress = math.min(0.99, terminal.progress + calibration.GreatBonus)
			if p then
				p.greats += 1
			end
		elseif grade == "Miss" then
			terminal.progress =
				math.max(0, terminal.progress - calibration.MissPenalty * modifier(userId, "MissPenalty"))
			emit("HackRisk", { matchId = session.matchId, userId = userId, terminalId = terminal.id })
		end
		emit("CalibrationResult", {
			matchId = session.matchId,
			userId = userId,
			terminalId = terminal.id,
			grade = grade,
		})
		emitTerminal(session, terminal.id, if grade == "Miss" then "CalibrationMissed" else nil)
	end

	local function processCalibration(
		session: Session,
		terminal: TerminalModel.TerminalModel,
		userId: number,
		now: number
	)
		if not config.interactiveChallenges then
			return
		end
		local pending = session.challenges[userId]
		if pending then
			if pending.terminalId ~= terminal.id then
				session.challenges[userId] = nil
			elseif HackChallenge.isExpired(pending.check, now) then
				resolveCalibration(session, terminal, userId, "Miss", now)
			end
			return
		end
		local due = session.nextCheckAt[userId]
		if due == nil then
			scheduleNextCheck(session, userId, now)
		elseif now >= due then
			session.challengeSequence += 1
			local check = HackChallenge.new(
				session.modes[terminal.id],
				session.challengeSequence,
				now,
				params.randomIndex(HackChallenge.SEEDS),
				session.objectives:completedCount(),
				modifier(userId, "CalibrationArc")
			)
			session.challenges[userId] = { terminalId = terminal.id, check = check }
			session.nextCheckAt[userId] = math.huge
			emit("CalibrationIssued", {
				matchId = session.matchId,
				userId = userId,
				terminalId = terminal.id,
				challenge = HackChallenge.public(check),
			})
		end
	end

	-- Calibration press for the caller's own pending pulse. `pressTime` is the client's synchronised
	-- press time; HackChallenge bounds how far back it may reach.
	function self:respondChallenge(
		userId: number,
		matchId: string,
		terminalId: string,
		nonce: number,
		pressTime: number,
		now: number
	): (boolean, string)
		local session = self.session
		if
			not session
			or session.matchId ~= matchId
			or self.machine.phase ~= "Active"
			or (session.deadline and now >= session.deadline)
		then
			return false, "StaleRequest"
		end
		local terminal = session.terminals[terminalId]
		if not terminal or terminal.state ~= "Hacking" or not terminal:hasParticipant(userId) then
			return false, "WrongRole"
		end
		local reason = hackerInvalidReason(session, terminal, userId)
		if reason then
			return false, reason
		end
		local pending = session.challenges[userId]
		if not pending or pending.terminalId ~= terminalId then
			return false, "StaleRequest"
		end
		local ok, code, grade = HackChallenge.respond(pending.check, nonce, pressTime, now)
		if grade then
			resolveCalibration(session, terminal, userId, grade, now)
		end
		return ok, code
	end

	function self:notifyDamage(userId: number, now: number)
		self:cancelHack(userId, "Damaged", now)
		self:stopAction(userId, "Damaged", now)
	end

	local function openExtraction(session: Session, now: number)
		if not session.extraction:activate(now, config.extractionWindow) then
			return
		end
		session.endgame:begin(now, config.extractionWindow)
		if session.rift.open then
			session.rift.open = false
			emit("RiftClosed", { matchId = session.matchId })
		end
		-- Remaining terminals no longer matter; lock them so nobody wastes time on them.
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal.state ~= "Completed" and terminal:lock() then
				emitTerminal(session, id, "ExtractionOpened")
			end
		end
		table.clear(session.challenges)
		setPhase("Extraction", now, session.extraction.endsAt)
		emit("ExtractionOpened", {
			matchId = session.matchId,
			endsAt = session.extraction.endsAt,
			gateOpen = session.endgame.gateOpen,
		})
		if session.endgame.gateOpen then
			emit("GateOpened", { matchId = session.matchId })
		end
	end

	local function hackSpeedOf(userId: number): number
		return if world.hackSpeed then world.hackSpeed(userId) else 1
	end

	local function processTerminals(session: Session, now: number, dt: number)
		-- Progress earned after the match timer expired must not count, even if a server hitch
		-- delivers the tick late; a hack finishing exactly at the deadline still counts.
		if self.machine.phase == "Active" and session.deadline ~= nil then
			now = math.min(now, session.deadline)
		end
		local efficiency = config.assistantEfficiency or SurvivalConfig.Objectives.ExtraHackerEfficiency
		local squadScale = if config.squadScaling
			then config.squadScaling[math.clamp(session.squadSize, 1, #config.squadScaling)]
			else 1
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal:tickLockout(now) then
				emitTerminal(session, id, nil)
			end
			if terminal.regressing then
				local rate = SurvivalConfig.Objectives.RegressionPerSecond
					* modifier(session.keeperUserId, "Regression")
				if terminal:regress(dt, rate) then
					emitTerminal(session, id, "RegressionEnded")
				elseif terminal:shouldBroadcast(now, config.progressBroadcastInterval * 4) then
					emit("TerminalProgress", { matchId = session.matchId, terminal = self:publicTerminal(id) })
				end
			end
			if terminal.state == "Hacking" then
				local reason = hackerInvalidReason(session, terminal, terminal.hackerUserId)
				if reason then
					interruptTerminal(session, terminal, reason, now)
				else
					local hacker = terminal.hackerUserId :: number
					for _, assistant in table.clone(terminal.assistants) do
						if hackerInvalidReason(session, terminal, assistant) then
							terminal:removeAssistant(assistant)
							session.challenges[assistant] = nil
							emitTerminal(session, id, "AssistantLeft")
						end
					end
					processCalibration(session, terminal, hacker, now)
					for _, assistant in terminal.assistants do
						processCalibration(session, terminal, assistant, now)
					end
					if terminal.state ~= "Hacking" then
						continue
					end
					local speed = hackSpeedOf(hacker)
					for _, assistant in terminal.assistants do
						speed += hackSpeedOf(assistant) * efficiency
					end
					local difficulty = 1
						+ session.objectives:completedCount() * (if config.interactiveChallenges then 0.1 else 0)
					local duration = config.hackDuration * squadScale * difficulty / math.clamp(speed, 0.5, 3.5)
					local helpers = table.clone(terminal.assistants)
					if terminal:advance(now, duration) then
						local accepted, thresholdReached = session.objectives:markComplete(id)
						if accepted then
							local p = session.participants[hacker]
							if p then
								p.hacks += 1
							end
							for _, assistant in helpers do
								session.participants[assistant].assists += 1
								session.challenges[assistant] = nil
							end
							session.challenges[hacker] = nil
							emit("TerminalCompleted", {
								matchId = session.matchId,
								terminalId = id,
								userId = hacker,
								assistants = helpers,
								completed = session.objectives:completedCount(),
								required = config.requiredHacks,
							})
							emitTerminal(session, id, "Completed")
							if thresholdReached then
								openExtraction(session, now)
							end
						end
					elseif terminal:shouldBroadcast(now, config.progressBroadcastInterval) then
						emit("TerminalProgress", {
							matchId = session.matchId,
							terminal = self:publicTerminal(id),
						})
					end
				end
			end
		end
	end

	local function processExtraction(session: Session, now: number)
		if not session.extraction.active then
			return
		end
		for _, userId in session.order do
			local p = session.participants[userId]
			if p.role == "Infiltrator" and p.status == "Active" and p.connected then
				local inZone = session.endgame.gateOpen
					and session.survival:isFree(userId)
					and world.isAlive(userId)
					and world.isInExtractionZone(userId)
				local before = session.extraction:channelProgress(userId, now, config.extractionChannelTime)
				if session.extraction:update(userId, inZone, now, config.extractionChannelTime) then
					p.status = "Extracted"
					p.extracted = true
					session.survival:remove(userId)
					self:stopAction(userId, "Extracted", now)
					emit("PlayerExtracted", { matchId = session.matchId, userId = userId })
					emit("ExtractionChannel", { matchId = session.matchId, userId = userId, progress = 1 })
				else
					local progress = session.extraction:channelProgress(userId, now, config.extractionChannelTime)
					local changedState = (before == 0) ~= (progress == 0)
					if
						changedState
						or (progress > 0 and now - p.lastChannelBroadcast >= config.progressBroadcastInterval)
					then
						p.lastChannelBroadcast = now
						emit("ExtractionChannel", { matchId = session.matchId, userId = userId, progress = progress })
					end
				end
			end
		end
	end

	---------------------------------------------------------------------------
	-- Survival: actions (Re-sync, Patch, Rescue, Phase-Lock, Overload, Relay, Rift)
	---------------------------------------------------------------------------

	local integrity = SurvivalConfig.Integrity
	local containment = SurvivalConfig.Containment
	local endgameConfig = SurvivalConfig.Endgame
	local KEEPER_ACTIONS: { [string]: boolean } = { Contain = true, Overload = true }
	local INFILTRATOR_ACTIONS: { [string]: boolean } = { Revive = true, Heal = true, Rescue = true, Relay = true }

	local function conditionOf(session: Session, userId: number): string?
		local vital = session.survival:get(userId)
		return if vital then vital.condition else nil
	end

	local function emitCondition(session: Session, userId: number, previous: string?, cause: string, by: number?)
		emit("ConditionChanged", {
			matchId = session.matchId,
			userId = userId,
			condition = conditionOf(session, userId),
			previous = previous,
			cause = cause,
			by = by,
		})
	end

	local function distanceTo(userId: number, kind: string, id: any): number?
		if not world.distanceTo then
			return nil
		end
		local d = world.distanceTo(userId, kind, id)
		if d == nil or d ~= d then
			return nil
		end
		return d
	end

	local function helpersOn(session: Session, kind: string, target: any): { number }
		local list = {}
		for _, userId in session.order do
			local action = session.actions[userId]
			if action and action.kind == kind and action.target == target then
				table.insert(list, userId)
			end
		end
		return list
	end

	local function durationFor(session: Session, userId: number, kind: string): number?
		if kind == "Contain" then
			return containment.ContainTime
		elseif kind == "Rescue" then
			return containment.RescueTime
		elseif kind == "Overload" then
			return SurvivalConfig.Objectives.OverloadTime
		elseif kind == "Rift" then
			return if session.participants[userId].role == "TimeKeeper"
				then endgameConfig.RiftSealTime
				else endgameConfig.RiftChannel
		end
		return nil -- progress lives on the target (Revive, Heal) or relay
	end

	-- Returns nil when the actor may (keep) performing the action, otherwise a rejection code.
	local function actionInvalidReason(
		session: Session,
		userId: number,
		kind: string,
		target: any,
		starting: boolean
	): string?
		local phase = self.machine.phase
		if phase ~= "Active" and phase ~= "Extraction" then
			return "WrongPhase"
		end
		local p = session.participants[userId]
		if not p or not p.connected or p.status ~= "Active" then
			return "NotParticipant"
		end
		local keeper = p.role == "TimeKeeper"
		if kind == "Rift" then
			if not session.rift.open or phase ~= "Active" then
				return "WrongPhase"
			end
		elseif KEEPER_ACTIONS[kind] then
			if not keeper then
				return "WrongRole"
			end
		elseif INFILTRATOR_ACTIONS[kind] then
			if keeper then
				return "WrongRole"
			end
		else
			return "InvalidPayload"
		end
		if not world.isAlive(userId) then
			return "NotAlive"
		end
		if world.isRestrained(userId) then
			return "Restrained"
		end
		if not keeper and not session.survival:isFree(userId) then
			return "NotAlive"
		end
		if starting and findHackedTerminal(session, userId) then
			return "AlreadyHacking"
		end

		if kind == "Revive" or kind == "Heal" or kind == "Contain" or kind == "Rescue" then
			if type(target) ~= "number" then
				return "UnknownTarget"
			end
			local tp = session.participants[target]
			if not tp or tp.role ~= "Infiltrator" or tp.status ~= "Active" or not tp.connected then
				return "UnknownTarget"
			end
			local vital = session.survival:get(target) :: SurvivalModel.Vital
			local wanted = if kind == "Heal" then "Injured" elseif kind == "Rescue" then "Contained" else "Downed"
			if not vital or vital.condition ~= wanted then
				return "UnknownTarget"
			end
			if kind == "Rescue" then
				local d = distanceTo(userId, "Pod", vital.podId)
				if d == nil or d > containment.RescueRange then
					return "OutOfRange"
				end
				if starting and #helpersOn(session, kind, target) >= 1 then
					return "Busy"
				end
			elseif target == userId then
				if kind ~= "Heal" or not (world.canSelfHeal and world.canSelfHeal(userId)) then
					return "UnknownTarget"
				end
			else
				local range = if kind == "Contain" then containment.ContainRange else integrity.HelperRange
				local d = distanceTo(userId, "Player", target)
				if d == nil or d > range then
					return "OutOfRange"
				end
				if starting and kind ~= "Contain" and #helpersOn(session, kind, target) >= integrity.MaxHelpers then
					return "Busy"
				end
			end
		elseif kind == "Overload" then
			local terminal = if type(target) == "string" then session.terminals[target] else nil
			if phase ~= "Active" or not terminal then
				return "UnknownTarget"
			end
			if terminal.state == "Hacking" then
				return "Busy"
			end
			if
				starting
				and (
					(terminal.state ~= "Available" and terminal.state ~= "Interrupted")
					or terminal.progress <= 0
					or terminal.regressing
				)
			then
				return "Locked"
			end
			local d = distanceTo(userId, "Terminal", target)
			if d == nil or d > SurvivalConfig.Objectives.OverloadRange then
				return "OutOfRange"
			end
		elseif kind == "Relay" then
			if phase ~= "Extraction" or type(target) ~= "string" or session.endgame.relays[target] == nil then
				return "UnknownTarget"
			end
			if session.endgame.gateOpen then
				return "AlreadyCompleted"
			end
			local d = distanceTo(userId, "Relay", target)
			if d == nil or d > endgameConfig.RelayRange then
				return "OutOfRange"
			end
		elseif kind == "Rift" then
			local d = distanceTo(userId, "Rift", session.rift.site)
			if d == nil or d > endgameConfig.RiftRange then
				return "OutOfRange"
			end
		end
		return nil
	end

	local function endAction(session: Session, userId: number, completed: boolean, reason: string)
		local action = session.actions[userId]
		if not action then
			return
		end
		session.actions[userId] = nil
		emit("ActionEnded", {
			matchId = session.matchId,
			userId = userId,
			kind = action.kind,
			target = action.target,
			completed = completed,
			reason = reason,
		})
	end

	-- Ends every action aimed at `target` (e.g. the downed player was Phase-Locked).
	local function endActionsOn(session: Session, target: number, reason: string)
		for _, userId in session.order do
			local action = session.actions[userId]
			if action and action.target == target then
				endAction(session, userId, false, reason)
			end
		end
	end

	local function performContain(session: Session, target: number, by: number?, now: number)
		local podId: string? = nil
		local occupied = session.survival:occupied()
		if world.choosePod then
			podId = world.choosePod(target, occupied)
		end
		if podId == nil or occupied[podId] then
			podId = nil
			for _, id in session.survival.podOrder do
				if not occupied[id] then
					podId = id
					break
				end
			end
		end
		self:cancelHack(target, "Contained", now)
		endAction(session, target, false, "Contained")
		endActionsOn(session, target, "Contained")
		local outcome = if podId then session.survival:contain(target, podId, now) else "Erased"
		if outcome == "Contained" then
			local keeper = if by then session.participants[by] else nil
			if keeper then
				keeper.containments += 1
			end
			emit("PlayerContained", {
				matchId = session.matchId,
				userId = target,
				podId = podId,
				stage = (session.survival:get(target) :: SurvivalModel.Vital).stage,
				by = by,
			})
			emitCondition(session, target, "Downed", if by then "PhaseLock" else "BledOut", by)
		elseif outcome == "Erased" then
			self:eliminate(target, session.keeperUserId, now)
		end
	end

	local function completeAction(session: Session, userId: number, action: Action, now: number)
		local kind, target = action.kind, action.target
		endAction(session, userId, true, "Completed")
		if kind == "Contain" then
			performContain(session, target, userId, now)
		elseif kind == "Rescue" then
			if session.survival:release(target, now, modifier(userId, "Endurance")) then
				local p = session.participants[userId]
				p.rescues += 1
				endActionsOn(session, target, "Rescued")
				emit("PlayerRescued", { matchId = session.matchId, userId = target, by = userId, cause = "Rescue" })
				emitCondition(session, target, "Contained", "Rescue", userId)
			end
		elseif kind == "Overload" then
			local terminal = session.terminals[target]
			if terminal and terminal:overload(SurvivalConfig.Objectives.OverloadInstantLoss) then
				emit("TerminalOverloaded", { matchId = session.matchId, terminalId = target, by = userId })
				emitTerminal(session, target, "Overloaded")
			end
		elseif kind == "Rift" then
			if not session.rift.open then
				return
			end
			session.rift.open = false
			local p = session.participants[userId]
			if p.role == "TimeKeeper" then
				emit("RiftSealed", { matchId = session.matchId, by = userId })
				openExtraction(session, now)
			else
				p.status = "Extracted"
				p.extracted = true
				session.survival:remove(userId)
				emit("RiftClosed", { matchId = session.matchId })
				emit("PlayerExtracted", { matchId = session.matchId, userId = userId, via = "Rift" })
			end
		end
	end

	-- Revive/Heal/Relay progress accumulates from every helper (extra helpers at reduced efficiency).
	local function pooledRate(helpers: { number }, kind: string, target: any): number
		local rate = 0
		for index, helper in helpers do
			local speed = if world.actionSpeed then world.actionSpeed(helper, kind) else 1
			if kind == "Heal" and helper == target then
				speed *= integrity.SelfHealRate
			end
			rate += speed * (if index == 1 then 1 else integrity.ExtraHelperEfficiency)
		end
		local base = if kind == "Revive"
			then integrity.ReviveTime
			elseif kind == "Heal" then integrity.HealTime
			else endgameConfig.RelayTime
		return rate / base
	end

	local function processActions(session: Session, now: number, dt: number)
		local pooled: { [string]: { kind: string, target: any, helpers: { number } } } = {}
		local pooledOrder: { string } = {}
		for _, userId in table.clone(session.order) do
			local action = session.actions[userId]
			if action then
				local reason = actionInvalidReason(session, userId, action.kind, action.target, false)
				if reason then
					endAction(session, userId, false, reason)
				elseif action.duration then
					action.progress = math.min(1, (now - action.startedAt) / (action.duration :: number))
					if action.progress >= 1 - 1e-6 then
						completeAction(session, userId, action, now)
						if session.result ~= nil then
							return
						end
					end
				else
					local key = `{action.kind}:{action.target}`
					if not pooled[key] then
						pooled[key] = { kind = action.kind, target = action.target, helpers = {} }
						table.insert(pooledOrder, key)
					end
					table.insert(pooled[key].helpers, userId)
				end
			end
		end
		for _, key in pooledOrder do
			local group = pooled[key]
			local amount = pooledRate(group.helpers, group.kind, group.target) * dt
			if group.kind == "Relay" then
				if session.endgame:power(group.target, amount) then
					for _, helper in group.helpers do
						endAction(session, helper, true, "Completed")
					end
					for _, userId in session.order do
						local action = session.actions[userId]
						if action and action.kind == "Relay" then
							endAction(session, userId, false, "GateOpened")
						end
					end
					emit("GateOpened", { matchId = session.matchId, relayId = group.target, by = group.helpers[1] })
				end
			else
				local target = group.target :: number
				local previous = conditionOf(session, target)
				if session.survival:recover(target, group.kind, amount) then
					for _, helper in group.helpers do
						local p = session.participants[helper]
						if group.kind == "Revive" then
							p.revives += 1
						else
							p.heals += 1
						end
						endAction(session, helper, true, "Completed")
					end
					endActionsOn(session, target, "Recovered")
					emitCondition(session, target, previous, group.kind, group.helpers[1])
				end
			end
		end
	end

	function self:beginAction(userId: number, kind: string, target: any, now: number): (boolean, string)
		local session = self.session
		if not session or session.result ~= nil then
			return false, "WrongPhase"
		end
		if session.actions[userId] then
			return false, "Busy"
		end
		local reason = actionInvalidReason(session, userId, kind, target, true)
		if reason then
			return false, reason
		end
		local duration = durationFor(session, userId, kind)
		session.actions[userId] = { kind = kind, target = target, startedAt = now, progress = 0, duration = duration }
		emit("ActionStarted", {
			matchId = session.matchId,
			userId = userId,
			kind = kind,
			target = target,
			duration = duration,
		})
		return true, "Ok"
	end

	function self:stopAction(userId: number, reason: string, _now: number): boolean
		local session = self.session
		if not session or not session.actions[userId] then
			return false
		end
		endAction(session, userId, false, reason)
		return true
	end

	-- Instant Patch/Re-sync progress (Mend). Returns true when it applied to the target.
	function self:boost(target: number, kind: string, amount: number, by: number?, _now: number): boolean
		local session = self.session
		local phase = self.machine.phase
		if not session or session.result ~= nil or (phase ~= "Active" and phase ~= "Extraction") then
			return false
		end
		local p = session.participants[target]
		local previous = conditionOf(session, target)
		local wanted = if kind == "Heal" then "Injured" elseif kind == "Revive" then "Downed" else nil
		if not p or p.status ~= "Active" or previous == nil or previous ~= wanted then
			return false
		end
		if session.survival:recover(target, kind, amount) then
			local helper = if by then session.participants[by] else nil
			if helper then
				if kind == "Revive" then
					helper.revives += 1
				else
					helper.heals += 1
				end
			end
			endActionsOn(session, target, "Recovered")
			emitCondition(session, target, previous, kind, by)
		end
		return true
	end

	function self:getAction(userId: number): Action?
		local session = self.session
		return if session then session.actions[userId] else nil
	end

	function self:isFree(userId: number): boolean
		local session = self.session
		return session ~= nil and session.survival:isFree(userId)
	end

	function self:getCondition(userId: number): string?
		local session = self.session
		return if session then conditionOf(session, userId) else nil
	end

	-- A Chrono Strike landed on `victimId`. Returns "Injured", "Downed", "Endured" or "Ignored".
	function self:strike(victimId: number, byUserId: number?, now: number): string
		local session = self.session
		local phase = self.machine.phase
		if not session or session.result ~= nil or (phase ~= "Active" and phase ~= "Extraction") then
			return "Ignored"
		end
		local p = session.participants[victimId]
		if not p or p.role ~= "Infiltrator" or p.status ~= "Active" or not p.connected then
			return "Ignored"
		end
		local previous = conditionOf(session, victimId)
		local outcome = session.survival:hit(victimId, now)
		if outcome == "Ignored" then
			return outcome
		end
		self:notifyDamage(victimId, now)
		if outcome == "Downed" then
			endActionsOn(session, victimId, "Downed")
			local keeper = if byUserId then session.participants[byUserId] else nil
			if keeper and keeper.role == "TimeKeeper" then
				keeper.downs += 1
			end
		end
		emitCondition(session, victimId, previous, if outcome == "Endured" then "Endured" else "Strike", byUserId)
		checkOutcome(now)
		return outcome
	end

	local function processSurvival(session: Session, now: number, dt: number)
		local drain = (
			if self.machine.phase == "Extraction" and session.endgame:tier(now) ~= "Stable"
				then endgameConfig.RisingPodDrain
				else 1
		) * modifier(session.keeperUserId, "PodDrain")
		local events = session.survival:tick(now, dt, {
			isCamped = function(podId: string)
				return world.isKeeperNear ~= nil and world.isKeeperNear(podId)
			end,
			drainMultiplier = drain,
		})
		for _, event in events do
			if session.result ~= nil then
				return
			end
			if event.kind == "BledOut" then
				performContain(session, event.userId, nil, now)
			elseif event.kind == "Erased" then
				endActionsOn(session, event.userId, "Erased")
				self:eliminate(event.userId, session.keeperUserId, now)
			elseif event.kind == "Released" then
				endActionsOn(session, event.userId, "Released")
				emit("PlayerRescued", {
					matchId = session.matchId,
					userId = event.userId,
					podId = event.podId,
					cause = "Feedback",
				})
				emitCondition(session, event.userId, "Contained", "Feedback", nil)
			end
		end
	end

	-- A lone Infiltrator left in play (with teammates gone) gets one Slip Rift before the Collapse.
	local function processRift(session: Session, now: number)
		if self.machine.phase ~= "Active" or session.rift.open or session.rift.openedAt ~= nil then
			return
		end
		local inPlay, gone = 0, 0
		for _, p in session.participants do
			if p.role == "Infiltrator" then
				if p.status == "Active" then
					inPlay += 1
				elseif p.status == "Eliminated" or p.status == "Disconnected" then
					gone += 1
				end
			end
		end
		if inPlay == 1 and gone >= 1 then
			local site = if world.riftSite then world.riftSite() else "Rift"
			session.rift = { open = true, site = site, openedAt = now }
			emit("RiftOpened", { matchId = session.matchId, site = site })
		end
	end

	local function processCollapse(session: Session, now: number)
		if self.machine.phase ~= "Extraction" then
			return
		end
		local tier = session.endgame:tier(now)
		if tier ~= session.collapseTier then
			session.collapseTier = tier
			emit("CollapseTier", { matchId = session.matchId, tier = tier })
		end
		if session.endgame:shockwaveDue(now) then
			emit("Shockwave", { matchId = session.matchId, duration = endgameConfig.ShockwaveReveal })
		end
	end

	---------------------------------------------------------------------------
	-- Participants
	---------------------------------------------------------------------------

	-- Erases an Infiltrator (final containment stage, pod timer, collapse, or an unexpected death).
	function self:eliminate(userId: number, byUserId: number?, now: number): boolean
		local session = self.session
		if not session or session.result ~= nil then
			return false
		end
		if not MatchStateMachine.isInMatchPhase(self.machine.phase) then
			return false
		end
		local p = session.participants[userId]
		if not p or p.role ~= "Infiltrator" or p.status ~= "Active" then
			return false -- idempotent: already eliminated/extracted/disconnected
		end
		local terminal = findHackedTerminal(session, userId)
		if terminal then
			self:cancelHack(userId, "Eliminated", now)
		end
		endAction(session, userId, false, "Eliminated")
		endActionsOn(session, userId, "Eliminated")
		p.status = "Eliminated"
		session.survival:remove(userId)
		session.challenges[userId] = nil
		session.extraction:resetChannel(userId)
		local credited: number? = nil
		if byUserId ~= nil and byUserId == session.keeperUserId then
			local keeper = session.participants[byUserId]
			if keeper then
				keeper.eliminations += 1
				credited = byUserId
			end
		end
		emit("PlayerEliminated", { matchId = session.matchId, userId = userId, byUserId = credited })
		checkOutcome(now)
		return true
	end

	function self:playerRemoving(userId: number, now: number)
		self.queue:remove(userId)
		local session = self.session
		if not session then
			return
		end
		local p = session.participants[userId]
		if not p or not p.connected then
			return
		end
		p.connected = false
		if session.result ~= nil or not MatchStateMachine.isInMatchPhase(self.machine.phase) then
			return -- result already final; reward eligibility uses `connected`
		end
		local terminal = findHackedTerminal(session, userId)
		if terminal then
			self:cancelHack(userId, "Disconnected", now)
		end
		endAction(session, userId, false, "Disconnected")
		endActionsOn(session, userId, "Disconnected")
		session.challenges[userId] = nil
		if p.status == "Active" then
			p.status = "Disconnected"
			session.survival:remove(userId)
			session.extraction:resetChannel(userId)
		end
		emit("ParticipantLeft", { matchId = session.matchId, userId = userId, role = p.role })
		checkOutcome(now)
	end

	---------------------------------------------------------------------------
	-- Phase driver
	---------------------------------------------------------------------------

	local function createSession(roles: { [number]: string }, order: { number }, now: number): Session
		self.matchesStarted += 1
		local objectives = ObjectiveTracker.new(config.requiredHacks)
		local terminals: { [string]: TerminalModel.TerminalModel } = {}
		local terminalOrder: { string } = {}
		local specs: { TerminalSpec } = if params.prepareMatch then params.prepareMatch(order) else params.terminals
		for _, spec in specs do
			terminals[spec.id] = TerminalModel.new(spec.id, spec.name)
			table.insert(terminalOrder, spec.id)
			objectives:register(spec.id)
		end
		local participants: { [number]: Participant } = {}
		local keeper: number? = nil
		for _, userId in order do
			local role: Role = if roles[userId] == "TimeKeeper" then "TimeKeeper" else "Infiltrator"
			if role == "TimeKeeper" then
				keeper = userId
			end
			participants[userId] = {
				userId = userId,
				name = world.getName(userId),
				role = role,
				status = "Active",
				connected = true,
				hacks = 0,
				eliminations = 0,
				extracted = false,
				lastChannelBroadcast = -math.huge,
				assists = 0,
				downs = 0,
				containments = 0,
				rescues = 0,
				revives = 0,
				heals = 0,
				greats = 0,
			}
		end
		local survival = SurvivalModel.new(if world.podIds then world.podIds() else {})
		local squadSize = 0
		for userId, participant in participants do
			if participant.role == "Infiltrator" then
				survival:add(userId)
				squadSize += 1
			end
		end
		return {
			matchId = params.newMatchId(),
			startedAt = now,
			activeAt = nil,
			deadline = nil,
			keeperUserId = keeper,
			participants = participants,
			order = table.clone(order),
			terminals = terminals,
			terminalOrder = terminalOrder,
			objectives = objectives,
			extraction = ExtractionModel.new(),
			result = nil,
			challenges = {},
			challengeSequence = 0,
			modes = (function(): { [string]: string }
				local modes = {}
				local offset = params.randomIndex(3) - 1
				local choices = { "Sequence", "Cipher", "Timing" }
				for i, id in terminalOrder do
					modes[id] = choices[(i - 1 + offset) % 3 + 1]
				end
				return modes
			end)(),
			nextCheckAt = {},
			survival = survival,
			actions = {},
			endgame = EndgameModel.new(if world.relayIds then world.relayIds() else {}),
			rift = { open = false },
			lastTickAt = nil,
			squadSize = squadSize,
			collapseTier = nil,
		}
	end

	local function beginRoleAssignment(now: number)
		if not setPhase("RoleAssignment", now, nil) then
			return
		end
		local taken = self.queue:take(config.maxPlayers, world.isEligibleForMatch)
		if #taken < minRequired() then
			self.queue:restore(taken)
			setPhase("WaitingForPlayers", now, nil)
			return
		end
		local keeperless = config.allowKeeperless and #taken == 1
		local roles = RoleSelector.assign(taken, self.roleHistory, params.randomIndex, keeperless)
		local ok, created = pcall(createSession, roles, taken, now)
		if not ok then
			self.matchesStarted -= 1
			self.queue:restore(taken)
			setPhase("WaitingForPlayers", now, nil)
			warn(`[MatchDirector] match setup failed: {created}`)
			return
		end
		RoleSelector.recordMatch(self.roleHistory, roles)
		local session = created :: Session
		self.session = session
		setPhase("Intro", now, now + config.introDuration)
		emit("MatchStarted", {
			matchId = session.matchId,
			roles = roles,
			order = table.clone(session.order),
			keeperUserId = session.keeperUserId,
		})
	end

	local function beginActive(session: Session, now: number)
		session.activeAt = now
		session.lastTickAt = now
		session.deadline = now + config.matchDuration
		for _, id in session.terminalOrder do
			if session.terminals[id]:unlock() then
				emitTerminal(session, id, nil)
			end
		end
		setPhase("Active", now, session.deadline)
		emit("MatchActive", { matchId = session.matchId, deadline = session.deadline })
	end

	local function finishMatch(now: number)
		local session = self.session
		self.session = nil
		setPhase("WaitingForPlayers", now, nil)
		if session then
			emit("MatchCleanup", { matchId = session.matchId })
		end
	end

	function self:tick(now: number)
		self.lastNow = now
		local phase = self.machine.phase
		if phase == "WaitingForPlayers" then
			if eligibleCount() >= minRequired() then
				local duration = if config.allowKeeperless and eligibleCount() < config.minPlayers
					then config.soloIntermissionDuration
					else config.intermissionDuration
				setPhase("Intermission", now, now + duration)
			end
		elseif phase == "Intermission" then
			if eligibleCount() < minRequired() then
				setPhase("WaitingForPlayers", now, nil)
			elseif self.phaseEndsAt ~= nil and now >= self.phaseEndsAt then
				beginRoleAssignment(now)
			end
		elseif phase == "RoleAssignment" then
			-- Role assignment is synchronous; reaching here means it was interrupted. Recover.
			setPhase("WaitingForPlayers", now, nil)
		elseif phase == "Intro" then
			local session = self.session :: Session
			checkOutcome(now)
			if self.machine.phase == "Intro" and self.phaseEndsAt ~= nil and now >= self.phaseEndsAt then
				beginActive(session, now)
			end
		elseif phase == "Active" or phase == "Extraction" then
			local session = self.session :: Session
			local dt = if session.lastTickAt then math.max(0, now - session.lastTickAt) else 0
			session.lastTickAt = now
			local function live(): boolean
				return session.result == nil and (self.machine.phase == "Active" or self.machine.phase == "Extraction")
			end
			processTerminals(session, now, dt)
			if live() then
				processActions(session, now, dt)
			end
			if live() then
				processSurvival(session, now, dt)
			end
			if live() then
				processRift(session, now)
				processCollapse(session, now)
				processExtraction(session, now)
			end
			checkOutcome(now)
		elseif phase == "Resolving" then
			if self.phaseEndsAt ~= nil and now >= self.phaseEndsAt then
				local session = self.session
				local returning: { number } = {}
				if session then
					for _, userId in session.order do
						if session.participants[userId].connected then
							table.insert(returning, userId)
						end
					end
				end
				setPhase("ReturningToLobby", now, now + config.returnToLobbyDuration)
				emit("ReturnToLobby", {
					matchId = if session then session.matchId else nil,
					userIds = returning,
				})
			end
		elseif phase == "ReturningToLobby" then
			if self.phaseEndsAt ~= nil and now >= self.phaseEndsAt then
				finishMatch(now)
			end
		end
	end

	function self:destroy()
		self.events:DisconnectAll()
		self.session = nil
	end

	return self :: MatchDirector
end

return MatchDirector
