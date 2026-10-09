--!strict
-- Extraction phase rules: opens once, times out at a server deadline, and requires an eligible
-- Infiltrator to remain inside the zone for a continuous channel time. Each player extracts once.

export type ExtractionModel = {
	active: boolean,
	opensAt: number?,
	endsAt: number?,
	activate: (self: ExtractionModel, now: number, window: number) -> boolean,
	-- Returns true exactly once per player: when they complete extraction.
	update: (self: ExtractionModel, userId: number, inZone: boolean, now: number, channelTime: number) -> boolean,
	resetChannel: (self: ExtractionModel, userId: number) -> (),
	channelProgress: (self: ExtractionModel, userId: number, now: number, channelTime: number) -> number,
	hasExtracted: (self: ExtractionModel, userId: number) -> boolean,
	extractedCount: (self: ExtractionModel) -> number,
	isExpired: (self: ExtractionModel, now: number) -> boolean,
}

local ExtractionModel = {}

function ExtractionModel.new(): ExtractionModel
	local enteredAt: { [number]: number } = {}
	local extracted: { [number]: boolean } = {}
	local count = 0
	local self = { active = false, opensAt = nil, endsAt = nil } :: any

	function self:activate(now: number, window: number): boolean
		if self.active then
			return false
		end
		self.active = true
		self.opensAt = now
		self.endsAt = now + window
		return true
	end

	function self:update(userId: number, inZone: boolean, now: number, channelTime: number): boolean
		if not self.active or extracted[userId] then
			return false
		end
		if self.endsAt and now > self.endsAt then
			return false
		end
		if not inZone then
			enteredAt[userId] = nil
			return false
		end
		local since = enteredAt[userId]
		if since == nil then
			enteredAt[userId] = now
			since = now
		end
		if now - (since :: number) >= channelTime then
			extracted[userId] = true
			enteredAt[userId] = nil
			count += 1
			return true
		end
		return false
	end

	function self:resetChannel(userId: number)
		enteredAt[userId] = nil
	end

	function self:channelProgress(userId: number, now: number, channelTime: number): number
		local since = enteredAt[userId]
		if since == nil or channelTime <= 0 then
			return 0
		end
		return math.clamp((now - since) / channelTime, 0, 1)
	end

	function self:hasExtracted(userId: number): boolean
		return extracted[userId] == true
	end

	function self:extractedCount(): number
		return count
	end

	function self:isExpired(now: number): boolean
		return self.active and self.endsAt ~= nil and now >= self.endsAt
	end

	return self :: ExtractionModel
end

return ExtractionModel
