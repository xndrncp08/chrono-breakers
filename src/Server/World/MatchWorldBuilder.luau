--!strict
-- Builds the lobby and selected authored map deterministically at startup and between matches.
-- Every registered layout must pass MapValidator before gameplay starts.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local MapLayout = require(script.Parent.MapLayout)

export type TerminalHandle = {
	id: string,
	name: string,
	model: Model,
	console: BasePart,
	screen: BasePart,
	light: PointLight,
	prompt: ProximityPrompt,
	position: Vector3,
}

export type BuiltWorld = {
	root: Folder,
	vault: Folder,
	static: Folder,
	runtime: Folder,
	lobby: Folder,
	terminals: { [string]: TerminalHandle },
	terminalOrder: { string },
	gate: BasePart,
	extractionPad: BasePart,
	extractionBeacon: BasePart,
	lobbySpawn: SpawnLocation,
}

local MatchWorldBuilder = {}

MatchWorldBuilder.TERMINAL_TAG = "ChronoTerminal"

local function makePart(box: MapLayout.Box, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = box.name
	part.Anchored = true
	part.Size = box.size
	part.CFrame = CFrame.new(box.center)
	part.Color = (Theme.World :: any)[box.color] or Theme.World.Wall
	local material = (Enum.Material :: any)[box.material]
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = box.collide
	part.CanTouch = false
	part.CastShadow = box.kind ~= "Trim" and box.kind ~= "Decor"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if box.kind == "Trim" or box.kind == "Decor" then
		part.CanQuery = false
	end
	part:SetAttribute("Kind", box.kind)
	part.Parent = parent
	return part
end

local function makeTerminal(spec: MapLayout.TerminalSpec, parent: Instance): TerminalHandle
	local model = Instance.new("Model")
	model.Name = `Terminal_{spec.id}`
	model:SetAttribute("TerminalId", spec.id)
	model:SetAttribute("DisplayName", spec.name)
	model:SetAttribute("State", "Locked")

	local facingCFrame = CFrame.lookAt(spec.position, spec.position + spec.facing)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(5, 0.6, 3.4)
	base.CFrame = facingCFrame * CFrame.new(0, -2.2, 0)
	base.Color = Theme.World.TerminalBody
	base.Material = Enum.Material.Metal
	base.CanTouch = false
	base.Parent = model

	local console = Instance.new("Part")
	console.Name = "Console"
	console.Anchored = true
	console.Size = Vector3.new(4, 4, 1.6)
	console.CFrame = facingCFrame
	console.Color = Theme.World.TerminalBody
	console.Material = Enum.Material.Metal
	console.CanTouch = false
	console.Parent = model

	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanTouch = false
	screen.CanQuery = false
	screen.Size = Vector3.new(3.2, 2.4, 0.1)
	-- Front face of the console is -Z in its local space (lookAt points -Z toward `facing`).
	screen.CFrame = facingCFrame * CFrame.new(0, 0.4, -0.85)
	screen.Color = Theme.TerminalStateColors.Locked
	screen.Material = Enum.Material.Neon
	screen.Parent = model

	local light = Instance.new("PointLight")
	light.Brightness = 1.6
	light.Range = 14
	light.Color = Theme.TerminalStateColors.Locked
	light.Parent = screen

	local label = Instance.new("SurfaceGui")
	label.Name = "Label"
	label.Face = Enum.NormalId.Front
	label.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	label.PixelsPerStud = 50
	label.LightInfluence = 0
	label.Parent = screen
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Theme.Fonts.Heading
	text.TextScaled = true
	text.TextColor3 = Theme.Colors.TextOnAccent
	text.Text = string.upper(spec.name)
	text.Parent = label

	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.Position = Vector3.new(0, 0, -1.2)
	attachment.Parent = console

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HackPrompt"
	prompt.ActionText = "Hack"
	prompt.ObjectText = spec.name
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = TerminalConfig.PromptActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = attachment

	model.PrimaryPart = console
	model.Parent = parent
	CollectionService:AddTag(model, MatchWorldBuilder.TERMINAL_TAG)

	return {
		id = spec.id,
		name = spec.name,
		model = model,
		console = console,
		screen = screen,
		light = light,
		prompt = prompt,
		position = spec.position,
	}
end

local function applyLighting(map: MapLayout.MapDefinition)
	local atmosphere = (Theme.Atmospheres :: any)[map.name]
	Lighting.ClockTime = atmosphere.Clock
	Lighting.Brightness = 1.2
	Lighting.Ambient = atmosphere.Ambient
	Lighting.OutdoorAmbient = Color3.fromRGB(56, 64, 100)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.FogColor = atmosphere.Fog
	Lighting.FogStart = 120
	Lighting.FogEnd = 520
	Lighting.GlobalShadows = true

	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local effect = Instance.new(className)
		effect.Name = name
		effect.Parent = Lighting
		return effect
	end
	local bloom = ensure("BloomEffect", "ChronoBloom") :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 20
	bloom.Threshold = 1.4
	local grade = ensure("ColorCorrectionEffect", "ChronoGrade") :: ColorCorrectionEffect
	grade.Contrast = 0.08
	grade.Saturation = 0.05
	grade.TintColor = Color3.fromRGB(235, 242, 255)
end

local function makeLobbySign(lobby: MapLayout.LobbyDefinition, parent: Instance)
	local sign = Instance.new("Part")
	sign.Name = "TitleSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.Size = Vector3.new(40, 10, 0.4)
	sign.CFrame = CFrame.new(lobby.center + Vector3.new(0, 10, -40.6))
	sign.Transparency = 1
	sign.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Font = Theme.Fonts.Display
	title.TextScaled = true
	title.TextColor3 = Theme.Colors.Stable
	title.Text = "CHRONO BREAKERS"
	title.Parent = gui
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0, 0.62)
	subtitle.Size = UDim2.fromScale(1, 0.3)
	subtitle.Font = Theme.Fonts.Heading
	subtitle.TextScaled = true
	subtitle.TextColor3 = Theme.Colors.Temporal
	subtitle.Text = string.upper(GameConfig.GameSubtitle)
	subtitle.Parent = gui
end

function MatchWorldBuilder.build(selectedMap: MapLayout.MapDefinition?): BuiltWorld
	local map = selectedMap or MapLayout.Vault
	local existing = Workspace:FindFirstChild("ChronoBreakers")
	if existing then
		existing:Destroy()
	end
	applyLighting(map)

	local root = Instance.new("Folder")
	root.Name = "ChronoBreakers"

	-- Lobby
	local lobbyFolder = Instance.new("Folder")
	lobbyFolder.Name = "Lobby"
	lobbyFolder.Parent = root
	local lobby = MapLayout.Lobby
	for _, box in lobby.boxes do
		makePart(box, lobbyFolder)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(lobby.spawn - Vector3.new(0, 2.8, 0))
	spawn.Color = Theme.World.TrimCyan
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.CanTouch = true
	spawn.Parent = lobbyFolder
	makeLobbySign(lobby, lobbyFolder)

	-- Vault
	local vault = Instance.new("Folder")
	vault.Name = "Vault"
	vault.Parent = root
	local static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = vault
	for _, box in map.boxes do
		makePart(box, static)
	end

	for _, landmark in map.landmarks do
		local sign = Instance.new("Part")
		sign.Name = "Wayfinding_" .. landmark.name
		sign.Anchored, sign.CanCollide, sign.CanQuery, sign.CanTouch = true, false, false, false
		sign.Size, sign.Position = Vector3.new(14, 2, 0.2), landmark.position + Vector3.new(0, 16, 0)
		sign.Color, sign.Material = Theme.World.TerminalBody, Enum.Material.Metal
		sign.Parent = static
		local gui = Instance.new("SurfaceGui")
		gui.Face, gui.SizingMode, gui.PixelsPerStud, gui.LightInfluence =
			Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 30, 0
		gui.Parent = sign
		local text = Instance.new("TextLabel")
		text.Size, text.BackgroundTransparency, text.Text, text.Font, text.TextScaled, text.TextColor3 =
			UDim2.fromScale(1, 1), 1, string.upper(landmark.name), Theme.Fonts.Heading, true, Theme.Colors.Stable
		text.Parent = gui
		local reverse = gui:Clone()
		reverse.Face = Enum.NormalId.Back
		reverse.Parent = sign
	end

	local terminalsFolder = Instance.new("Folder")
	terminalsFolder.Name = "Terminals"
	terminalsFolder.Parent = static
	local terminals: { [string]: TerminalHandle } = {}
	local order: { string } = {}
	for _, spec in map.terminals do
		terminals[spec.id] = makeTerminal(spec, terminalsFolder)
		table.insert(order, spec.id)
	end

	local gate = makePart(map.gate, static)
	gate.Transparency = 0.35
	gate:SetAttribute("Open", false)

	local pad = Instance.new("Part")
	pad.Name = "ExtractionPad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.Size = Vector3.new(map.extractionSize.X, 0.2, map.extractionSize.Z)
	pad.CFrame = CFrame.new(map.extractionCenter.X, 0.12, map.extractionCenter.Z)
	pad.Color = Theme.World.ExtractionPad
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.85
	pad:SetAttribute("Active", false)
	pad.Parent = vault

	local beacon = Instance.new("Part")
	beacon.Name = "ExtractionBeacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(60, 3, 3)
	beacon.CFrame = CFrame.new(map.extractionCenter.X, 30, map.extractionCenter.Z) * CFrame.Angles(0, 0, math.rad(90))
	beacon.Color = Theme.World.ExtractionPad
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 1
	beacon.Parent = vault

	local runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = root

	root:SetAttribute("MapName", map.name)
	root.Parent = Workspace

	return {
		root = root,
		vault = vault,
		static = static,
		runtime = runtime,
		lobby = lobbyFolder,
		terminals = terminals,
		terminalOrder = order,
		gate = gate,
		extractionPad = pad,
		extractionBeacon = beacon,
		lobbySpawn = spawn,
	}
end

return MatchWorldBuilder
