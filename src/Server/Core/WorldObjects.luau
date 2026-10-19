--!strict
-- WorldObjects: per-match state of the chase furniture (pure).
--   * Breach Rails: vaultable by both roles. Infiltrator vaults of the same rail are counted in a
--     sliding window; FatigueVaults inside FatigueWindow seal the rail for Infiltrators for
--     FatigueSeal seconds, which ends infinite loops without removing short ones.
--   * Stasis Barriers: Standing -> Dropped (Infiltrator) -> Broken (Keeper). Only dropped barriers
--     can be vaulted, and only by Infiltrators.
--   * Blast Doors: toggled by anyone with a short per-door cooldown.
--   * Phase Lockers: at most one occupant; one locker per player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

export type Spec = { id: string, kind: string }

export type WorldObjects = {
	kinds: { [string]: string },
	barriers: { [string]: string },
	doors: { [string]: boolean },
	lockers: { [string]: number },
	canVault: (self: WorldObjects, id: string, isKeeper: boolean, now: number) -> (boolean, string),
	recordVault: (self: WorldObjects, id: string, isKeeper: boolean, now: number) -> boolean,
	sealedUntil: (self: WorldObjects, id: string) -> number,
	dropBarrier: (self: WorldObjects, id: string) -> boolean,
	breakBarrier: (self: WorldObjects, id: string) -> boolean,
	toggleDoor: (self: WorldObjects, id: string, now: number) -> (boolean, boolean?),
	enterLocker: (self: WorldObjects, id: string, userId: number) -> (boolean, string),
	leaveLocker: (self: WorldObjects, userId: number) -> string?,
	lockerOf: (self: WorldObjects, userId: number) -> string?,
}

local WorldObjects = {}
local config = SurvivalConfig.World

function WorldObjects.new(obstacles: { Spec }, lockerIds: { string }): WorldObjects
	local vaults: { [string]: { number } } = {}
	local sealed: { [string]: number } = {}
	local doorReadyAt: { [string]: number } = {}
	local self = {
		kinds = {} :: { [string]: string },
		barriers = {} :: { [string]: string },
		doors = {} :: { [string]: boolean }, -- true = open
		lockers = {} :: { [string]: number },
	} :: any
	for _, spec in obstacles do
		self.kinds[spec.id] = spec.kind
		if spec.kind == "Barrier" then
			self.barriers[spec.id] = "Standing"
		elseif spec.kind == "Door" then
			self.doors[spec.id] = true
		end
	end
	local lockerSet: { [string]: boolean } = {}
	for _, id in lockerIds do
		lockerSet[id] = true
	end

	function self:sealedUntil(id: string): number
		return sealed[id] or -math.huge
	end

	function self:canVault(id: string, isKeeper: boolean, now: number): (boolean, string)
		local kind = self.kinds[id]
		if kind == "Rail" then
			if not isKeeper and now < self:sealedUntil(id) then
				return false, "Locked"
			end
			return true, "Ok"
		elseif kind == "Barrier" then
			if isKeeper then
				return false, "WrongRole"
			end
			return self.barriers[id] == "Dropped", if self.barriers[id] == "Dropped" then "Ok" else "Locked"
		end
		return false, "UnknownTarget"
	end

	-- Records a completed vault. Returns true when this vault sealed the rail (fatigue).
	function self:recordVault(id: string, isKeeper: boolean, now: number): boolean
		if isKeeper or self.kinds[id] ~= "Rail" then
			return false
		end
		local list = vaults[id] or {}
		vaults[id] = list
		table.insert(list, now)
		while #list > 0 and now - list[1] > config.FatigueWindow do
			table.remove(list, 1)
		end
		if #list >= config.FatigueVaults then
			table.clear(list)
			sealed[id] = now + config.FatigueSeal
			return true
		end
		return false
	end

	function self:dropBarrier(id: string): boolean
		if self.barriers[id] ~= "Standing" then
			return false
		end
		self.barriers[id] = "Dropped"
		return true
	end

	function self:breakBarrier(id: string): boolean
		if self.barriers[id] ~= "Dropped" then
			return false
		end
		self.barriers[id] = "Broken"
		return true
	end

	-- Returns (ok, nowOpen).
	function self:toggleDoor(id: string, now: number): (boolean, boolean?)
		if self.doors[id] == nil or now < (doorReadyAt[id] or -math.huge) then
			return false, nil
		end
		self.doors[id] = not self.doors[id]
		doorReadyAt[id] = now + config.DoorCooldown
		return true, self.doors[id]
	end

	function self:lockerOf(userId: number): string?
		for id, occupant in self.lockers do
			if occupant == userId then
				return id
			end
		end
		return nil
	end

	function self:enterLocker(id: string, userId: number): (boolean, string)
		if not lockerSet[id] then
			return false, "UnknownTarget"
		elseif self.lockers[id] ~= nil then
			return false, "Busy"
		elseif self:lockerOf(userId) ~= nil then
			return false, "AlreadyHacking"
		end
		self.lockers[id] = userId
		return true, "Ok"
	end

	function self:leaveLocker(userId: number): string?
		local id = self:lockerOf(userId)
		if id then
			self.lockers[id] = nil
		end
		return id
	end

	return self :: WorldObjects
end

-- Which side of an obstacle a point is on (+1 / -1) along its thin axis.
function WorldObjects.side(axis: string, center: Vector3, point: Vector3): number
	local delta = if axis == "X" then point.Z - center.Z else point.X - center.X
	return if delta >= 0 then 1 else -1
end

-- Landing point of a vault from `point` across the obstacle (floor level + `height`). The lateral
-- position along the obstacle is kept but clamped inside its length.
function WorldObjects.landing(axis: string, center: Vector3, point: Vector3, height: number, length: number): Vector3
	local side = WorldObjects.side(axis, center, point)
	local offset = -side * config.VaultClearance
	local reach = math.max(0, length / 2 - 0.75)
	if axis == "X" then
		return Vector3.new(
			math.clamp(point.X, center.X - reach, center.X + reach),
			center.Y + height,
			center.Z + offset
		)
	end
	return Vector3.new(center.X + offset, center.Y + height, math.clamp(point.Z, center.Z - reach, center.Z + reach))
end

return table.freeze(WorldObjects)
