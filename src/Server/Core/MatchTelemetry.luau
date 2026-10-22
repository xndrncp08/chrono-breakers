--!strict
-- MatchTelemetry: aggregates one match into an anonymous balance summary (pure).
-- Fed with MatchDirector events (`observe`), chase transitions and ability uses; `summary` returns
-- counts and durations only — never user ids or names — so it is safe to log and aggregate.
-- Metrics are described in docs/BALANCE.md ("Telemetry").

export type ClassStats = { picked: number, extracted: number, erased: number }

export type Summary = {
	mapId: string,
	squad: number,
	durationSec: number,
	winner: string,
	reason: string,
	extracted: number,
	erased: number,
	terminals: number,
	firstTerminalSec: number?,
	hits: number,
	downs: number,
	containments: number,
	rescues: number,
	campReleases: number,
	bleedOuts: number,
	tunnelHits: number, -- hits on an Infiltrator within TunnelWindow seconds of their rescue
	chases: number,
	avgChaseSec: number,
	maxChaseSec: number,
	calibration: { [string]: number },
	abilities: { [string]: number },
	classes: { [string]: ClassStats },
	disconnects: { [string]: number },
}

export type MatchTelemetry = {
	observe: (self: MatchTelemetry, name: string, payload: any, now: number) -> (),
	chase: (self: MatchTelemetry, userId: number, started: boolean, now: number) -> (),
	ability: (self: MatchTelemetry, abilityId: string) -> (),
	summary: (self: MatchTelemetry, now: number) -> Summary?,
}

local MatchTelemetry = {}

MatchTelemetry.TunnelWindow = 15

-- `classOf` maps an Infiltrator's user id to their class id (nil for the Keeper).
function MatchTelemetry.new(mapId: string, classOf: (number) -> string?): MatchTelemetry
	local startedAt: number? = nil
	local result: any = nil
	local roles: { [number]: string } = {}
	local classes: { [number]: string } = {} -- captured at match start; players may leave later
	local rescuedAt: { [number]: number } = {}
	local chaseFrom: { [number]: number } = {}
	local chaseTotal, chaseMax, chaseCount = 0, 0, 0
	local s: Summary = {
		mapId = mapId,
		squad = 0,
		durationSec = 0,
		winner = "None",
		reason = "None",
		extracted = 0,
		erased = 0,
		terminals = 0,
		firstTerminalSec = nil,
		hits = 0,
		downs = 0,
		containments = 0,
		rescues = 0,
		campReleases = 0,
		bleedOuts = 0,
		tunnelHits = 0,
		chases = 0,
		avgChaseSec = 0,
		maxChaseSec = 0,
		calibration = { Great = 0, Good = 0, Miss = 0 },
		abilities = {},
		classes = {},
		disconnects = { Infiltrator = 0, TimeKeeper = 0 },
	}

	local function classStats(userId: number): ClassStats?
		local classId = classes[userId]
		if not classId then
			return nil
		end
		local stats = s.classes[classId]
		if not stats then
			stats = { picked = 0, extracted = 0, erased = 0 }
			s.classes[classId] = stats
		end
		return stats
	end

	local function closeChase(userId: number, now: number)
		local from = chaseFrom[userId]
		if from then
			chaseFrom[userId] = nil
			local length = math.max(0, now - from)
			chaseTotal += length
			chaseMax = math.max(chaseMax, length)
			chaseCount += 1
		end
	end

	local self = {} :: any

	function self:observe(name: string, payload: any, now: number)
		if type(payload) ~= "table" then
			return
		end
		if name == "MatchStarted" then
			startedAt = now
			for userId, role in payload.roles or {} do
				roles[userId] = role
				if role == "Infiltrator" then
					s.squad += 1
					classes[userId] = classOf(userId) :: string
					local stats = classStats(userId)
					if stats then
						stats.picked += 1
					end
				end
			end
		elseif startedAt == nil or result ~= nil then
			return -- only events inside the match window count
		elseif name == "ConditionChanged" then
			local cause = payload.cause
			if cause == "Strike" or cause == "Endured" then
				s.hits += 1
				local rescued = rescuedAt[payload.userId]
				if rescued and now - rescued <= MatchTelemetry.TunnelWindow then
					s.tunnelHits += 1
				end
				if payload.condition == "Downed" then
					s.downs += 1
				end
			end
		elseif name == "PlayerContained" then
			s.containments += 1
			if payload.by == nil then
				s.bleedOuts += 1
			end
			closeChase(payload.userId, now)
		elseif name == "PlayerRescued" then
			rescuedAt[payload.userId] = now
			if payload.cause == "Feedback" then
				s.campReleases += 1
			else
				s.rescues += 1
			end
		elseif name == "TerminalCompleted" then
			s.terminals += 1
			if s.firstTerminalSec == nil then
				s.firstTerminalSec = math.floor(now - (startedAt :: number) + 0.5)
			end
		elseif name == "CalibrationResult" then
			local grade = payload.grade
			if type(grade) == "string" and s.calibration[grade] ~= nil then
				s.calibration[grade] += 1
			end
		elseif name == "PlayerExtracted" then
			s.extracted += 1
			local stats = classStats(payload.userId)
			if stats then
				stats.extracted += 1
			end
			closeChase(payload.userId, now)
		elseif name == "PlayerEliminated" then
			s.erased += 1
			local stats = classStats(payload.userId)
			if stats then
				stats.erased += 1
			end
			closeChase(payload.userId, now)
		elseif name == "ParticipantLeft" then
			local role = payload.role or roles[payload.userId]
			if role == "Infiltrator" or role == "TimeKeeper" then
				s.disconnects[role] += 1
			end
			closeChase(payload.userId, now)
		elseif name == "MatchResolved" then
			result = payload
			s.winner = if type(payload.winner) == "string" then payload.winner else "None"
			s.reason = if type(payload.reason) == "string" then payload.reason else "None"
		end
	end

	function self:chase(userId: number, started: boolean, now: number)
		if startedAt == nil or result ~= nil then
			return
		end
		if started then
			chaseFrom[userId] = chaseFrom[userId] or now
		else
			closeChase(userId, now)
		end
	end

	function self:ability(abilityId: string)
		if startedAt ~= nil and result == nil then
			s.abilities[abilityId] = (s.abilities[abilityId] or 0) + 1
		end
	end

	function self:summary(now: number): Summary?
		if startedAt == nil then
			return nil
		end
		for userId in chaseFrom do
			closeChase(userId, now)
		end
		s.durationSec = math.floor(now - (startedAt :: number) + 0.5)
		s.chases = chaseCount
		s.avgChaseSec = if chaseCount > 0 then math.floor(chaseTotal / chaseCount * 10 + 0.5) / 10 else 0
		s.maxChaseSec = math.floor(chaseMax * 10 + 0.5) / 10
		return s
	end

	return self :: MatchTelemetry
end

export type Aggregate = {
	matches: number,
	keeperWinRate: number,
	avgDurationSec: number,
	avgExtracted: number,
	avgTerminals: number,
	avgChaseSec: number,
	hitsPerMatch: number,
	rescuesPerMatch: number,
	campReleasesPerMatch: number,
	tunnelHitShare: number, -- tunnel hits / all hits
	disconnectsPerMatch: number,
	byMap: { [string]: { matches: number, keeperWins: number } },
}

local function ratio(a: number, b: number): number
	return if b > 0 then math.floor(a / b * 1000 + 0.5) / 1000 else 0
end

-- Rolls many summaries into the headline balance numbers (docs/BALANCE.md lists the targets).
function MatchTelemetry.aggregate(summaries: { Summary }): Aggregate
	local n = #summaries
	local keeperWins, duration, extracted, terminals, hits, rescues, camps, tunnels, leaves = 0, 0, 0, 0, 0, 0, 0, 0, 0
	local chaseTime, chases = 0, 0
	local byMap: { [string]: { matches: number, keeperWins: number } } = {}
	for _, summary in summaries do
		local won = summary.winner == "TimeKeeper"
		keeperWins += if won then 1 else 0
		duration += summary.durationSec
		extracted += summary.extracted
		terminals += summary.terminals
		hits += summary.hits
		rescues += summary.rescues
		camps += summary.campReleases
		tunnels += summary.tunnelHits
		leaves += summary.disconnects.Infiltrator + summary.disconnects.TimeKeeper
		chaseTime += summary.avgChaseSec * summary.chases
		chases += summary.chases
		local map = byMap[summary.mapId] or { matches = 0, keeperWins = 0 }
		map.matches += 1
		map.keeperWins += if won then 1 else 0
		byMap[summary.mapId] = map
	end
	return {
		matches = n,
		keeperWinRate = ratio(keeperWins, n),
		avgDurationSec = ratio(duration, n),
		avgExtracted = ratio(extracted, n),
		avgTerminals = ratio(terminals, n),
		avgChaseSec = ratio(chaseTime, chases),
		hitsPerMatch = ratio(hits, n),
		rescuesPerMatch = ratio(rescues, n),
		campReleasesPerMatch = ratio(camps, n),
		tunnelHitShare = ratio(tunnels, hits),
		disconnectsPerMatch = ratio(leaves, n),
		byMap = byMap,
	}
end

return table.freeze(MatchTelemetry)
