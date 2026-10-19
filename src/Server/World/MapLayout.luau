--!strict
-- Authored blockout for the first map, "Chronos Vault", plus the separate lobby.
-- Coordinates: +X east, +Z south, floor top at Y = 0. Layout (top-down):
--
--   z=-90 +-------------+--------------+--------------+
--         |  ARCHIVE    |   SANCTUM    |   REACTOR    |   T1 Archive, Keeper spawn, T2 Reactor
--         |   (T1)      |  (Keeper)    |    (T2)      |
--   z=-35 +--d----d-----+---d------d---+----d-----d---+
--         |      WEST HALL   ·  ATRIUM (Chrono Core)  ·   EAST HALL     |
--   z= 35 +--d----d-----+------d-------+----d-----d---+
--         |  SPAWN BAY  d    DOCK      d OBSERVATORY  |   Infiltrator spawn, extraction, T3
--         | (Infiltr.)  |  [GATE]      |    (T3)      |
--         |             | [EXTRACTION] |              |
--   z= 90 +-------------+--------------+--------------+
--
-- Every room has at least two entrances; the extraction pad sits behind the Breach Gate, which
-- opens only during the Extraction phase. MapValidator checks bounds, spacing, and reachability.

export type BoxKind = "Floor" | "Wall" | "Cover" | "Trim" | "Gate" | "Decor" | "Platform"

export type Box = {
	name: string,
	kind: BoxKind,
	center: Vector3,
	size: Vector3,
	color: string, -- WorldTheme token
	material: string, -- Enum.Material name
	collide: boolean,
}

export type TerminalSpec = {
	id: string,
	name: string,
	position: Vector3, -- console centre (distance checks use this)
	facing: Vector3, -- unit vector pointing from the console toward the hacker's side
}

-- Survival fixtures: Stasis Pods (rescue from the facing side), Gate Relay consoles and Phase
-- Lockers (entered from the facing side).
export type Fixture = {
	id: string,
	position: Vector3, -- floor-level centre (pods) or console centre (relays)
	facing: Vector3, -- unit vector toward the side players interact from
}

-- Chase furniture. Rails and dropped barriers are vaulted across their thin axis; doors fill a wall
-- gap. `axis` is the long direction ("X" or "Z"); `center` is at floor level.
export type ObstacleKind = "Rail" | "Barrier" | "Door"
export type Obstacle = {
	id: string,
	kind: ObstacleKind,
	center: Vector3,
	axis: string,
	length: number,
}

export type MapDefinition = {
	name: string,
	pods: { Fixture },
	relays: { Fixture },
	lockers: { Fixture },
	obstacles: { Obstacle },
	anomalySites: { Vector3 },
	boundsMin: Vector3,
	boundsMax: Vector3,
	floorY: number,
	boxes: { Box },
	infiltratorSpawns: { Vector3 },
	keeperSpawn: Vector3,
	terminals: { TerminalSpec },
	extractionCenter: Vector3,
	extractionSize: Vector3,
	gate: Box,
	landmarks: { { name: string, position: Vector3 } },
}

export type LobbyDefinition = {
	center: Vector3,
	spawn: Vector3,
	boxes: { Box },
}

local WALL_HEIGHT = 20
local WALL_THICKNESS = 2

local MapLayout = {}

local function box(
	name: string,
	kind: BoxKind,
	center: Vector3,
	size: Vector3,
	color: string,
	material: string,
	collide: boolean?
): Box
	return {
		name = name,
		kind = kind,
		center = center,
		size = size,
		color = color,
		material = material,
		collide = if collide == nil then true else collide,
	}
end

type Gap = { center: number, width: number }

-- Splits a straight wall run into segments around door gaps.
local function segments(from: number, to: number, gaps: { Gap }): { { number } }
	table.sort(gaps, function(a, b)
		return a.center < b.center
	end)
	local runs: { { number } } = {}
	local cursor = from
	for _, gap in gaps do
		local gapStart = gap.center - gap.width / 2
		local gapEnd = gap.center + gap.width / 2
		if gapStart > cursor then
			table.insert(runs, { cursor, gapStart })
		end
		cursor = math.max(cursor, gapEnd)
	end
	if to > cursor then
		table.insert(runs, { cursor, to })
	end
	return runs
end

-- Wall running along X at constant Z.
local function wallX(boxes: { Box }, name: string, z: number, x1: number, x2: number, gaps: { Gap }, height: number?)
	local h = height or WALL_HEIGHT
	for i, run in segments(x1, x2, gaps) do
		local length = run[2] - run[1]
		table.insert(
			boxes,
			box(
				`{name}_{i}`,
				"Wall",
				Vector3.new((run[1] + run[2]) / 2, h / 2, z),
				Vector3.new(length, h, WALL_THICKNESS),
				"Wall",
				"SmoothPlastic"
			)
		)
		-- Neon floor trim along the wall base for readability.
		table.insert(
			boxes,
			box(
				`{name}_{i}_Trim`,
				"Trim",
				Vector3.new((run[1] + run[2]) / 2, 0.15, z),
				Vector3.new(length, 0.3, WALL_THICKNESS + 0.4),
				"TrimCyan",
				"Neon",
				false
			)
		)
	end
end

-- Wall running along Z at constant X.
local function wallZ(boxes: { Box }, name: string, x: number, z1: number, z2: number, gaps: { Gap }, height: number?)
	local h = height or WALL_HEIGHT
	for i, run in segments(z1, z2, gaps) do
		local length = run[2] - run[1]
		table.insert(
			boxes,
			box(
				`{name}_{i}`,
				"Wall",
				Vector3.new(x, h / 2, (run[1] + run[2]) / 2),
				Vector3.new(WALL_THICKNESS, h, length),
				"Wall",
				"SmoothPlastic"
			)
		)
		table.insert(
			boxes,
			box(
				`{name}_{i}_Trim`,
				"Trim",
				Vector3.new(x, 0.15, (run[1] + run[2]) / 2),
				Vector3.new(WALL_THICKNESS + 0.4, 0.3, length),
				"TrimCyan",
				"Neon",
				false
			)
		)
	end
end

local function fixture(id: string, x: number, y: number, z: number, fx: number, fz: number): Fixture
	return { id = id, position = Vector3.new(x, y, z), facing = Vector3.new(fx, 0, fz).Unit }
end

local function obstacle(kind: ObstacleKind, id: string, x: number, z: number, axis: string, length: number): Obstacle
	return { id = id, kind = kind, center = Vector3.new(x, 0, z), axis = axis, length = length }
end

local function cover(
	boxes: { Box },
	name: string,
	x: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: string?
)
	table.insert(
		boxes,
		box(name, "Cover", Vector3.new(x, sy / 2, z), Vector3.new(sx, sy, sz), color or "Cover", "Metal")
	)
end

local function buildVault(): MapDefinition
	local boxes: { Box } = {}

	-- Floor and zone floor tints
	table.insert(boxes, box("Floor", "Floor", Vector3.new(0, -1, 0), Vector3.new(184, 2, 184), "Floor", "Slate"))
	table.insert(
		boxes,
		box("HallStripe", "Decor", Vector3.new(0, 0.05, 0), Vector3.new(176, 0.1, 6), "FloorAccent", "Neon", false)
	)

	-- Outer shell
	wallX(boxes, "OuterNorth", -91, -92, 92, {})
	wallX(boxes, "OuterSouth", 91, -92, 92, {})
	wallZ(boxes, "OuterWest", -91, -90, 90, {})
	wallZ(boxes, "OuterEast", 91, -90, 90, {})

	-- Interior partitions with doors (10-12 studs wide)
	wallX(boxes, "NorthPartition", -35, -90, 90, {
		{ center = -72, width = 10 },
		{ center = -46, width = 10 },
		{ center = -14, width = 10 },
		{ center = 14, width = 10 },
		{ center = 46, width = 10 },
		{ center = 72, width = 10 },
	})
	wallX(boxes, "SouthPartition", 35, -90, 90, {
		{ center = -72, width = 10 },
		{ center = -46, width = 10 },
		{ center = 0, width = 12 },
		{ center = 46, width = 10 },
		{ center = 72, width = 10 },
	})
	wallZ(boxes, "ArchiveSanctumWall", -30, -90, -35, { { center = -62, width = 10 } })
	wallZ(boxes, "SanctumReactorWall", 30, -90, -35, { { center = -62, width = 10 } })
	wallZ(boxes, "SpawnDockWall", -30, 35, 90, { { center = 56, width = 10 } })
	wallZ(boxes, "DockObservatoryWall", 30, 35, 90, { { center = 56, width = 10 } })
	-- Breach wall in the Dock; the central gap is closed by the Gate until extraction opens.
	wallX(boxes, "BreachWall", 70, -30, 30, { { center = 0, width = 14 } })

	-- ARCHIVE (NW): shelving rows create lanes; terminal on the north wall.
	cover(boxes, "ArchiveShelf_A", -78, -70, 14, 9, 2, "Shelf")
	cover(boxes, "ArchiveShelf_B", -50, -70, 14, 9, 2, "Shelf")
	cover(boxes, "ArchiveShelf_C", -72, -54, 16, 9, 2, "Shelf")
	cover(boxes, "ArchiveShelf_D", -44, -54, 12, 9, 2, "Shelf")
	cover(boxes, "ArchiveCrate", -62, -44, 4, 4, 4)

	-- SANCTUM (N): Keeper spawn dais and pillars.
	table.insert(
		boxes,
		box("SanctumDais", "Platform", Vector3.new(0, 0.5, -75), Vector3.new(16, 1, 16), "Danger", "SmoothPlastic")
	)
	cover(boxes, "SanctumPillar_W", -18, -60, 4, 16, 4, "Pillar")
	cover(boxes, "SanctumPillar_E", 18, -60, 4, 16, 4, "Pillar")
	cover(boxes, "SanctumPillar_SW", -18, -45, 4, 16, 4, "Pillar")
	cover(boxes, "SanctumPillar_SE", 18, -45, 4, 16, 4, "Pillar")

	-- REACTOR (NE): reactor core blocks sight lines; terminal on the east wall.
	table.insert(boxes, box("ReactorCore", "Cover", Vector3.new(58, 7, -62), Vector3.new(12, 14, 12), "Danger", "Neon"))
	cover(boxes, "ReactorConsoleBank", 58, -82, 18, 4, 3)
	cover(boxes, "ReactorCrate_A", 42, -48, 5, 4, 5)
	cover(boxes, "ReactorCrate_B", 76, -44, 5, 6, 5)

	-- MIDDLE BAND: Atrium core plus staggered cover for flanking routes.
	cover(boxes, "ChronoCore", 0, 0, 12, 14, 12, "Pillar")
	table.insert(
		boxes,
		box(
			"ChronoCoreGlow",
			"Decor",
			Vector3.new(0, 14.25, 0),
			Vector3.new(12.4, 0.5, 12.4),
			"TrimCyan",
			"Neon",
			false
		)
	)
	cover(boxes, "WestLane_Wall", -55, -12, 2, 8, 18)
	cover(boxes, "EastLane_Wall", 55, 12, 2, 8, 18)
	cover(boxes, "MidCrate_NW", -24, -20, 6, 4, 6)
	cover(boxes, "MidCrate_SE", 24, 20, 6, 4, 6)
	cover(boxes, "MidCrate_NE", 30, -18, 4, 6, 8)
	cover(boxes, "MidCrate_SW", -30, 18, 4, 6, 8)
	cover(boxes, "WestPillar", -76, 10, 5, 16, 5, "Pillar")
	cover(boxes, "EastPillar", 76, -10, 5, 16, 5, "Pillar")

	-- SPAWN BAY (SW)
	cover(boxes, "SpawnCrate_A", -48, 50, 6, 4, 6)
	cover(boxes, "SpawnCrate_B", -80, 52, 4, 6, 10)
	cover(boxes, "SpawnBarrier", -45, 76, 2, 8, 14)

	-- DOCK (S): approach cover before the Breach Gate.
	cover(boxes, "DockCrate_W", -14, 52, 6, 4, 6)
	cover(boxes, "DockCrate_E", 14, 58, 6, 4, 6)

	-- OBSERVATORY (SE): telescope platform is low enough to jump onto (3 studs).
	table.insert(
		boxes,
		box("TelescopePlatform", "Platform", Vector3.new(58, 1.5, 58), Vector3.new(12, 3, 12), "Cover", "Metal")
	)
	cover(boxes, "Telescope", 58, 58, 3, 12, 3, "Pillar")
	cover(boxes, "ObservatoryCrate_A", 44, 76, 5, 4, 5)
	cover(boxes, "ObservatoryCrate_B", 80, 46, 5, 6, 5)

	local gate = box(
		"BreachGate",
		"Gate",
		Vector3.new(0, WALL_HEIGHT / 2, 70),
		Vector3.new(14, WALL_HEIGHT, 1.5),
		"Danger",
		"ForceField"
	)

	return {
		name = "Chronos Vault",
		pods = {
			fixture("P1", -40, 0, 24, 1, 0),
			fixture("P2", 40, 0, -24, -1, 0),
			fixture("P3", -72, 0, -46, 0, 1),
			fixture("P4", 78, 0, 64, -1, 0),
		},
		relays = {
			fixture("R1", -87, 2.5, 40, 1, 0),
			fixture("R2", 87, 2.5, 56, -1, 0),
		},
		lockers = {
			fixture("L1", -88.7, 0, -45, 1, 0),
			fixture("L2", 78, 0, -88.7, 0, 1),
			fixture("L3", -30, 0, -33.7, 0, 1),
			fixture("L4", -88.7, 0, 82, 1, 0),
			fixture("L5", 88.7, 0, 74, -1, 0),
			fixture("L6", 30, 0, 33.7, 0, -1),
		},
		obstacles = {
			-- Stasis Barriers in doorways: dropping one forces the Keeper round or through it.
			obstacle("Barrier", "B1", -46, -35, "X", 10),
			obstacle("Barrier", "B2", 46, -35, "X", 10),
			obstacle("Barrier", "B3", -46, 35, "X", 10),
			obstacle("Barrier", "B4", 72, 35, "X", 10),
			obstacle("Barrier", "B5", -30, -62, "Z", 10),
			obstacle("Barrier", "B6", 30, 56, "Z", 10),
			-- Breach Rails: vault windows that turn cover into loops.
			obstacle("Rail", "V1", -55, 1, "Z", 8),
			obstacle("Rail", "V2", 55, -1, "Z", 8),
			obstacle("Rail", "V3", -64, -70, "X", 14),
			obstacle("Rail", "V4", -57, -54, "X", 14),
			obstacle("Rail", "V5", -45, 63, "Z", 8),
			obstacle("Rail", "V6", 70, -62, "Z", 8),
			-- Blast Doors break sight lines between rooms.
			obstacle("Door", "D1", -14, -35, "X", 10),
			obstacle("Door", "D2", 30, -62, "Z", 10),
			obstacle("Door", "D3", -30, 56, "Z", 10),
		},
		anomalySites = {
			Vector3.new(-16, 0, -16),
			Vector3.new(16, 0, 16),
			Vector3.new(-70, 0, 12),
			Vector3.new(70, 0, -6),
		},
		boundsMin = Vector3.new(-90, -5, -90),
		boundsMax = Vector3.new(90, 40, 90),
		floorY = 0,
		boxes = boxes,
		infiltratorSpawns = {
			Vector3.new(-72, 3, 64),
			Vector3.new(-62, 3, 64),
			Vector3.new(-72, 3, 74),
			Vector3.new(-62, 3, 74),
		},
		keeperSpawn = Vector3.new(0, 4, -75),
		terminals = {
			{
				id = "ArchiveTerminal",
				name = "Archive Terminal",
				position = Vector3.new(-62, 2.5, -87),
				facing = Vector3.new(0, 0, 1),
			},
			{
				id = "ReactorTerminal",
				name = "Reactor Terminal",
				position = Vector3.new(87, 2.5, -62),
				facing = Vector3.new(-1, 0, 0),
			},
			{
				id = "ObservatoryTerminal",
				name = "Observatory Terminal",
				position = Vector3.new(62, 2.5, 87),
				facing = Vector3.new(0, 0, -1),
			},
			{
				id = "WestTerminal",
				name = "West Hall Terminal",
				position = Vector3.new(-87, 2.5, -10),
				facing = Vector3.new(1, 0, 0),
			},
			{
				id = "EastTerminal",
				name = "East Hall Terminal",
				position = Vector3.new(87, 2.5, 14),
				facing = Vector3.new(-1, 0, 0),
			},
		},
		extractionCenter = Vector3.new(0, 5, 81),
		extractionSize = Vector3.new(56, 12, 16),
		gate = gate,
		landmarks = {
			{ name = "Archive", position = Vector3.new(-60, 0, -62) },
			{ name = "Sanctum", position = Vector3.new(0, 0, -62) },
			{ name = "Reactor", position = Vector3.new(60, 0, -62) },
			{ name = "Atrium", position = Vector3.new(0, 0, 0) },
			{ name = "Spawn Bay", position = Vector3.new(-60, 0, 62) },
			{ name = "Dock", position = Vector3.new(0, 0, 55) },
			{ name = "Observatory", position = Vector3.new(60, 0, 62) },
		},
	}
end

local function buildLobby(): LobbyDefinition
	local center = Vector3.new(0, 0, 320)
	local boxes: { Box } = {}
	table.insert(
		boxes,
		box("LobbyFloor", "Floor", center + Vector3.new(0, -1, 0), Vector3.new(84, 2, 84), "Floor", "Slate")
	)
	local function lobbyWall(name: string, offset: Vector3, size: Vector3)
		table.insert(boxes, box(name, "Wall", center + offset, size, "Wall", "SmoothPlastic"))
	end
	lobbyWall("LobbyWall_N", Vector3.new(0, 8, -42), Vector3.new(86, 16, 2))
	lobbyWall("LobbyWall_S", Vector3.new(0, 8, 42), Vector3.new(86, 16, 2))
	lobbyWall("LobbyWall_W", Vector3.new(-42, 8, 0), Vector3.new(2, 16, 86))
	lobbyWall("LobbyWall_E", Vector3.new(42, 8, 0), Vector3.new(2, 16, 86))
	table.insert(
		boxes,
		box(
			"LobbyRing",
			"Decor",
			center + Vector3.new(0, 0.05, 0),
			Vector3.new(30, 0.1, 30),
			"FloorAccent",
			"Neon",
			false
		)
	)
	table.insert(
		boxes,
		box("LobbyPedestal", "Platform", center + Vector3.new(0, 0.5, -20), Vector3.new(12, 1, 6), "Cover", "Metal")
	)
	table.insert(
		boxes,
		box(
			"LobbyHoloPillar",
			"Decor",
			center + Vector3.new(0, 6, -20),
			Vector3.new(1, 10, 1),
			"TrimCyan",
			"Neon",
			false
		)
	)
	return {
		center = center,
		spawn = center + Vector3.new(0, 3, 12),
		boxes = boxes,
	}
end

MapLayout.Vault = buildVault()
-- Authored alternatives share the perimeter and sealed extraction contract, with distinct routes.
-- A loop "jungle gym": two walls meeting at a corner, a rail window in one wall and a barrier slot
-- between the other wall and a pillar. `turns` rotates the module by 90° steps around its centre.
local function gym(boxes: { Box }, obstacles: { Obstacle }, id: string, cx: number, cz: number, turns: number)
	local function rotate(x: number, z: number): (number, number)
		for _ = 1, turns % 4 do
			x, z = -z, x
		end
		return cx + x, cz + z
	end
	local function axisOf(axis: string): string
		return if turns % 2 == 0 then axis elseif axis == "X" then "Z" else "X"
	end
	local function wall(name: string, x: number, z: number, sx: number, sz: number)
		local wx, wz = rotate(x, z)
		local size = if turns % 2 == 0 then Vector3.new(sx, 9, sz) else Vector3.new(sz, 9, sx)
		table.insert(boxes, box(`{id}_{name}`, "Cover", Vector3.new(wx, 4.5, wz), size, "Cover", "Metal"))
	end
	wall("WallA1", -4, -6, 4, 1.5)
	wall("WallA2", 4, -6, 4, 1.5)
	wall("WallB", 6, 0, 1.5, 12)
	wall("Pillar", -2, 6, 2, 2)
	local rx, rz = rotate(0, -6)
	table.insert(obstacles, obstacle("Rail", `{id}V`, rx, rz, axisOf("X"), 4))
	local bx, bz = rotate(2.1, 6)
	table.insert(obstacles, obstacle("Barrier", `{id}B`, bx, bz, axisOf("X"), 6.2))
end

export type AlternativeExtras = {
	pods: { Fixture },
	lockers: { Fixture },
	gyms: { { number } }, -- { x, z, turns }
	fifthTerminal: string,
	westTerminal: string,
}

local function buildAlternative(
	id: string,
	name: string,
	structures: { { any } },
	extras: AlternativeExtras
): MapDefinition
	local original = MapLayout.Vault
	local boxes: { Box } = {
		box("Floor", "Floor", Vector3.new(0, -1, 0), Vector3.new(184, 2, 184), "Floor", "Slate"),
	}
	wallX(boxes, "OuterNorth", -91, -92, 92, {})
	wallX(boxes, "OuterSouth", 91, -92, 92, {})
	wallZ(boxes, "OuterWest", -91, -90, 90, {})
	wallZ(boxes, "OuterEast", 91, -90, 90, {})
	wallX(boxes, "DockSeal", 70, -90, 90, { { center = 0, width = 14 } })
	for _, entry in structures do
		cover(boxes, entry[1], entry[2], entry[3], entry[4], entry[5], entry[6], entry[7])
	end
	local obstacles: { Obstacle } = {}
	for index, entry in extras.gyms do
		gym(boxes, obstacles, `G{index}`, entry[1], entry[2], entry[3])
	end
	for _, x in { -32, 32 } do
		table.insert(
			boxes,
			box("RouteLight", "Trim", Vector3.new(x, 0.08, 0), Vector3.new(0.5, 0.16, 130), "TrimCyan", "Neon", false)
		)
	end
	local map: MapDefinition = table.clone(original)
	map.name = name
	map.boxes = boxes
	map.infiltratorSpawns =
		{ Vector3.new(-76, 3, 50), Vector3.new(-66, 3, 50), Vector3.new(-76, 3, 60), Vector3.new(-66, 3, 60) }
	map.extractionSize = Vector3.new(24, 12, 16)
	map.pods = extras.pods
	map.lockers = extras.lockers
	map.obstacles = obstacles
	map.relays = { fixture("R1", -87, 2.5, 30, 1, 0), fixture("R2", 87, 2.5, 30, -1, 0) }
	map.terminals = {
		{
			id = "ArchiveTerminal",
			name = if id == "Metropolis"
				then "Transit Relay"
				elseif id == "Laboratory" then "Genome Archive"
				else "Past Anchor",
			position = Vector3.new(-62, 2.5, -87),
			facing = Vector3.new(0, 0, 1),
		},
		{
			id = "ReactorTerminal",
			name = if id == "Metropolis"
				then "Grid Relay"
				elseif id == "Laboratory" then "Containment Console"
				else "Future Anchor",
			position = Vector3.new(87, 2.5, -62),
			facing = Vector3.new(-1, 0, 0),
		},
		{
			id = "ObservatoryTerminal",
			name = if id == "Metropolis"
				then "Skyline Uplink"
				elseif id == "Laboratory" then "Research Backup"
				else "Present Anchor",
			position = Vector3.new(72, 2.5, 56),
			facing = Vector3.new(-1, 0, 0),
		},
		{
			id = "WestTerminal",
			name = extras.westTerminal,
			position = Vector3.new(-87, 2.5, -5),
			facing = Vector3.new(1, 0, 0),
		},
		{
			id = "EastTerminal",
			name = extras.fifthTerminal,
			position = Vector3.new(20, 2.5, 68),
			facing = Vector3.new(0, 0, -1),
		},
	}
	map.landmarks = {
		{ name = "West Wing", position = Vector3.new(-60, 0, -50) },
		{ name = "Core", position = Vector3.new(0, 0, 0) },
		{ name = "East Wing", position = Vector3.new(60, 0, -50) },
		{ name = "Breach Dock", position = Vector3.new(0, 0, 55) },
	}
	return map
end

MapLayout.Maps = {
	Vault = MapLayout.Vault,
	Metropolis = buildAlternative("Metropolis", "Fractured Metropolis", {
		{ "WestTower", -55, -40, 24, 28, 28, "Wall" },
		{ "EastTower", 55, -28, 24, 32, 28, "Wall" },
		{ "TransitHub", 0, -42, 24, 12, 12, "Cover" },
		{ "MarketWest", -55, 22, 24, 10, 22, "Shelf" },
		{ "MarketEast", 55, 24, 24, 10, 22, "Shelf" },
		{ "Tram", 0, 16, 10, 8, 22, "Pillar" },
		{ "TaxiWest", -22, -8, 6, 4, 10 },
		{ "TaxiEast", 24, 44, 6, 4, 10 },
	}, {
		pods = {
			fixture("P1", -30, 0, -60, 1, 0),
			fixture("P2", 30, 0, -2, -1, 0),
			fixture("P3", -30, 0, 45, 1, 0),
			fixture("P4", 78, 0, -70, -1, 0),
		},
		lockers = {
			fixture("L1", -88.7, 0, -10, 1, 0),
			fixture("L2", 88.7, 0, 10, -1, 0),
			fixture("L3", 0, 0, -34.7, 0, 1),
			fixture("L4", -55, 0, 9.7, 0, -1),
		},
		gyms = { { 25, -70, 0 }, { -30, 15, 1 }, { 45, 58, 2 } },
		westTerminal = "Overpass Relay",
		fifthTerminal = "Harbor Uplink",
	}),
	Laboratory = buildAlternative("Laboratory", "The Forgotten Laboratory", {
		{ "WestResearchWing", -38, -20, 2, 18, 68, "Wall" },
		{ "EastResearchWing", 38, -20, 2, 18, 68, "Wall" },
		{ "ContainmentTank", 0, -6, 16, 18, 16, "Danger" },
		{ "WestSpecimens", -65, -32, 10, 10, 18, "Shelf" },
		{ "EastSpecimens", 65, -28, 10, 10, 18, "Shelf" },
		{ "WestBench", -60, 28, 18, 4, 6 },
		{ "EastBench", 60, 28, 18, 4, 6 },
		{ "ControlDesk", 0, -48, 18, 4, 6 },
		{ "IsolationScreen", 0, 40, 18, 9, 2 },
	}, {
		pods = {
			fixture("P1", -20, 0, -70, 1, 0),
			fixture("P2", 20, 0, 20, 1, 0),
			fixture("P3", -75, 0, 0, 1, 0),
			fixture("P4", 55, 0, -75, -1, 0),
		},
		lockers = {
			fixture("L1", -34.7, 0, -40, 1, 0),
			fixture("L2", 34.7, 0, -40, -1, 0),
			fixture("L3", -88.7, 0, -60, 1, 0),
			fixture("L4", 88.7, 0, 10, -1, 0),
		},
		gyms = { { -20, -25, 3 }, { 20, -30, 1 }, { 55, 50, 2 } },
		westTerminal = "Cryo Ledger",
		fifthTerminal = "Quarantine Console",
	}),
	Nexus = buildAlternative("Nexus", "Temporal Nexus", {
		{ "FracturedCore", 0, 0, 18, 24, 18, "Danger" },
		{ "PastPylon", -44, -38, 10, 20, 10, "Pillar" },
		{ "FuturePylon", 44, -38, 10, 20, 10, "Pillar" },
		{ "EchoPylon", -44, 38, 10, 20, 10, "Pillar" },
		{ "PresentPylon", 44, 38, 10, 20, 10, "Pillar" },
		{ "WestFracture", -58, 0, 24, 8, 2, "Cover" },
		{ "EastFracture", 58, 0, 24, 8, 2, "Cover" },
		{ "NorthFracture", 0, -50, 20, 8, 2, "Cover" },
		{ "SouthFracture", 0, 50, 20, 8, 2, "Cover" },
	}, {
		pods = {
			fixture("P1", -25, 0, -25, 1, 0),
			fixture("P2", 25, 0, 25, -1, 0),
			fixture("P3", -70, 0, -50, 1, 0),
			fixture("P4", 70, 0, -20, -1, 0),
		},
		lockers = {
			fixture("L1", 0, 0, -47.7, 0, 1),
			fixture("L2", 0, 0, 47.7, 0, -1),
			fixture("L3", -88.7, 0, 30, 1, 0),
			fixture("L4", 88.7, 0, 40, -1, 0),
		},
		gyms = { { -25, 25, 0 }, { 25, -25, 2 }, { -60, -20, 1 } },
		westTerminal = "Echo Anchor",
		fifthTerminal = "Paradox Anchor",
	}),
} :: { [string]: MapDefinition }

MapLayout.Lobby = buildLobby()
MapLayout.WALL_HEIGHT = WALL_HEIGHT
MapLayout.POD_SIZE = Vector3.new(5, 8, 5)
MapLayout.LOCKER_SIZE = Vector3.new(3.4, 7.5, 2.6)
MapLayout.OBSTACLE_HEIGHT = 3.2 -- rails and dropped barriers: above a hop, below a vault
MapLayout.OBSTACLE_THICKNESS = 1.2

return MapLayout
