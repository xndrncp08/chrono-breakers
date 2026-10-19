--!strict
-- PerkService: locks each participant's perk loadout at match start (like gadgets and classes) and
-- answers modifier lookups for the systems that own each rule. Lobby changes never affect a live
-- match; perks a player has not unlocked never reach this table (ProfileSchema + Economy guard it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkConfig = require(ReplicatedStorage.Shared.Config.PerkConfig)

local PerkService = {}

local deps: { [string]: any } = {}
local locked: { [number]: { string } } = {}

function PerkService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		locked[player.UserId] = nil
	end)
end

function PerkService.Start()
	deps.MatchService.GetDirector().events:Connect(function(name: string, payload: any)
		if name == "MatchStarted" then
			table.clear(locked)
			for _, userId in payload.order do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					local role = payload.roles[userId]
					local perks = deps.InventoryService.GetPerks(player, role)
					local class = deps.MatchService.GetMatchClass(player)
					local valid = {}
					for _, id in perks do
						local definition = PerkConfig.get(id)
						if
							definition
							and definition.Role == role
							and (definition.Class == nil or definition.Class == class)
						then
							table.insert(valid, id)
						end
					end
					locked[userId] = valid
				end
			end
		elseif name == "MatchCleanup" then
			table.clear(locked)
		end
	end)
end

-- Combined multiplicative modifier for a participant (1 when absent).
function PerkService.ValueFor(userId: number?, key: string): number
	local perks = if userId then locked[userId] else nil
	return if perks then PerkConfig.modifier(perks, key) else 1
end

function PerkService.Value(player: Player?, key: string): number
	return PerkService.ValueFor(if player then player.UserId else nil, key)
end

function PerkService.Has(player: Player?, key: string): boolean
	local perks = if player then locked[player.UserId] else nil
	if not perks then
		return false
	end
	for _, id in perks do
		local definition = PerkConfig.get(id)
		if definition and definition.Modifiers[key] ~= nil then
			return true
		end
	end
	return false
end

function PerkService.GetLocked(player: Player): { string }
	return table.clone(locked[player.UserId] or {})
end

return PerkService
