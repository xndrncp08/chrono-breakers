--!strict
-- Server-authoritative cooldowns keyed by string (e.g. "<userId>:<abilityId>").

export type CooldownTracker = {
	isReady: (self: CooldownTracker, key: string, now: number) -> boolean,
	start: (self: CooldownTracker, key: string, now: number, duration: number) -> number,
	readyAt: (self: CooldownTracker, key: string) -> number,
	remaining: (self: CooldownTracker, key: string, now: number) -> number,
	clearPrefix: (self: CooldownTracker, prefix: string) -> (),
	clear: (self: CooldownTracker) -> (),
}

local CooldownTracker = {}

function CooldownTracker.new(): CooldownTracker
	local readyTimes: { [string]: number } = {}
	local self = {} :: any

	function self:isReady(key: string, now: number): boolean
		local t = readyTimes[key]
		return t == nil or now >= t
	end

	function self:start(key: string, now: number, duration: number): number
		local t = now + math.max(0, duration)
		readyTimes[key] = t
		return t
	end

	function self:readyAt(key: string): number
		return readyTimes[key] or 0
	end

	function self:remaining(key: string, now: number): number
		local t = readyTimes[key]
		if t == nil then
			return 0
		end
		return math.max(0, t - now)
	end

	function self:clearPrefix(prefix: string)
		for key in readyTimes do
			if string.sub(key, 1, #prefix) == prefix then
				readyTimes[key] = nil
			end
		end
	end

	function self:clear()
		table.clear(readyTimes)
	end

	return self :: CooldownTracker
end

return CooldownTracker
