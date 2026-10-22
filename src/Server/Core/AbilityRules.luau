--!strict
-- Pure ability legality checks shared by every ability/gadget, plus Chrono Strike target selection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)

export type CasterContext = {
	matchId: string?,
	currentMatchId: string?,
	abilityId: any, -- untrusted
	phase: string,
	role: string?, -- nil when not a participant
	participantActive: boolean,
	alive: boolean,
	restrained: boolean,
	cooldownReady: boolean,
	equippedGadget: string?,
	classAbility: string?,
	free: boolean?, -- false while Desynced or In Stasis (nil = not tracked, treated as free)
}

-- `rewound` is where the Keeper saw the target (lag compensation); `position` is the server's now.
export type StrikeCandidate = { userId: number, position: Vector3, rewound: Vector3? }

local AbilityRules = {}

local CASTABLE_PHASES = { Active = true, Extraction = true }

-- Returns (ok, code). Checks run cheapest/most-informative first.
function AbilityRules.checkCaster(ctx: CasterContext): (boolean, string)
	if type(ctx.abilityId) ~= "string" then
		return false, "InvalidPayload"
	end
	local definition = AbilityConfig.get(ctx.abilityId)
	if definition == nil then
		return false, "InvalidPayload"
	end
	if ctx.currentMatchId and ctx.matchId ~= ctx.currentMatchId then
		return false, "StaleRequest"
	end
	if not CASTABLE_PHASES[ctx.phase] then
		return false, "WrongPhase"
	end
	if ctx.role == nil then
		return false, "NotParticipant"
	end
	if definition.Role ~= ctx.role then
		return false, "WrongRole"
	end
	if ctx.role == "Infiltrator" and ctx.equippedGadget ~= ctx.abilityId and ctx.classAbility ~= ctx.abilityId then
		return false, "NotOwned"
	end
	if not ctx.participantActive or not ctx.alive or ctx.free == false then
		return false, "NotAlive"
	end
	if ctx.restrained then
		return false, "Restrained"
	end
	if not ctx.cooldownReady then
		return false, "OnCooldown"
	end
	return true, "Ok"
end

-- Picks the nearest candidate within `range` whose horizontal bearing is inside the aim cone and
-- who is visible. `aim` must already be validated as a non-degenerate direction.
-- Lag compensation: a candidate also qualifies at its `rewound` position, but only while its current
-- position is still within `range + rewindSlack` and `visible` (always judged at the current
-- position), so nobody is hit through the wall they already rounded or from far behind them.
function AbilityRules.selectStrikeTarget(
	origin: Vector3,
	aim: Vector3,
	candidates: { StrikeCandidate },
	range: number,
	coneDegrees: number,
	visible: (StrikeCandidate) -> boolean,
	rewindSlack: number?
): number?
	local flatAim = Vector3.new(aim.X, 0, aim.Z)
	if flatAim.Magnitude < 1e-3 then
		return nil
	end
	flatAim = flatAim.Unit
	local cosLimit = math.cos(math.rad(coneDegrees / 2))
	local function reach(position: Vector3): number?
		local offset = position - origin
		local distance = offset.Magnitude
		if distance > range then
			return nil
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		-- Targets practically on top of the caster are always inside the cone.
		if flat.Magnitude < 1.5 or flat.Unit:Dot(flatAim) >= cosLimit then
			return distance
		end
		return nil
	end
	local bestId: number? = nil
	local bestDistance = math.huge
	for _, candidate in candidates do
		local distance = reach(candidate.position)
		local rewound = candidate.rewound
		if rewound and (candidate.position - origin).Magnitude <= range + (rewindSlack or 0) then
			local past = reach(rewound)
			if past and (distance == nil or past < distance) then
				distance = past
			end
		end
		if distance and distance < bestDistance and visible(candidate) then
			bestDistance = distance
			bestId = candidate.userId
		end
	end
	return bestId
end

return table.freeze(AbilityRules)
