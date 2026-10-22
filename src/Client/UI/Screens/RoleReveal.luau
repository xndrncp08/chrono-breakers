--!strict
-- Role reveal / match introduction overlay. Shown when a RoleAssigned arrives during Intro and
-- dismissed automatically when the match goes Active.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local ConditionConfig = require(ReplicatedStorage.Shared.Config.ConditionConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

local RoleReveal = {}

function RoleReveal.new(parent: Instance, deps: { [string]: any })
	local root = Create("Frame", {
		Name = "RoleReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	local accent = Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 290),
		BackgroundColor3 = Theme.Colors.Surface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = root,
	}, {})
	local gradient = Style.gradient(Theme.Colors.Surface, Theme.Colors.Background, 0)
	gradient.Parent = accent

	local content = Create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 1, -24),
		ZIndex = 42,
		Parent = accent,
	}, {
		Create("UISizeConstraint", { MaxSize = Vector2.new(820, 400) }),
		Style.list(Enum.FillDirection.Vertical, Theme.Spacing.S, Enum.HorizontalAlignment.Center),
	})
	local kicker = Style.text({
		Text = "YOUR ROLE",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = content,
	})
	local roleName = Style.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Hero,
		Size = UDim2.new(1, 0, 0, 64),
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = content,
	})
	local tagline = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Heading,
		Size = UDim2.new(1, 0, 0, 30),
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		Parent = content,
	})
	local description = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 44),
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = content,
	})
	local kit = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Font = Theme.Fonts.Heading,
		Color = Theme.Colors.TextPrimary,
		Size = UDim2.new(1, 0, 0, 24),
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 5,
		Parent = content,
	})
	local timeline = Style.text({
		Name = "TimelineCondition",
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Temporal,
		Size = UDim2.new(1, 0, 0, 20),
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 6,
		Parent = content,
	})
	local countdown = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 7,
		Parent = content,
	})
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = 43
		end
	end
	kicker.ZIndex = 43

	local shownFor: string? = nil
	local entrance: Tween? = nil
	local revealScale = Create("UIScale", { Scale = 1, Parent = accent }) :: UIScale

	local function hide()
		if entrance then
			entrance:Cancel()
			entrance = nil
		end
		revealScale.Scale = 1
		root.Visible = false
	end

	local function show(role: any)
		local color = (Theme.RoleColors :: any)[role.role] or Theme.Colors.Stable
		local class = ClassConfig.get(role.classId)
		roleName.Text = string.upper(if class then class.Name else role.displayName)
		if class then
			color = class.Color
		end
		kicker.Text = `DEPLOYMENT / {string.upper(role.mapName or "CHRONOS VAULT")} / {role.role}`
		roleName.TextColor3 = color
		tagline.Text = role.tagline
		tagline.TextColor3 = color
		description.Text = if class then class.Description else role.description
		local names = {}
		for _, abilityId in role.abilities do
			local definition = AbilityConfig.get(abilityId)
			if definition then
				table.insert(names, definition.DisplayName)
			end
		end
		local kitText = if #names > 0 then "KIT: " .. table.concat(names, "  ·  ") else ""
		if role.role == "Infiltrator" and role.hasKeeper then
			kitText ..= `   |   TIME-KEEPER: {role.keeperName}`
		end
		kit.Text = kitText
		local condition = ConditionConfig.get(role.condition)
		timeline.Text = if condition and condition.Id ~= "Stable"
			then `TIMELINE: {string.upper(condition.Name)} — {condition.Description}`
			else ""
		timeline.Visible = timeline.Text ~= ""
		gradient.Color = ColorSequence.new(color:Lerp(Theme.Colors.Background, 0.75), Theme.Colors.Background)
		root.Visible = true
		deps.AudioController.Play("RoleReveal")
		local settings = ClientState.get("settings")
		if not (settings and settings.ReducedMotion) then
			if entrance then
				entrance:Cancel()
			end
			revealScale.Scale = 0.97
			entrance = TweenService:Create(
				revealScale,
				TweenInfo.new(Theme.Motion.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Scale = 1 }
			)
			local current = entrance :: Tween
			current:Play()
		end
	end

	local function evaluate()
		local role = ClientState.get("role")
		local snapshot = ClientState.get("snapshot")
		if role and snapshot and snapshot.matchId == role.matchId and snapshot.phase == "Intro" then
			if shownFor ~= role.matchId then
				shownFor = role.matchId
				show(role)
			end
		elseif root.Visible then
			hide()
		end
	end

	ClientState.changed:Connect(function(key: string)
		if key == "settings" and ClientState.get("settings").ReducedMotion then
			if entrance then
				entrance:Cancel()
				entrance = nil
			end
			revealScale.Scale = 1
		end
		if key == "role" or key == "snapshot" then
			evaluate()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 or not root.Visible then
			return
		end
		accumulator = 0
		local snapshot = ClientState.get("snapshot")
		if snapshot and snapshot.phaseEndsAt then
			countdown.Text = `Match begins in {math.max(0, math.ceil(snapshot.phaseEndsAt - ClientState.now()))}s`
		end
	end)
end

return RoleReveal
