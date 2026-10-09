--!strict
-- In-match HUD: phase timer, role badge, objective tracker, team status, health, status chips,
-- terminal hacking panel (progress / interruption / completion), extraction channel bar, ability
-- bar, and control hints. Renders only server-provided state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local AbilityBar = require(script.Parent.AbilityBar)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)

local HudScreen = {}

local player = Players.LocalPlayer

local STATUS_TEXT: { [string]: string } = {
	Active = "●",
	Eliminated = "✕ OUT",
	Extracted = "⇪ ESCAPED",
	Disconnected = "… LEFT",
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

	-- Objectives (left, below the chat area)
	local objectives = Style.panel({
		Name = "Objectives",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Spacing.L, 0.45, 0),
		Size = UDim2.fromOffset(260, 0),
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

	-- Team status (top right)
	local team = Style.panel({
		Name = "Team",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, Theme.Spacing.S),
		Size = UDim2.fromOffset(230, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = Theme.Spacing.M,
		Parent = root,
	})
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS).Parent = team
	Style.text({
		Text = "SQUAD STATUS",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		LayoutOrder = 0,
		Parent = team,
	})
	local teamRows = Create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = team,
	}, { Style.list(Enum.FillDirection.Vertical, 2) })

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
		Size = UDim2.fromOffset(380, 112),
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
		Position = UDim2.fromOffset(0, 30),
		Color = Theme.Colors.Warning,
		Parent = hackPanel,
	})
	local hackDetail = Style.text({
		Text = `Stay within {TerminalConfig.MaxInteractionDistance} studs. Taking damage interrupts the hack.`,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 54),
		Parent = hackPanel,
	})
	local cancelButton = Button.new({
		Text = "Cancel",
		Style = "Ghost",
		Size = UDim2.fromOffset(100, 32),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -4),
		TextSize = Theme.TextSize.Small,
		OnActivated = function()
			deps.InputController.CancelHack()
		end,
		Parent = hackPanel,
	})

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

	local abilityBar = AbilityBar.new(root, deps)

	local interruptedUntil = 0
	local lastHackTerminal: string? = nil
	local hackBound = false

	local function renderTimer()
		local snapshot = ClientState.get("snapshot")
		if not snapshot then
			return
		end
		local phase = snapshot.phase
		local remaining = if snapshot.phaseEndsAt then snapshot.phaseEndsAt - ClientState.now() else 0
		timeLabel.Text = if snapshot.phaseEndsAt then Style.formatTime(remaining) else "--:--"
		local label = "BREACH"
		local color = Theme.Colors.TextPrimary
		if phase == "Intro" then
			label = "DEPLOYING"
		elseif phase == "Extraction" then
			label = "EXTRACTION WINDOW"
			color = Theme.Colors.Success
		elseif phase == "Resolving" or phase == "ReturningToLobby" then
			label = "MATCH OVER"
		end
		if (phase == "Active" or phase == "Extraction") and remaining <= 30 then
			color = Theme.Colors.Danger
		end
		phaseLabel.Text = label
		timeLabel.TextColor3 = color
	end

	local function renderObjectives()
		local snapshot = ClientState.get("snapshot")
		local role = ClientState.currentRole()
		if not snapshot then
			return
		end
		if role then
			local color = (Theme.RoleColors :: any)[role.role] or Theme.Colors.Stable
			roleBadge.Text = string.upper(role.displayName)
			roleBadge.TextColor3 = color
			objectiveHeader.Text = if role.role == "TimeKeeper"
				then `STOP THE BREACH · {snapshot.completedHacks}/{snapshot.requiredHacks} breached`
				else `HACK TERMINALS · {snapshot.completedHacks}/{snapshot.requiredHacks}`
		end
		for _, child in terminalRows:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
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
			Style.text({
				Text = `{TERMINAL_ICON[state] or "·"}  {terminal.name}{suffix}`,
				TextSize = Theme.TextSize.Small,
				Color = color,
				Wrapped = false,
				LayoutOrder = index,
				Parent = terminalRows,
			})
		end
		if snapshot.extractionActive then
			extractionRow.Text = "⇪  EXTRACTION OPEN — reach the Breach Dock"
			extractionRow.Visible = true
		else
			extractionRow.Visible = false
		end
	end

	local function renderTeam()
		local snapshot = ClientState.get("snapshot")
		for _, child in teamRows:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		if not snapshot then
			return
		end
		for index, p in snapshot.participants do
			local color = (Theme.RoleColors :: any)[p.role] or Theme.Colors.TextPrimary
			if p.status ~= "Active" then
				color = color:Lerp(Theme.Colors.TextMuted, 0.6)
			end
			local you = if p.userId == player.UserId then " (you)" else ""
			local roleTag = if p.role == "TimeKeeper" then "KEEPER" else "INF"
			Style.text({
				Text = `{roleTag}  {TableUtil.truncate(p.name, 14)}{you}  {STATUS_TEXT[p.status] or ""}`,
				TextSize = Theme.TextSize.Small,
				Color = color,
				Wrapped = false,
				LayoutOrder = index,
				Parent = teamRows,
			})
		end
	end

	local function renderVitals()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MaxHealth > 0 then
			local fraction = humanoid.Health / humanoid.MaxHealth
			local color = if fraction > 0.5
				then Theme.Colors.Success
				elseif fraction > 0.25 then Theme.Colors.Warning
				else Theme.Colors.Danger
			healthBar:Set(fraction, color)
			healthBar:SetLabel(`{math.ceil(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`)
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

	local function renderHackPanel()
		local terminals = ClientState.get("terminals") or {}
		local mine: any = nil
		for _, terminal in terminals do
			if terminal.hackerUserId == player.UserId and terminal.state == "Hacking" then
				mine = terminal
			end
		end
		local now = os.clock()
		if mine then
			lastHackTerminal = mine.id
			hackPanel.Visible = true
			hackTitle.Text = `HACKING · {mine.name}`
			hackTitle.TextColor3 = Theme.Colors.Warning
			hackBar:Set(mine.progress, Theme.Colors.Warning)
			hackBar:SetLabel(string.format("%d%%", math.floor(mine.progress * 100)))
			hackDetail.Text =
				`Stay within {TerminalConfig.MaxInteractionDistance} studs. Taking damage interrupts the hack.`
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
				hackDetail.Text = "Progress is kept — resume when the terminal is ready."
				cancelButton.Instance.Visible = false
				interruptedUntil = now + 1.5
			end
			lastHackTerminal = nil
		elseif now > interruptedUntil then
			hackPanel.Visible = false
		end
		local shouldBind = mine ~= nil
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
		if inputType == "KeyboardMouse" then
			table.insert(lines, "WASD move · Space jump · RMB drag camera")
			if role and role.role == "Infiltrator" then
				table.insert(lines, "E hack terminal · C cancel hack")
			end
		elseif inputType == "Gamepad" then
			table.insert(lines, "L-stick move · A jump · R-stick camera")
			if role and role.role == "Infiltrator" then
				table.insert(lines, "X hack terminal · B cancel hack")
			end
		else
			table.insert(lines, "Tap terminal prompts to hack · use the right-side buttons for abilities")
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
			renderHints()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 or not root.Visible then
			return
		end
		accumulator = 0
		renderTimer()
		renderVitals()
		renderHackPanel()
		renderExtraction()
	end)

	local self = {}
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
			if hackBound then
				hackBound = false
				deps.InputController.SetHackCancelBound(false)
			end
		end
	end
	return self
end

return HudScreen
