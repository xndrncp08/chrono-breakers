--!strict
-- Pure placement validation for ground-targeted abilities. World access (raycasts) is injected so
-- the rules can be unit-tested. The rule (documented in docs/GAME_DESIGN.md):
--   1. Target must be a finite Vector3.
--   2. Horizontal distance from the caster must be within the ability's MaxCastRange.
--   3. Target must be inside the vault's playable bounds.
--   4. A downward probe from just above the target must hit a walkable surface (normal.Y >= 0.7)
--      within PROBE_DEPTH studs; the hit point becomes the authoritative placement position.
--   5. The caster's eye must have line of sight to a point just above the placement position.
-- The client-supplied position is only a hint; the server-derived ground position is what is used.

local Validate = require(script.Parent.Validate)

export type GroundHit = { position: Vector3, normal: Vector3 }

export type PlacementInput = {
	casterPosition: Vector3,
	eyePosition: Vector3,
	target: any, -- untrusted
	maxRange: number,
	boundsMin: Vector3,
	boundsMax: Vector3,
	castDown: (from: Vector3, depth: number) -> GroundHit?,
	lineOfSight: (from: Vector3, to: Vector3) -> boolean,
}

local PlacementRules = {}

PlacementRules.PROBE_HEIGHT = 3
PlacementRules.PROBE_DEPTH = 10
PlacementRules.MIN_WALKABLE_NORMAL_Y = 0.7
PlacementRules.RANGE_TOLERANCE = 1
PlacementRules.LOS_CLEARANCE = 1.5

function PlacementRules.horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function PlacementRules.isInsideBounds(position: Vector3, boundsMin: Vector3, boundsMax: Vector3): boolean
	return position.X >= boundsMin.X
		and position.X <= boundsMax.X
		and position.Y >= boundsMin.Y
		and position.Y <= boundsMax.Y
		and position.Z >= boundsMin.Z
		and position.Z <= boundsMax.Z
end

-- Returns (ok, code, groundPosition).
function PlacementRules.validateGroundTarget(input: PlacementInput): (boolean, string, Vector3?)
	if not Validate.isFiniteVector3(input.target) then
		return false, "InvalidPayload", nil
	end
	local target = input.target :: Vector3
	if
		PlacementRules.horizontalDistance(input.casterPosition, target)
		> input.maxRange + PlacementRules.RANGE_TOLERANCE
	then
		return false, "OutOfRange", nil
	end
	if not PlacementRules.isInsideBounds(target, input.boundsMin, input.boundsMax) then
		return false, "OutOfBounds", nil
	end
	local hit = input.castDown(target + Vector3.new(0, PlacementRules.PROBE_HEIGHT, 0), PlacementRules.PROBE_DEPTH)
	if hit == nil then
		return false, "InvalidPlacement", nil
	end
	if hit.normal.Y < PlacementRules.MIN_WALKABLE_NORMAL_Y then
		return false, "InvalidPlacement", nil
	end
	local ground = hit.position
	if not PlacementRules.isInsideBounds(ground, input.boundsMin, input.boundsMax) then
		return false, "OutOfBounds", nil
	end
	if not input.lineOfSight(input.eyePosition, ground + Vector3.new(0, PlacementRules.LOS_CLEARANCE, 0)) then
		return false, "NoLineOfSight", nil
	end
	return true, "Ok", ground
end

-- True when `position` is at least `minDistance` (horizontal) from every point.
function PlacementRules.isClearOf(position: Vector3, points: { Vector3 }, minDistance: number): boolean
	for _, point in points do
		if PlacementRules.horizontalDistance(position, point) < minDistance then
			return false
		end
	end
	return true
end

-- Cylinder membership used by area effects: horizontal radius plus a vertical tolerance.
function PlacementRules.isInsideCylinder(center: Vector3, radius: number, height: number, position: Vector3): boolean
	if math.abs(position.Y - center.Y) > height then
		return false
	end
	return PlacementRules.horizontalDistance(center, position) <= radius
end

return table.freeze(PlacementRules)
