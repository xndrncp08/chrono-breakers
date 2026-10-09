--!strict
-- WorldService: validates the authored map contract (fails loudly), builds the world once, and
-- exposes read-only world queries (spawns, terminal positions, extraction membership, raycasts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local MapLayout = require(script.Parent.Parent.World.MapLayout)
local MapValidator = require(script.Parent.Parent.World.MapValidator)
local MatchWorldBuilder = require(script.Parent.Parent.World.MatchWorldBuilder)
local PlacementRules = require(script.Parent.Parent.Core.PlacementRules)

local WorldService = {}

local world: MatchWorldBuilder.BuiltWorld? = nil
local geometryParams: RaycastParams? = nil

local function getWorld(): MatchWorldBuilder.BuiltWorld
	assert(world, "WorldService used before Init")
	return world :: MatchWorldBuilder.BuiltWorld
end

function WorldService.Init(_deps: { [string]: any })
	local errors = MapValidator.validate(MapLayout.Vault, TerminalConfig.RequiredHacks)
	if #errors > 0 then
		error("[WorldService] map contract violated:\n  " .. table.concat(errors, "\n  "))
	end
	world = MatchWorldBuilder.build()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { getWorld().static }
	params.IgnoreWater = true
	geometryParams = params
end

function WorldService.GetMap(): MapLayout.MapDefinition
	return MapLayout.Vault
end

function WorldService.GetTerminalSpecs(): { { id: string, name: string } }
	local specs = {}
	for _, terminal in MapLayout.Vault.terminals do
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
	for _, terminal in MapLayout.Vault.terminals do
		table.insert(list, terminal.position)
	end
	return list
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
	local spawns = MapLayout.Vault.infiltratorSpawns
	local position = spawns[((index - 1) % #spawns) + 1]
	-- Face north toward the vault interior.
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

function WorldService.GetKeeperSpawnCFrame(): CFrame
	local position = MapLayout.Vault.keeperSpawn
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

function WorldService.IsInsideExtraction(position: Vector3): boolean
	local map = MapLayout.Vault
	local half = map.extractionSize / 2
	local d = position - map.extractionCenter
	return math.abs(d.X) <= half.X and math.abs(d.Y) <= half.Y and math.abs(d.Z) <= half.Z
end

function WorldService.IsInsideVault(position: Vector3): boolean
	local map = MapLayout.Vault
	return PlacementRules.isInsideBounds(position, map.boundsMin, map.boundsMax)
end

function WorldService.SetExtractionOpen(open: boolean)
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

-- Downward probe against static vault geometry only (characters/effects are excluded).
function WorldService.CastDown(from: Vector3, depth: number): PlacementRules.GroundHit?
	local result = Workspace:Raycast(from, Vector3.new(0, -depth, 0), geometryParams)
	if result then
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
