--!strict
-- InteractionController: world-space navigation and interaction presentation.
--   * Terminal markers (BillboardGui): Infiltrators always see objectives with state, progress, and
--     distance; the Time-Keeper only sees terminals that are being breached (Hacking/Interrupted).
--   * Extraction marker once extraction opens.
--   * Hides terminal prompts locally for non-Infiltrators (the server still validates every hack).
--   * Filters every survival prompt (Re-sync, Patch, Phase-Lock, Rescue, Relay, Overload, Vault,
--     barriers, doors, lockers, rift) by role, condition and ownership. Filtering only zeroes the
--     prompt's local activation distance; the server validates every request regardless.
--   * Markers for teammates' integrity, occupied Stasis Pods, Gate Relays and the Slip Rift.
--   * Disables the reset button while the local player is an active match participant.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
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
local teammates: { [number]: BillboardGui } = {}
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
	local console = model:WaitForChild("Console", 5)
	if type(id) ~= "string" or not console or model.Parent == nil then
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

---------------------------------------------------------------------------
-- Survival prompt filtering
---------------------------------------------------------------------------

-- Audience per prompt name: "Infiltrator", "Keeper", "Any", "Ally" (Infiltrators, never on your
-- own character), "Occupant" (only the player hiding in that locker) or "Vault" (rails: both roles;
-- dropped barriers: Infiltrators only).
local AUDIENCE: { [string]: string } = {
	HackPrompt = "Infiltrator",
	ResyncPrompt = "Ally",
	PatchPrompt = "Ally",
	PhaseLockPrompt = "Keeper",
	RescuePrompt = "Infiltrator",
	RelayPrompt = "Infiltrator",
	OverloadPrompt = "Keeper",
	VaultPrompt = "Vault",
	DropPrompt = "Infiltrator",
	BreakPrompt = "Keeper",
	TogglePrompt = "Any",
	HidePrompt = "Infiltrator",
	SearchPrompt = "Keeper",
	LeavePrompt = "Occupant",
	EscapePrompt = "Infiltrator",
	SealPrompt = "Keeper",
}

local trackedPrompts: { [ProximityPrompt]: number } = {} -- prompt -> authored activation distance

local function promptAllowed(prompt: ProximityPrompt): boolean
	local audience = AUDIENCE[prompt.Name]
	if not audience then
		return true
	end
	local role = myRole()
	if not inLiveMatch() or not role then
		return false
	end
	local character = player.Character
	local hidden = character ~= nil and character:GetAttribute("Hidden") == true
	if audience == "Occupant" then
		local model = prompt:FindFirstAncestorOfClass("Model")
		return model ~= nil and model:GetAttribute("Occupant") == player.UserId
	end
	if hidden or not ClientState.canAct() then
		return false
	end
	if audience == "Any" then
		return true
	elseif audience == "Keeper" then
		return role == "TimeKeeper"
	elseif audience == "Ally" then
		if role ~= "Infiltrator" then
			return false
		end
		if prompt:GetAttribute("TargetUserId") ~= player.UserId then
			return true
		end
		-- Your own Patch prompt only with the Field Patch protocol in this class's loadout.
		local profile = ClientState.get("profile")
		local current = ClientState.currentRole()
		local loadout = profile and profile.perks and current and profile.perks[current.classId]
		return prompt.Name == "PatchPrompt" and loadout ~= nil and table.find(loadout, "FieldPatch") ~= nil
	elseif audience == "Vault" then
		local obstacle = prompt:FindFirstAncestorWhichIsA("BasePart")
		if not obstacle then
			return false
		end
		if obstacle:GetAttribute("ObstacleKind") == "Barrier" then
			return role == "Infiltrator"
		end
		local sealedUntil = obstacle:GetAttribute("SealedUntil")
		return role == "TimeKeeper" or not (type(sealedUntil) == "number" and ClientState.now() < sealedUntil)
	end
	return role == "Infiltrator"
end

local function filterPrompts()
	for prompt, distance in trackedPrompts do
		if prompt.Parent == nil then
			trackedPrompts[prompt] = nil
		else
			local wanted = if promptAllowed(prompt) then distance else 0
			if prompt.MaxActivationDistance ~= wanted then
				prompt.MaxActivationDistance = wanted
			end
		end
	end
end

local function trackPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and AUDIENCE[instance.Name] and not trackedPrompts[instance] then
		trackedPrompts[instance] = instance.MaxActivationDistance
		local wanted = if promptAllowed(instance) then instance.MaxActivationDistance else 0
		instance.MaxActivationDistance = wanted
	end
end

---------------------------------------------------------------------------
-- Survival markers
---------------------------------------------------------------------------

type WorldMarker = { gui: BillboardGui, label: TextLabel }
local worldMarkers: { [Instance]: WorldMarker } = {}

local function worldMarker(adornee: Instance, color: Color3): WorldMarker
	local existing = worldMarkers[adornee]
	if existing then
		return existing
	end
	local gui = Create("BillboardGui", {
		Name = "SurvivalMarker",
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(180, 34),
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		LightInfluence = 0,
		MaxDistance = 2000,
		Parent = markerFolder,
	}) :: BillboardGui
	local panel = Style.panel({
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Colors.Background,
		Transparency = 0.25,
		StrokeColor = color,
		Radius = Theme.Radius.S,
		Parent = gui,
	})
	local label = Style.text({
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Size = UDim2.fromScale(1, 1),
		XAlign = Enum.TextXAlignment.Center,
		Color = color,
		Parent = panel,
	})
	local marker = { gui = gui, label = label }
	worldMarkers[adornee] = marker
	return marker
end

local function refreshSurvivalMarkers()
	local role = myRole()
	local live = inLiveMatch() or (ClientState.myParticipant() ~= nil and role ~= nil)
	local snapshot = ClientState.get("snapshot")
	local seen: { [Instance]: boolean } = {}
	local root = Workspace:FindFirstChild("ChronoBreakers")
	if live and snapshot and root then
		local now = ClientState.now()
		-- Occupied pods (both roles) with the captive's stage and timer.
		local byPod: { [string]: any } = {}
		for _, p in snapshot.participants do
			if p.podId then
				byPod[p.podId] = p
			end
		end
		for _, pod in CollectionService:GetTagged("ChronoPod") do
			local podId = pod:GetAttribute("PodId")
			local captive = if type(podId) == "string" then byPod[podId] else nil
			local glass = pod:FindFirstChild("Glass")
			if captive and glass and pod:IsDescendantOf(root) then
				seen[glass] = true
				local marker = worldMarker(glass, Theme.ConditionColors.Contained)
				marker.label.Text =
					`STASIS {captive.stage or 1}/{#SurvivalConfig.Containment.StageDurations + 1} · {captive.name} · {math.max(
						0,
						captive.podRemaining or 0
					)}s`
			end
		end
		-- Gate Relays during the Collapse.
		if snapshot.collapse and not snapshot.collapse.gateOpen then
			for _, relay in CollectionService:GetTagged("ChronoRelay") do
				local id = relay:GetAttribute("RelayId")
				local console = relay:FindFirstChild("Console")
				if type(id) == "string" and console and relay:IsDescendantOf(root) then
					seen[console] = true
					local marker = worldMarker(console, Theme.Colors.Warning)
					marker.label.Text = `GATE RELAY · {math.floor((snapshot.collapse.relays[id] or 0) * 100)}%`
				end
			end
		end
		-- Slip Rift.
		local rift = if snapshot.rift then root:FindFirstChild("SlipRift", true) else nil
		if rift then
			seen[rift] = true
			worldMarker(rift, Theme.World.Rift).label.Text = "SLIP RIFT"
		end
		-- Desynced teammates' aura for Infiltrators.
		if role == "Infiltrator" then
			for _, p in snapshot.participants do
				if p.condition == "Downed" and p.status == "Active" and p.userId ~= player.UserId then
					local other = Players:GetPlayerByUserId(p.userId)
					local otherRoot = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
					if otherRoot then
						seen[otherRoot] = true
						local left = if p.bleedoutAt then math.max(0, math.ceil(p.bleedoutAt - now)) else 0
						worldMarker(otherRoot, Theme.ConditionColors.Downed).label.Text =
							`DESYNCED · {p.name} · {left}s`
					end
				end
			end
		end
	end
	for adornee, marker in worldMarkers do
		if not seen[adornee] then
			marker.gui:Destroy()
			worldMarkers[adornee] = nil
		end
	end
end

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
	local seen: { [number]: boolean } = {}
	local snapshot = ClientState.get("snapshot")
	if live and role == "Infiltrator" and snapshot then
		for _, participant in snapshot.participants do
			if
				participant.role ~= "Infiltrator"
				or participant.userId == player.UserId
				or participant.status ~= "Active"
			then
				continue
			end
			local other = Players:GetPlayerByUserId(participant.userId)
			local character = other and other.Character
			local allyRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if allyRoot and humanoid then
				seen[participant.userId] = true
				local gui = teammates[participant.userId]
				if not gui then
					gui = Create("BillboardGui", {
						Name = "Teammate",
						Adornee = allyRoot,
						AlwaysOnTop = true,
						Size = UDim2.fromOffset(170, 40),
						StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
						MaxDistance = 2000,
						Parent = markerFolder,
					}) :: BillboardGui
					Style.text({
						Name = "Label",
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromScale(1, 1),
						XAlign = Enum.TextXAlignment.Center,
						Parent = gui,
					})
					teammates[participant.userId] = gui
				end
				gui.Adornee = allyRoot
				local label = gui:FindFirstChild("Label") :: TextLabel
				local class = ClassConfig.get(participant.classId)
				local condition = participant.condition or "Healthy"
				label.Text = `{participant.name} · {SurvivalConfig.ConditionNames[condition] or condition}`
				label.TextColor3 = if condition == "Healthy"
					then (if class then class.Color else Theme.Colors.Stable)
					else (Theme.ConditionColors :: any)[condition]
				gui.Enabled = condition ~= "Downed" -- Desynced allies get the stronger aura marker
			end
		end
	end
	for userId, gui in teammates do
		if not seen[userId] then
			gui:Destroy()
			teammates[userId] = nil
		end
	end

	if extractionMarker then
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
				prompt.Enabled = (
					model:GetAttribute("State") == "Available" or model:GetAttribute("State") == "Hacking"
				)
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
	if not marker then
		return
	end
	markers[id] = marker
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

	for _, instance in Workspace:GetDescendants() do
		trackPrompt(instance)
	end
	Workspace.DescendantAdded:Connect(trackPrompt)

	-- Distance text and prompt filters refresh at a modest rate (not every frame).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			refreshMarkers()
			refreshSurvivalMarkers()
			filterPrompts()
		end
	end)
end

return InteractionController
