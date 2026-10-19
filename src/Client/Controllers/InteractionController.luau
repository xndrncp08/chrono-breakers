--!strict
-- InteractionController: world-space navigation and interaction presentation.
--   * Terminal markers (BillboardGui): Infiltrators always see objectives with state, progress, and
--     distance; the Time-Keeper only sees terminals that are being breached (Hacking/Interrupted).
--   * Extraction marker once extraction opens.
--   * Hides terminal prompts locally for non-Infiltrators (the server still validates every hack).
--   * Disables the reset button while the local player is an active match participant.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.UI.Components.Create)
local Style = require(script.Parent.Parent.UI.Components.Style)

local InteractionController = {}

local player = Players.LocalPlayer
local TERMINAL_TAG = "ChronoTerminal"

type Marker = {
	gui: BillboardGui,
	title: TextLabel,
	detail: TextLabel,
	dot: Frame,
	model: Model,
}

local markers: { [string]: Marker } = {}
local extractionMarker: BillboardGui? = nil
local markerFolder: Folder? = nil
local resetDisabled = false

local function myRole(): string?
	local role = ClientState.get("role")
	local snapshot = ClientState.get("snapshot")
	if not role or not snapshot or snapshot.matchId ~= role.matchId then
		return nil
	end
	return role.role
end

local function inLiveMatch(): boolean
	local snapshot = ClientState.get("snapshot")
	if not snapshot then
		return false
	end
	local phase = snapshot.phase
	if phase ~= "Intro" and phase ~= "Active" and phase ~= "Extraction" then
		return false
	end
	for _, p in snapshot.participants do
		if p.userId == player.UserId then
			return p.status == "Active"
		end
	end
	return false
end

local function createMarker(model: Model): Marker?
	local id = model:GetAttribute("TerminalId")
	local console = model:FindFirstChild("Console")
	if type(id) ~= "string" or not console then
		return nil
	end
	local gui = Create("BillboardGui", {
		Name = `Marker_{id}`,
		Adornee = console,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(170, 58),
		StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0),
		LightInfluence = 0,
		MaxDistance = 2000,
		Enabled = false,
		ResetOnSpawn = false,
		Parent = markerFolder,
	}) :: BillboardGui
	local panel = Style.panel({
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Colors.Background,
		Transparency = 0.25,
		Radius = Theme.Radius.S,
		Parent = gui,
	})
	local dot = Create("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromOffset(10, 12),
		BackgroundColor3 = Theme.TerminalStateColors.Locked,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Style.corner(Theme.Radius.Pill) }) :: Frame
	local title = Style.text({
		Text = tostring(model:GetAttribute("DisplayName") or id),
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Size = UDim2.new(1, -30, 0, 20),
		Position = UDim2.fromOffset(26, 6),
		Wrapped = false,
		Parent = panel,
	})
	local detail = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(10, 30),
		Wrapped = false,
		Parent = panel,
	})
	return { gui = gui, title = title, detail = detail, dot = dot, model = model }
end

local STATE_LABEL: { [string]: string } = {
	Locked = "LOCKED",
	Available = "READY TO HACK",
	Hacking = "BREACH IN PROGRESS",
	Interrupted = "INTERRUPTED",
	Completed = "BREACHED ✓",
}

local function refreshMarkers()
	local role = myRole()
	local live = inLiveMatch()
	local terminals = ClientState.get("terminals") or {}
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for id, marker in markers do
		local terminal = terminals[id]
		local state = if terminal then terminal.state else "Locked"
		local visible = false
		if live and role == "Infiltrator" then
			visible = state ~= "Locked" or ClientState.get("snapshot").phase == "Intro"
		elseif live and role == "TimeKeeper" then
			visible = state == "Hacking" or state == "Interrupted"
		end
		marker.gui.Enabled = visible
		if visible then
			local color = (Theme.TerminalStateColors :: any)[state] or Theme.TerminalStateColors.Locked
			marker.dot.BackgroundColor3 = color
			local console = marker.model:FindFirstChild("Console") :: BasePart?
			local distanceText = ""
			if root and console then
				distanceText = string.format(" · %dm", math.floor((root.Position - console.Position).Magnitude))
			end
			local progressText = ""
			if
				terminal
				and (state == "Hacking" or state == "Interrupted" or state == "Available")
				and terminal.progress > 0
			then
				progressText = string.format(" · %d%%", math.floor(terminal.progress * 100))
			end
			marker.detail.Text = (STATE_LABEL[state] or state) .. progressText .. distanceText
			marker.detail.TextColor3 = color
		end
	end
	if extractionMarker then
		local snapshot = ClientState.get("snapshot")
		extractionMarker.Enabled = live and role == "Infiltrator" and snapshot ~= nil and snapshot.extractionActive
	end
end

local function updatePrompts()
	local role = myRole()
	local hidePrompts = role == "TimeKeeper"
	for _, model in CollectionService:GetTagged(TERMINAL_TAG) do
		local prompt = model:FindFirstChild("HackPrompt", true) :: ProximityPrompt?
		if prompt then
			-- Local-only visibility; the server re-validates role on every trigger.
			if hidePrompts then
				prompt.Enabled = false
			else
				prompt.Enabled = model:GetAttribute("State") == "Available"
			end
		end
	end
end

local function setResetEnabled(enabled: boolean)
	if resetDisabled == not enabled then
		return
	end
	local ok = pcall(function()
		StarterGui:SetCore("ResetButtonCallback", enabled)
	end)
	if ok then
		resetDisabled = not enabled
	end
end

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("TerminalId")
	if type(id) ~= "string" then
		return
	end
	if markers[id] then
		markers[id].gui:Destroy()
	end
	local marker = createMarker(model)
	if marker then
		markers[id] = marker
	end
	model:GetAttributeChangedSignal("State"):Connect(updatePrompts)
	local prompt = model:FindFirstChild("HackPrompt", true) :: ProximityPrompt?
	if prompt then
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if myRole() == "TimeKeeper" and prompt.Enabled then
				prompt.Enabled = false
			end
		end)
	end
end

local function createExtractionMarker()
	local root = Workspace:FindFirstChild("ChronoBreakers")
	local vault = root and root:FindFirstChild("Vault")
	local pad = vault and vault:FindFirstChild("ExtractionPad")
	if not pad then
		return
	end
	if extractionMarker then
		extractionMarker:Destroy()
	end
	local gui = Create("BillboardGui", {
		Name = "ExtractionMarker",
		Adornee = pad,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(160, 40),
		StudsOffsetWorldSpace = Vector3.new(0, 8, 0),
		LightInfluence = 0,
		Enabled = false,
		Parent = markerFolder,
	}) :: BillboardGui
	local panel = Style.panel({
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Colors.Background,
		Transparency = 0.2,
		StrokeColor = Theme.Colors.Success,
		Radius = Theme.Radius.S,
		Parent = gui,
	})
	Style.text({
		Text = "⇪ EXTRACTION",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Success,
		Size = UDim2.fromScale(1, 1),
		XAlign = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	extractionMarker = gui
end

function InteractionController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "ChronoMarkers"
	folder.Parent = player:WaitForChild("PlayerGui")
	markerFolder = folder
end

function InteractionController.Start()
	for _, model in CollectionService:GetTagged(TERMINAL_TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TERMINAL_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TERMINAL_TAG):Connect(function(model: Instance)
		local id = model:GetAttribute("TerminalId")
		if type(id) ~= "string" then
			return
		end
		local marker = markers[id]
		if marker and marker.model == model then
			marker.gui:Destroy()
			markers[id] = nil
		end
	end)
	Workspace.DescendantAdded:Connect(function(instance)
		if instance.Name == "ExtractionPad" and instance:IsA("BasePart") then
			task.defer(createExtractionMarker)
		end
	end)
	task.spawn(function()
		-- The vault is built by the server at startup; wait briefly for it to replicate.
		local root = Workspace:WaitForChild("ChronoBreakers", 30)
		if root then
			local vault = root:WaitForChild("Vault", 10)
			if vault then
				vault:WaitForChild("ExtractionPad", 10)
				createExtractionMarker()
			end
		end
	end)

	ClientState.changed:Connect(function(key: string)
		if key == "snapshot" or key == "role" then
			updatePrompts()
			setResetEnabled(not inLiveMatch())
		end
		if key == "snapshot" or key == "role" or key == "terminals" then
			refreshMarkers()
		end
	end)

	-- Distance text refresh at a modest rate (not every frame).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			refreshMarkers()
		end
	end)
end

return InteractionController
