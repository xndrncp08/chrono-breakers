--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.AnomalyConfig)
export type Event = {
	id: string,
	kind: string,
	position: Vector3,
	destination: Vector3,
	radius: number,
	activatesAt: number,
	endsAt: number,
	state: string,
}
export type Model = {
	current: Event?,
	nextAt: number,
	tick: (self: Model, now: number) -> (Event?, string?),
	clear: (self: Model) -> (),
}
local AnomalyModel = {}
function AnomalyModel.contains(event: Event, position: Vector3): boolean
	local delta = position - event.position
	return math.abs(delta.Y) <= 12 and Vector3.new(delta.X, 0, delta.Z).Magnitude <= event.radius
end
function AnomalyModel.portalAllowed(
	active: boolean,
	alive: boolean,
	restrained: boolean,
	distance: number,
	readyAt: number,
	now: number
): boolean
	return active
		and alive
		and not restrained
		and distance == distance
		and distance <= 6
		and distance >= 0
		and now >= readyAt
end
function AnomalyModel.new(matchId: string, sites: { Vector3 }, now: number, randomIndex: (number) -> number): Model
	assert(#sites >= 2, "Anomalies require two authored sites")
	local self = { current = nil :: Event?, nextAt = now + Config.FirstDelay } :: any
	local sequence, last = 0, ""
	function self:tick(t: number): (Event?, string?)
		local event = self.current
		if event and t >= event.endsAt then
			self.current = nil
			self.nextAt = t + Config.Interval
			return event, "Ended"
		elseif event and event.state == "Warning" and t >= event.activatesAt then
			event.state = "Active"
			return event, "Active"
		elseif event == nil and t >= self.nextAt then
			local choices = {}
			for _, id in Config.Order do
				if id ~= last then
					table.insert(choices, id)
				end
			end
			local kind = choices[randomIndex(#choices)]
			last = kind
			local site = randomIndex(#sites)
			sequence += 1
			local nextEvent: Event = {
				id = `{matchId}:{sequence}`,
				kind = kind,
				position = sites[site],
				destination = sites[site % #sites + 1],
				radius = Config.Radius,
				activatesAt = t + Config.Warning,
				endsAt = t + Config.Warning + (Config.Events :: any)[kind].Duration,
				state = "Warning",
			}
			self.current = nextEvent
			return nextEvent, "Warning"
		end
		return nil, nil
	end
	function self:clear()
		self.current = nil
		self.nextAt = math.huge
	end
	return self :: Model
end
return table.freeze(AnomalyModel)
