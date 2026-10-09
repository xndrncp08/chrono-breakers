--!strict
-- Horizontal progress bar with an optional centred label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)

export type ProgressBar = {
	Instance: Frame,
	Set: (self: ProgressBar, fraction: number, color: Color3?) -> (),
	SetLabel: (self: ProgressBar, text: string) -> (),
}

local ProgressBar = {}

function ProgressBar.new(props: {
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	LayoutOrder: number?,
	Parent: Instance?,
}): ProgressBar
	local frame = Create("Frame", {
		Name = "ProgressBar",
		Size = props.Size or UDim2.new(1, 0, 0, 14),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
	}, {
		Style.corner(Theme.Radius.Pill) :: Instance,
		Style.stroke(Theme.Colors.Border, Theme.Stroke.Thin, 0.3),
	}) :: Frame
	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.Color or Theme.Colors.Stable,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Style.corner(Theme.Radius.Pill) }) :: Frame
	local label = Create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		TextColor3 = Theme.Colors.TextPrimary,
		TextStrokeTransparency = 0.6,
		Text = "",
		ZIndex = 2,
		Parent = frame,
	}) :: TextLabel

	local self = { Instance = frame } :: any

	function self:Set(fraction: number, color: Color3?)
		local f = if fraction ~= fraction then 0 else math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(f, 1)
		if color then
			fill.BackgroundColor3 = color
		end
	end

	function self:SetLabel(text: string)
		label.Text = text
	end

	if props.Parent then
		frame.Parent = props.Parent
	end
	return self :: ProgressBar
end

return ProgressBar
