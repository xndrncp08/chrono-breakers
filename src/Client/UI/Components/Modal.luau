--!strict
-- Centred modal dialog with a dimmed backdrop, title bar, close button, and gamepad support
-- (ButtonB / Escape-equivalent closes it; first selectable child receives focus on open).

local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Button = require(script.Parent.Button)
local Create = require(script.Parent.Create)
local Style = require(script.Parent.Style)

export type Modal = {
	Root: Frame,
	Body: Frame,
	IsOpen: (self: Modal) -> boolean,
	Open: (self: Modal) -> (),
	Close: (self: Modal) -> (),
	SetTitle: (self: Modal, text: string) -> (),
	Focus: (self: Modal, target: GuiObject?) -> (),
}

local Modal = {}

function Modal.new(props: {
	Name: string,
	Title: string,
	Width: number,
	Height: number,
	Parent: Instance,
	OnClosed: (() -> ())?,
}): Modal
	local open = false
	local actionName = `CloseModal_{props.Name}`

	local root = Create("Frame", {
		Name = props.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = Theme.Transparency.Overlay,
		Visible = false,
		ZIndex = 20,
		Active = true,
		Parent = props.Parent,
	}) :: Frame

	local window = Style.panel({
		Name = "Window",
		Size = UDim2.fromOffset(props.Width, props.Height),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Surface,
		Transparency = 0.04,
		StrokeColor = Theme.Colors.BorderStrong,
		Radius = Theme.Radius.L,
		Parent = root,
	})
	Create("UISizeConstraint", { MaxSize = Vector2.new(props.Width, props.Height), Parent = window })
	-- Keep the window inside small screens.
	window.Size = UDim2.fromScale(0.94, 0.9)
	local motionScale = Create("UIScale", { Scale = 1, Parent = window }) :: UIScale
	local transition: Tween? = nil
	local previousSelection: GuiObject? = nil
	local function animateScale(to: number)
		if transition then
			transition:Cancel()
			transition = nil
		end
		local settings = ClientState.get("settings")
		if settings and settings.ReducedMotion then
			motionScale.Scale = to
			return
		end
		transition = TweenService:Create(
			motionScale,
			TweenInfo.new(Theme.Motion.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Scale = to }
		)
		local current = transition :: Tween
		current:Play()
	end

	local title = Style.text({
		Name = "Title",
		Text = string.upper(props.Title),
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Heading,
		Color = Theme.Colors.Stable,
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.fromOffset(Theme.Spacing.XL, Theme.Spacing.L),
		Wrapped = false,
		Parent = window,
	})

	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.Spacing.XL, 84),
		Size = UDim2.new(1, -Theme.Spacing.XL * 2, 1, -84 - Theme.Spacing.XL),
		Parent = window,
	}) :: Frame

	local self = { Root = root, Body = body } :: any
	ClientState.observe("settings", function(value)
		if value and value.ReducedMotion then
			if transition then
				transition:Cancel()
				transition = nil
			end
			motionScale.Scale = 1
		end
	end)
	ClientState.observe("modal", function(name)
		if open and name ~= props.Name then
			self:Close()
		end
	end)

	local closeButton = Button.new({
		Text = "Close",
		Style = "Ghost",
		Size = UDim2.fromOffset(96, 40),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, Theme.Spacing.L),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = Theme.TextSize.Small,
		OnActivated = function()
			self:Close()
		end,
		Parent = window,
	})

	function self:IsOpen(): boolean
		return open
	end

	function self:Focus(target: GuiObject?)
		if GuiService:IsTenFootInterface() or game:GetService("UserInputService").GamepadEnabled then
			GuiService.SelectedObject = target or closeButton.Instance
		end
	end

	function self:Open()
		if open then
			return
		end
		open = true
		previousSelection = GuiService.SelectedObject
		ClientState.set("modal", props.Name)
		root.Visible = true
		motionScale.Scale = 0.97
		animateScale(1)
		ContextActionService:BindActionAtPriority(actionName, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				self:Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		self:Focus(nil)
	end

	function self:Close()
		if not open then
			return
		end
		open = false
		if transition then
			transition:Cancel()
			transition = nil
		end
		motionScale.Scale = 1
		root.Visible = false
		if ClientState.get("modal") == props.Name then
			ClientState.set("modal", nil)
		end
		ContextActionService:UnbindAction(actionName)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = if previousSelection and previousSelection.Parent
				then previousSelection
				else nil
		end
		if props.OnClosed then
			props.OnClosed()
		end
	end

	function self:SetTitle(text: string)
		title.Text = string.upper(text)
	end

	return self :: Modal
end

return Modal
