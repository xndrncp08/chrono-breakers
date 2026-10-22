--!strict
-- PerkService: locks each participant's perk loadout at match start (like gadgets and classes) and
-- answers modifier lookups for the systems that own each rule. Lobby changes never affect a live
-- match; perks a player has not unlocked never reach this table (ProfileSchema + Economy guard it).
-- It also owns the match's Timeline Condition (ConditionConfig), whose modifiers multiply with perks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ConditionConfig = require(ReplicatedStorage.Shared.Config.ConditionConfig)
local PerkConfig = require(ReplicatedStorage.Shared.Config.PerkConfig)

local ServerConfig = require(script.Parent.Parent.ServerConfig)

local PerkService = {}

local deps: { [string]: any } = {}
local locked: { [number]: { string } } = {}
local condition = "Stable"
local random = Random.new()

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
			condition = "Stable"
		end
	end)
end

-- Rolls this match's Timeline Condition (called by MatchService before roles are announced).
-- Server-side `ForceTimelineCondition` on ServerScriptService pins it (tests, events).
function PerkService.RollCondition(): string
	local forced = ServerScriptService:GetAttribute("ForceTimelineCondition")
	if type(forced) == "string" and ConditionConfig.get(forced) then
		condition = forced
	elseif ServerConfig.TimelineConditions.Enabled then
		condition = ConditionConfig.roll(random:NextNumber())
	else
		condition = "Stable"
	end
	return condition
end

function PerkService.GetCondition(): string
	return condition
end

-- Combined multiplicative modifier for a participant (1 when absent), including the condition.
function PerkService.ValueFor(userId: number?, key: string): number
	local perks = if userId then locked[userId] else nil
	return (if perks then PerkConfig.modifier(perks, key) else 1) * ConditionConfig.modifier(condition, key)
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
