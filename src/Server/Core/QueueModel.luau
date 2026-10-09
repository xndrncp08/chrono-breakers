--!strict
-- Server-owned FIFO matchmaking queue. Pure data structure: eligibility is decided by the caller
-- (QueueService) and passed in where needed.

export type QueueModel = {
	join: (self: QueueModel, userId: number) -> (boolean, string),
	leave: (self: QueueModel, userId: number) -> (boolean, string),
	remove: (self: QueueModel, userId: number) -> boolean,
	contains: (self: QueueModel, userId: number) -> boolean,
	count: (self: QueueModel) -> number,
	countEligible: (self: QueueModel, isEligible: (number) -> boolean) -> number,
	list: (self: QueueModel) -> { number },
	-- Removes and returns up to `maxCount` eligible users in FIFO order; ineligible users are dropped.
	take: (self: QueueModel, maxCount: number, isEligible: (number) -> boolean) -> { number },
	-- Re-inserts users at the front (used when a match could not start after taking them).
	restore: (self: QueueModel, userIds: { number }) -> (),
	clear: (self: QueueModel) -> (),
}

local QueueModel = {}

function QueueModel.new(): QueueModel
	local order: { number } = {}
	local self = {} :: any

	function self:contains(userId: number): boolean
		return table.find(order, userId) ~= nil
	end

	function self:join(userId: number): (boolean, string)
		if table.find(order, userId) then
			return false, "AlreadyQueued"
		end
		table.insert(order, userId)
		return true, "Ok"
	end

	function self:leave(userId: number): (boolean, string)
		local index = table.find(order, userId)
		if not index then
			return false, "NotQueued"
		end
		table.remove(order, index)
		return true, "Ok"
	end

	function self:remove(userId: number): boolean
		local index = table.find(order, userId)
		if index then
			table.remove(order, index)
			return true
		end
		return false
	end

	function self:count(): number
		return #order
	end

	function self:countEligible(isEligible: (number) -> boolean): number
		local n = 0
		for _, userId in order do
			if isEligible(userId) then
				n += 1
			end
		end
		return n
	end

	function self:list(): { number }
		return table.clone(order)
	end

	function self:take(maxCount: number, isEligible: (number) -> boolean): { number }
		local taken: { number } = {}
		local remaining: { number } = {}
		for _, userId in order do
			if #taken < maxCount and isEligible(userId) then
				table.insert(taken, userId)
			elseif isEligible(userId) then
				table.insert(remaining, userId)
			end
			-- Ineligible users (left the server, dead data) are dropped from the queue.
		end
		order = remaining
		return taken
	end

	function self:restore(userIds: { number })
		for i = #userIds, 1, -1 do
			local userId = userIds[i]
			if not table.find(order, userId) then
				table.insert(order, 1, userId)
			end
		end
	end

	function self:clear()
		table.clear(order)
	end

	return self :: QueueModel
end

return QueueModel
