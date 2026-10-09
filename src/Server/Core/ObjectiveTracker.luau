--!strict
-- Owns the set of registered objectives for one match and which of them have been completed.
-- Completion is deduplicated, and the "threshold reached" signal is reported exactly once.

export type ObjectiveTracker = {
	required: number,
	register: (self: ObjectiveTracker, id: string) -> (),
	isRegistered: (self: ObjectiveTracker, id: string) -> boolean,
	isCompleted: (self: ObjectiveTracker, id: string) -> boolean,
	-- Returns (accepted, thresholdJustReached).
	markComplete: (self: ObjectiveTracker, id: string) -> (boolean, boolean),
	completedCount: (self: ObjectiveTracker) -> number,
	registeredCount: (self: ObjectiveTracker) -> number,
	isThresholdReached: (self: ObjectiveTracker) -> boolean,
	completedIds: (self: ObjectiveTracker) -> { string },
}

local ObjectiveTracker = {}

function ObjectiveTracker.new(required: number): ObjectiveTracker
	assert(required >= 1, "ObjectiveTracker requires at least one objective")
	local registered: { [string]: boolean } = {}
	local completed: { [string]: boolean } = {}
	local completedOrder: { string } = {}
	local thresholdFired = false

	local self = { required = required } :: any

	function self:register(id: string)
		registered[id] = true
	end

	function self:isRegistered(id: string): boolean
		return registered[id] == true
	end

	function self:isCompleted(id: string): boolean
		return completed[id] == true
	end

	function self:markComplete(id: string): (boolean, boolean)
		if not registered[id] or completed[id] then
			return false, false
		end
		completed[id] = true
		table.insert(completedOrder, id)
		if not thresholdFired and #completedOrder >= self.required then
			thresholdFired = true
			return true, true
		end
		return true, false
	end

	function self:completedCount(): number
		return #completedOrder
	end

	function self:registeredCount(): number
		local n = 0
		for _ in registered do
			n += 1
		end
		return n
	end

	function self:isThresholdReached(): boolean
		return thresholdFired
	end

	function self:completedIds(): { string }
		return table.clone(completedOrder)
	end

	return self :: ObjectiveTracker
end

return ObjectiveTracker
