--!strict
-- Shared string enums for payloads, plus human-readable copy for server rejection codes.

local Protocol = {}

Protocol.QueueActions = table.freeze({ Join = "Join", Leave = "Leave" })
Protocol.ObjectiveActions = table.freeze({ Cancel = "Cancel" })
Protocol.ShopActions = table.freeze({ Purchase = "Purchase", Equip = "Equip" })

Protocol.NotifyKinds = table.freeze({
	Toast = "Toast", -- small transient message
	Announcement = "Announcement", -- large centred banner
	Warning = "Warning", -- danger-coloured toast
})

Protocol.EffectKinds = table.freeze({
	FreezeTelegraph = "FreezeTelegraph",
	FreezeActive = "FreezeActive",
	FreezeEnd = "FreezeEnd",
	TrapPlaced = "TrapPlaced",
	TrapTriggered = "TrapTriggered",
	Strike = "Strike",
	Hit = "Hit",
	GadgetUsed = "GadgetUsed",
	Reveal = "Reveal",
	ExtractionOpened = "ExtractionOpened",
	PlayerExtracted = "PlayerExtracted",
	PlayerEliminated = "PlayerEliminated",
	TerminalCompleted = "TerminalCompleted",
})

-- Rejection codes returned to clients. Text is shown verbatim in toasts.
Protocol.Codes = table.freeze({
	Ok = "Ok",
	RateLimited = "RateLimited",
	InvalidPayload = "InvalidPayload",
	WrongPhase = "WrongPhase",
	NotParticipant = "NotParticipant",
	WrongRole = "WrongRole",
	NotAlive = "NotAlive",
	OutOfRange = "OutOfRange",
	OnCooldown = "OnCooldown",
	Busy = "Busy",
	AlreadyCompleted = "AlreadyCompleted",
	Locked = "Locked",
	AlreadyHacking = "AlreadyHacking",
	UnknownTarget = "UnknownTarget",
	InvalidPlacement = "InvalidPlacement",
	NoLineOfSight = "NoLineOfSight",
	OutOfBounds = "OutOfBounds",
	LimitReached = "LimitReached",
	Restrained = "Restrained",
	AlreadyQueued = "AlreadyQueued",
	NotQueued = "NotQueued",
	InMatch = "InMatch",
	NotOwned = "NotOwned",
	AlreadyOwned = "AlreadyOwned",
	InsufficientFunds = "InsufficientFunds",
	UnknownItem = "UnknownItem",
	ProfileUnavailable = "ProfileUnavailable",
	NoTarget = "NoTarget",
	TooClose = "TooClose",
})

Protocol.CodeMessages = table.freeze({
	RateLimited = "Slow down — too many requests.",
	InvalidPayload = "That request was invalid.",
	WrongPhase = "You can't do that right now.",
	NotParticipant = "You're not part of this match.",
	WrongRole = "Your role can't do that.",
	NotAlive = "You need to be alive to do that.",
	OutOfRange = "Too far away.",
	OnCooldown = "Still recharging.",
	Busy = "Someone else is already hacking this terminal.",
	AlreadyCompleted = "This terminal is already breached.",
	Locked = "This terminal is locked right now.",
	AlreadyHacking = "You're already hacking a terminal.",
	UnknownTarget = "Target not found.",
	InvalidPlacement = "Can't place that there.",
	NoLineOfSight = "No line of sight to that spot.",
	OutOfBounds = "That spot is outside the vault.",
	LimitReached = "Limit reached for that ability.",
	Restrained = "You're restrained by a temporal effect.",
	AlreadyQueued = "You're already in the queue.",
	NotQueued = "You're not in the queue.",
	InMatch = "You're already in a match.",
	NotOwned = "You don't own that item.",
	AlreadyOwned = "You already own that item.",
	InsufficientFunds = "Not enough Chronos Scrap.",
	UnknownItem = "Unknown item.",
	ProfileUnavailable = "Your profile isn't available right now.",
	NoTarget = "No Infiltrator in reach.",
	TooClose = "Too close to another trap or objective.",
} :: { [string]: string })

function Protocol.messageFor(code: string): string
	return Protocol.CodeMessages[code] or "Request rejected."
end

return table.freeze(Protocol)
