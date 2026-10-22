--!strict
-- PositionHistory: short per-player position trails for lag-compensated hit checks (pure).
-- `record` appends samples in time order; `sample` linearly interpolates the position at a past
-- time, clamping to the oldest/newest sample. Samples older than `window` seconds are dropped.

export type PositionHistory = {
	record: (self: PositionHistory, userId: number, t: number, position: Vector3) -> (),
	sample: (self: PositionHistory, userId: number, t: number) -> Vector3?,
	forget: (self: PositionHistory, userId: number) -> (),
	clear: (self: PositionHistory) -> (),
}

type Entry = { t: number, position: Vector3 }

local PositionHistory = {}

function PositionHistory.new(window: number): PositionHistory
	local trails: { [number]: { Entry } } = {}
	local self = {} :: any

	function self:record(userId: number, t: number, position: Vector3)
		local trail = trails[userId]
		if not trail then
			trail = {}
			trails[userId] = trail
		end
		local list = trail :: { Entry }
		if #list > 0 and t <= list[#list].t then
			list[#list] = { t = t, position = position } -- same tick (or clock skew): keep the newest
		else
			table.insert(list, { t = t, position = position })
		end
		while #list > 2 and t - list[1].t > window do
			table.remove(list, 1)
		end
	end

	function self:sample(userId: number, t: number): Vector3?
		local list = trails[userId]
		if not list or #list == 0 then
			return nil
		end
		if t <= list[1].t then
			return list[1].position
		end
		for i = #list, 1, -1 do
			local entry = list[i]
			if entry.t <= t then
				local after = list[i + 1]
				if not after then
					return entry.position
				end
				local alpha = (t - entry.t) / (after.t - entry.t)
				return entry.position:Lerp(after.position, alpha)
			end
		end
		return list[#list].position
	end

	function self:forget(userId: number)
		trails[userId] = nil
	end

	function self:clear()
		table.clear(trails)
	end

	return self :: PositionHistory
end

return table.freeze(PositionHistory)
