--!strict
-- WorldService: validates every authored map contract, builds/replaces the selected world, and
-- exposes read-only world queries (spawns, terminal positions, extraction membership, raycasts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local MapLayout = require(script.Parent.Parent.World.MapLayout)
local MapValidator = require(script.Parent.Parent.World.MapValidator)
local MatchWorldBuilder = require(script.Parent.Parent.World.MatchWorldBuilder)
local PlacementRules = require(script.Parent.Parent.Core.PlacementRules)

local WorldService = {}

export type RiftHandle = { site: string, part: BasePart, escape: ProximityPrompt, seal: ProximityPrompt }

local world: MatchWorldBuilder.BuiltWorld? = nil
local rift: RiftHandle? = nil
local geometryParams: RaycastParams? = nil
local selectedId = "Vault"
local selectedMap = MapLayout.Vault
local lightingTween: Tween? = nil

local function getWorld(): MatchWorldBuilder.BuiltWorld
	assert(world, "WorldService used before Init")
	return world :: MatchWorldBuilder.BuiltWorld
end

function WorldService.Init(_deps: { [string]: any })
	for id, map in MapLayout.Maps do
		local errors = MapValidator.validate(map, TerminalConfig.RequiredHacks)
		if #errors > 0 then
			error(`[WorldService] {id}: ` .. table.concat(errors, "; "))
		end
	end
	world = MatchWorldBuilder.build()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { getWorld().static }
	params.IgnoreWater = true
	geometryParams = params
end

function WorldService.SelectMap(mapId: string)
	local map = (MapLayout.Maps :: any)[mapId]
	assert(map, "unknown map")
	rift = nil
	if lightingTween then
		lightingTween:Cancel()
		lightingTween = nil
	end
	selectedId, selectedMap = mapId, map
	world = MatchWorldBuilder.build(map)
	if geometryParams then
		geometryParams.FilterDescendantsInstances = { getWorld().static }
	end
end

function WorldService.GetMapId(): string
	return selectedId
end

function WorldService.GetMap(): MapLayout.MapDefinition
	return selectedMap
end

function WorldService.GetTerminalSpecs(): { { id: string, name: string } }
	local specs = {}
	for _, terminal in selectedMap.terminals do
		table.insert(specs, { id = terminal.id, name = terminal.name })
	end
	return specs
end

function WorldService.GetTerminal(terminalId: string): MatchWorldBuilder.TerminalHandle?
	return getWorld().terminals[terminalId]
end

function WorldService.GetTerminals(): { MatchWorldBuilder.TerminalHandle }
	local list = {}
	local w = getWorld()
	for _, id in w.terminalOrder do
		table.insert(list, w.terminals[id])
	end
	return list
end

function WorldService.GetTerminalPositions(): { Vector3 }
	local list = {}
	for _, terminal in selectedMap.terminals do
		table.insert(list, terminal.position)
	end
	return list
end

function WorldService.GetGeometryFolder(): Folder
	return getWorld().static
end

function WorldService.GetRuntimeFolder(): Folder
	return getWorld().runtime
end

function WorldService.GetLobbySpawnCFrame(): CFrame
	local spawn = MapLayout.Lobby.spawn
	local jitter = Vector3.new(math.random(-6, 6), 0, math.random(-4, 4))
	return CFrame.new(spawn + jitter) * CFrame.Angles(0, math.pi, 0)
end

function WorldService.GetInfiltratorSpawnCFrame(index: number): CFrame
	local spawns = selectedMap.infiltratorSpawns
	local position = spawns[((index - 1) % #spawns) + 1]
	-- Face north toward the vault interior.
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

function WorldService.GetKeeperSpawnCFrame(): CFrame
	local position = selectedMap.keeperSpawn
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

function WorldService.IsInsideExtraction(position: Vector3): boolean
	local map = selectedMap
	local half = map.extractionSize / 2
	local d = position - map.extractionCenter
	return math.abs(d.X) <= half.X and math.abs(d.Y) <= half.Y and math.abs(d.Z) <= half.Z
end

function WorldService.IsInsideVault(position: Vector3): boolean
	local map = selectedMap
	return PlacementRules.isInsideBounds(position, map.boundsMin, map.boundsMax)
end

function WorldService.SetExtractionOpen(open: boolean)
	if lightingTween then
		lightingTween:Cancel()
	end
	local atmosphere = (Theme.Atmospheres :: any)[selectedMap.name]
	lightingTween = TweenService:Create(
		Lighting,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Ambient = if open then Theme.Colors.StableDim else atmosphere.Ambient }
	)
	local current = lightingTween :: Tween
	current:Play()
	local w = getWorld()
	w.gate:SetAttribute("Open", open)
	w.gate.CanCollide = not open
	w.gate.CanQuery = not open
	w.gate.Transparency = if open then 1 else 0.35
	w.extractionPad:SetAttribute("Active", open)
	w.extractionPad.Transparency = if open then 0.45 else 0.85
	w.extractionBeacon.Transparency = if open then 0.55 else 1
end

function WorldService.SetTerminalVisual(terminalId: string, state: string, promptEnabled: boolean)
	local terminal = getWorld().terminals[terminalId]
	if not terminal then
		return
	end
	local color = (Theme.TerminalStateColors :: any)[state] or Theme.TerminalStateColors.Locked
	terminal.screen.Color = color
	terminal.light.Color = color
	terminal.model:SetAttribute("State", state)
	terminal.prompt.Enabled = promptEnabled
end

function WorldService.GetObstacles(): { [string]: MatchWorldBuilder.ObstacleHandle }
	return getWorld().obstacles
end

function WorldService.GetObstacle(id: string): MatchWorldBuilder.ObstacleHandle?
	return getWorld().obstacles[id]
end

function WorldService.GetLockers(): { [string]: MatchWorldBuilder.LockerHandle }
	return getWorld().lockers
end

function WorldService.GetLocker(id: string): MatchWorldBuilder.LockerHandle?
	return getWorld().lockers[id]
end

-- "Standing" | "Dropped" | "Broken"
function WorldService.SetBarrierState(id: string, state: string)
	local handle = getWorld().obstacles[id]
	if not handle or handle.kind ~= "Barrier" then
		return
	end
	local dropped = state == "Dropped"
	handle.part:SetAttribute("State", state)
	handle.part.CanCollide = dropped
	handle.part.CanQuery = dropped
	handle.part.Transparency = if dropped then 0.15 else 1
	if handle.pylon then
		handle.pylon.Transparency = if state == "Standing" then 0 else 0.6
	end
	handle.prompts.Drop.Enabled = state == "Standing"
	handle.prompts.Vault.Enabled = dropped
	handle.prompts.Break.Enabled = dropped
end

function WorldService.SetDoorOpen(id: string, open: boolean)
	local handle = getWorld().obstacles[id]
	if not handle or handle.kind ~= "Door" then
		return
	end
	handle.part:SetAttribute("Open", open)
	handle.part.CanCollide = not open
	handle.part.CanQuery = not open
	handle.part.Transparency = if open then 0.85 else 0
	handle.prompts.Toggle.ActionText = if open then "Close" else "Open"
end

function WorldService.SetLockerOccupant(id: string, occupant: number?)
	local handle = getWorld().lockers[id]
	if not handle then
		return
	end
	-- The occupant attribute is public on purpose: every client filters prompts locally, and a
	-- Keeper client can already see all positions, so it reveals nothing new.
	handle.model:SetAttribute("Occupant", occupant)
	handle.prompts.Hide.Enabled = occupant == nil
	handle.prompts.Leave.Enabled = occupant ~= nil
end

-- Restores every interactable to its match-start state (called when a match begins/cleans up).
function WorldService.ResetFurniture()
	for id, handle in getWorld().obstacles do
		if handle.kind == "Barrier" then
			WorldService.SetBarrierState(id, "Standing")
		elseif handle.kind == "Door" then
			WorldService.SetDoorOpen(id, true)
		end
	end
	for id in getWorld().lockers do
		WorldService.SetLockerOccupant(id, nil)
	end
end

function WorldService.GetPods(): { [string]: MatchWorldBuilder.PodHandle }
	return getWorld().pods
end

function WorldService.GetPod(podId: string): MatchWorldBuilder.PodHandle?
	return getWorld().pods[podId]
end

function WorldService.GetPodIds(): { string }
	local ids = {}
	for _, spec in selectedMap.pods do
		table.insert(ids, spec.id)
	end
	return ids
end

function WorldService.GetRelay(relayId: string): MatchWorldBuilder.RelayHandle?
	return getWorld().relays[relayId]
end

function WorldService.GetRelays(): { [string]: MatchWorldBuilder.RelayHandle }
	return getWorld().relays
end

function WorldService.GetRelayIds(): { string }
	local ids = {}
	for _, spec in selectedMap.relays do
		table.insert(ids, spec.id)
	end
	return ids
end

-- Pod visuals: occupied pods glow toward danger as their stage rises.
function WorldService.SetPodState(podId: string, occupant: number?, stage: number?)
	local pod = getWorld().pods[podId]
	if not pod then
		return
	end
	pod.model:SetAttribute("Occupant", occupant)
	pod.model:SetAttribute("Stage", stage)
	local color = if occupant == nil
		then Theme.World.PodGlass
		elseif (stage or 1) >= 2 then Theme.Colors.Danger
		else Theme.Colors.Temporal
	pod.light.Color = color
	pod.light.Brightness = if occupant then 2.4 else 0.8
	pod.glass.Color = color
	pod.prompt.Enabled = occupant ~= nil
end

function WorldService.SetRelayState(relayId: string, power: number, available: boolean)
	local relay = getWorld().relays[relayId]
	if not relay then
		return
	end
	local color = if power >= 1
		then Theme.TerminalStateColors.Completed
		elseif available then Theme.TerminalStateColors.Hacking
		else Theme.TerminalStateColors.Locked
	relay.model:SetAttribute("Power", power)
	relay.model:SetAttribute("Available", available)
	relay.screen.Color = color
	relay.light.Color = color
	relay.prompt.Enabled = available and power < 1
end

function WorldService.GetRiftSitePosition(site: string): Vector3?
	local index = tonumber(string.match(site, "^Site(%d+)$"))
	return if index then selectedMap.anomalySites[index] else nil
end

function WorldService.GetRiftSites(): { string }
	local ids = {}
	for index in selectedMap.anomalySites do
		table.insert(ids, `Site{index}`)
	end
	return ids
end

-- Opens (site) or closes (nil) the Slip Rift. Returns the handle so prompts can be bound.
function WorldService.SetRift(site: string?): RiftHandle?
	if rift then
		rift.part:Destroy()
		rift = nil
	end
	local position = if site then WorldService.GetRiftSitePosition(site) else nil
	if not site or not position then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "SlipRift"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, 7, 7)
	part.CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(90), 0)
	part.Color = Theme.World.Rift
	part.Material = Enum.Material.Neon
	part.Transparency = 0.25
	part:SetAttribute("RiftSite", site)
	local light = Instance.new("PointLight")
	light.Color = Theme.World.Rift
	light.Range = 20
	light.Brightness = 3
	light.Parent = part
	local function prompt(name: string, action: string): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		p.Name = name
		p.ActionText = action
		p.ObjectText = "Slip Rift"
		p.HoldDuration = 0
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.GamepadKeyCode = Enum.KeyCode.ButtonX
		p.MaxActivationDistance = 6
		p.RequiresLineOfSight = false
		p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		p.Parent = part
		return p
	end
	local handle: RiftHandle = {
		site = site,
		part = part,
		escape = prompt("EscapePrompt", "Slip Through"),
		seal = prompt("SealPrompt", "Seal Rift"),
	}
	part.Parent = getWorld().runtime
	rift = handle
	return handle
end

-- Downward probe against static vault geometry only (characters/effects are excluded).
function WorldService.CastDown(from: Vector3, depth: number): PlacementRules.GroundHit?
	local result = Workspace:Raycast(from, Vector3.new(0, -depth, 0), geometryParams)
	if result and result.Instance.CanCollide then
		return { position = result.Position, normal = result.Normal }
	end
	return nil
end

-- True when nothing in the static geometry blocks the segment.
function WorldService.HasLineOfSight(from: Vector3, to: Vector3): boolean
	local delta = to - from
	if delta.Magnitude < 1e-3 then
		return true
	end
	local result = Workspace:Raycast(from, delta, geometryParams)
	if result == nil then
		return true
	end
	return (result.Position - from).Magnitude >= delta.Magnitude - 0.5
end

return WorldService
