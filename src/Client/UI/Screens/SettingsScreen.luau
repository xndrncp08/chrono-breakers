--!strict
-- Settings: audio volumes, reduced motion, UI scale, and control hints. Changes apply locally at
-- once (so the player sees the effect) and are sent to the server, which validates and persists
-- them. Every control is a button, so mouse, touch, and gamepad navigation all work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Parent.Net)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local Modal = require(script.Parent.Parent.Components.Modal)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)

local SettingsScreen = {}

local SCALE_OPTIONS =
	{ { label = "Small", value = 0.85 }, { label = "Default", value = 1 }, { label = "Large", value = 1.2 } }

function SettingsScreen.new(parent: Instance, deps: { [string]: any })
	local modal = Modal.new({ Name = "Settings", Title = "Settings", Width = 600, Height = 540, Parent = parent })
	local body = modal.Body
	local rows = Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -28),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Selectable = false,
		Parent = body,
	}, { Style.list(Enum.FillDirection.Vertical, Theme.Spacing.M) })
	local footer = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextMuted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = body,
	})

	local pendingSend: { [string]: any } = {}
	local sendToken = 0
	local firstButton: GuiObject? = nil

	local function current(): { [string]: any }
		return ClientState.get("settings") or {}
	end

	local function update(key: string, value: any)
		local settings = table.clone(current())
		settings[key] = value
		ClientState.set("settings", settings)
		pendingSend[key] = value
		sendToken += 1
		local token = sendToken
		-- Debounce so rapid stepping sends one request.
		task.delay(0.5, function()
			if token == sendToken and next(pendingSend) then
				Net.send(RemoteNames.SettingsUpdate, pendingSend)
				pendingSend = {}
			end
		end)
	end

	local renderers: { () -> () } = {}

	local function row(label: string, order: number): Frame
		local frame = Create("Frame", {
			Name = label,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, Theme.MinTouchTarget),
			LayoutOrder = order,
			Parent = rows,
		}) :: Frame
		Style.text({
			Text = label,
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Body,
			Size = UDim2.fromScale(0.4, 1),
			Parent = frame,
		})
		return frame
	end

	local function volumeRow(label: string, key: string, order: number, note: string?)
		local frame = row(label, order)
		local bar = ProgressBar.new({
			Size = UDim2.new(0.2, 0, 0, 16),
			Position = UDim2.fromScale(0.4, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = frame,
		})
		local function step(delta: number)
			local value = math.clamp(math.floor(((current()[key] or 0.5) + delta) * 10 + 0.5) / 10, 0, 1)
			update(key, value)
			deps.AudioController.Play("UiClick")
		end
		local minus = Button.new({
			Text = "−",
			Style = "Secondary",
			Size = UDim2.fromOffset(Theme.MinTouchTarget, Theme.MinTouchTarget),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(Theme.MinTouchTarget + 8), 0, 0),
			OnActivated = function()
				step(-0.1)
			end,
			Parent = frame,
		})
		Button.new({
			Text = "+",
			Style = "Secondary",
			Size = UDim2.fromOffset(Theme.MinTouchTarget, Theme.MinTouchTarget),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			OnActivated = function()
				step(0.1)
			end,
			Parent = frame,
		})
		if firstButton == nil then
			firstButton = minus.Instance
		end
		table.insert(renderers, function()
			local value = current()[key] or 0
			bar:Set(value)
			bar:SetLabel(`{math.floor(value * 100 + 0.5)}%{if note then " " .. note else ""}`)
		end)
	end

	local function toggleRow(label: string, key: string, order: number)
		local frame = row(label, order)
		local button: Button.Button
		button = Button.new({
			Text = "",
			Style = "Secondary",
			Size = UDim2.fromOffset(160, Theme.MinTouchTarget),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			OnActivated = function()
				update(key, not current()[key])
				deps.AudioController.Play("UiClick")
			end,
			Parent = frame,
		})
		table.insert(renderers, function()
			local on = current()[key] == true
			button:SetText(if on then "On" else "Off")
			button:SetStyle(if on then "Primary" else "Secondary")
		end)
	end

	local function scaleRow(order: number)
		local frame = row("Interface size", order)
		local group = Create("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.6, 1),
			Parent = frame,
		}, { Style.list(Enum.FillDirection.Horizontal, Theme.Spacing.S, Enum.HorizontalAlignment.Right) })
		local buttons: { Button.Button } = {}
		for index, option in SCALE_OPTIONS do
			buttons[index] = Button.new({
				Text = option.label,
				Style = "Secondary",
				Size = UDim2.new(1 / 3, -6, 0, Theme.MinTouchTarget),
				LayoutOrder = index,
				TextSize = Theme.TextSize.Small,
				OnActivated = function()
					update("UIScale", option.value)
					deps.AudioController.Play("UiClick")
				end,
				Parent = group,
			})
		end
		table.insert(renderers, function()
			local value = current().UIScale or 1
			for index, option in SCALE_OPTIONS do
				buttons[index]:SetStyle(if math.abs(option.value - value) < 0.01 then "Primary" else "Secondary")
			end
		end)
	end

	volumeRow("Effects volume", "SfxVolume", 1)
	volumeRow("Interface volume", "UiVolume", 2)
	volumeRow("Music volume", "MusicVolume", 3, "(no track configured)")
	toggleRow("Reduced motion", "ReducedMotion", 4)
	scaleRow(5)
	toggleRow("Control hints", "ShowControlHints", 6)

	local function render()
		for _, renderer in renderers do
			renderer()
		end
		local profile = ClientState.get("profile")
		footer.Text = if profile and profile.persistent
			then "Settings are saved to your profile."
			else "Settings apply now but won't persist (profile unavailable)."
	end

	ClientState.observe("settings", function()
		if modal:IsOpen() then
			render()
		end
	end)

	local self = {}
	self.Modal = modal
	function self.Open()
		render()
		modal:Open()
		modal:Focus(firstButton)
	end
	return self
end

return SettingsScreen
