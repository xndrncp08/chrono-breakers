--!strict
-- Lobby screen: identity, profile/currency/stats, queue status + queue button, live match ticker,
-- and entry points to Loadout, Settings, and Spectate. Visible whenever the local player is not an
-- active match participant. Every state shown here comes from the server (snapshot/queue/profile).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Parent.Net)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

local LobbyScreen = {}

local player = Players.LocalPlayer

local PHASE_TEXT: { [string]: string } = {
	WaitingForPlayers = "Waiting for players",
	Intermission = "Match starting",
	RoleAssignment = "Assigning roles",
	Intro = "Match in progress",
	Active = "Match in progress",
	Extraction = "Extraction underway",
	Resolving = "Match ending",
	ReturningToLobby = "Returning to lobby",
}

function LobbyScreen.new(parent: Instance, deps: { [string]: any })
	local root = Create("Frame", {
		Name = "Lobby",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})

	-- Identity + profile card (top-left)
	local profileCard = Style.panel({
		Name = "ProfileCard",
		-- Vertically centred on the left so it never sits under the default chat window.
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Theme.Spacing.L, 0.45, 0),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = Theme.Spacing.L,
		Parent = root,
	})
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.S).Parent = profileCard
	Style.text({
		Text = "CHRONO BREAKERS",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Heading,
		Color = Theme.Colors.Stable,
		Wrapped = false,
		LayoutOrder = 1,
		Parent = profileCard,
	})
	Style.text({
		Text = string.upper(GameConfig.GameSubtitle),
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.Temporal,
		Wrapped = false,
		LayoutOrder = 2,
		Parent = profileCard,
	})
	local nameLabel = Style.text({
		Text = player.DisplayName,
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Body,
		Wrapped = false,
		LayoutOrder = 3,
		Parent = profileCard,
	})
	local currencyLabel = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Heading,
		Color = Theme.Colors.Warning,
		Wrapped = false,
		LayoutOrder = 4,
		Parent = profileCard,
	})
	local statsLabel = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = profileCard,
	})
	local persistenceBadge = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Font = Theme.Fonts.Heading,
		Color = Theme.Colors.Warning,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 6,
		Parent = profileCard,
	})

	-- Menu buttons (top-right, below the toast area)
	local menu = Create("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Spacing.L, 0, Theme.Spacing.L),
		Size = UDim2.fromOffset(180, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { Style.list(Enum.FillDirection.Vertical, Theme.Spacing.S, Enum.HorizontalAlignment.Right) })
	Button.new({
		Text = "Deployment & Maps",
		Style = "Primary",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 0,
		OnActivated = function()
			deps.UIController.OpenModal("Deployment")
		end,
		Parent = menu,
	})
	local loadoutButton = Button.new({
		Text = "Loadout & Shop",
		Style = "Secondary",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 1,
		OnActivated = function()
			deps.AudioController.Play("UiClick")
			deps.UIController.OpenModal("Loadout")
		end,
		Parent = menu,
	})
	Button.new({
		Text = "Settings",
		Style = "Secondary",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 2,
		OnActivated = function()
			deps.AudioController.Play("UiClick")
			deps.UIController.OpenModal("Settings")
		end,
		Parent = menu,
	})
	Button.new({
		Text = "Career & Contracts",
		Style = "Secondary",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 3,
		OnActivated = function()
			deps.UIController.OpenModal("Career")
		end,
		Parent = menu,
	})
	local spectateButton = Button.new({
		Text = "Spectate",
		Style = "Ghost",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 4,
		OnActivated = function()
			deps.AudioController.Play("UiClick")
			if ClientState.get("spectating") then
				deps.CameraController.Stop()
			else
				deps.CameraController.Cycle(1)
			end
		end,
		Parent = menu,
	})
	local nextSpectate = Button.new({
		Text = "Next ▶",
		Style = "Ghost",
		Size = UDim2.new(1, 0, 0, Theme.MinTouchTarget),
		LayoutOrder = 4,
		OnActivated = function()
			deps.CameraController.Cycle(1)
		end,
		Parent = menu,
	})

	-- Queue card (bottom centre)
	local queueCard = Style.panel({
		Name = "QueueCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Spacing.XL),
		Size = UDim2.fromScale(0.9, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = Theme.Spacing.L,
		StrokeColor = Theme.Colors.BorderStrong,
		Parent = root,
	})
	Create("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge), Parent = queueCard })
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.S, Enum.HorizontalAlignment.Center).Parent = queueCard
	local phaseLabel = Style.text({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Heading,
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = queueCard,
	})
	local detailLabel = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = queueCard,
	})
	local pending = false
	local pendingToken = 0
	local queueButton: Button.Button
	queueButton = Button.new({
		Text = "Join Queue",
		Style = "Primary",
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = Theme.TextSize.Heading,
		LayoutOrder = 3,
		OnActivated = function()
			local queue = ClientState.get("queue")
			local action = if queue and queue.queued then Protocol.QueueActions.Leave else Protocol.QueueActions.Join
			deps.AudioController.Play("UiClick")
			pending = true
			pendingToken += 1
			local token = pendingToken
			queueButton:SetLoading(true)
			Net.send(RemoteNames.QueueRequest, action)
			task.delay(4, function()
				if pending and pendingToken == token then
					pending = false
					queueButton:SetLoading(false)
				end
			end)
		end,
		Parent = queueCard,
	})
	local hint = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Parent = queueCard,
	})

	local function renderProfile()
		local profile = ClientState.get("profile")
		if not profile or not profile.loaded then
			currencyLabel.Text = "Loading profile…"
			statsLabel.Text = ""
			persistenceBadge.Text = ""
			return
		end
		currencyLabel.Text = `◆ {profile.currency} {RewardConfig.CurrencyShort}`
		local title = ItemConfig.get(profile.equipped.Title or "TitleRookie")
		nameLabel.Text = `{player.DisplayName} / {if title then title.DisplayName else "Recruit"}`
		if profile.progression then
			currencyLabel.Text ..= ` · LV {profile.progression.level}`
		end
		local s = profile.stats
		statsLabel.Text = string.format(
			"Matches %d  ·  Wins %d\nTerminals hacked %d  ·  Extractions %d\nEliminations %d",
			s.MatchesPlayed or 0,
			s.Wins or 0,
			s.TerminalsHacked or 0,
			s.Extractions or 0,
			s.Eliminations or 0
		)
		persistenceBadge.Text = if profile.persistent then "" else "! UNSAVED SESSION — progress won't persist"
	end

	local function render()
		local snapshot = ClientState.get("snapshot")
		local queue = ClientState.get("queue")
		if not snapshot then
			phaseLabel.Text = "Connecting…"
			detailLabel.Text = ""
			queueButton:SetEnabled(false)
			return
		end
		local phase = snapshot.phase
		local text = PHASE_TEXT[phase] or phase
		local now = ClientState.now()
		if phase == "Intermission" and snapshot.phaseEndsAt then
			text = `Match starting in {math.max(0, math.ceil(snapshot.phaseEndsAt - now))}s`
		end
		phaseLabel.Text = text
		phaseLabel.TextColor3 = if phase == "Intermission" then Theme.Colors.Warning else Theme.Colors.TextPrimary

		local queued = queue ~= nil and queue.queued
		local count = if queue then queue.count else snapshot.queueCount
		local minPlayers = if queue then queue.minPlayers else snapshot.minPlayers
		local details = { `SECTOR / {snapshot.mapName or "Chronos Vault"}` }
		if queued then
			table.insert(details, `You're in the queue (#{queue.position} of {count}).`)
		else
			table.insert(details, `{count} queued · {minPlayers} needed to start · max {snapshot.maxPlayers}`)
		end
		local inProgress = phase == "Intro" or phase == "Active" or phase == "Extraction"
		if inProgress then
			local remaining = if snapshot.phaseEndsAt then Style.formatTime(snapshot.phaseEndsAt - now) else "--:--"
			table.insert(
				details,
				`Live: terminals {snapshot.completedHacks}/{snapshot.requiredHacks} · {remaining}{if snapshot.extractionActive
					then " · EXTRACTION"
					else ""}`
			)
			if queued then
				table.insert(details, "You'll join the next match.")
			end
		end
		detailLabel.Text = table.concat(details, "\n")

		if not pending then
			queueButton:SetLoading(false)
		end
		queueButton:SetText(if queued then "Leave Queue" else "Join Queue")
		queueButton:SetStyle(if queued then "Secondary" else "Primary")
		queueButton:SetEnabled(not (queue and queue.inMatch))

		local inputType = ClientState.get("inputType")
		hint.Text = if inputType == "Gamepad"
			then "Use the D-pad to move between buttons · A to select"
			else "Queue up, then hack terminals or hunt as the Time-Keeper."

		local canSpectate = inProgress and deps.CameraController.CanSpectate()
		local spectating = ClientState.get("spectating") ~= nil
		spectateButton.Instance.Visible = canSpectate or spectating
		spectateButton:SetText(if spectating then "Stop Spectating" else "Spectate")
		nextSpectate.Instance.Visible = spectating
		loadoutButton:SetEnabled(true)
	end

	ClientState.changed:Connect(function(key: string)
		if key == "queue" then
			pending = false
			render()
		elseif key == "snapshot" or key == "inputType" or key == "spectating" then
			render()
		elseif key == "profile" then
			renderProfile()
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 and root.Visible then
			accumulator = 0
			render()
		end
	end)

	renderProfile()
	render()
	nameLabel.Text = player.DisplayName

	local self = {}
	function self.SetVisible(visible: boolean)
		root.Visible = visible
		if not visible and ClientState.get("spectating") then
			deps.CameraController.Stop()
		end
	end
	function self.GetDefaultSelection(): GuiObject
		return queueButton.Instance
	end
	return self
end

return LobbyScreen
