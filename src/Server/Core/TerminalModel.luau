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
-- One primary channel; MatchDirector owns the optional assistant slot. Duplicate primary requests return
-- "Busy" (other player) or "AlreadyHacking" (same player).

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
	assistantUserId: number?,
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
		assistantUserId = nil :: number?,
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
			self.assistantUserId = nil
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
		self.assistantUserId = nil
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
		self.assistantUserId = nil
		self.state = "Locked"
		return true
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
