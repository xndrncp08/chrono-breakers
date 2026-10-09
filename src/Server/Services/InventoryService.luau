--!strict
-- InventoryService: shop purchases, loadout equips, and persisted settings. All operations run on the
-- server against the authoritative profile via PlayerDataService.Mutate; the client only names an
-- action and an item id. Loadout changes are blocked while the player is in a live match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local Economy = require(script.Parent.Parent.Core.Economy)
local ProfileSchema = require(script.Parent.Parent.Core.ProfileSchema)
local Validate = require(script.Parent.Parent.Core.Validate)

local InventoryService = {}

local deps: { [string]: any } = {}

local SETTINGS_KEYS: { [string]: boolean } = {}
for key in ProfileSchema.SETTINGS :: any do
	SETTINGS_KEYS[key] = true
end

function InventoryService.Init(injected: { [string]: any })
	deps = injected
end

function InventoryService.GetEquipped(player: Player, slot: string): string?
	local profile = deps.PlayerDataService.GetProfile(player)
	if profile then
		return profile.Equipped[slot]
	end
	return (ItemConfig.DefaultEquipped :: any)[slot]
end

local function handleShopRequest(player: Player, action: any, itemId: any, ...: any)
	if
		select("#", ...) > 0
		or not Validate.isOneOf(action, Protocol.ShopActions)
		or not Validate.isShortString(itemId, 32)
	then
		deps.SecurityService.Report(player, "InvalidPayload", "ShopRequest")
		deps.NetworkService.Reject(player, "Shop", Protocol.Codes.InvalidPayload)
		return
	end
	if ItemConfig.get(itemId) == nil then
		deps.NetworkService.Reject(player, "Shop", Protocol.Codes.UnknownItem)
		return
	end
	if deps.MatchService.IsInMatch(player) then
		deps.NetworkService.Reject(player, "Shop", Protocol.Codes.InMatch)
		return
	end
	local operation: (any, any) -> (boolean, string) = if action == Protocol.ShopActions.Purchase
		then Economy.purchase
		else Economy.equip
	local code = Protocol.Codes.ProfileUnavailable
	local applied = deps.PlayerDataService.Mutate(player, function(profile)
		local ok, resultCode = operation(profile, itemId)
		code = resultCode
		return ok
	end)
	if applied and code == Protocol.Codes.Ok then
		deps.NetworkService.Accept(player, "Shop", { shopAction = action, itemId = itemId })
		if action == Protocol.ShopActions.Equip then
			deps.CharacterService.RefreshCosmetics(player)
		end
		deps.PlayerDataService.SaveSoon(player)
	else
		deps.NetworkService.Reject(player, "Shop", code)
	end
end

local function handleSettingsUpdate(player: Player, settings: any, ...: any)
	if select("#", ...) > 0 or not Validate.isPlainTable(settings, SETTINGS_KEYS, 8) then
		deps.SecurityService.Report(player, "InvalidPayload", "SettingsUpdate")
		deps.NetworkService.Reject(player, "Settings", Protocol.Codes.InvalidPayload)
		return
	end
	local sanitized: { [string]: any } = {}
	for key, value in settings do
		local clean = ProfileSchema.sanitizeSetting(key, value)
		if clean == nil then
			deps.NetworkService.Reject(player, "Settings", Protocol.Codes.InvalidPayload)
			return
		end
		sanitized[key] = clean
	end
	local applied = deps.PlayerDataService.Mutate(player, function(profile)
		local current = profile.Settings :: any
		for key, value in sanitized do
			current[key] = value
		end
		return true
	end)
	if applied then
		deps.NetworkService.Accept(player, "Settings")
	else
		deps.NetworkService.Reject(player, "Settings", Protocol.Codes.ProfileUnavailable)
	end
end

function InventoryService.Start()
	deps.NetworkService.OnRequest(RemoteNames.ShopRequest, handleShopRequest)
	deps.NetworkService.OnRequest(RemoteNames.SettingsUpdate, handleSettingsUpdate)
end

return InventoryService
