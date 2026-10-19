--!strict
-- Vault terminal (hacking objective) tunables.

local TerminalConfig = {
	RequiredHacks = 4, -- of five terminals per map, so the Keeper must choose what to defend
	HackDuration = 40, -- solo seconds for a four-Infiltrator squad (SurvivalConfig squad scaling)
	MaxInteractionDistance = 12, -- studs, measured server-side from the hacker's root to the console
	PromptActivationDistance = 10, -- ProximityPrompt range (kept inside the server limit)
	InterruptLockout = 1.5, -- seconds a terminal stays "Interrupted" before it can be resumed
	ProgressBroadcastInterval = 0.25, -- minimum seconds between progress updates per terminal
	-- Progress is retained on interruption so a team can resume a partially hacked terminal.
	RetainProgressOnInterrupt = true,
	-- One primary plus assistants (SurvivalConfig.Objectives.MaxHackers); one terminal per player.
	CooperativeHacking = true,
	-- Calibration Pulses (SurvivalConfig.Calibration) during every hack.
	InteractiveChallenges = true,
}

return table.freeze(TerminalConfig)
