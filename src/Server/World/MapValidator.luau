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
-- Boxes whose top is at/below this are treated as walkable: match jumps are a small hop
-- (SurvivalConfig.Movement.MatchJumpPower), so anything taller needs a route or a vault.
MapValidator.MAX_STEP_HEIGHT = 2.2
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

function MapValidator.interactionPoint(terminal: MapLayout.TerminalSpec | MapLayout.Fixture): Vector3
	local p = terminal.position + terminal.facing * MapValidator.INTERACTION_OFFSET
	return Vector3.new(p.X, 3, p.Z)
end

-- Stasis Pods are solid; this is the box every geometry check uses for them.
function MapValidator.podBox(pod: MapLayout.Fixture): Box
	return {
		name = `StasisPod_{pod.id}`,
		kind = "Cover",
		center = pod.position + Vector3.new(0, MapLayout.POD_SIZE.Y / 2, 0),
		size = MapLayout.POD_SIZE,
		color = "Cover",
		material = "Glass",
		collide = true,
	}
end

function MapValidator.lockerBox(locker: MapLayout.Fixture): Box
	local size = MapLayout.LOCKER_SIZE
	local along = if math.abs(locker.facing.X) > 0.5 then Vector3.new(size.Z, size.Y, size.X) else size
	return {
		name = `PhaseLocker_{locker.id}`,
		kind = "Cover",
		center = locker.position + Vector3.new(0, size.Y / 2, 0),
		size = along,
		color = "Cover",
		material = "Metal",
		collide = true,
	}
end

-- The solid box of a Rail, a dropped Barrier or a closed Door.
function MapValidator.obstacleBox(o: MapLayout.Obstacle): Box
	local height = if o.kind == "Door" then MapLayout.WALL_HEIGHT else MapLayout.OBSTACLE_HEIGHT
	local thick = MapLayout.OBSTACLE_THICKNESS
	return {
		name = `{o.kind}_{o.id}`,
		kind = "Cover",
		center = o.center + Vector3.new(0, height / 2, 0),
		size = if o.axis == "X" then Vector3.new(o.length, height, thick) else Vector3.new(thick, height, o.length),
		color = "Cover",
		material = "Metal",
		collide = true,
	}
end

-- Geometry that is always solid. Rails are solid but vaultable, so they are excluded from walking
-- reachability; doors and barriers are passable by default (open / standing).
local function solidBoxes(map: MapDefinition, includeRails: boolean?): { Box }
	local boxes = table.clone(map.boxes)
	for _, pod in map.pods do
		table.insert(boxes, MapValidator.podBox(pod))
	end
	for _, locker in map.lockers do
		table.insert(boxes, MapValidator.lockerBox(locker))
	end
	if includeRails then
		for _, o in map.obstacles do
			if o.kind == "Rail" then
				table.insert(boxes, MapValidator.obstacleBox(o))
			end
		end
	end
	return boxes
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
	for _, b in solidBoxes(map) do
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
		for _, b in solidBoxes(map, true) do
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

	local pods, relays, lockers = map.pods, map.relays, map.lockers
	if #pods < 4 then
		fail(`only {#pods} stasis pods; 4 required`)
	end
	for _, o in map.obstacles do
		if not inside(o.center, min, max) then
			fail(`obstacle {o.id} outside bounds`)
		end
		if o.axis ~= "X" and o.axis ~= "Z" then
			fail(`obstacle {o.id} has an invalid axis`)
		end
		-- Both landing points of a vault must be open floor.
		if o.kind ~= "Door" then
			local normal = if o.axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
			for _, side in { 1, -1 } do
				checkClear(`obstacle {o.id} landing`, o.center + normal * side * 3.5 + Vector3.new(0, 3, 0))
			end
		end
	end
	for _, list in { pods, relays, lockers } do
		local ids: { [string]: boolean } = {}
		for _, item in list do
			if ids[item.id] then
				fail(`duplicate fixture id {item.id}`)
			end
			ids[item.id] = true
			if not inside(item.position, min, max) then
				fail(`fixture {item.id} outside bounds`)
			end
			checkClear(`fixture {item.id} interaction point`, MapValidator.interactionPoint(item))
		end
	end
	for i, pod in pods do
		for j = i + 1, #pods do
			if (pod.position - pods[j].position).Magnitude < 30 then
				fail(`pods {pod.id} and {pods[j].id} are closer than 30 studs`)
			end
		end
	end

	if #map.anomalySites < 2 then
		fail("fewer than two anomaly sites")
	end
	for i, site in map.anomalySites do
		if not inside(site, min, max) then
			fail(`anomaly site {i} outside bounds`)
		end
		checkClear(`anomaly site {i}`, site + Vector3.new(0, 3, 0))
		for _, terminal in map.terminals do
			if (site - terminal.position).Magnitude < 22 then
				fail(`anomaly site {i} too close to terminal`)
			end
		end
		for _, spawn in map.infiltratorSpawns do
			if (site - spawn).Magnitude < 22 then
				fail(`anomaly site {i} too close to spawn`)
			end
		end
		if (site - map.extractionCenter).Magnitude < 24 or (site - map.keeperSpawn).Magnitude < 22 then
			fail(`anomaly site {i} too close to protected area`)
		end
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
		for i, site in map.anomalySites do
			if not reachable(site) then
				fail(`anomaly site {i} unreachable`)
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
		for _, item in pods do
			if not reachable(MapValidator.interactionPoint(item)) then
				fail(`pod {item.id} is not reachable`)
			end
		end
		for _, item in relays do
			if not reachable(MapValidator.interactionPoint(item)) then
				fail(`relay {item.id} is not reachable`)
			end
		end
		for _, item in lockers do
			if not reachable(MapValidator.interactionPoint(item)) then
				fail(`locker {item.id} is not reachable`)
			end
		end

		local closedGrid = MapValidator.buildGrid(map, false)
		local reachableClosed = closedGrid.reachableFrom(map.infiltratorSpawns[1])
		for i, spawn in map.infiltratorSpawns do
			if not reachableClosed(spawn) then
				fail(`infiltrator spawn {i} inaccessible before extraction`)
			end
		end
		for _, terminal in map.terminals do
			if not reachableClosed(MapValidator.interactionPoint(terminal)) then
				fail(`terminal {terminal.id} inaccessible before extraction`)
			end
		end
		if not reachableClosed(map.keeperSpawn) then
			fail("keeper inaccessible before extraction")
		end
		if reachableClosed(map.extractionCenter) then
			fail("extraction pad is reachable while the gate is closed")
		end
	end

	return errors
end

return table.freeze(MapValidator)
