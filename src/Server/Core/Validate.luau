--!strict
-- Defensive type guards for untrusted client payloads. Every client->server handler runs its
-- arguments through these before touching game state.

local Validate = {}

Validate.MAX_STRING_LENGTH = 64
Validate.MAX_COORDINATE = 100_000

function Validate.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isNumberInRange(value: any, min: number, max: number): boolean
	return Validate.isFiniteNumber(value) and value >= min and value <= max
end

function Validate.isInteger(value: any, min: number, max: number): boolean
	return Validate.isNumberInRange(value, min, max) and math.floor(value) == value
end

function Validate.isShortString(value: any, maxLength: number?): boolean
	local limit = maxLength or Validate.MAX_STRING_LENGTH
	return type(value) == "string" and #value > 0 and #value <= limit
end

function Validate.isOneOf(value: any, options: { [string]: any }): boolean
	return type(value) == "string" and options[value] ~= nil
end

function Validate.isFiniteVector3(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	local m = Validate.MAX_COORDINATE
	return Validate.isNumberInRange(v.X, -m, m)
		and Validate.isNumberInRange(v.Y, -m, m)
		and Validate.isNumberInRange(v.Z, -m, m)
end

-- A non-degenerate direction vector (normalised by the caller).
function Validate.isDirection(value: any): boolean
	return Validate.isFiniteVector3(value) and (value :: Vector3).Magnitude > 1e-3
end

-- Validates a table with only the allowed string keys and at most `maxKeys` entries.
function Validate.isPlainTable(value: any, allowedKeys: { [string]: boolean }, maxKeys: number): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	local count = 0
	for key in value do
		count += 1
		if count > maxKeys or type(key) ~= "string" or not allowedKeys[key] then
			return false
		end
	end
	return true
end

-- Remote handlers receive varargs; reject calls with unexpected extra arguments.
function Validate.argCount(expectedMax: number, ...: any): boolean
	return select("#", ...) <= expectedMax
end

return table.freeze(Validate)
