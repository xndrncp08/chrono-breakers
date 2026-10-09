--!strict
-- Reusable button with hover, pressed, gamepad-selected, disabled, and loading states. Activated
-- fires for mouse click, touch tap, and gamepad A (when selected), so one handler serves all inputs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)

export type ButtonStyle = "Primary" | "Secondary" | "Danger" | "Ghost" | "Temporal"

export type ButtonProps = {
	Text: string,
	Style: ButtonStyle?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	TextSize: number?,
	Hint: string?, -- optional key hint shown at the right edge
	OnActivated: () -> (),
	Parent: Instance?,
}

export type Button = {
	Instance: TextButton,
	SetText: (self: Button, text: string) -> (),
	SetEnabled: (self: Button, enabled: boolean) -> (),
	SetLoading: (self: Button, loading: boolean) -> (),
	SetStyle: (self: Button, style: ButtonStyle) -> (),
	SetHint: (self: Button, hint: string?) -> (),
	Destroy: (self: Button) -> (),
}

local PALETTE: { [string]: { bg: Color3, text: Color3, stroke: Color3 } } = {
	Primary = { bg = Theme.Colors.Stable, text = Theme.Colors.TextOnAccent, stroke = Theme.Colors.Stable },
	Temporal = { bg = Theme.Colors.Temporal, text = Theme.Colors.TextPrimary, stroke = Theme.Colors.Temporal },
	Secondary = { bg = Theme.Colors.SurfaceRaised, text = Theme.Colors.TextPrimary, stroke = Theme.Colors.BorderStrong },
	Danger = { bg = Theme.Colors.Danger, text = Theme.Colors.TextPrimary, stroke = Theme.Colors.Danger },
	Ghost = { bg = Theme.Colors.Surface, text = Theme.Colors.TextSecondary, stroke = Theme.Colors.Border },
}

local ButtonModule = {}

function ButtonModule.new(props: ButtonProps): Button
	local style: ButtonStyle = props.Style or "Primary"
	local enabled = true
	local loading = false
	local hovered = false
	local selected = false
	local label = props.Text

	local stroke = Style.stroke(PALETTE[style].stroke, Theme.Stroke.Regular, 0)
	local instance = Create("TextButton", {
		Name = "Button_" .. string.gsub(props.Text, "%W", ""),
		Size = props.Size or UDim2.fromOffset(200, Theme.MinTouchTarget),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = props.Text,
		Font = Theme.Fonts.Heading,
		TextSize = props.TextSize or Theme.TextSize.Body,
		TextWrapped = true,
		Selectable = true,
	}, {
		Style.corner(Theme.Radius.S) :: Instance,
		stroke,
	}) :: TextButton

	local hint = Create("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(60, 18),
		Font = Theme.Fonts.Mono,
		TextSize = Theme.TextSize.Micro,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = instance,
	}) :: TextLabel

	-- Visible selection ring for gamepad focus.
	instance.SelectionImageObject = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 8, 1, 8),
		Position = UDim2.fromOffset(-4, -4),
	}, {
		Style.corner(Theme.Radius.M) :: Instance,
		Style.stroke(Theme.Colors.Warning, Theme.Stroke.Strong, 0),
	})

	local function render()
		local palette = PALETTE[style]
		local bg = palette.bg
		local transparency = 0
		if style == "Ghost" then
			transparency = 0.3
		end
		if not enabled then
			bg = Theme.Colors.SurfaceRaised
			instance.TextColor3 = Theme.Colors.TextMuted
			stroke.Color = Theme.Colors.Border
			transparency = 0.2
		else
			instance.TextColor3 = palette.text
			stroke.Color = if selected then Theme.Colors.Warning else palette.stroke
			if hovered or selected then
				bg = bg:Lerp(Color3.new(1, 1, 1), 0.12)
			end
		end
		instance.BackgroundColor3 = bg
		instance.BackgroundTransparency = transparency
		instance.Text = if loading then "…" else label
		hint.TextColor3 = instance.TextColor3
		instance.Active = enabled and not loading
		instance.AutoButtonColor = false
	end

	instance.MouseEnter:Connect(function()
		hovered = true
		render()
	end)
	instance.MouseLeave:Connect(function()
		hovered = false
		render()
	end)
	instance.SelectionGained:Connect(function()
		selected = true
		render()
	end)
	instance.SelectionLost:Connect(function()
		selected = false
		render()
	end)
	instance.Activated:Connect(function()
		if enabled and not loading then
			props.OnActivated()
		end
	end)

	local self = { Instance = instance } :: any

	function self:SetText(text: string)
		label = text
		render()
	end

	function self:SetEnabled(value: boolean)
		enabled = value
		render()
	end

	function self:SetLoading(value: boolean)
		loading = value
		render()
	end

	function self:SetStyle(value: ButtonStyle)
		style = value
		render()
	end

	function self:SetHint(value: string?)
		hint.Text = value or ""
		hint.Visible = value ~= nil and value ~= ""
	end

	function self:Destroy()
		instance:Destroy()
	end

	self:SetHint(props.Hint)
	render()
	if props.Parent then
		instance.Parent = props.Parent
	end
	return self :: Button
end

return ButtonModule
