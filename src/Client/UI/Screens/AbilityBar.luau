--!strict
-- Ability bar for the Time-Keeper kit or the Infiltrator's gadget. Each slot shows name, key hint
-- for the current device, a cooldown sweep with seconds remaining, and unavailable states
-- (restrained, intro, limit reached, aiming). Slots are buttons, so touch and gamepad users can
-- activate abilities directly; on touch the bar moves to the right edge above the jump button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

local AbilityBar = {}

type Slot = {
	abilityId: string,
	button: TextButton,
	name: TextLabel,
	hint: TextLabel,
	cooldownFill: Frame,
	cooldownText: TextLabel,
	stroke: UIStroke,
	count: TextLabel,
}

local Workspace = game:GetService("Workspace")
local SLOT_SIZE = 92

function AbilityBar.new(parent: Instance, deps: { [string]: any })
	local bar = Create("Frame", {
		Name = "AbilityBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Spacing.L),
		Size = UDim2.fromOffset(0, SLOT_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = parent,
	})
	local layout = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		CellPadding = UDim2.fromOffset(8, 8),
		FillDirectionMaxCells = 4,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	}) :: UIGridLayout

	-- Touch confirm/cancel for ground targeting.
	local targetingRow = Create("Frame", {
		Name = "TargetingControls",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SLOT_SIZE + Theme.Spacing.XL + 40)),
		Size = UDim2.fromOffset(300, 52),
		Visible = false,
		Parent = parent,
	}, { Style.list(Enum.FillDirection.Horizontal, Theme.Spacing.M, Enum.HorizontalAlignment.Center) })
	local targetingLabel = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Temporal,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SLOT_SIZE + Theme.Spacing.XL)),
		Size = UDim2.fromOffset(460, 24),
		XAlign = Enum.TextXAlignment.Center,
		Parent = parent,
	})
	targetingLabel.Visible = false

	local function makeTouchButton(text: string, color: Color3, onActivated: () -> ())
		local b = Create("TextButton", {
			Size = UDim2.fromOffset(130, 52),
			BackgroundColor3 = color,
			Text = text,
			Font = Theme.Fonts.Heading,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Colors.TextOnAccent,
			AutoButtonColor = true,
			Parent = targetingRow,
		}, { Style.corner(Theme.Radius.S) }) :: TextButton
		b.Activated:Connect(onActivated)
	end
	makeTouchButton("Confirm", Theme.Colors.Temporal, function()
		deps.InputController.ConfirmTargeting()
	end)
	makeTouchButton("Cancel", Theme.Colors.TextSecondary, function()
		deps.InputController.CancelTargeting()
	end)

	local slots: { Slot } = {}

	local function clear()
		for _, slot in slots do
			slot.button:Destroy()
		end
		table.clear(slots)
	end

	local function build(abilityIds: { string })
		clear()
		for index, abilityId in abilityIds do
			local definition = AbilityConfig.get(abilityId)
			if definition then
				local stroke = Style.stroke(Theme.Colors.BorderStrong, Theme.Stroke.Regular, 0)
				local button = Create("TextButton", {
					Name = `Slot_{abilityId}`,
					Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
					BackgroundColor3 = Theme.Colors.Surface,
					BackgroundTransparency = 0.1,
					AutoButtonColor = false,
					Text = "",
					LayoutOrder = index,
					Selectable = true,
					ClipsDescendants = true,
					Parent = bar,
				}, { Style.corner(Theme.Radius.M) :: Instance, stroke }) :: TextButton
				local cooldownFill = Create("Frame", {
					Name = "Cooldown",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Size = UDim2.fromScale(1, 0),
					BackgroundColor3 = Theme.Colors.Overlay,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = button,
				}) :: Frame
				local name = Style.text({
					Text = definition.DisplayName,
					Font = Theme.Fonts.Heading,
					TextSize = Theme.TextSize.Micro,
					Size = UDim2.new(1, -8, 0, 32),
					Position = UDim2.fromOffset(4, 30),
					XAlign = Enum.TextXAlignment.Center,
					Parent = button,
				})
				name.ZIndex = 3
				local hint = Style.text({
					Text = "",
					Font = Theme.Fonts.Mono,
					TextSize = Theme.TextSize.Small,
					Color = Theme.Colors.Warning,
					Size = UDim2.new(1, 0, 0, 20),
					Position = UDim2.fromOffset(0, 6),
					XAlign = Enum.TextXAlignment.Center,
					Wrapped = false,
					Parent = button,
				})
				hint.ZIndex = 3
				local cooldownText = Style.text({
					Text = "",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Heading,
					Size = UDim2.new(1, 0, 0, 26),
					Position = UDim2.new(0, 0, 1, -30),
					XAlign = Enum.TextXAlignment.Center,
					Parent = button,
				})
				cooldownText.ZIndex = 3
				local count = Style.text({
					Text = "",
					Font = Theme.Fonts.Heading,
					TextSize = Theme.TextSize.Micro,
					Color = Theme.Colors.TextSecondary,
					Size = UDim2.new(1, -8, 0, 16),
					Position = UDim2.new(0, 4, 1, -20),
					XAlign = Enum.TextXAlignment.Right,
					Parent = button,
				})
				count.ZIndex = 3
				button.Activated:Connect(function()
					deps.InputController.Activate(abilityId)
				end)
				table.insert(slots, {
					abilityId = abilityId,
					button = button,
					name = name,
					hint = hint,
					cooldownFill = cooldownFill,
					cooldownText = cooldownText,
					stroke = stroke,
					count = count,
				})
			end
		end
	end

	local function applyLayout()
		local touch = ClientState.get("inputType") == "Touch"
		local camera = Workspace.CurrentCamera
		local portrait = camera ~= nil and camera.ViewportSize.X < 700
		local cell = if touch then 76 else SLOT_SIZE
		local columns = if touch then 2 else math.max(1, #slots)
		local rows = math.max(1, math.ceil(#slots / columns))
		layout.CellSize = UDim2.fromOffset(cell, cell)
		layout.FillDirectionMaxCells = columns
		bar.AutomaticSize = Enum.AutomaticSize.None
		bar.Size = UDim2.fromOffset(math.min(columns, math.max(1, #slots)) * (cell + 8) - 8, rows * (cell + 8) - 8)
		bar.AnchorPoint = if touch and not portrait then Vector2.new(1, 1) else Vector2.new(0.5, 1)
		bar.Position = if touch and not portrait
			then UDim2.new(1, -Theme.Spacing.L, 1, -190)
			else UDim2.new(0.5, 0, 1, -Theme.Spacing.L)
		local slotSize = if touch then 76 else SLOT_SIZE
		for _, slot in slots do
			slot.button.Size = UDim2.fromOffset(slotSize, slotSize)
			local hintText = deps.InputController.HintFor(slot.abilityId)
			slot.hint.Text = hintText
			slot.hint.Visible = hintText ~= ""
		end
	end

	local function refresh()
		local states = ClientState.get("abilities") or {}
		local movement = ClientState.get("movement") or {}
		local snapshot = ClientState.get("snapshot")
		local phase = if snapshot then snapshot.phase else ""
		local castable = phase == "Active" or phase == "Extraction"
		local restrained = movement.stunned or movement.rooted
		local targeting = ClientState.get("targeting")
		local now = ClientState.now()
		for _, slot in slots do
			local state = states[slot.abilityId]
			local definition = AbilityConfig.get(slot.abilityId)
			local remaining = if state then math.max(0, state.readyAt - now) else 0
			local cooldown = if state then state.cooldown else (if definition then definition.Cooldown else 1)
			local fraction = if cooldown > 0 then math.clamp(remaining / cooldown, 0, 1) else 0
			slot.cooldownFill.Size = UDim2.fromScale(1, fraction)
			slot.cooldownText.Text = if remaining > 0
				then (if remaining >= 10 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining))
				else ""
			local limitReached = state ~= nil and state.maxActive ~= nil and state.active >= state.maxActive
			slot.count.Text = if state
					and state.maxActive
					and state.maxActive > 1
				then `{state.active}/{state.maxActive}`
				else ""
			local available = castable and not restrained and remaining <= 0 and not limitReached
			if targeting == slot.abilityId then
				slot.stroke.Color = Theme.Colors.Temporal
				slot.stroke.Thickness = Theme.Stroke.Strong
			elseif available then
				slot.stroke.Color = Theme.Colors.Stable
				slot.stroke.Thickness = Theme.Stroke.Regular
			else
				slot.stroke.Color = Theme.Colors.Border
				slot.stroke.Thickness = Theme.Stroke.Thin
			end
			slot.name.TextColor3 = if available then Theme.Colors.TextPrimary else Theme.Colors.TextMuted
			if not castable then
				slot.cooldownText.Text = if phase == "Intro" then "…" else ""
			elseif restrained and remaining <= 0 then
				slot.cooldownText.Text = "✕"
			end
		end
		local targetingDef = if targeting then AbilityConfig.get(targeting) else nil
		local touch = ClientState.get("inputType") == "Touch"
		targetingRow.Visible = targetingDef ~= nil and touch
		targetingLabel.Visible = targetingDef ~= nil
		if targetingDef then
			local inputType = ClientState.get("inputType")
			local how = if inputType == "KeyboardMouse"
				then "Click to place · Right-click to cancel"
				elseif inputType == "Gamepad" then "Press again or R2 to place · B to cancel"
				else "Aim with the camera, then Confirm"
			targetingLabel.Text = `{targetingDef.DisplayName}: {how}`
		end
	end

	local currentKey = ""
	local function rebuildFromRole()
		local role = ClientState.currentRole()
		local ids: { string } = {}
		if role and ClientState.isLiveParticipant() then
			ids = role.abilities
		end
		local key = table.concat(ids, ",")
		if key ~= currentKey then
			currentKey = key
			build(ids)
			deps.InputController.BindAbilities(ids)
		end
		applyLayout()
		refresh()
	end

	ClientState.changed:Connect(function(key: string)
		if key == "role" or key == "snapshot" then
			rebuildFromRole()
		elseif key == "inputType" then
			applyLayout()
			refresh()
		elseif key == "abilities" or key == "movement" or key == "targeting" then
			refresh()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 and #slots > 0 then
			accumulator = 0
			refresh()
		end
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	local self = {}
	function self.Reset()
		currentKey = ""
		build({})
		deps.InputController.UnbindAbilities()
	end
	function self.SetVisible(visible: boolean)
		bar.Visible = visible
		if not visible then
			targetingRow.Visible = false
			targetingLabel.Visible = false
			deps.InputController.CancelTargeting()
		end
	end
	return self
end

return AbilityBar
