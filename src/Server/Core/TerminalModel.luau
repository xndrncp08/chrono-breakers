--!strict
-- Pure state machine for one vault terminal. Owns progress; knows nothing about Instances.
--
--   Locked      -> Available    (match becomes Active)
--   Available   -> Hacking      (validated hacker starts)
--   Hacking     -> Completed    (progress reached 1)
--   Hacking     -> Interrupted  (hacker invalidated: death, range, damage, stun, disconnect, cancel)
--   Interrupted -> Available    (lockout elapsed)
--   any         -> Locked       (match ended; lockAll) — Completed stays Completed
--
-- One primary channel plus assistants (MatchDirector caps them). Duplicate primary requests return
-- "Busy" (other player) or "AlreadyHacking" (same player). An Overloaded terminal regresses while
-- nobody hacks it; starting a hack clears the overload.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)

type TerminalState = GameTypes.TerminalState

local LEGAL: { [TerminalState]: { [TerminalState]: boolean } } = {
	Locked = { Available = true },
	Available = { Hacking = true, Locked = true },
	Hacking = { Completed = true, Interrupted = true, Locked = true },
	Interrupted = { Available = true, Locked = true },
	Completed = {},
}

export type TerminalModel = {
	id: string,
	name: string,
	state: TerminalState,
	progress: number,
	hackerUserId: number?,
	assistants: { number },
	regressing: boolean,
	lastProgressAt: number,
	interruptedUntil: number,
	lastInterruptReason: string?,
	lastBroadcastAt: number,
	completedBy: number?,

	canStart: (self: TerminalModel, userId: number) -> (boolean, string),
	start: (self: TerminalModel, userId: number, now: number) -> (boolean, string),
	advance: (self: TerminalModel, now: number, duration: number) -> boolean,
	interrupt: (self: TerminalModel, reason: string, now: number, lockout: number, retainProgress: boolean) -> boolean,
	tickLockout: (self: TerminalModel, now: number) -> boolean,
	unlock: (self: TerminalModel) -> boolean,
	lock: (self: TerminalModel) -> boolean,
	shouldBroadcast: (self: TerminalModel, now: number, interval: number) -> boolean,
	overload: (self: TerminalModel, instantLoss: number) -> boolean,
	regress: (self: TerminalModel, dt: number, rate: number) -> boolean,
	hasParticipant: (self: TerminalModel, userId: number) -> boolean,
	removeAssistant: (self: TerminalModel, userId: number) -> boolean,
}

local TerminalModel = {}
TerminalModel.LEGAL = LEGAL

function TerminalModel.isLegal(from: TerminalState, to: TerminalState): boolean
	local targets = LEGAL[from]
	return targets ~= nil and targets[to] == true
end

function TerminalModel.new(id: string, name: string): TerminalModel
	local self = {
		id = id,
		name = name,
		state = "Locked" :: TerminalState,
		progress = 0,
		hackerUserId = nil :: number?,
		assistants = {} :: { number },
		regressing = false,
		lastProgressAt = 0,
		interruptedUntil = 0,
		lastInterruptReason = nil :: string?,
		lastBroadcastAt = -math.huge,
		completedBy = nil :: number?,
	} :: any

	local function setState(to: TerminalState): boolean
		if not TerminalModel.isLegal(self.state, to) then
			return false
		end
		self.state = to
		return true
	end

	function self:canStart(userId: number): (boolean, string)
		if self.state == "Completed" then
			return false, "AlreadyCompleted"
		elseif self.state == "Hacking" then
			if self.hackerUserId == userId then
				return false, "AlreadyHacking"
			end
			return false, "Busy"
		elseif self.state ~= "Available" then
			return false, "Locked"
		end
		return true, "Ok"
	end

	function self:start(userId: number, now: number): (boolean, string)
		local ok, code = self:canStart(userId)
		if not ok then
			return false, code
		end
		setState("Hacking")
		self.hackerUserId = userId
		self.regressing = false
		self.lastProgressAt = now
		self.lastInterruptReason = nil
		self.lastBroadcastAt = -math.huge
		return true, "Ok"
	end

	-- Advances progress using server time. Returns true exactly once: on the tick that completes.
	function self:advance(now: number, duration: number): boolean
		if self.state ~= "Hacking" then
			return false
		end
		local dt = math.max(0, now - self.lastProgressAt)
		self.lastProgressAt = now
		if duration <= 0 then
			self.progress = 1
		else
			self.progress = math.min(1, self.progress + dt / duration)
		end
		-- Tolerate float drift from summing many tick-sized steps (0.1 s ticks can land on 0.99999…).
		if self.progress >= 1 - 1e-6 then
			self.progress = 1
			self.completedBy = self.hackerUserId
			self.hackerUserId = nil
			table.clear(self.assistants)
			self.regressing = false
			setState("Completed")
			return true
		end
		return false
	end

	function self:interrupt(reason: string, now: number, lockout: number, retainProgress: boolean): boolean
		if self.state ~= "Hacking" then
			return false
		end
		setState("Interrupted")
		self.hackerUserId = nil
		table.clear(self.assistants)
		self.lastInterruptReason = reason
		self.interruptedUntil = now + lockout
		if not retainProgress then
			self.progress = 0
		end
		self.lastBroadcastAt = -math.huge
		return true
	end

	-- Returns true when the terminal leaves the Interrupted lockout.
	function self:tickLockout(now: number): boolean
		if self.state == "Interrupted" and now >= self.interruptedUntil then
			return setState("Available")
		end
		return false
	end

	function self:unlock(): boolean
		if self.state == "Locked" then
			return setState("Available")
		end
		return false
	end

	function self:lock(): boolean
		if self.state == "Completed" or self.state == "Locked" then
			return false
		end
		self.hackerUserId = nil
		table.clear(self.assistants)
		self.regressing = false
		self.state = "Locked"
		return true
	end

	-- Keeper Overload: only an idle terminal with progress that is not already regressing.
	function self:overload(instantLoss: number): boolean
		if (self.state ~= "Available" and self.state ~= "Interrupted") or self.progress <= 0 or self.regressing then
			return false
		end
		self.regressing = true
		self.progress = math.max(0, self.progress - instantLoss)
		self.lastBroadcastAt = -math.huge
		return true
	end

	-- Returns true when regression stopped because progress reached zero.
	function self:regress(dt: number, rate: number): boolean
		if not self.regressing or self.state == "Hacking" then
			return false
		end
		self.progress = math.max(0, self.progress - dt * rate)
		if self.progress <= 0 then
			self.regressing = false
			return true
		end
		return false
	end

	function self:hasParticipant(userId: number): boolean
		return self.hackerUserId == userId or table.find(self.assistants, userId) ~= nil
	end

	function self:removeAssistant(userId: number): boolean
		local index = table.find(self.assistants, userId)
		if index then
			table.remove(self.assistants, index)
			return true
		end
		return false
	end

	function self:shouldBroadcast(now: number, interval: number): boolean
		if now - self.lastBroadcastAt >= interval then
			self.lastBroadcastAt = now
			return true
		end
		return false
	end

	return self :: TerminalModel
end

return TerminalModel
