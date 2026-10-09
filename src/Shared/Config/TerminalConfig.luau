--!strict
-- Vault terminal (hacking objective) tunables.

local TerminalConfig = {
	RequiredHacks = 3,
	HackDuration = 15, -- seconds of uninterrupted hacking to complete a terminal
	MaxInteractionDistance = 12, -- studs, measured server-side from the hacker's root to the console
	PromptActivationDistance = 10, -- ProximityPrompt range (kept inside the server limit)
	InterruptLockout = 1.5, -- seconds a terminal stays "Interrupted" before it can be resumed
	ProgressBroadcastInterval = 0.25, -- minimum seconds between progress updates per terminal
	-- Progress is retained on interruption so a team can resume a partially hacked terminal.
	RetainProgressOnInterrupt = true,
	-- One active hacker per terminal, one terminal per hacker.
	MaxHackersPerTerminal = 1,
}

return table.freeze(TerminalConfig)
