--!strict
local PlacementRules = require(script.Parent.PlacementRules)
local Validate = require(script.Parent.Validate)
local MovementRules = {}
function MovementRules.valid(
	from: Vector3,
	to: any,
	elapsed: number,
	speed: number,
	minimum: Vector3,
	maximum: Vector3,
	tolerance: number,
	slack: number
): boolean
	if not Validate.isFiniteVector3(to) or not PlacementRules.isInsideBounds(to, minimum, maximum) then
		return false
	end
	local delta = to - from
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= speed * math.max(0, elapsed) * tolerance + slack
end
return table.freeze(MovementRules)
