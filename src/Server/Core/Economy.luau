--!strict
-- Server-side economy operations on a Profile. Each operation validates everything first and only
-- then mutates, so a failed operation never leaves a partial change (no currency consumed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)

local ProfileSchema = require(script.Parent.ProfileSchema)

type Profile = ProfileSchema.Profile

local Economy = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Adds a non-negative integer amount, clamped to MaxCurrency. Returns the amount actually added.
function Economy.grant(profile: Profile, amount: number): number
	if not isFinite(amount) or amount <= 0 then
		return 0
	end
	local whole = math.floor(amount)
	local before = profile.ChronosScrap
	profile.ChronosScrap = math.min(RewardConfig.MaxCurrency, before + whole)
	return profile.ChronosScrap - before
end

-- Spends currency only if the full amount is available. Never goes negative.
function Economy.spend(profile: Profile, amount: number): boolean
	if not isFinite(amount) or amount < 0 or math.floor(amount) ~= amount then
		return false
	end
	if profile.ChronosScrap < amount then
		return false
	end
	profile.ChronosScrap -= amount
	return true
end

function Economy.purchase(profile: Profile, itemId: any): (boolean, string)
	if type(itemId) ~= "string" then
		return false, "InvalidPayload"
	end
	local item = ItemConfig.get(itemId)
	if item == nil then
		return false, "UnknownItem"
	end
	if profile.OwnedItems[itemId] then
		return false, "AlreadyOwned"
	end
	if profile.ChronosScrap < item.Cost then
		return false, "InsufficientFunds"
	end
	if not Economy.spend(profile, item.Cost) then
		return false, "InsufficientFunds"
	end
	profile.OwnedItems[itemId] = true
	return true, "Ok"
end

function Economy.equip(profile: Profile, itemId: any): (boolean, string)
	if type(itemId) ~= "string" then
		return false, "InvalidPayload"
	end
	local item = ItemConfig.get(itemId)
	if item == nil then
		return false, "UnknownItem"
	end
	if not profile.OwnedItems[itemId] then
		return false, "NotOwned"
	end
	profile.Equipped[item.Slot] = itemId
	return true, "Ok"
end

return table.freeze(Economy)
