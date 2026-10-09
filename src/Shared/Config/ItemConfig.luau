--!strict
-- Item catalogue for the loadout/shop. Items are purchased with Chronos Scrap earned in matches.
-- Gameplay items (gadgets) are side-grades with distinct trade-offs, not strict upgrades;
-- cosmetics (trails) have no gameplay effect. No real-money items exist.

export type ItemSlot = "Gadget" | "Trail"

export type ItemDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Slot: ItemSlot,
	Cost: number,
	DefaultOwned: boolean,
	-- Gadget items reference an AbilityConfig id; trails carry a colour.
	AbilityId: string?,
	Color: Color3?,
	SortOrder: number,
}

local ItemConfig = {}

ItemConfig.Items = table.freeze({
	Stabilizer = table.freeze({
		Id = "Stabilizer",
		DisplayName = "Chrono Stabilizer",
		Description = "Gadget: purge slows/stuns and gain brief immunity. Hard counter to the Time-Freeze Zone.",
		Slot = "Gadget",
		Cost = 0,
		DefaultOwned = true,
		AbilityId = "Stabilizer",
		SortOrder = 1,
	} :: ItemDefinition),
	PhaseDash = table.freeze({
		Id = "PhaseDash",
		DisplayName = "Phase Dash",
		Description = "Gadget: a short burst of speed for escapes and terminal rotations.",
		Slot = "Gadget",
		Cost = 150,
		DefaultOwned = false,
		AbilityId = "PhaseDash",
		SortOrder = 2,
	} :: ItemDefinition),
	EchoScanner = table.freeze({
		Id = "EchoScanner",
		DisplayName = "Echo Scanner",
		Description = "Gadget: reveal the Time-Keeper and armed traps to your team.",
		Slot = "Gadget",
		Cost = 250,
		DefaultOwned = false,
		AbilityId = "EchoScanner",
		SortOrder = 3,
	} :: ItemDefinition),
	TrailCyan = table.freeze({
		Id = "TrailCyan",
		DisplayName = "Stable Cyan Trail",
		Description = "Cosmetic: a cyan chrono-trail.",
		Slot = "Trail",
		Cost = 0,
		DefaultOwned = true,
		Color = Color3.fromRGB(64, 232, 255),
		SortOrder = 10,
	} :: ItemDefinition),
	TrailMagenta = table.freeze({
		Id = "TrailMagenta",
		DisplayName = "Rift Magenta Trail",
		Description = "Cosmetic: a magenta chrono-trail.",
		Slot = "Trail",
		Cost = 100,
		DefaultOwned = false,
		Color = Color3.fromRGB(255, 72, 196),
		SortOrder = 11,
	} :: ItemDefinition),
	TrailGold = table.freeze({
		Id = "TrailGold",
		DisplayName = "Paradox Gold Trail",
		Description = "Cosmetic: a gold chrono-trail for veteran breakers.",
		Slot = "Trail",
		Cost = 400,
		DefaultOwned = false,
		Color = Color3.fromRGB(255, 200, 72),
		SortOrder = 12,
	} :: ItemDefinition),
})

ItemConfig.DefaultEquipped = table.freeze({
	Gadget = "Stabilizer",
	Trail = "TrailCyan",
})

ItemConfig.Slots = table.freeze({ "Gadget", "Trail" })

function ItemConfig.get(itemId: string): ItemDefinition?
	return (ItemConfig.Items :: any)[itemId]
end

-- Items sorted for display.
function ItemConfig.list(): { ItemDefinition }
	local list: { ItemDefinition } = {}
	for _, item in ItemConfig.Items :: any do
		table.insert(list, item)
	end
	table.sort(list, function(a, b)
		return a.SortOrder < b.SortOrder
	end)
	return list
end

return table.freeze(ItemConfig)
