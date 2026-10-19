--!strict
-- Calibration Pulse ring: a needle sweeps a segmented ring once; the marked arc (leading part green
-- = Great) is where to press. Rendered from Theme-coloured frames only (no image assets). Timing
-- comes from the server's synchronised clock; the server judges the press, this only displays it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

export type CalibrationRing = {
	Instance: Frame,
	Show: (self: CalibrationRing, challenge: any, hint: string) -> (),
	Hide: (self: CalibrationRing) -> (),
	Update: (self: CalibrationRing) -> (),
	Flash: (self: CalibrationRing, grade: string) -> (),
	Pressed: (callback: () -> ()) -> (),
}

local CalibrationRing = {}

local SEGMENTS = 48
local RADIUS = 66

local GRADE_COLORS: { [string]: Color3 } = {
	Great = Theme.Colors.Success,
	Good = Theme.Colors.Stable,
	Miss = Theme.Colors.Danger,
}

function CalibrationRing.new(parent: Instance): CalibrationRing
	local root = Create("Frame", {
		Name = "CalibrationRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RADIUS * 2 + 40, RADIUS * 2 + 64),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local dial = Create("Frame", {
		Name = "Dial",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, RADIUS + 20),
		Size = UDim2.fromOffset(RADIUS * 2 + 20, RADIUS * 2 + 20),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.35,
		Parent = root,
	}, { Style.corner(Theme.Radius.Pill) :: Instance, Style.stroke(Theme.Colors.Border, Theme.Stroke.Regular, 0.2) }) :: Frame
	local segments: { Frame } = {}
	for i = 1, SEGMENTS do
		local angle = (i - 0.5) / SEGMENTS * 360
		local radians = math.rad(angle)
		local segment = Create("Frame", {
			Name = `Seg{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(radians) * RADIUS, 0.5, -math.cos(radians) * RADIUS),
			Size = UDim2.fromOffset(6, 13),
			Rotation = angle,
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.Colors.Border,
			Parent = dial,
		}, { Style.corner(UDim.new(0, 2)) }) :: Frame
		segments[i] = segment
	end
	local needle = Create("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, RADIUS + 6),
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Colors.TextPrimary,
		Parent = dial,
	}, { Style.corner(UDim.new(0, 2)) }) :: Frame
	local center = Style.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Heading,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(110, 40),
		XAlign = Enum.TextXAlignment.Center,
		Parent = dial,
	})
	local hintLabel = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Warning,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 40, 0, 22),
		XAlign = Enum.TextXAlignment.Center,
		Parent = root,
	})
	-- Large invisible tap target for touch players.
	local tap = Create("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = root,
	}) :: TextButton

	local current: any = nil
	local flashUntil = 0
	local self = { Instance = root } :: any

	local function needleAngle(displayAngle: number): number
		return if current and current.direction == -1 then 360 - displayAngle else displayAngle
	end

	local function paint()
		if not current then
			return
		end
		local arcStart, arcEnd = current.arcStart, current.arcStart + current.arcWidth
		local greatEnd = current.arcStart + current.greatWidth
		for i, segment in segments do
			local angle = needleAngle((i - 0.5) / SEGMENTS * 360)
			if angle >= arcStart and angle <= arcEnd then
				segment.BackgroundColor3 = if angle <= greatEnd then Theme.Colors.Success else Theme.Colors.Warning
				segment.Size = UDim2.fromOffset(8, 17)
			else
				segment.BackgroundColor3 = Theme.Colors.Border
				segment.Size = UDim2.fromOffset(6, 13)
			end
		end
	end

	function self:Show(challenge: any, hint: string)
		if not current or current.nonce ~= challenge.nonce then
			current = challenge
			paint()
		end
		hintLabel.Text = hint
		root.Visible = true
	end

	function self:Hide()
		current = nil
		if os.clock() > flashUntil then
			root.Visible = false
		end
	end

	function self:Flash(grade: string)
		flashUntil = os.clock() + 0.7
		center.Text = string.upper(grade)
		center.TextColor3 = GRADE_COLORS[grade] or Theme.Colors.TextPrimary
		root.Visible = true
	end

	function self:Update()
		local now = os.clock()
		if not current then
			if now > flashUntil then
				root.Visible = false
			end
			return
		end
		local t = ClientState.now() - current.startAt
		if t < 0 then
			needle.Rotation = 0
			needle.BackgroundColor3 = Theme.Colors.TextMuted
			if now > flashUntil then
				center.Text = "READY"
				center.TextColor3 = Theme.Colors.Warning
			end
			return
		end
		local angle = math.clamp(t / current.sweep, 0, 1) * 360
		needle.Rotation = if current.direction == -1 then -angle else angle
		needle.BackgroundColor3 = Theme.Colors.TextPrimary
		if now > flashUntil then
			center.Text = ""
		end
	end

	function self.Pressed(callback: () -> ())
		tap.Activated:Connect(callback)
	end

	return self :: CalibrationRing
end

return CalibrationRing
