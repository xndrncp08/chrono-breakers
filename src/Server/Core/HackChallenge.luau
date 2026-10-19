--!strict
-- Calibration Pulses: server-issued timing checks during a hack (pure).
-- After a short audible warning a needle sweeps a ring once; the hacker presses while it crosses the
-- marked arc. The leading GreatFraction of the arc is a Great. The server judges a press by the
-- claimed press time, bounded to LatencyAllowance before arrival (anything else uses arrival time),
-- so honest latency is forgiven while a client cannot rewind further than that allowance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type Challenge = {
	nonce: number,
	mode: string,
	startAt: number,
	sweep: number,
	direction: number,
	arcStart: number,
	arcWidth: number,
	opensAt: number,
	greatUntil: number,
	closesAt: number,
	expiresAt: number,
	used: boolean,
}

local HackChallenge = {}
local config = SurvivalConfig.Calibration

HackChallenge.SEEDS = 9 -- distinct arc placements; callers pass seed in 1..SEEDS

function HackChallenge.arcWidth(mode: string, completed: number): number
	local flavour = (config.Flavours :: any)[mode] or config.Flavours.Timing
	local base = math.max(config.MinArc, config.BaseArc - completed * config.ArcShrinkPerTerminal)
	return base * flavour.ArcScale
end

function HackChallenge.new(
	mode: string,
	nonce: number,
	now: number,
	seed: number,
	completed: number,
	arcScale: number?
): Challenge
	local flavour = (config.Flavours :: any)[mode]
	if flavour == nil then
		mode = "Timing"
		flavour = config.Flavours.Timing
	end
	local sweep = flavour.Sweep
	local width = math.min(120, HackChallenge.arcWidth(mode, completed) * (arcScale or 1))
	-- Arc starts between 100° and 276° so there is always a readable lead-in.
	local arcStart = 100 + ((seed - 1) % HackChallenge.SEEDS) * 22
	local startAt = now + config.Warning
	local opensAt = startAt + arcStart / 360 * sweep
	local closesAt = opensAt + width / 360 * sweep
	return {
		nonce = nonce,
		mode = mode,
		startAt = startAt,
		sweep = sweep,
		direction = flavour.Direction,
		arcStart = arcStart,
		arcWidth = width,
		opensAt = opensAt,
		greatUntil = opensAt + width * config.GreatFraction / 360 * sweep,
		closesAt = closesAt,
		expiresAt = startAt + sweep + 0.25,
		used = false,
	}
end

-- Returns (ok, code, grade) where grade is "Great", "Good" or "Miss".
function HackChallenge.respond(
	challenge: Challenge,
	nonce: number,
	pressTime: number,
	now: number
): (boolean, string, string?)
	if challenge.used or nonce ~= challenge.nonce then
		return false, "StaleRequest", nil
	end
	if now > challenge.expiresAt + config.LatencyAllowance then
		return false, "StaleRequest", nil
	end
	local effective = pressTime
	if pressTime ~= pressTime or pressTime > now + 0.05 or pressTime < now - config.LatencyAllowance then
		effective = now
	end
	challenge.used = true
	if effective >= challenge.opensAt and effective <= challenge.closesAt then
		return true, "Ok", if effective <= challenge.greatUntil then "Great" else "Good"
	end
	return false, "ChallengeFailed", "Miss"
end

function HackChallenge.isExpired(challenge: Challenge, now: number): boolean
	return not challenge.used and now > challenge.expiresAt + config.LatencyAllowance
end

function HackChallenge.public(challenge: Challenge): any
	return {
		nonce = challenge.nonce,
		mode = challenge.mode,
		startAt = challenge.startAt,
		sweep = challenge.sweep,
		direction = challenge.direction,
		arcStart = challenge.arcStart,
		arcWidth = challenge.arcWidth,
		greatWidth = challenge.arcWidth * config.GreatFraction,
	}
end

return table.freeze(HackChallenge)
