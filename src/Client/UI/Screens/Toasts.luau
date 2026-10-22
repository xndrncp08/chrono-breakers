--!strict
-- Toast stack (right side) and announcement banner (top centre). Bounded: at most MAX_TOASTS on
-- screen; older toasts are removed first. Banners replace each other. Toasts draw above modals (they
-- report shop/loadout actions); the banner draws beneath them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Workspace = game:GetService("Workspace")
local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Severity = require(script.Parent.Severity)
local Style = require(script.Parent.Parent.Components.Style)

export type Toasts = {
	Toast: (self: Toasts, text: string, severity: string?, duration: number?) -> (),
	Announce: (self: Toasts, text: string, severity: string?, duration: number?) -> (),
}

local MAX_TOASTS = 4

local Toasts = {}

function Toasts.new(parent: Instance): Toasts
	local stack = Create("Frame", {
		Name = "ToastStack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, 440), -- below the lobby menu / squad panel
		-- Fill the space left below the lobby menu so short screens never push toasts offscreen.
		Size = UDim2.new(0, 340, 1, -(440 + Theme.Spacing.L)),
		ZIndex = 30,
		Parent = parent,
	}, {
		Create("UIListLayout", {
			Padding = UDim.new(0, Theme.Spacing.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})

	local banner = Style.panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(620, 88),
		Color = Theme.Colors.Background,
		Transparency = 0.15,
		Radius = Theme.Radius.M,
		Parent = parent,
	})
	banner.Visible = false
	banner.ZIndex = 15 -- above the HUD but beneath modals (20), so it never covers a dialog's title bar
	Create("UISizeConstraint", { MaxSize = Vector2.new(620, 88), Parent = banner })
	banner.Size = UDim2.new(0.9, 0, 0, 88)
	local bannerAccent = Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 4, 1, -16),
		Position = UDim2.fromOffset(10, 8),
		BorderSizePixel = 0,
		Parent = banner,
	}, { Style.corner(Theme.Radius.Pill) }) :: Frame
	local bannerText = Style.text({
		Name = "Text",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(26, 0),
		XAlign = Enum.TextXAlignment.Center,
		Parent = banner,
	})
	local bannerToken = 0
	local bannerTween: Tween? = nil
	local order = 0

	local self = {} :: any

	function self:Toast(text: string, severity: string?, duration: number?)
		local children = {}
		for _, child in stack:GetChildren() do
			if child:IsA("Frame") then
				table.insert(children, child)
			end
		end
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local camera = Workspace.CurrentCamera
		local compact = ClientState.get("inputType") == "Touch" and camera ~= nil and camera.ViewportSize.Y < 600
		local top = if compact then 115 else 440
		stack.Position = UDim2.new(1, -Theme.Spacing.L, 0, top)
		stack.Size = UDim2.new(0, if compact then 300 else 340, 1, -(top + Theme.Spacing.L))
		local limit = if compact then 1 else MAX_TOASTS
		while #children >= limit do
			local oldest = table.remove(children, 1)
			if oldest then
				oldest:Destroy()
			end
		end
		order += 1
		local color = Severity.color(severity)
		local toast = Style.panel({
			Name = "Toast",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Color = Theme.Colors.Background,
			Transparency = 0.1,
			StrokeColor = color,
			Radius = Theme.Radius.S,
			Padding = Theme.Spacing.M,
			LayoutOrder = order,
			Parent = stack,
		})
		Style.text({
			Text = `{Severity.icon(severity)}  {text}`,
			TextSize = Theme.TextSize.Small,
			Font = Theme.Fonts.Body,
			Color = color,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = toast,
		})
		task.delay(duration or 3, function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end

	function self:Announce(text: string, severity: string?, duration: number?)
		local userId = game:GetService("Players").LocalPlayer.UserId
		for _, terminal in ClientState.get("terminals") or {} do
			if
				terminal.state == "Hacking"
				and (terminal.hackerUserId == userId or table.find(terminal.assistants or {}, userId) ~= nil)
			then
				self:Toast(text, severity, duration)
				return
			end
		end
		bannerToken += 1
		local token = bannerToken
		local color = Severity.color(severity)
		bannerAccent.BackgroundColor3 = color
		bannerText.TextColor3 = color
		bannerText.Text = text
		banner.Visible = true
		if bannerTween then
			bannerTween:Cancel()
			bannerTween = nil
		end
		local settings = ClientState.get("settings")
		if not (settings and settings.ReducedMotion) then
			banner.Position = UDim2.new(0.5, 0, 0, 80)
			bannerTween = TweenService:Create(
				banner,
				TweenInfo.new(Theme.Motion.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, 96) }
			)
			local current = bannerTween :: Tween
			current:Play()
		else
			banner.Position = UDim2.new(0.5, 0, 0, 96)
		end
		task.delay(duration or 4, function()
			if bannerToken == token then
				banner.Visible = false
			end
		end)
	end

	return self :: Toasts
end

return Toasts
