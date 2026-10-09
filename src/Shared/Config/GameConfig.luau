--!strict
-- Central match-flow tunables. Every timer, threshold, and player-count rule lives here.
-- See docs/BALANCE.md for the rationale behind each value.

local GameConfig = {
	GameTitle = "Chrono Breakers: Temporal Heist",
	GameSubtitle = "Temporal Heist",

	-- Participants
	MinPlayers = 2, -- 1 Time-Keeper + at least 1 Infiltrator
	MaxPlayers = 5, -- 1 Time-Keeper + up to 4 Infiltrators
	KeeperCount = 1,

	-- Phase durations (seconds, server time)
	IntermissionDuration = 15,
	IntroDuration = 8,
	MatchDuration = 600,
	ExtractionWindow = 60,
	ResultsDuration = 12,
	ReturnToLobbyDuration = 3,

	-- Time-Keeper is held in the Sanctum for this long after Active begins (anti spawn-camp).
	KeeperReleaseDelay = 10,
	-- Infiltrators cannot be damaged for this long after Active begins.
	InfiltratorSpawnProtection = 8,

	-- Extraction
	ExtractionChannelTime = 3, -- seconds a living Infiltrator must stay inside the zone

	-- Server tick for match logic (hack progress, zone membership, outcome checks).
	DirectorTickInterval = 0.1,
	-- Snapshot broadcast cadence for non-critical state (critical changes are pushed immediately).
	SnapshotInterval = 1,

	-- Elimination attribution window for Time-Keeper elimination credit.
	DamageAttributionWindow = 10,

	-- Studio-only conveniences. These are ignored on live servers (RunService:IsStudio() is checked).
	Studio = table.freeze({
		-- Allows a single queued player to start a match as an Infiltrator with no Time-Keeper,
		-- so the objective/extraction loop can be exercised solo in Studio.
		AllowSoloMatch = true,
		SoloIntermissionDuration = 5,
	}),
}

return table.freeze(GameConfig)
