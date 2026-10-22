--!strict
-- In-match HUD built around survival information: phase timer and Temporal Collapse, squad
-- integrity cards, objectives, pursuit overlay, status chips, terminal hacking with Calibration
-- Pulses, survival channels, extraction, ability bar and control hints. Renders only server state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local AnomalyConfig = require(ReplicatedStorage.Shared.Config.AnomalyConfig)
local ConditionConfig = require(ReplicatedStorage.Shared.Config.ConditionConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local AbilityBar = require(script.Parent.AbilityBar)
local CalibrationRing = require(script.Parent.CalibrationRing)
local SquadPanel = require(script.Parent.SquadPanel)
local SurvivalOverlay = require(script.Parent.SurvivalOverlay)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)

local HudScreen = {}

local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local TIER_COLOR: { [string]: Color3 } = {
	Stable = Theme.Colors.Warning,
	Rising = Theme.Colors.Temporal,
	Critical = Theme.Colors.Danger,
}

local TERMINAL_ICON: { [string]: string } = {
	Locked = "▢",
	Available = "◇",
	Hacking = "◈",
	Interrupted = "!",
	Completed = "✓",
}

function HudScreen.new(parent: Instance, deps: { [string]: any })
	local root = Create("Frame", {
		Name = "Hud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = parent,
	})
	local overlay = SurvivalOverlay.new(root)

	-- Timer (top centre)
	local timerPanel = Style.panel({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.Spacing.S),
		Size = UDim2.fromOffset(220, 74),
		Color = Theme.Colors.Background,
		Transparency = 0.2,
		Parent = root,
	})
	local phaseLabel = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 6),
		XAlign = Enum.TextXAlignment.Center,
		Parent = timerPanel,
	})
	local timeLabel = Style.text({
		Text = "--:--",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 24),
		XAlign = Enum.TextXAlignment.Center,
		Parent = timerPanel,
	})

	local anomalyLabel = Style.text({
		Name = "Anomaly",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(420, 48),
		TextSize = Theme.TextSize.Small,
		Font = Theme.Fonts.Heading,
		XAlign = Enum.TextXAlignment.Center,
		Color = Theme.Colors.Warning,
		Parent = root,
	})

	-- Temporal Collapse (under the timer during the endgame)
	local collapsePanel = Style.panel({
		Name = "Collapse",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(300, 58),
		Color = Theme.Colors.Background,
		Transparency = 0.2,
		StrokeColor = Theme.Colors.Temporal,
		Padding = Theme.Spacing.S,
		Parent = root,
	})
	collapsePanel.Visible = false
	local collapseLabel = Style.text({
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Temporal,
		Size = UDim2.new(1, 0, 0, 18),
		XAlign = Enum.TextXAlignment.Center,
		Wrapped = false,
		Parent = collapsePanel,
	})
	local collapseBar = ProgressBar.new({
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 24),
		Color = Theme.Colors.Temporal,
		Parent = collapsePanel,
	})

	-- Squad integrity (left, below the chat area)
	local squad = SquadPanel.new(root)
	squad.Instance.AnchorPoint = Vector2.new(0, 0.5)
	squad.Instance.Position = UDim2.new(0, Theme.Spacing.L, 0.5, 0)

	-- Objectives (top right)
	local objectives = Style.panel({
		Name = "Objectives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, Theme.Spacing.S),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = Theme.Spacing.M,
		Parent = root,
	})
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS).Parent = objectives
	local roleBadge = Style.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		Wrapped = false,
		LayoutOrder = 1,
		Parent = objectives,
	})
	local objectiveHeader = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		Wrapped = false,
		LayoutOrder = 2,
		Parent = objectives,
	})
	local terminalRows = Create("Frame", {
		Name = "TerminalRows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = objectives,
	}, { Style.list(Enum.FillDirection.Vertical, 2) })
	local extractionRow = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Success,
		Wrapped = false,
		LayoutOrder = 4,
		Parent = objectives,
	})

	local pingButton = Button.new({
		Text = "Team ping / G · R1",
		Style = "Secondary",
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 5,
		OnActivated = function()
			deps.InputController.Ping()
		end,
		Parent = objectives,
	})

	-- Health + status chips (bottom left of centre, above the ability bar)
	local vitals = Create("Frame", {
		Name = "Vitals",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -122),
		Size = UDim2.fromOffset(360, 40),
		Parent = root,
	})
	local healthBar = ProgressBar.new({
		Size = UDim2.new(1, 0, 0, 14),
		Color = Theme.Colors.Success,
		Parent = vitals,
	})
	local chips = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 18),
		XAlign = Enum.TextXAlignment.Center,
		RichText = true,
		Parent = vitals,
	})

	-- Terminal hacking panel (centre-low)
	local hackPanel = Style.panel({
		Name = "HackPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -176),
		Size = UDim2.fromOffset(420, 132),
		Color = Theme.Colors.Background,
		Transparency = 0.1,
		StrokeColor = Theme.Colors.Warning,
		Padding = Theme.Spacing.M,
		Parent = root,
	})
	hackPanel.Visible = false
	local hackTitle = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.Warning,
		Size = UDim2.new(1, -110, 0, 22),
		Wrapped = false,
		Parent = hackPanel,
	})
	local hackBar = ProgressBar.new({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 68),
		Color = Theme.Colors.Warning,
		Parent = hackPanel,
	})
	local hackDetail = Style.text({
		Text = `Stay within {TerminalConfig.MaxInteractionDistance} studs. Taking damage interrupts the hack.`,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 94),
		Parent = hackPanel,
	})
	local cancelButton = Button.new({
		Text = "Cancel",
		Style = "Ghost",
		Size = UDim2.fromOffset(100, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -4),
		TextSize = Theme.TextSize.Small,
		OnActivated = function()
			deps.InputController.CancelHack()
		end,
		Parent = hackPanel,
	})

	local calibration = CalibrationRing.new(root)
	calibration.Instance.Position = UDim2.fromScale(0.5, 0.56)
	calibration.Pressed(function()
		deps.InputController.PressCalibration()
	end)

	-- Extraction channel bar
	local extractPanel = Style.panel({
		Name = "ExtractPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -176),
		Size = UDim2.fromOffset(340, 64),
		Color = Theme.Colors.Background,
		Transparency = 0.1,
		StrokeColor = Theme.Colors.Success,
		Padding = Theme.Spacing.M,
		Parent = root,
	})
	extractPanel.Visible = false
	local extractLabel = Style.text({
		Text = "EXTRACTING… hold position",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Success,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = extractPanel,
	})
	local extractBar = ProgressBar.new({
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 24),
		Color = Theme.Colors.Success,
		Parent = extractPanel,
	})

	-- Control hints (bottom left)
	local hints = Style.text({
		Name = "ControlHints",
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextMuted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.Spacing.L, 1, -Theme.Spacing.L),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})

	anomalyLabel.Parent = objectives
	anomalyLabel.Size = UDim2.new(1, 0, 0, 40)
	anomalyLabel.LayoutOrder = 6
	-- Timeline Condition for this match (hidden when Stable).
	local conditionLabel = Style.text({
		Name = "Condition",
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.Temporal,
		RichText = true,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 6,
		Parent = objectives,
	})
	local abilityBar = AbilityBar.new(root, deps)

	local function layout()
		local camera = Workspace.CurrentCamera
		local narrow = camera ~= nil and camera.ViewportSize.X < 700
		local short = camera ~= nil and camera.ViewportSize.Y < 600
		objectives.Size = UDim2.fromOffset(if narrow then 190 else 250, 0)
		squad:SetCompact(narrow or short)
		squad.Instance.Position = UDim2.new(0, Theme.Spacing.L, if short then 0.56 else 0.5, 0)
		timerPanel.Size = UDim2.fromOffset(if narrow then 190 else 220, 74)
		terminalRows.Visible = not (short and ClientState.get("inputType") == "Touch")
	end
	Button.new({
		Text = "Settings",
		Style = "Ghost",
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 7,
		OnActivated = function()
			deps.UIController.OpenModal("Settings")
		end,
		Parent = objectives,
	})
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	layout()

	local interruptedUntil = 0
	local lastHackTerminal: string? = nil
	local hackBound = false

	local function renderTimer()
		local snapshot = ClientState.get("snapshot")
		if not snapshot then
			return
		end
		local condition = ConditionConfig.get(snapshot.condition)
		conditionLabel.Visible = condition ~= nil and condition.Id ~= "Stable"
		if condition and conditionLabel.Visible then
			conditionLabel.Text = `<b>◇ {string.upper(condition.Name)}</b>\n{condition.Description}`
		end
		local anomaly = snapshot.anomaly
		anomalyLabel.Visible = anomaly ~= nil
		if anomaly then
			local definition = (AnomalyConfig.Events :: any)[anomaly.kind]
			local warning = anomaly.state == "Warning"
			local left =
				math.max(0, math.ceil((if warning then anomaly.activatesAt else anomaly.endsAt) - ClientState.now()))
			anomalyLabel.Text = `{definition.Name} / {if warning then "INCOMING" else "ACTIVE"} {left}s`
		end
		local phase = snapshot.phase
		local remaining = if snapshot.phaseEndsAt then snapshot.phaseEndsAt - ClientState.now() else 0
		timeLabel.Text = if snapshot.phaseEndsAt then Style.formatTime(remaining) else "--:--"
		local label = `BREACH · {snapshot.completedHacks}/{snapshot.requiredHacks} TERMINALS`
		local color = Theme.Colors.TextPrimary
		if phase == "Intro" then
			label = "DEPLOYING"
		elseif phase == "Extraction" then
			label = "TEMPORAL COLLAPSE"
			color = Theme.Colors.Temporal
		elseif phase == "Resolving" or phase == "ReturningToLobby" then
			label = "MATCH OVER"
		end
		if (phase == "Active" or phase == "Extraction") and remaining <= 30 then
			color = Theme.Colors.Danger
		end
		phaseLabel.Text = label
		timeLabel.TextColor3 = color

		local collapse = snapshot.collapse
		collapsePanel.Visible = phase == "Extraction" and collapse ~= nil
		if collapse and phase == "Extraction" then
			local tierColor = TIER_COLOR[collapse.tier] or Theme.Colors.Temporal
			local relayText = ""
			if not collapse.gateOpen then
				local best = 0
				for _, power in collapse.relays do
					best = math.max(best, power)
				end
				relayText = ` · RELAY {math.floor(best * 100)}%`
			end
			collapseLabel.Text =
				`{string.upper(collapse.tier)} · GATE {if collapse.gateOpen then "OPEN" else "SEALED"}{relayText}`
			collapseLabel.TextColor3 = tierColor
			local total = SurvivalConfig.Endgame.CollapseDuration
			collapseBar:Set(math.clamp(remaining / total, 0, 1), tierColor)
		end
		if snapshot.rift and phase == "Active" then
			anomalyLabel.Visible = true
			anomalyLabel.Text = "SLIP RIFT OPEN — the last Infiltrator can escape through it"
		end
	end

	local objectiveLabels: { [string]: TextLabel } = {}
	local function renderObjectives()
		local snapshot = ClientState.get("snapshot")
		local role = ClientState.currentRole()
		if not snapshot then
			return
		end
		pingButton.Instance.Visible = role ~= nil and role.role == "Infiltrator"
		if role then
			local color = (Theme.RoleColors :: any)[role.role] or Theme.Colors.Stable
			local class = ClassConfig.get(role.classId)
			roleBadge.Text = string.upper(if class then class.Name else role.displayName)
			if class then
				color = class.Color
			end
			roleBadge.TextColor3 = color
			objectiveHeader.Text = if role.role == "TimeKeeper"
				then `DEFEND · {snapshot.completedHacks}/{snapshot.requiredHacks} breached · Overload idle terminals`
				else `BREACH {snapshot.requiredHacks} OF {#snapshot.terminals} · {snapshot.completedHacks} done`
		end

		local terminals = ClientState.get("terminals") or {}
		for index, publicTerminal in snapshot.terminals do
			local terminal = terminals[publicTerminal.id] or publicTerminal
			local state = terminal.state
			local color = (Theme.TerminalStateColors :: any)[state] or Theme.Colors.TextMuted
			local suffix = ""
			if (state == "Hacking" or state == "Interrupted" or state == "Available") and terminal.progress > 0 then
				suffix = string.format("  %d%%", math.floor(terminal.progress * 100))
			end
			if terminal.regressing then
				suffix ..= "  ▼ OVERLOADED"
				color = Theme.Colors.Danger
			elseif state == "Hacking" then
				suffix ..= `  ×{1 + #(terminal.assistants or {})}`
			end
			local row = objectiveLabels[terminal.id]
			if not row then
				row = Style.text({ TextSize = Theme.TextSize.Small, Wrapped = false, Parent = terminalRows })
				objectiveLabels[terminal.id] = row
			end
			row.Text = `{TERMINAL_ICON[state] or "·"}  {terminal.name}{suffix}`
			row.TextColor3 = color
			row.LayoutOrder = index
		end
		if snapshot.extractionActive then
			local gateOpen = snapshot.collapse ~= nil and snapshot.collapse.gateOpen
			extractionRow.Text = if gateOpen
				then "⇪  GATE OPEN — reach the Breach Dock"
				else "⚡  Power a Gate Relay to open the Breach Gate"
			extractionRow.Visible = true
		else
			extractionRow.Visible = false
		end
	end

	local function renderTeam()
		squad:Render()
	end

	local function renderVitals()
		-- Integrity ladder, not hit points: Stable / Fractured / Desynced / In Stasis.
		local role = ClientState.currentRole()
		local condition = ClientState.myCondition()
		healthBar.Instance.Visible = role ~= nil and role.role == "Infiltrator"
		if condition then
			local fraction = if condition == "Healthy" then 1 elseif condition == "Injured" then 0.5 else 0.12
			healthBar:Set(fraction, (Theme.ConditionColors :: any)[condition])
			healthBar:SetLabel(string.upper(SurvivalConfig.ConditionNames[condition] or condition))
		end
		local movement = ClientState.get("movement") or {}
		local parts = {}
		local function chip(text: string, color: Color3)
			table.insert(parts, `<font color="#{color:ToHex()}">{text}</font>`)
		end
		if movement.rooted then
			chip("◼ HELD", Theme.Colors.TextSecondary)
		end
		if movement.stunned then
			chip("✕ STUNNED", Theme.Colors.Danger)
		end
		if movement.slowed then
			chip("◈ SLOWED", Theme.Colors.Temporal)
		end
		if movement.slowImmune then
			chip("◆ STABILIZED", Theme.Colors.Stable)
		end
		if movement.hasted then
			chip("» HASTE", Theme.Colors.Stable)
		end
		if movement.invulnerable then
			chip("◇ PROTECTED", Theme.Colors.Success)
		end
		for _, effect in movement.effects or {} do
			if effect.kind == "Revealed" then
				chip("! SCANNED", Theme.Colors.Warning)
			end
		end
		chips.Text = table.concat(parts, "   ")
	end

	local calibrationBound = false
	local function renderHackPanel()
		local terminals = ClientState.get("terminals") or {}
		local mine: any = nil
		for _, terminal in terminals do
			if
				terminal.state == "Hacking"
				and (terminal.hackerUserId == player.UserId or table.find(terminal.assistants or {}, player.UserId))
			then
				mine = terminal
			end
		end
		local now = os.clock()
		-- Calibration Pulse: shown only while it belongs to the terminal we are hacking right now.
		local pending = ClientState.get("calibration")
		local challenge = if pending and mine and pending.terminalId == mine.id then pending.challenge else nil
		if challenge and ClientState.now() > challenge.startAt + challenge.sweep + 0.5 then
			challenge = nil
		end
		if challenge then
			local inputType = ClientState.get("inputType")
			calibration:Show(
				challenge,
				if inputType == "Touch"
					then "TAP THE RING IN THE ARC"
					elseif inputType == "Gamepad" then "PRESS A IN THE ARC"
					else "PRESS SPACE IN THE ARC"
			)
		else
			calibration:Hide()
		end
		calibration:Update()
		if (challenge ~= nil) ~= calibrationBound then
			calibrationBound = challenge ~= nil
			deps.InputController.SetCalibrationBound(calibrationBound)
		end
		if mine then
			lastHackTerminal = mine.id
			hackPanel.Visible = true
			local assisting = mine.hackerUserId ~= player.UserId
			local hackers = 1 + #(mine.assistants or {})
			hackTitle.Text = `{if assisting then "ASSIST" else "HACK"} · {mine.name}`
			hackTitle.TextColor3 = Theme.Colors.Warning
			hackBar:Set(mine.progress, Theme.Colors.Warning)
			hackBar:SetLabel(string.format("%d%%", math.floor(mine.progress * 100)))
			local flavour = (SurvivalConfig.Calibration.Flavours :: any)[mine.mode or "Timing"]
			hackDetail.Text = `{hackers}/{SurvivalConfig.Objectives.MaxHackers} hackers · {if flavour
				then flavour.Name
				else "Calibration"} pulses: Great +{math.floor(SurvivalConfig.Calibration.GreatBonus * 1000) / 10}%, miss −{math.floor(
				SurvivalConfig.Calibration.MissPenalty * 100
			)}% and a trace.`
			cancelButton.Instance.Visible = true
			local hint = ""
			local inputType = ClientState.get("inputType")
			if inputType == "KeyboardMouse" then
				hint = "C"
			elseif inputType == "Gamepad" then
				hint = "B"
			end
			cancelButton:SetHint(if hint ~= "" then hint else nil)
		elseif lastHackTerminal then
			local terminal = terminals[lastHackTerminal]
			if terminal and terminal.state == "Completed" then
				hackPanel.Visible = true
				hackTitle.Text = `BREACHED · {terminal.name}`
				hackTitle.TextColor3 = Theme.Colors.Success
				hackBar:Set(1, Theme.Colors.Success)
				hackBar:SetLabel("100%")
				hackDetail.Text = "Terminal complete."
				cancelButton.Instance.Visible = false
				interruptedUntil = now + 1.5
			elseif terminal and terminal.state == "Interrupted" then
				hackPanel.Visible = true
				hackTitle.Text = `INTERRUPTED · {terminal.name}`
				hackTitle.TextColor3 = Theme.Colors.Danger
				hackBar:Set(terminal.progress, Theme.Colors.Danger)
				hackBar:SetLabel(string.format("%d%% saved", math.floor(terminal.progress * 100)))
				hackDetail.Text = "Progress is kept — but the Keeper can Overload an idle terminal."
				cancelButton.Instance.Visible = false
				interruptedUntil = now + 1.5
			end
			lastHackTerminal = nil
		elseif now > interruptedUntil then
			hackPanel.Visible = false
		end
		local shouldBind = mine ~= nil or ClientState.get("action") ~= nil
		if shouldBind ~= hackBound then
			hackBound = shouldBind
			deps.InputController.SetHackCancelBound(shouldBind)
		end
	end

	local function renderExtraction()
		local progress = ClientState.get("extraction") or 0
		local snapshot = ClientState.get("snapshot")
		local me = ClientState.myParticipant()
		local show = snapshot ~= nil
			and snapshot.extractionActive
			and me ~= nil
			and me.status == "Active"
			and progress > 0
		extractPanel.Visible = show and not hackPanel.Visible
		if show then
			extractBar:Set(progress)
			extractLabel.Text = if progress >= 1 then "EXTRACTED!" else "EXTRACTING… hold position"
		end
	end

	local function renderHints()
		local settings = ClientState.get("settings")
		if settings and settings.ShowControlHints == false then
			hints.Visible = false
			return
		end
		hints.Visible = true
		local role = ClientState.currentRole()
		local inputType = ClientState.get("inputType")
		local lines = {}
		local infiltrator = role ~= nil and role.role == "Infiltrator"
		if inputType == "KeyboardMouse" then
			table.insert(lines, "WASD move · RMB drag camera · E interact · C cancel")
			if infiltrator then
				table.insert(lines, "Shift sprint · Space on calibration pulses")
			else
				table.insert(lines, "E Phase-Lock / Overload / Break / Search")
			end
		elseif inputType == "Gamepad" then
			table.insert(lines, "L-stick move · R-stick camera · X interact · B cancel")
			if infiltrator then
				table.insert(lines, "L3 sprint · A on calibration pulses")
			end
		else
			table.insert(lines, "Tap prompts to interact · hold SPRINT · tap the ring on pulses")
		end
		if role then
			for _, abilityId in role.abilities do
				local definition = AbilityConfig.get(abilityId)
				local hint = deps.InputController.HintFor(abilityId)
				if definition and hint ~= "" then
					table.insert(lines, `{hint} {definition.DisplayName}`)
				end
			end
		end
		hints.Text = table.concat(lines, "\n")
	end

	ClientState.changed:Connect(function(key: string)
		if not root.Visible then
			return
		end
		if key == "snapshot" then
			renderObjectives()
			renderTeam()
			renderTimer()
		elseif key == "terminals" then
			renderObjectives()
			renderHackPanel()
		elseif key == "movement" then
			renderVitals()
		elseif key == "extraction" then
			renderExtraction()
		elseif key == "inputType" or key == "settings" or key == "role" then
			layout()
			renderHints()
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		-- The needle and vignette animate every frame; everything else refreshes at 10 Hz.
		local settings = ClientState.get("settings")
		overlay:Update(settings ~= nil and settings.ReducedMotion == true)
		calibration:Update()
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		renderTimer()
		renderVitals()
		renderHackPanel()
		renderExtraction()
		renderTeam()
	end)

	local self = {}
	function self.FlashCalibration(grade: string)
		calibration:Flash(grade)
	end
	function self.SetVisible(visible: boolean)
		root.Visible = visible
		abilityBar.SetVisible(visible)
		if visible then
			renderTimer()
			renderObjectives()
			renderTeam()
			renderVitals()
			renderHints()
		else
			hackPanel.Visible = false
			extractPanel.Visible = false
			calibration:Hide()
			if calibrationBound then
				calibrationBound = false
				deps.InputController.SetCalibrationBound(false)
			end
			if hackBound then
				hackBound = false
				deps.InputController.SetHackCancelBound(false)
			end
		end
	end
	return self
end

return HudScreen
