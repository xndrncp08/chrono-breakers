--!strict
-- Pure map-contract validation. Runs at server start (fail loudly on a broken map) and in tests.
--
-- Map contract (docs/GAME_DESIGN.md, "Map contract"):
--   * Spawns, terminals, extraction, and gate lie inside the playable bounds.
--   * At least `requiredHacks` terminals with unique ids, spaced >= MIN_TERMINAL_SPACING apart.
--   * No spawn point or terminal interaction point is inside solid geometry.
--   * Every terminal, every spawn, and the extraction pad are reachable on foot from the first
--     Infiltrator spawn (grid flood fill, character footprint inflated), with the gate open.
--   * With the gate closed, the extraction pad is NOT reachable (the gate actually gates it).

local MapLayout = require(script.Parent.MapLayout)

type MapDefinition = MapLayout.MapDefinition
type Box = MapLayout.Box

local MapValidator = {}

MapValidator.CELL = 1
MapValidator.CHARACTER_RADIUS = 1.5
MapValidator.MAX_STEP_HEIGHT = 5 -- boxes whose top is at/below this are treated as jumpable
MapValidator.INTERACTION_OFFSET = 4
MapValidator.MIN_TERMINAL_SPACING = 40

local function inside(position: Vector3, min: Vector3, max: Vector3): boolean
	return position.X >= min.X
		and position.X <= max.X
		and position.Y >= min.Y
		and position.Y <= max.Y
		and position.Z >= min.Z
		and position.Z <= max.Z
end

local function pointInBox(point: Vector3, b: Box, inflate: number): boolean
	local half = b.size / 2
	local d = point - b.center
	return math.abs(d.X) <= half.X + inflate and math.abs(d.Y) <= half.Y + inflate and math.abs(d.Z) <= half.Z + inflate
end

-- Solid boxes that block walking (tall enough that a character cannot hop over them).
local function blocksWalking(b: Box, floorY: number, gateOpen: boolean): boolean
	if not b.collide or b.kind == "Floor" or b.kind == "Trim" or b.kind == "Decor" then
		return false
	end
	if b.kind == "Gate" and gateOpen then
		return false
	end
	local top = b.center.Y + b.size.Y / 2
	return top - floorY > MapValidator.MAX_STEP_HEIGHT
end

function MapValidator.interactionPoint(terminal: MapLayout.TerminalSpec): Vector3
	local p = terminal.position + terminal.facing * MapValidator.INTERACTION_OFFSET
	return Vector3.new(p.X, 3, p.Z)
end

export type Grid = {
	isBlocked: (x: number, z: number) -> boolean,
	reachableFrom: (start: Vector3) -> (Vector3) -> boolean,
}

function MapValidator.buildGrid(map: MapDefinition, gateOpen: boolean): Grid
	local cell = MapValidator.CELL
	local minX, maxX = map.boundsMin.X, map.boundsMax.X
	local minZ, maxZ = map.boundsMin.Z, map.boundsMax.Z
	local width = math.floor((maxX - minX) / cell) + 1
	local depth = math.floor((maxZ - minZ) / cell) + 1
	local blocked: { [number]: boolean } = {}

	local boxes: { Box } = {}
	for _, b in map.boxes do
		if blocksWalking(b, map.floorY, gateOpen) then
			table.insert(boxes, b)
		end
	end
	if blocksWalking(map.gate, map.floorY, gateOpen) then
		table.insert(boxes, map.gate)
	end

	local r = MapValidator.CHARACTER_RADIUS
	for _, b in boxes do
		local half = b.size / 2
		local x0 = math.max(0, math.floor((b.center.X - half.X - r - minX) / cell))
		local x1 = math.min(width - 1, math.ceil((b.center.X + half.X + r - minX) / cell))
		local z0 = math.max(0, math.floor((b.center.Z - half.Z - r - minZ) / cell))
		local z1 = math.min(depth - 1, math.ceil((b.center.Z + half.Z + r - minZ) / cell))
		for ix = x0, x1 do
			for iz = z0, z1 do
				local cx = minX + ix * cell
				local cz = minZ + iz * cell
				if math.abs(cx - b.center.X) < half.X + r and math.abs(cz - b.center.Z) < half.Z + r then
					blocked[ix * depth + iz] = true
				end
			end
		end
	end

	local function toCell(p: Vector3): (number, number)
		return math.floor((p.X - minX) / cell + 0.5), math.floor((p.Z - minZ) / cell + 0.5)
	end

	local function isBlockedCell(ix: number, iz: number): boolean
		if ix < 0 or iz < 0 or ix >= width or iz >= depth then
			return true
		end
		return blocked[ix * depth + iz] == true
	end

	local grid = {} :: any
	function grid.isBlocked(x: number, z: number): boolean
		local ix, iz = toCell(Vector3.new(x, 0, z))
		return isBlockedCell(ix, iz)
	end

	function grid.reachableFrom(start: Vector3): (Vector3) -> boolean
		local visited: { [number]: boolean } = {}
		local sx, sz = toCell(start)
		if not isBlockedCell(sx, sz) then
			local queue: { number } = { sx * depth + sz }
			visited[sx * depth + sz] = true
			local head = 1
			while head <= #queue do
				local key = queue[head]
				head += 1
				local ix, iz = key // depth, key % depth
				for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx, nz = ix + offset[1], iz + offset[2]
					local nkey = nx * depth + nz
					if not visited[nkey] and not isBlockedCell(nx, nz) then
						visited[nkey] = true
						table.insert(queue, nkey)
					end
				end
			end
		end
		return function(target: Vector3): boolean
			local tx, tz = toCell(target)
			return visited[tx * depth + tz] == true
		end
	end

	return grid :: Grid
end

-- Returns a list of human-readable problems; empty means the map satisfies the contract.
function MapValidator.validate(map: MapDefinition, requiredHacks: number): { string }
	local errors: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end

	local min, max = map.boundsMin, map.boundsMax
	if #map.infiltratorSpawns == 0 then
		fail("no infiltrator spawns")
	end
	for i, spawn in map.infiltratorSpawns do
		if not inside(spawn, min, max) then
			fail(`infiltrator spawn {i} outside bounds`)
		end
	end
	if not inside(map.keeperSpawn, min, max) then
		fail("keeper spawn outside bounds")
	end
	if not inside(map.extractionCenter, min, max) then
		fail("extraction outside bounds")
	end
	if not inside(map.gate.center, min, max) then
		fail("gate outside bounds")
	end

	if #map.terminals < requiredHacks then
		fail(`only {#map.terminals} terminals; {requiredHacks} required`)
	end
	local seen: { [string]: boolean } = {}
	for i, terminal in map.terminals do
		if seen[terminal.id] then
			fail(`duplicate terminal id {terminal.id}`)
		end
		seen[terminal.id] = true
		if not inside(terminal.position, min, max) then
			fail(`terminal {terminal.id} outside bounds`)
		end
		if math.abs(terminal.facing.Magnitude - 1) > 1e-3 then
			fail(`terminal {terminal.id} facing is not a unit vector`)
		end
		for j = i + 1, #map.terminals do
			local other = map.terminals[j]
			local dx = terminal.position.X - other.position.X
			local dz = terminal.position.Z - other.position.Z
			if math.sqrt(dx * dx + dz * dz) < MapValidator.MIN_TERMINAL_SPACING then
				fail(`terminals {terminal.id} and {other.id} are closer than {MapValidator.MIN_TERMINAL_SPACING} studs`)
			end
		end
	end

	-- Points must not be embedded in solid geometry.
	local function checkClear(label: string, point: Vector3)
		for _, b in map.boxes do
			if b.collide and b.kind ~= "Floor" and b.kind ~= "Platform" and pointInBox(point, b, 0.5) then
				fail(`{label} is inside solid geometry '{b.name}'`)
				return
			end
		end
	end
	for i, spawn in map.infiltratorSpawns do
		checkClear(`infiltrator spawn {i}`, spawn)
	end
	checkClear("keeper spawn", map.keeperSpawn)
	for _, terminal in map.terminals do
		checkClear(`terminal {terminal.id} interaction point`, MapValidator.interactionPoint(terminal))
	end

	-- Reachability with the gate open.
	if #map.infiltratorSpawns > 0 then
		local openGrid = MapValidator.buildGrid(map, true)
		local reachable = openGrid.reachableFrom(map.infiltratorSpawns[1])
		for i, spawn in map.infiltratorSpawns do
			if not reachable(spawn) then
				fail(`infiltrator spawn {i} is not reachable`)
			end
		end
		if not reachable(map.keeperSpawn) then
			fail("keeper spawn is not reachable")
		end
		for _, terminal in map.terminals do
			if not reachable(MapValidator.interactionPoint(terminal)) then
				fail(`terminal {terminal.id} is not reachable`)
			end
		end
		if not reachable(map.extractionCenter) then
			fail("extraction pad is not reachable with the gate open")
		end

		local closedGrid = MapValidator.buildGrid(map, false)
		local reachableClosed = closedGrid.reachableFrom(map.infiltratorSpawns[1])
		if reachableClosed(map.extractionCenter) then
			fail("extraction pad is reachable while the gate is closed")
		end
	end

	return errors
end

return table.freeze(MapValidator)
