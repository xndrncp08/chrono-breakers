--!strict
-- Field Guide: contextual coaching for a player's first matches in each role. Tips fire once per
-- match on real moments (first calibration, first chase, a teammate in a pod...), never on a timer.
-- Shown while the player's match count for that role is below GuidedMatches and the
-- ShowControlHints setting is on. Text uses the default keyboard binds; gamepad/touch equivalents
-- are listed in each tip where they differ.

export type Tip = { Id: string, Title: string, Text: string }

local CoachConfig = {}

CoachConfig.GuidedMatches = 3
CoachConfig.Duration = 8 -- seconds a card stays up
CoachConfig.Gap = 2.5 -- minimum seconds between two cards

local function tip(id: string, title: string, text: string): Tip
	return table.freeze({ Id = id, Title = title, Text = text })
end

CoachConfig.Infiltrator = table.freeze({
	Start = tip(
		"Start",
		"BREACH THE VAULT",
		"Hack 4 of 5 terminals: hold E (X / tap) at a terminal. Stay together — two hackers are faster."
	),
	Calibration = tip(
		"Calibration",
		"CALIBRATION PULSE",
		"Press Space (A / tap the ring) while the needle is inside the bright arc. Misses cost progress and show the Keeper where you are."
	),
	Resonance = tip(
		"Resonance",
		"TEMPORAL RESONANCE",
		"The heartbeat means the Time-Keeper is close. Break line of sight and save your sprint until you are chased."
	),
	Chased = tip(
		"Chased",
		"YOU ARE PURSUED",
		"Run to rails and barriers: vault (E), then drop a Stasis Barrier on the Keeper. Vaulting the same rail three times seals it."
	),
	Injured = tip(
		"Injured",
		"FRACTURED",
		"One more hit Desyncs you. Find an ally to Patch you, or hide in a Phase Locker until the Keeper moves on."
	),
	Downed = tip(
		"Downed",
		"DESYNCED",
		"Crawl toward cover and teammates. An ally can Re-sync you before the Keeper Phase-Locks you."
	),
	AllyPod = tip(
		"AllyPod",
		"TEAMMATE IN STASIS",
		"Rescue them at the pod (E) before the timer ends. If the Keeper camps it, the pod drains slower and releases them."
	),
	Collapse = tip(
		"Collapse",
		"TEMPORAL COLLAPSE",
		"Power a Gate Relay together, then stand on the Breach Gate pad. Anyone still inside when the timer ends is Erased."
	),
})

CoachConfig.TimeKeeper = table.freeze({
	Start = tip(
		"Start",
		"HUNT THE BREAKERS",
		"Glowing residue shows where Infiltrators sprinted. Patrol terminals; failed calibrations flash on your screen."
	),
	Chase = tip(
		"Chase",
		"CHRONO STRIKE",
		"Click (R2) to strike. It winds up, so aim where they are going, not where they are. Hunt Momentum builds while you chase."
	),
	Stunned = tip(
		"Stunned",
		"BARRIER STUN",
		"Dropped Stasis Barriers stun you. Break them (E) or path around — rails cost you far more time than them."
	),
	Downed = tip(
		"Downed",
		"TARGET DESYNCED",
		"Walk up and Phase-Lock them (E) into a Stasis Pod. Allies can interrupt you with barriers and Disruption Pulses."
	),
	Contained = tip(
		"Contained",
		"DON'T CAMP",
		"Waiting by a pod slows its timer and builds feedback that frees the captive. Pressure terminals instead."
	),
	Collapse = tip(
		"Collapse",
		"COLLAPSE",
		"Guard the Gate Relays and the Breach Gate. Shockwaves late in the Collapse reveal every free Infiltrator."
	),
})

-- True while this role still gets guided matches.
function CoachConfig.isGuided(stats: any, role: string?): boolean
	if type(stats) ~= "table" then
		return false
	end
	local played = if role == "TimeKeeper"
		then stats.KeeperMatches
		elseif role == "Infiltrator" then stats.InfiltratorMatches
		else nil
	return type(played) == "number" and played < CoachConfig.GuidedMatches
end

function CoachConfig.tip(role: string?, id: string): Tip?
	local set = if role == "TimeKeeper"
		then CoachConfig.TimeKeeper
		elseif role == "Infiltrator" then CoachConfig.Infiltrator
		else nil
	return if set then (set :: any)[id] else nil
end

return table.freeze(CoachConfig)
