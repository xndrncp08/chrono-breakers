--!strict
-- The authoritative match phase machine. Only transitions listed in LEGAL are permitted; every
-- other request is rejected (returns false) and reported to the caller. See docs/ARCHITECTURE.md.
--
--   WaitingForPlayers -> Intermission            (queue reached MinPlayers)
--   Intermission      -> WaitingForPlayers       (queue dropped below MinPlayers)
--   Intermission      -> RoleAssignment          (countdown elapsed)
--   RoleAssignment    -> Intro                   (roles assigned)
--   RoleAssignment    -> WaitingForPlayers       (not enough eligible players after all)
--   Intro             -> Active                  (intro elapsed)
--   Intro|Active|Extraction -> Resolving         (outcome decided)
--   Active            -> Extraction              (required hacks completed)
--   Resolving         -> ReturningToLobby        (results shown)
--   ReturningToLobby  -> WaitingForPlayers       (cleanup finished)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)

type Phase = GameTypes.Phase

local LEGAL: { [Phase]: { [Phase]: boolean } } = {
	WaitingForPlayers = { Intermission = true },
	Intermission = { WaitingForPlayers = true, RoleAssignment = true },
	RoleAssignment = { Intro = true, WaitingForPlayers = true },
	Intro = { Active = true, Resolving = true },
	Active = { Extraction = true, Resolving = true },
	Extraction = { Resolving = true },
	Resolving = { ReturningToLobby = true },
	ReturningToLobby = { WaitingForPlayers = true },
}

local IN_MATCH: { [Phase]: boolean } = {
	Intro = true,
	Active = true,
	Extraction = true,
}

export type MatchStateMachine = {
	phase: Phase,
	enteredAt: number,
	history: { { from: Phase, to: Phase, at: number } },
	canTransition: (self: MatchStateMachine, to: Phase) -> boolean,
	transition: (self: MatchStateMachine, to: Phase, now: number) -> boolean,
	isInMatch: (self: MatchStateMachine) -> boolean,
}

local MatchStateMachine = {}
MatchStateMachine.LEGAL = LEGAL
MatchStateMachine.HISTORY_LIMIT = 64

function MatchStateMachine.isLegal(from: Phase, to: Phase): boolean
	local targets = LEGAL[from]
	return targets ~= nil and targets[to] == true
end

-- True while a match is being played (participants are in the vault).
function MatchStateMachine.isInMatchPhase(phase: Phase): boolean
	return IN_MATCH[phase] == true
end

function MatchStateMachine.new(now: number): MatchStateMachine
	local self = {
		phase = "WaitingForPlayers" :: Phase,
		enteredAt = now,
		history = {},
	} :: any

	function self:canTransition(to: Phase): boolean
		return MatchStateMachine.isLegal(self.phase, to)
	end

	function self:transition(to: Phase, at: number): boolean
		if not MatchStateMachine.isLegal(self.phase, to) then
			return false
		end
		table.insert(self.history, { from = self.phase, to = to, at = at })
		if #self.history > MatchStateMachine.HISTORY_LIMIT then
			table.remove(self.history, 1)
		end
		self.phase = to
		self.enteredAt = at
		return true
	end

	function self:isInMatch(): boolean
		return IN_MATCH[self.phase] == true
	end

	return self :: MatchStateMachine
end

return MatchStateMachine
