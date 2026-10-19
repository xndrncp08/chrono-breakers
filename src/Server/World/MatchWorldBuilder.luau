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
	overloadPrompt: ProximityPrompt,
	position: Vector3,
}

export type PodHandle = {
	id: string,
	model: Model,
	glass: BasePart,
	light: PointLight,
	prompt: ProximityPrompt,
	holdCFrame: CFrame, -- where a captive is held
	exitCFrame: CFrame, -- where a rescued captive is released
	position: Vector3,
}

export type RelayHandle = {
	id: string,
	model: Model,
	screen: BasePart,
	light: PointLight,
	prompt: ProximityPrompt,
	position: Vector3,
}

export type ObstacleHandle = {
	id: string,
	kind: string,
	spec: MapLayout.Obstacle,
	part: BasePart, -- rail, door slab or (dropped) barrier slab
	pylon: BasePart?, -- standing barrier post
	prompts: { [string]: ProximityPrompt },
}

export type LockerHandle = {
	id: string,
	model: Model,
	prompts: { [string]: ProximityPrompt },
	holdCFrame: CFrame,
	exitCFrame: CFrame,
	position: Vector3,
}

export type BuiltWorld = {
	obstacles: { [string]: ObstacleHandle },
	lockers: { [string]: LockerHandle },
	pods: { [string]: PodHandle },
	relays: { [string]: RelayHandle },
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
MatchWorldBuilder.POD_TAG = "ChronoPod"
MatchWorldBuilder.RELAY_TAG = "ChronoRelay"
MatchWorldBuilder.OBSTACLE_TAG = "ChronoObstacle"
MatchWorldBuilder.LOCKER_TAG = "ChronoLocker"

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

	-- Keeper-only (filtered locally); the server validates the Overload request.
	local overload = prompt:Clone()
	overload.Name = "OverloadPrompt"
	overload.ActionText = "Overload"
	overload.MaxActivationDistance = 7.5
	overload.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	overload.Parent = attachment

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
		overloadPrompt = overload,
		position = spec.position,
	}
end

local function makePrompt(
	parent: Instance,
	name: string,
	action: string,
	object: string,
	range: number
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = range
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local function makePod(spec: MapLayout.Fixture, parent: Instance): PodHandle
	local size = MapLayout.POD_SIZE
	local model = Instance.new("Model")
	model.Name = `StasisPod_{spec.id}`
	model:SetAttribute("PodId", spec.id)
	local base = CFrame.lookAt(spec.position, spec.position + spec.facing)
	local function part(name: string, cframe: CFrame, partSize: Vector3, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.Size = partSize
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	part(
		"Base",
		base * CFrame.new(0, 0.3, 0),
		Vector3.new(size.X + 1, 0.6, size.Z + 1),
		Theme.World.PodFrame,
		Enum.Material.Metal
	)
	part(
		"Cap",
		base * CFrame.new(0, size.Y - 0.3, 0),
		Vector3.new(size.X + 1, 0.6, size.Z + 1),
		Theme.World.PodFrame,
		Enum.Material.Metal
	)
	local glass = part(
		"Glass",
		base * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(size.Y - 1.2, size.X, size.Z),
		Theme.World.PodGlass,
		Enum.Material.Glass
	)
	glass.Shape = Enum.PartType.Cylinder
	glass.Transparency = 0.55
	glass.CastShadow = false
	local ring = part(
		"Ring",
		base * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.1, size.X + 0.6, size.Z + 0.6),
		Theme.World.PodGlass,
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.CanCollide, ring.CanQuery = false, false
	local light = Instance.new("PointLight")
	light.Color = Theme.World.PodGlass
	light.Brightness = 0.8
	light.Range = 12
	light.Parent = glass
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.WorldCFrame = base * CFrame.new(0, 3, -size.Z / 2 - 0.5)
	attachment.Parent = glass
	local prompt = makePrompt(attachment, "RescuePrompt", "Rescue", "Stasis Pod", 7)
	model.PrimaryPart = glass
	model.Parent = parent
	CollectionService:AddTag(model, MatchWorldBuilder.POD_TAG)
	return {
		id = spec.id,
		model = model,
		glass = glass,
		light = light,
		prompt = prompt,
		holdCFrame = base * CFrame.new(0, 3.4, 0),
		exitCFrame = base * CFrame.new(0, 3, -(size.Z / 2 + 3)),
		position = spec.position,
	}
end

local function makeRelay(spec: MapLayout.Fixture, parent: Instance): RelayHandle
	local model = Instance.new("Model")
	model.Name = `GateRelay_{spec.id}`
	model:SetAttribute("RelayId", spec.id)
	model:SetAttribute("Power", 0)
	local facing = CFrame.lookAt(spec.position, spec.position + spec.facing)
	local console = Instance.new("Part")
	console.Name = "Console"
	console.Anchored = true
	console.CanTouch = false
	console.Size = Vector3.new(4, 5, 1.6)
	console.CFrame = facing * CFrame.new(0, 0.5, 0)
	console.Color = Theme.World.TerminalBody
	console.Material = Enum.Material.Metal
	console.Parent = model
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Anchored, screen.CanCollide, screen.CanQuery, screen.CanTouch = true, false, false, false
	screen.Size = Vector3.new(3.2, 3, 0.1)
	screen.CFrame = facing * CFrame.new(0, 0.9, -0.85)
	screen.Color = Theme.TerminalStateColors.Locked
	screen.Material = Enum.Material.Neon
	screen.Parent = model
	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 12
	light.Color = Theme.TerminalStateColors.Locked
	light.Parent = screen
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 0, -1.2)
	attachment.Parent = console
	local prompt = makePrompt(attachment, "RelayPrompt", "Power Relay", "Gate Relay", 7)
	model.PrimaryPart = console
	model.Parent = parent
	CollectionService:AddTag(model, MatchWorldBuilder.RELAY_TAG)
	return {
		id = spec.id,
		model = model,
		screen = screen,
		light = light,
		prompt = prompt,
		position = spec.position,
	}
end

local function obstacleCFrame(spec: MapLayout.Obstacle, height: number): CFrame
	return CFrame.new(spec.center + Vector3.new(0, height / 2, 0))
end

local function obstacleSize(spec: MapLayout.Obstacle, height: number): Vector3
	local thick = MapLayout.OBSTACLE_THICKNESS
	return if spec.axis == "X" then Vector3.new(spec.length, height, thick) else Vector3.new(thick, height, spec.length)
end

local function makeObstacle(spec: MapLayout.Obstacle, parent: Instance): ObstacleHandle
	local isDoor = spec.kind == "Door"
	local height = if isDoor then MapLayout.WALL_HEIGHT else MapLayout.OBSTACLE_HEIGHT
	local part = Instance.new("Part")
	part.Name = `{spec.kind}_{spec.id}`
	part.Anchored = true
	part.CanTouch = false
	part.Size = obstacleSize(spec, height)
	part.CFrame = obstacleCFrame(spec, height)
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part:SetAttribute("ObstacleId", spec.id)
	part:SetAttribute("ObstacleKind", spec.kind)
	local prompts: { [string]: ProximityPrompt } = {}
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.Position = Vector3.new(0, if isDoor then -height / 2 + 3 else 0.6, 0)
	attachment.Parent = part
	local pylon: BasePart? = nil
	if spec.kind == "Rail" then
		part.Color = Theme.World.Cover
		part.Material = Enum.Material.DiamondPlate
		local trim = Instance.new("Part")
		trim.Name = "RailTrim"
		trim.Anchored, trim.CanCollide, trim.CanQuery, trim.CanTouch = true, false, false, false
		trim.Size = part.Size * Vector3.new(1, 0, 1) + Vector3.new(0.1, 0.12, 0.1)
		trim.CFrame = part.CFrame * CFrame.new(0, height / 2, 0)
		trim.Color = Theme.World.TrimCyan
		trim.Material = Enum.Material.Neon
		trim.Parent = part
		prompts.Vault = makePrompt(attachment, "VaultPrompt", "Vault", "Breach Rail", 5)
		prompts.Vault.Enabled = true
	elseif spec.kind == "Barrier" then
		part.Color = Theme.World.Gate
		part.Material = Enum.Material.ForceField
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		local post = Instance.new("Part")
		post.Name = "BarrierPylon"
		post.Anchored, post.CanTouch = true, false
		post.Size = Vector3.new(1.2, 6, 1.2)
		local half = spec.length / 2 + 0.4
		post.CFrame =
			CFrame.new(spec.center + (if spec.axis == "X" then Vector3.new(-half, 3, 0) else Vector3.new(0, 3, -half)))
		post.Color = Theme.World.PodFrame
		post.Material = Enum.Material.Metal
		post:SetAttribute("ObstacleId", spec.id)
		local glow = Instance.new("PointLight")
		glow.Color = Theme.World.Gate
		glow.Range = 8
		glow.Brightness = 0.8
		glow.Parent = post
		post.Parent = parent
		pylon = post
		local postAttachment = Instance.new("Attachment")
		postAttachment.Position = Vector3.new(0, -1.5, 0)
		postAttachment.Parent = post
		prompts.Drop = makePrompt(postAttachment, "DropPrompt", "Drop Barrier", "Stasis Barrier", 6)
		prompts.Drop.Enabled = true
		prompts.Vault = makePrompt(attachment, "VaultPrompt", "Vault", "Stasis Barrier", 5)
		prompts.Break = makePrompt(attachment, "BreakPrompt", "Break", "Stasis Barrier", 6)
	else
		part.Color = Theme.World.Wall
		part.Material = Enum.Material.Metal
		part.Transparency = 0.85
		part.CanCollide = false
		part.CanQuery = false
		prompts.Toggle = makePrompt(attachment, "TogglePrompt", "Close", "Blast Door", 6)
		prompts.Toggle.Enabled = true
	end
	part.Parent = parent
	CollectionService:AddTag(part, MatchWorldBuilder.OBSTACLE_TAG)
	return { id = spec.id, kind = spec.kind, spec = spec, part = part, pylon = pylon, prompts = prompts }
end

local function makeLocker(spec: MapLayout.Fixture, parent: Instance): LockerHandle
	local size = MapLayout.LOCKER_SIZE
	local model = Instance.new("Model")
	model.Name = `PhaseLocker_{spec.id}`
	model:SetAttribute("LockerId", spec.id)
	local base = CFrame.lookAt(spec.position, spec.position + spec.facing)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored, body.CanTouch = true, false
	body.Size = size
	body.CFrame = base * CFrame.new(0, size.Y / 2, 0)
	body.Color = Theme.World.Shelf
	body.Material = Enum.Material.Metal
	body.Parent = model
	local slit = Instance.new("Part")
	slit.Name = "Vent"
	slit.Anchored, slit.CanCollide, slit.CanQuery, slit.CanTouch = true, false, false, false
	slit.Size = Vector3.new(size.X - 1, 0.25, 0.1)
	slit.CFrame = base * CFrame.new(0, size.Y - 1.4, -size.Z / 2 - 0.05)
	slit.Color = Theme.World.TrimCyan
	slit.Material = Enum.Material.Neon
	slit.Parent = model
	local attachment = Instance.new("Attachment")
	attachment.WorldCFrame = base * CFrame.new(0, 3, -size.Z / 2 - 0.6)
	attachment.Parent = body
	local prompts = {
		Hide = makePrompt(attachment, "HidePrompt", "Hide", "Phase Locker", 5),
		Search = makePrompt(attachment, "SearchPrompt", "Search", "Phase Locker", 6),
		Leave = makePrompt(attachment, "LeavePrompt", "Leave", "Phase Locker", 8),
	}
	prompts.Hide.Enabled = true
	prompts.Search.Enabled = true
	model.PrimaryPart = body
	model.Parent = parent
	CollectionService:AddTag(model, MatchWorldBuilder.LOCKER_TAG)
	return {
		id = spec.id,
		model = model,
		prompts = prompts,
		holdCFrame = base * CFrame.new(0, 3.2, 0),
		exitCFrame = base * CFrame.new(0, 3, -(size.Z / 2 + 2.5)),
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

	local podsFolder = Instance.new("Folder")
	podsFolder.Name = "StasisPods"
	podsFolder.Parent = static
	local pods: { [string]: PodHandle } = {}
	for _, spec in map.pods do
		pods[spec.id] = makePod(spec, podsFolder)
	end
	local relays: { [string]: RelayHandle } = {}
	for _, spec in map.relays do
		relays[spec.id] = makeRelay(spec, static)
	end
	local furniture = Instance.new("Folder")
	furniture.Name = "ChaseFurniture"
	furniture.Parent = static
	local obstacles: { [string]: ObstacleHandle } = {}
	for _, spec in map.obstacles do
		obstacles[spec.id] = makeObstacle(spec, furniture)
	end
	local lockers: { [string]: LockerHandle } = {}
	for _, spec in map.lockers do
		lockers[spec.id] = makeLocker(spec, furniture)
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
		obstacles = obstacles,
		lockers = lockers,
		pods = pods,
		relays = relays,
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
