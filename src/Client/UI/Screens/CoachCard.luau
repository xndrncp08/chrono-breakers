--!strict
-- Field Guide card (bottom left, above the control hints): one coaching tip at a time. Non-modal,
-- never blocks input, and fades only when ReducedMotion is off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CoachConfig = require(ReplicatedStorage.Shared.Config.CoachConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

export type CoachCard = {
	Show: (self: CoachCard, tip: CoachConfig.Tip) -> (),
	Hide: (self: CoachCard) -> (),
}

local CoachCard = {}

function CoachCard.new(parent: Instance): CoachCard
	local card = Style.panel({
		Name = "FieldGuide",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.Spacing.L, 1, -96),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Color = Theme.Colors.Background,
		Transparency = 0.12,
		StrokeColor = Theme.Colors.Temporal,
		Padding = Theme.Spacing.M,
		Parent = parent,
	})
	card.Visible = false
	card.ZIndex = 12
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS).Parent = card
	Create("UISizeConstraint", { MaxSize = Vector2.new(330, 400), Parent = card })
	local kicker = Style.text({
		Text = "FIELD GUIDE",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextMuted,
		LayoutOrder = 1,
		Parent = card,
	})
	local title = Style.text({
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.Temporal,
		LayoutOrder = 2,
		Parent = card,
	})
	local body = Style.text({
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextPrimary,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = card,
	})
	local labels = { kicker, title, body }
	local token = 0

	local function fade(transparency: number, duration: number)
		local settings = ClientState.get("settings")
		local instant = settings ~= nil and settings.ReducedMotion == true
		local info = TweenInfo.new(if instant then 0 else duration)
		TweenService:Create(card, info, { BackgroundTransparency = 0.12 + 0.88 * transparency }):Play()
		for _, label in labels do
			TweenService:Create(label, info, { TextTransparency = transparency }):Play()
		end
	end

	local self = {} :: any

	function self:Show(tip: CoachConfig.Tip)
		token += 1
		local mine = token
		title.Text = tip.Title
		body.Text = tip.Text
		card.Visible = true
		fade(1, 0)
		fade(0, Theme.Motion.Normal)
		task.delay(CoachConfig.Duration, function()
			if token == mine then
				self:Hide()
			end
		end)
	end

	function self:Hide()
		token += 1
		local mine = token
		fade(1, Theme.Motion.Normal)
		task.delay(Theme.Motion.Normal, function()
			if token == mine then
				card.Visible = false
			end
		end)
	end

	return self :: CoachCard
end

return CoachCard
