--!strict
-- Loadout & shop: every catalogue item with its slot, description, and state — Equipped, Owned
-- (Equip), Locked (Buy for N / Need N more) — followed by perks (Protocols / Edicts), which unlock
-- only through level or mastery and toggle into the matching two-slot loadout. Purchases and
-- equips are requests; the UI updates only from the server's ProfileSnapshot / ActionResult.
-- Changes are blocked during a live match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PerkConfig = require(ReplicatedStorage.Shared.Config.PerkConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Parent.Net)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local Modal = require(script.Parent.Parent.Components.Modal)
local Style = require(script.Parent.Parent.Components.Style)

local LoadoutScreen = {}

type Card = {
	frame: Frame,
	description: TextLabel,
	item: ItemConfig.ItemDefinition,
	status: TextLabel,
	button: Button.Button,
}

function LoadoutScreen.new(parent: Instance, deps: { [string]: any })
	local modal = Modal.new({ Name = "Loadout", Title = "Loadout & Shop", Width = 760, Height = 560, Parent = parent })
	local body = modal.Body

	local balance = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Heading,
		Color = Theme.Colors.Warning,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = body,
	})
	local notice = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 30),
		Parent = body,
	})

	local list = Create("ScrollingFrame", {
		Name = "Items",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.BorderStrong,
		Selectable = false,
		Parent = body,
	}, {
		Style.list(Enum.FillDirection.Vertical, Theme.Spacing.S) :: Instance,
		Style.padding(2, 2),
	})

	local cards: { Card } = {}
	local pendingItem: string? = nil

	local function request(action: string, itemId: string, card: Card)
		pendingItem = itemId
		card.button:SetLoading(true)
		deps.AudioController.Play("UiClick")
		Net.send(RemoteNames.ShopRequest, action, itemId)
		task.delay(4, function()
			if pendingItem == itemId then
				pendingItem = nil
				card.button:SetLoading(false)
			end
		end)
	end

	for index, item in ItemConfig.list() do
		local card = Style.panel({
			Name = `Item_{item.Id}`,
			Size = UDim2.new(1, -8, 0, 118),
			Color = Theme.Colors.SurfaceRaised,
			Transparency = 0.1,
			Padding = Theme.Spacing.M,
			LayoutOrder = index,
			Parent = list,
		})
		local swatchColor = item.Color
			or (if item.Slot == "Gadget" then Theme.Colors.Stable else Theme.Colors.TextMuted)
		Create("Frame", {
			Name = "Swatch",
			Size = UDim2.new(0, 6, 1, 0),
			BackgroundColor3 = swatchColor,
			BorderSizePixel = 0,
			Parent = card,
		}, { Style.corner(Theme.Radius.Pill) })
		Style.text({
			Text = `{item.DisplayName}  ·  {string.upper(item.Slot)}`,
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -200, 0, 22),
			Position = UDim2.fromOffset(16, 0),
			Wrapped = false,
			Parent = card,
		})
		local description = Style.text({
			Text = item.Description,
			TextSize = Theme.TextSize.Small,
			Color = Theme.Colors.TextSecondary,
			Size = UDim2.new(1, -200, 0, 38),
			Position = UDim2.fromOffset(16, 24),
			YAlign = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local status = Style.text({
			Text = "",
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Micro,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(170, 18),
			XAlign = Enum.TextXAlignment.Right,
			Parent = card,
		})
		local entry: Card
		local button = Button.new({
			Text = "",
			Style = "Primary",
			Size = UDim2.fromOffset(170, 40),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			TextSize = Theme.TextSize.Small,
			OnActivated = function()
				local profile = ClientState.get("profile")
				if not profile then
					return
				end
				if profile.owned[item.Id] then
					request(Protocol.ShopActions.Equip, item.Id, entry)
				else
					request(Protocol.ShopActions.Purchase, item.Id, entry)
				end
			end,
			Parent = card,
		})
		entry = { item = item, status = status, button = button, frame = card, description = description }
		table.insert(cards, entry)
	end

	-- Perks
	type PerkCard = { perk: PerkConfig.Perk, status: TextLabel, button: Button.Button }
	local perkCards: { PerkCard } = {}
	local itemCount = #cards
	Style.text({
		Text = `PROTOCOLS & EDICTS · {PerkConfig.Slots} per loadout · unlocked by playing, never bought`,
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Temporal,
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = itemCount + 1,
		Parent = list,
	})
	local function loadoutKey(perk: PerkConfig.Perk, profile: any): string
		if perk.Role == "TimeKeeper" then
			return "TimeKeeper"
		end
		return perk.Class or (profile and profile.equipped.Class) or "Ghost"
	end
	for index, perk in PerkConfig.list() do
		local card = Style.panel({
			Name = `Perk_{perk.Id}`,
			Size = UDim2.new(1, -8, 0, 92),
			Color = Theme.Colors.SurfaceRaised,
			Transparency = 0.1,
			Padding = Theme.Spacing.M,
			LayoutOrder = itemCount + 1 + index,
			Parent = list,
		})
		local class = ClassConfig.get(perk.Class)
		local owner = if perk.Role == "TimeKeeper" then "EDICT" elseif class then string.upper(class.Name) else "SHARED"
		Style.text({
			Text = `{perk.Name}  ·  {owner}`,
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -200, 0, 22),
			Wrapped = false,
			Color = if perk.Role == "TimeKeeper"
				then Theme.Colors.Temporal
				elseif class then class.Color
				else Theme.Colors.Stable,
			Parent = card,
		})
		Style.text({
			Text = perk.Description,
			TextSize = Theme.TextSize.Small,
			Color = Theme.Colors.TextSecondary,
			Size = UDim2.new(1, -200, 0, 36),
			Position = UDim2.fromOffset(0, 24),
			YAlign = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local status = Style.text({
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Micro,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(190, 18),
			XAlign = Enum.TextXAlignment.Right,
			Parent = card,
		})
		local button = Button.new({
			Text = "",
			Style = "Secondary",
			Size = UDim2.fromOffset(170, 40),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			TextSize = Theme.TextSize.Small,
			OnActivated = function()
				pendingItem = perk.Id
				deps.AudioController.Play("UiClick")
				Net.send(RemoteNames.ShopRequest, Protocol.ShopActions.TogglePerk, perk.Id)
			end,
			Parent = card,
		})
		table.insert(perkCards, { perk = perk, status = status, button = button })
	end

	local function renderPerks(profile: any, inMatch: boolean)
		local progression = profile and profile.progression
		local progress = {
			xp = if progression then progression.xp else 0,
			mastery = if progression then progression.mastery else {},
		}
		for _, card in perkCards do
			local perk = card.perk
			local key = loadoutKey(perk, profile)
			local equipped = profile and profile.perks and profile.perks[key] or {}
			local unlocked = profile ~= nil and PerkConfig.isUnlocked(perk, key, progress)
			if pendingItem ~= perk.Id then
				card.button:SetLoading(false)
			end
			if not profile or not profile.loaded then
				card.status.Text = ""
				card.button:SetText("…")
				card.button:SetEnabled(false)
			elseif table.find(equipped, perk.Id) then
				card.status.Text = `✓ EQUIPPED · {key}`
				card.status.TextColor3 = Theme.Colors.Success
				card.button:SetText("Unequip")
				card.button:SetEnabled(not inMatch)
			elseif unlocked then
				card.status.Text = `{#equipped}/{PerkConfig.Slots} · {key}`
				card.status.TextColor3 = Theme.Colors.Stable
				card.button:SetText("Equip")
				card.button:SetEnabled(not inMatch and #equipped < PerkConfig.Slots)
			else
				local need = perk.Unlock.Value
				local masteryKey = if perk.Role == "TimeKeeper" then "TimeKeeper" else key
				local have = if perk.Unlock.Kind == "Level"
					then ProgressionConfig.level(progress.xp)
					else ProgressionConfig.level(progress.mastery[masteryKey] or 0)
				card.status.Text = if perk.Unlock.Kind == "Level"
					then `🔒 LEVEL {need} (you: {have})`
					else `🔒 {string.upper(masteryKey)} MASTERY {need} (you: {have})`
				card.status.TextColor3 = Theme.Colors.TextMuted
				card.button:SetText("Locked")
				card.button:SetEnabled(false)
			end
		end
	end

	local function layout()
		local narrow = body.AbsoluteSize.X < 540
		for _, card in cards do
			card.frame.Size = UDim2.new(1, -8, 0, if narrow then 196 else 118)
			card.description.Size = UDim2.new(1, -200, 0, if narrow then 138 else 64)
		end
	end
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local function render()
		layout()
		local profile = ClientState.get("profile")
		local inMatch = ClientState.isLiveParticipant()
		if not profile or not profile.loaded then
			balance.Text = "Loading profile…"
		else
			balance.Text = `◆ {profile.currency} {RewardConfig.CurrencyName}`
		end
		if inMatch then
			notice.Text = "Loadout is locked during a match."
			notice.TextColor3 = Theme.Colors.Warning
		elseif profile and not profile.persistent and profile.loaded then
			notice.Text = "Unsaved session: purchases won't persist."
			notice.TextColor3 = Theme.Colors.Warning
		else
			notice.Text = "Earn Scrap by playing matches. Gadgets are side-grades; trails are cosmetic."
			notice.TextColor3 = Theme.Colors.TextSecondary
		end
		for _, card in cards do
			local item = card.item
			if pendingItem ~= item.Id then
				card.button:SetLoading(false)
			end
			if not profile or not profile.loaded then
				card.status.Text = ""
				card.button:SetText("…")
				card.button:SetEnabled(false)
			elseif profile.equipped[item.Slot] == item.Id then
				card.status.Text = "✓ EQUIPPED"
				card.status.TextColor3 = Theme.Colors.Success
				card.button:SetText("Equipped")
				card.button:SetStyle("Secondary")
				card.button:SetEnabled(false)
			elseif profile.owned[item.Id] then
				card.status.Text = "OWNED"
				card.status.TextColor3 = Theme.Colors.Stable
				card.button:SetText("Equip")
				card.button:SetStyle("Primary")
				card.button:SetEnabled(not inMatch)
			else
				local short = item.Cost - profile.currency
				card.status.Text = if short > 0 then `🔒 NEED {short} MORE` else "🔒 LOCKED"
				card.status.TextColor3 = if short > 0 then Theme.Colors.TextMuted else Theme.Colors.Warning
				card.button:SetText(if item.Milestone then "Earn milestone" else `Buy · {item.Cost}`)
				card.button:SetStyle("Temporal")
				card.button:SetEnabled(not item.Milestone and short <= 0 and not inMatch)
			end
		end
		renderPerks(profile, inMatch)
	end

	ClientState.changed:Connect(function(key: string)
		if key == "profile" then
			pendingItem = nil
			render()
		elseif key == "snapshot" and modal:IsOpen() then
			render()
		end
	end)

	local self = {}
	self.Modal = modal
	function self.Open()
		render()
		modal:Open()
		if cards[1] then
			modal:Focus(cards[1].button.Instance)
		end
	end
	function self.OnActionResult(result: any)
		if result.action == "Shop" then
			pendingItem = nil
			render()
		end
	end
	return self
end

return LoadoutScreen
