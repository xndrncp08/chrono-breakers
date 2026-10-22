--!strict
-- Item catalogue for the loadout/shop. Items are purchased with Chronos Scrap earned in matches.
-- Gameplay items (gadgets) are side-grades with distinct trade-offs, not strict upgrades;
-- cosmetics (trails) have no gameplay effect. No real-money items exist.

export type ItemSlot = "Gadget" | "Trail" | "Class" | "Title"

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
	Milestone: string?,
	SortOrder: number,
}

local ClassConfig = require(script.Parent.ClassConfig)
local ItemConfig = {}

local items: { [string]: ItemDefinition } = {
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
	Afterimage = table.freeze({
		Id = "Afterimage",
		DisplayName = "Afterimage",
		Description = "Gadget: leave a decoy echo running your old heading. Costs stamina; Chrono Pulse dispels it.",
		Slot = "Gadget",
		Cost = 200,
		DefaultOwned = false,
		AbilityId = "Afterimage",
		SortOrder = 4,
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
}
for index, id in ClassConfig.Order do
	local definition = ClassConfig.get(id) :: ClassConfig.Definition
	items[id] = table.freeze({
		Id = id,
		DisplayName = definition.Name,
		Description = definition.Description,
		Slot = "Class",
		Cost = 0,
		DefaultOwned = true,
		SortOrder = 20 + index,
	} :: ItemDefinition)
end

items.TitleRookie = {
	Id = "TitleRookie",
	DisplayName = "Temporal Recruit",
	Description = "Profile title: a fresh timeline awaits.",
	Slot = "Title",
	Cost = 0,
	DefaultOwned = true,
	SortOrder = 30,
}
items.TitleBreaker = {
	Id = "TitleBreaker",
	DisplayName = "Timeline Breaker",
	Description = "Unlock by extracting once.",
	Slot = "Title",
	Cost = 0,
	DefaultOwned = false,
	SortOrder = 31,
	Milestone = "FirstEscape",
}
items.TitleWarden = {
	Id = "TitleWarden",
	DisplayName = "Vault Warden",
	Description = "Unlock by winning five Keeper matches.",
	Slot = "Title",
	Cost = 0,
	DefaultOwned = false,
	SortOrder = 32,
	Milestone = "VaultWarden",
}
items.TitleVeteran = {
	Id = "TitleVeteran",
	DisplayName = "Temporal Veteran",
	Description = "Unlock by completing twenty heists.",
	Slot = "Title",
	Cost = 0,
	DefaultOwned = false,
	SortOrder = 33,
	Milestone = "Veteran",
}
items.TrailRift = {
	Id = "TrailRift",
	DisplayName = "Rift Walker Trail",
	Description = "Cosmetic: reach level ten to unlock a violet chrono-trail.",
	Slot = "Trail",
	Cost = 0,
	DefaultOwned = false,
	SortOrder = 13,
	Milestone = "RiftWalker",
	Color = Color3.fromRGB(156, 112, 255),
}
items.TitleLifeline = {
	Id = "TitleLifeline",
	DisplayName = "Lifeline",
	Description = "Unlock by rescuing ten allies from Stasis.",
	Slot = "Title",
	Cost = 0,
	DefaultOwned = false,
	SortOrder = 34,
	Milestone = "Lifeline",
}
-- Mastery cosmetics (ProgressionConfig.MasteryRoles): never purchasable, earned by playing a role.
local masteryNames: { [string]: string } = {
	Ghost = "Ghost",
	Engineer = "Engineer",
	ChronoMedic = "Chrono Medic",
	Phantom = "Phantom",
	Disruptor = "Disruptor",
	TimeKeeper = "Time-Keeper",
}
for index, id in { "Ghost", "Engineer", "ChronoMedic", "Phantom", "Disruptor", "TimeKeeper" } do
	local class = ClassConfig.get(id)
	local color = if class then class.Color else Color3.fromRGB(255, 72, 196)
	items[`Title{id}Adept`] = {
		Id = `Title{id}Adept`,
		DisplayName = `{masteryNames[id]} Adept`,
		Description = `Mastery 5 as {masteryNames[id]}.`,
		Slot = "Title",
		Cost = 0,
		DefaultOwned = false,
		SortOrder = 40 + index,
		Milestone = `{id}Adept`,
	}
	items[`Trail{id}`] = {
		Id = `Trail{id}`,
		DisplayName = `{masteryNames[id]} Signature Trail`,
		Description = `Mastery 10 as {masteryNames[id]}: a trail in the role's colour.`,
		Slot = "Trail",
		Cost = 0,
		DefaultOwned = false,
		SortOrder = 50 + index,
		Milestone = `{id}Signature`,
		Color = color,
	}
end
ItemConfig.Items = table.freeze(items)

ItemConfig.DefaultEquipped = table.freeze({
	Gadget = "Stabilizer",
	Class = "Ghost",
	Title = "TitleRookie",
	Trail = "TrailCyan",
})

ItemConfig.Slots = table.freeze({ "Gadget", "Trail", "Class", "Title" })

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
