--!strict
-- Computes the reward breakdown and stat deltas for one participant from an authoritative result.
-- Pure: never touches profiles. Applying the reward (idempotently) is RewardLedger's job.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)

export type ResultLike = {
	matchId: string,
	winner: GameTypes.Team?,
	reason: GameTypes.ResolutionReason,
	rewardedAt: number?,
}

export type ParticipantLike = {
	userId: number,
	role: GameTypes.Role,
	status: GameTypes.ParticipantStatus,
	connected: boolean,
	hacks: number,
	eliminations: number,
	extracted: boolean,
	assists: number?,
	classId: string?,
	rescues: number?,
	revives: number?,
	heals: number?,
	downs: number?,
	containments: number?,
	greats: number?,
}

export type Breakdown = {
	eligible: boolean,
	xp: number,
	masteryId: string?,
	timestamp: number?,
	won: boolean,
	lines: { GameTypes.RewardLine },
	total: number,
	statDeltas: { [string]: number },
}

local RewardCalculator = {}

function RewardCalculator.didWin(role: GameTypes.Role, winner: GameTypes.Team?): boolean
	if winner == nil then
		return false
	end
	if role == "TimeKeeper" then
		return winner == "TimeKeeper"
	end
	return winner == "Infiltrators"
end

function RewardCalculator.compute(result: ResultLike, participant: ParticipantLike): Breakdown
	local won = RewardCalculator.didWin(participant.role, result.winner)
	local breakdown: Breakdown = {
		eligible = false,
		won = won,
		lines = {},
		total = 0,
		statDeltas = {},
		xp = 0,
		masteryId = if participant.role == "TimeKeeper" then "TimeKeeper" else participant.classId,
		timestamp = result.rewardedAt,
	}
	-- Aborted matches and players who left before the result are not eligible.
	if result.reason == "Aborted" or not participant.connected then
		return breakdown
	end
	breakdown.eligible = true
	local xp = ProgressionConfig.XP
	breakdown.xp = xp.Participation
		+ (if won then xp.Win else 0)
		+ participant.hacks * xp.Hack
		+ (participant.assists or 0) * xp.Assist
		+ participant.eliminations * xp.Elimination
		+ (if participant.extracted then xp.Extraction else 0)
		+ (participant.rescues or 0) * xp.Rescue
		+ (participant.revives or 0) * xp.Resync
		+ (participant.heals or 0) * xp.Patch
		+ (participant.greats or 0) * xp.Great
		+ (participant.downs or 0) * xp.Down
		+ (participant.containments or 0) * xp.Containment

	local function line(label: string, amount: number)
		if amount > 0 then
			table.insert(breakdown.lines, { label = label, amount = amount })
			breakdown.total += amount
		end
	end

	line("Participation", RewardConfig.Participation)
	if won then
		line("Victory", RewardConfig.Win)
	end
	if participant.role == "Infiltrator" then
		line(`Terminals hacked ×{participant.hacks}`, participant.hacks * RewardConfig.PerTerminalHacked)
		line(`Rescues ×{participant.rescues or 0}`, (participant.rescues or 0) * RewardConfig.PerRescue)
		line(`Re-syncs ×{participant.revives or 0}`, (participant.revives or 0) * RewardConfig.PerResync)
		if participant.extracted then
			line("Extracted", RewardConfig.Extracted)
		end
	else
		line(
			`Phase-Locks ×{participant.containments or 0}`,
			(participant.containments or 0) * RewardConfig.PerContainment
		)
		line(`Erasures ×{participant.eliminations}`, participant.eliminations * RewardConfig.PerElimination)
	end

	local deltas = breakdown.statDeltas
	deltas.HackAssists = participant.assists or 0
	deltas.KeeperWins = if won and participant.role == "TimeKeeper" then 1 else 0
	deltas.MatchesPlayed = 1
	deltas.Wins = if won then 1 else 0
	deltas.Losses = if won then 0 else 1
	deltas.TerminalsHacked = participant.hacks
	deltas.Extractions = if participant.extracted then 1 else 0
	deltas.Eliminations = participant.eliminations
	deltas.KeeperMatches = if participant.role == "TimeKeeper" then 1 else 0
	deltas.InfiltratorMatches = if participant.role == "Infiltrator" then 1 else 0
	deltas.Rescues = participant.rescues or 0
	deltas.Resyncs = participant.revives or 0
	deltas.Patches = participant.heals or 0
	deltas.Containments = participant.containments or 0
	deltas.Downs = participant.downs or 0
	deltas.GreatCalibrations = participant.greats or 0
	return breakdown
end

return table.freeze(RewardCalculator)
