--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local MapVote = {}

function MapVote.cast(votes: { [number]: string }, userId: number, mapId: any): boolean
	if type(mapId) ~= "string" or (MapConfig.Maps :: any)[mapId] == nil then
		return false
	end
	votes[userId] = mapId
	return true
end

-- Only selected participants count; rotating tie priority also rotates maps when nobody votes.
function MapVote.select(votes: { [number]: string }, participants: { number }, round: number): string
	local counts: { [string]: number } = {}
	for _, userId in participants do
		local id = votes[userId]
		if id then
			counts[id] = (counts[id] or 0) + 1
		end
	end
	local winner = MapConfig.Order[round % #MapConfig.Order + 1]
	local best = -1
	for offset = 0, #MapConfig.Order - 1 do
		local id = MapConfig.Order[(round + offset) % #MapConfig.Order + 1]
		local count = counts[id] or 0
		if count > best then
			winner, best = id, count
		end
	end
	return winner
end
return table.freeze(MapVote)
