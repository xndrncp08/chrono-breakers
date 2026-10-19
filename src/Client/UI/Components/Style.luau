--!strict
-- Shared styling primitives built on Theme tokens: corners, strokes, padding, text, panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = require(script.Parent.Create)

local Style = {}

function Style.corner(radius: UDim?): UICorner
	return Create("UICorner", { CornerRadius = radius or Theme.Radius.M })
end

function Style.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Create("UIStroke", {
		Color = color or Theme.Colors.Border,
		Thickness = thickness or Theme.Stroke.Regular,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Style.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Style.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or Theme.Spacing.S),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function Style.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Create("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

export type TextProps = {
	Text: string?,
	TextSize: number?,
	Font: Enum.Font?,
	Color: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	XAlign: Enum.TextXAlignment?,
	YAlign: Enum.TextYAlignment?,
	Wrapped: boolean?,
	AutomaticSize: Enum.AutomaticSize?,
	LayoutOrder: number?,
	Name: string?,
	RichText: boolean?,
	Parent: Instance?,
}

function Style.text(props: TextProps): TextLabel
	return Create("TextLabel", {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.TextSize.Body,
		Font = props.Font or Theme.Fonts.Body,
		TextColor3 = props.Color or Theme.Colors.TextPrimary,
		Size = props.Size or UDim2.new(1, 0, 0, (props.TextSize or Theme.TextSize.Body) + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = if props.Wrapped == nil then true else props.Wrapped,
		TextTruncate = if props.Wrapped == false then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		RichText = props.RichText or false,
		Parent = props.Parent,
	})
end

export type PanelProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	Transparency: number?,
	StrokeColor: Color3?,
	Radius: UDim?,
	Padding: number?,
	AutomaticSize: Enum.AutomaticSize?,
	LayoutOrder: number?,
	Parent: Instance?,
}

function Style.panel(props: PanelProps): Frame
	local frame = Create("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = props.Color or Theme.Colors.Surface,
		BackgroundTransparency = props.Transparency or Theme.Transparency.Panel,
		BorderSizePixel = 0,
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
	}, {
		Style.corner(props.Radius) :: Instance,
		Style.stroke(props.StrokeColor or Theme.Colors.Border, Theme.Stroke.Thin, 0.2),
		Style.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 204, 236), 110),
	})
	if props.Padding then
		Style.padding(props.Padding).Parent = frame
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- Formats seconds as m:ss (never negative).
function Style.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Style
