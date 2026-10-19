--!strict
-- MatchDirector: the single authoritative owner of match flow, participants, roles, terminal
-- progress, extraction, and resolution. It is pure Luau (no Instance access): the Roblox-facing
-- MatchService feeds it world facts through the injected WorldQuery and turns its events into
-- world/network effects. This keeps every rule testable offline (see src/Tests).
--
-- Time is always passed in explicitly (`now`, server seconds). Each match has a unique matchId;
-- every event carries it so adapters can drop stale callbacks from a previous match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local ExtractionModel = require(script.Parent.ExtractionModel)
local MatchStateMachine = require(script.Parent.MatchStateMachine)
local ObjectiveTracker = require(script.Parent.ObjectiveTracker)
local QueueModel = require(script.Parent.QueueModel)
local RoleSelector = require(script.Parent.RoleSelector)
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
}

export type ResultParticipant = {
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

	tick: (self: MatchDirector, now: number) -> (),
	getPhase: (self: MatchDirector) -> Phase,
	isCurrentMatch: (self: MatchDirector, matchId: string?) -> boolean,
	getParticipant: (self: MatchDirector, userId: number) -> Participant?,
	isActiveParticipant: (self: MatchDirector, userId: number) -> boolean,
	getRole: (self: MatchDirector, userId: number) -> Role?,
	requestHackStart: (self: MatchDirector, userId: number, terminalId: string, now: number) -> (boolean, string),
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
			table.insert(list, { userId = p.userId, name = p.name, role = p.role, status = p.status })
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
		local active, extracted, eliminated, total = 0, 0, 0, 0
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

		if active == 0 then
			if extracted > 0 then
				resolve("Infiltrators", "Extracted", now)
			elseif eliminated > 0 then
				resolve("TimeKeeper", "AllEliminated", now)
			else
				resolve("TimeKeeper", "InfiltratorsLeft", now)
			end
			return
		end

		if phase == "Active" and session.deadline ~= nil and now >= session.deadline then
			resolve("TimeKeeper", "TimeExpired", now)
			return
		end

		if phase == "Extraction" and session.extraction:isExpired(now) then
			if extracted > 0 then
				resolve("Infiltrators", "Extracted", now)
			else
				resolve("TimeKeeper", "ExtractionFailed", now)
			end
		end
	end

	---------------------------------------------------------------------------
	-- Hacking
	---------------------------------------------------------------------------

	local function findHackedTerminal(session: Session, userId: number): TerminalModel.TerminalModel?
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal.state == "Hacking" and terminal.hackerUserId == userId then
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
	local function hackerInvalidReason(session: Session, terminal: TerminalModel.TerminalModel): string?
		local userId = terminal.hackerUserId
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
		if p.status ~= "Active" or not world.isAlive(userId) then
			return false, "NotAlive"
		end
		if world.isRestrained(userId) then
			return false, "Restrained"
		end
		local terminal = session.terminals[terminalId]
		if not terminal or not session.objectives:isRegistered(terminalId) then
			return false, "UnknownTarget"
		end
		local current = findHackedTerminal(session, userId)
		if current ~= nil then
			return false, "AlreadyHacking"
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
		interruptTerminal(session, terminal, reason, now)
		return true
	end

	function self:notifyDamage(userId: number, now: number)
		self:cancelHack(userId, "Damaged", now)
	end

	local function openExtraction(session: Session, now: number)
		if not session.extraction:activate(now, config.extractionWindow) then
			return
		end
		-- Remaining terminals no longer matter; lock them so nobody wastes time on them.
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal.state ~= "Completed" and terminal:lock() then
				emitTerminal(session, id, "ExtractionOpened")
			end
		end
		setPhase("Extraction", now, session.extraction.endsAt)
		emit("ExtractionOpened", { matchId = session.matchId, endsAt = session.extraction.endsAt })
	end

	local function processTerminals(session: Session, now: number)
		-- Progress earned after the match timer expired must not count, even if a server hitch
		-- delivers the tick late; a hack finishing exactly at the deadline still counts.
		if self.machine.phase == "Active" and session.deadline ~= nil then
			now = math.min(now, session.deadline)
		end
		for _, id in session.terminalOrder do
			local terminal = session.terminals[id]
			if terminal:tickLockout(now) then
				emitTerminal(session, id, nil)
			end
			if terminal.state == "Hacking" then
				local reason = hackerInvalidReason(session, terminal)
				if reason then
					interruptTerminal(session, terminal, reason, now)
				else
					local hacker = terminal.hackerUserId :: number
					if terminal:advance(now, config.hackDuration) then
						local accepted, thresholdReached = session.objectives:markComplete(id)
						if accepted then
							local p = session.participants[hacker]
							if p then
								p.hacks += 1
							end
							emit("TerminalCompleted", {
								matchId = session.matchId,
								terminalId = id,
								userId = hacker,
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
				local inZone = world.isAlive(userId) and world.isInExtractionZone(userId)
				local before = session.extraction:channelProgress(userId, now, config.extractionChannelTime)
				if session.extraction:update(userId, inZone, now, config.extractionChannelTime) then
					p.status = "Extracted"
					p.extracted = true
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
	-- Participants
	---------------------------------------------------------------------------

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
			interruptTerminal(session, terminal, "Eliminated", now)
		end
		p.status = "Eliminated"
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
			interruptTerminal(session, terminal, "Disconnected", now)
		end
		if p.status == "Active" then
			p.status = "Disconnected"
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
			}
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
		RoleSelector.recordMatch(self.roleHistory, roles)
		local session = createSession(roles, taken, now)
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
			processTerminals(session, now)
			if self.machine.phase == "Active" or self.machine.phase == "Extraction" then
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
