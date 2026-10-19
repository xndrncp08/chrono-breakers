--!strict
-- InteractionService: server-authoritative chase furniture (WorldObjects rules + Instances).
--   * Breach Rails / dropped Stasis Barriers: the server moves the vaulter along a short arc while
--     their root is anchored, so a vault can never be extended into a teleport. Rail fatigue seals
--     over-used rails for Infiltrators.
--   * Stasis Barriers: dropping one stuns a Keeper standing in it; the Keeper breaks it with a
--     channel. Blast Doors toggle with a cooldown and never close on a character.
--   * Phase Lockers: hidden players are anchored, invisible and excluded from strikes, scans and
--     chases. The Keeper's Search ejects and Fractures an occupant.
-- Every request is a ProximityPrompt trigger (rate limited) validated for phase, role, condition,
-- restraint, busy state and server-measured range.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

local MapLayout = require(script.Parent.Parent.World.MapLayout)
local WorldObjects = require(script.Parent.Parent.Core.WorldObjects)

local InteractionService = {}

type Busy = { kind: string, token: number }

local deps: { [string]: any } = {}
local objects: WorldObjects.WorldObjects = WorldObjects.new({}, {})
local busy: { [Player]: Busy } = {}
local hidden: { [Player]: string } = {}
local tokenCounter = 0
local config = SurvivalConfig.World

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function classOf(player: Player): ClassConfig.Definition?
	return ClassConfig.get(deps.MatchService.GetMatchClass(player))
end

local function horizontal(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Distance from a point to an obstacle's centre line (perpendicular, clamped to its length).
local function distanceToObstacle(spec: any, point: Vector3): number
	local along = if spec.axis == "X" then point.X - spec.center.X else point.Z - spec.center.Z
	local across = if spec.axis == "X" then point.Z - spec.center.Z else point.X - spec.center.X
	local excess = math.max(0, math.abs(along) - spec.length / 2)
	return math.sqrt(excess * excess + across * across)
end

function InteractionService.IsHidden(player: Player): boolean
	return hidden[player] ~= nil
end

function InteractionService.IsBusy(player: Player): boolean
	return busy[player] ~= nil
end

local function claim(player: Player, kind: string): number
	tokenCounter += 1
	busy[player] = { kind = kind, token = tokenCounter }
	return tokenCounter
end

local function release(player: Player, token: number)
	local current = busy[player]
	if current and current.token == token then
		busy[player] = nil
	end
end

local function reject(player: Player, code: string)
	deps.NetworkService.Reject(player, "Interact", code)
end

-- Common legality: returns nil or a rejection code.
local function actorProblem(player: Player, wantRole: string?): string?
	local phase = deps.MatchService.GetPhase()
	if phase ~= "Active" and phase ~= "Extraction" then
		return Protocol.Codes.WrongPhase
	end
	if not deps.MatchService.IsActiveParticipant(player) then
		return Protocol.Codes.NotParticipant
	end
	local role = deps.MatchService.GetRole(player)
	if wantRole and role ~= wantRole then
		return Protocol.Codes.WrongRole
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not rootOf(player) then
		return Protocol.Codes.NotAlive
	end
	if role == "Infiltrator" and not deps.MatchService.GetDirector():isFree(player.UserId) then
		return Protocol.Codes.NotAlive
	end
	if deps.StatusEffectService.IsRestrained(player) then
		return Protocol.Codes.Restrained
	end
	if busy[player] then
		return Protocol.Codes.Busy
	end
	if deps.MatchService.GetDirector():getHackingTerminal(player.UserId) then
		return Protocol.Codes.AlreadyHacking
	end
	return nil
end

local function channelSlow(player: Player, duration: number)
	deps.StatusEffectService.Apply(player, {
		key = "channel",
		kind = "Slow",
		magnitude = 0.9,
		duration = duration + 0.2,
		source = "Channel",
	})
end

local function effect(payload: { [string]: any })
	deps.NetworkService.FireList(RemoteNames.Effect, deps.MatchService.GetParticipants(), payload)
end

---------------------------------------------------------------------------
-- Vaulting
---------------------------------------------------------------------------

local function performVault(player: Player, handle: any, duration: number, isKeeper: boolean)
	local root = rootOf(player) :: BasePart
	local character = player.Character :: Model
	local spec = handle.spec
	local from = root.Position
	local landing = WorldObjects.landing(spec.axis, spec.center, from, from.Y - spec.center.Y, spec.length)
	local flat = Vector3.new(landing.X - from.X, 0, landing.Z - from.Z)
	local facing = if flat.Magnitude > 1e-3 then flat.Unit else root.CFrame.LookVector
	local token = claim(player, "Vault")
	deps.MatchService.GetDirector():stopAction(player.UserId, "Vaulted", now())
	root.Anchored = true
	character:SetAttribute("Vaulting", duration)
	effect({ kind = "Vault", userId = player.UserId, duration = duration, position = spec.center })
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
		if root.Parent == nil or player.Character ~= character then
			connection:Disconnect()
			release(player, token)
			return
		end
		local position = from:Lerp(landing, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * 1.8, 0)
		character:PivotTo(CFrame.lookAt(position, position + facing))
		if alpha >= 1 then
			connection:Disconnect()
			root.Anchored = false
			root.AssemblyLinearVelocity = facing * 6
			character:SetAttribute("Vaulting", nil)
			deps.SecurityService.ResetMovement(player)
			release(player, token)
			if not isKeeper and deps.PerkService.Has(player, "LandingHaste") then
				deps.StatusEffectService.Apply(player, {
					key = "featherFall",
					kind = "Haste",
					magnitude = 0.3,
					duration = 0.8,
					source = "FeatherFall",
				})
			end
			if objects:recordVault(spec.id, isKeeper, now()) then
				deps.NetworkService.Notify(
					deps.MatchService.GetParticipants(),
					Protocol.NotifyKinds.Toast,
					"A Breach Rail destabilized from overuse!",
					"Warning",
					2
				)
				handle.part:SetAttribute("SealedUntil", objects:sealedUntil(spec.id))
				effect({ kind = "RailSealed", position = spec.center, duration = config.FatigueSeal })
			end
		end
	end)
end

local function requestVault(player: Player, id: string)
	local isKeeper = deps.MatchService.GetRole(player) == "TimeKeeper"
	local problem = actorProblem(player, nil)
	if problem then
		return reject(player, problem)
	end
	local handle = deps.WorldService.GetObstacle(id)
	if not handle or handle.kind == "Door" then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	local ok, code = objects:canVault(id, isKeeper, now())
	if not ok then
		return reject(player, code)
	end
	local root = rootOf(player) :: BasePart
	if
		distanceToObstacle(handle.spec, root.Position) > 3.2
		or math.abs(root.Position.Y - 3 - handle.spec.center.Y) > 4
	then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	local class = if isKeeper then nil else classOf(player)
	local duration = if isKeeper
		then config.KeeperVaultTime
		else config.VaultTime / ((if class then class.VaultSpeed else 1) * deps.PerkService.Value(
			player,
			"VaultSpeed"
		))
	performVault(player, handle, duration, isKeeper)
end

---------------------------------------------------------------------------
-- Barriers and doors
---------------------------------------------------------------------------

local function insideSlab(spec: any, position: Vector3): boolean
	return distanceToObstacle(spec, position) <= config.BarrierStunRadius / 2 and math.abs(position.Y - 3) < 5
end

local function requestDrop(player: Player, id: string)
	local problem = actorProblem(player, "Infiltrator")
	if problem then
		return reject(player, problem)
	end
	local handle = deps.WorldService.GetObstacle(id)
	local root = rootOf(player) :: BasePart
	if not handle or handle.kind ~= "Barrier" then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	if distanceToObstacle(handle.spec, root.Position) > config.InteractRange then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	if not objects:dropBarrier(id) then
		return reject(player, Protocol.Codes.Locked)
	end
	deps.WorldService.SetBarrierState(id, "Dropped")
	local spec = handle.spec
	local normal = if spec.axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	local keeper = deps.MatchService.GetKeeper()
	for _, other in deps.MatchService.GetParticipants() do
		local otherRoot = rootOf(other)
		if otherRoot and other.Character and insideSlab(spec, otherRoot.Position) then
			-- Nobody is left inside the slab: step them out on the side they were already on.
			local side = WorldObjects.side(spec.axis, spec.center, otherRoot.Position)
			local across = MapLayout.OBSTACLE_THICKNESS / 2 + 1.8
			local position = otherRoot.Position
			local target = if spec.axis == "X"
				then Vector3.new(position.X, position.Y, spec.center.Z + side * across)
				else Vector3.new(spec.center.X + side * across, position.Y, position.Z)
			if (target - position).Magnitude < across + 0.5 then
				(other.Character :: Model):PivotTo(CFrame.new(target) * otherRoot.CFrame.Rotation)
				deps.SecurityService.ResetMovement(other)
			end
			if other == keeper then
				local class = classOf(player)
				local stun = config.BarrierStun
					* (if class then class.BarrierStunScale else 1)
					* deps.PerkService.Value(player, "BarrierStun")
				deps.StatusEffectService.Apply(other, {
					key = "barrierStun",
					kind = "Stun",
					magnitude = 1,
					duration = stun,
					source = "StasisBarrier",
				})
				deps.HuntService.OnKeeperStunned(other)
				deps.NetworkService.Notify(
					{ other },
					Protocol.NotifyKinds.Warning,
					"Stunned by a Stasis Barrier!",
					"Danger",
					2
				)
				deps.NetworkService.Notify({ player }, Protocol.NotifyKinds.Toast, "Keeper stunned!", "Success", 2)
				effect({ kind = "KeeperStunned", userId = other.UserId, duration = stun })
			end
		end
	end
	effect({ kind = "BarrierDropped", position = spec.center, normal = normal })
end

local function requestBreak(player: Player, id: string)
	local problem = actorProblem(player, "TimeKeeper")
	if problem then
		return reject(player, problem)
	end
	local handle = deps.WorldService.GetObstacle(id)
	local root = rootOf(player) :: BasePart
	if not handle or handle.kind ~= "Barrier" or objects.barriers[id] ~= "Dropped" then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	if distanceToObstacle(handle.spec, root.Position) > config.InteractRange then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	local token = claim(player, "Break")
	local matchId = deps.MatchService.CurrentMatchId()
	channelSlow(player, config.BarrierBreakTime)
	effect({ kind = "BarrierBreaking", position = handle.spec.center, duration = config.BarrierBreakTime })
	task.delay(config.BarrierBreakTime, function()
		release(player, token)
		local current = rootOf(player)
		if
			not deps.MatchService.IsCurrentMatch(matchId)
			or not current
			or deps.StatusEffectService.IsRestrained(player)
			or not deps.MatchService.IsActiveParticipant(player)
			or distanceToObstacle(handle.spec, current.Position) > config.InteractRange + 1
		then
			deps.StatusEffectService.Remove(player, "channel")
			return reject(player, Protocol.Codes.Restrained)
		end
		if objects:breakBarrier(id) then
			deps.WorldService.SetBarrierState(id, "Broken")
			effect({ kind = "BarrierBroken", position = handle.spec.center })
		end
	end)
end

local function requestDoor(player: Player, id: string)
	local problem = actorProblem(player, nil)
	if problem then
		return reject(player, problem)
	end
	local handle = deps.WorldService.GetObstacle(id)
	local root = rootOf(player) :: BasePart
	if not handle or handle.kind ~= "Door" then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	if distanceToObstacle(handle.spec, root.Position) > config.InteractRange then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	if objects.doors[id] then
		-- Never close a door on someone standing in the frame.
		for _, other in Players:GetPlayers() do
			local otherRoot = rootOf(other)
			if otherRoot and distanceToObstacle(handle.spec, otherRoot.Position) < 1.6 then
				return reject(player, Protocol.Codes.Busy)
			end
		end
	end
	local ok, open = objects:toggleDoor(id, now())
	if not ok then
		return reject(player, Protocol.Codes.OnCooldown)
	end
	deps.WorldService.SetDoorOpen(id, open == true)
	effect({ kind = "Door", position = handle.spec.center, open = open })
end

---------------------------------------------------------------------------
-- Lockers
---------------------------------------------------------------------------

local function setHidden(player: Player, lockerId: string?)
	local root = rootOf(player)
	local character = player.Character
	if lockerId then
		hidden[player] = lockerId
	else
		hidden[player] = nil
	end
	if character then
		character:SetAttribute("Hidden", lockerId ~= nil)
	end
	if root then
		root.Anchored = lockerId ~= nil
		root.AssemblyLinearVelocity = Vector3.zero
	end
	deps.StatusEffectService.Reapply(player) -- refreshes cloak visuals
end

local function leave(player: Player, ejected: boolean)
	local lockerId = objects:leaveLocker(player.UserId)
	hidden[player] = nil
	if not lockerId then
		setHidden(player, nil)
		return
	end
	deps.WorldService.SetLockerOccupant(lockerId, nil)
	setHidden(player, nil)
	local locker = deps.WorldService.GetLocker(lockerId)
	if locker and player.Character then
		(player.Character :: Model):PivotTo(locker.exitCFrame)
		deps.SecurityService.ResetMovement(player)
	end
	effect({ kind = if ejected then "LockerEjected" else "LockerLeft", userId = player.UserId })
end

function InteractionService.Unhide(player: Player)
	if hidden[player] then
		leave(player, false)
	end
end

local function requestHide(player: Player, id: string)
	local problem = actorProblem(player, "Infiltrator")
	if problem then
		return reject(player, problem)
	end
	local locker = deps.WorldService.GetLocker(id)
	local root = rootOf(player) :: BasePart
	if not locker then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	if horizontal(root.Position, locker.exitCFrame.Position) > 4.5 then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	if locker.model:GetAttribute("Occupant") ~= nil then
		return reject(player, Protocol.Codes.Busy)
	end
	deps.MatchService.GetDirector():stopAction(player.UserId, "Hiding", now())
	local token = claim(player, "Hide")
	local matchId = deps.MatchService.CurrentMatchId()
	local enterTime = config.LockerEnterTime * deps.PerkService.Value(player, "LockerEnter")
	channelSlow(player, enterTime)
	task.delay(enterTime, function()
		release(player, token)
		if
			not deps.MatchService.IsCurrentMatch(matchId)
			or actorProblem(player, "Infiltrator") ~= nil
			or horizontal((rootOf(player) or root).Position, locker.exitCFrame.Position) > 5
		then
			return
		end
		local ok = objects:enterLocker(id, player.UserId)
		if not ok then
			return reject(player, Protocol.Codes.Busy)
		end
		deps.StatusEffectService.Remove(player, "channel")
		deps.WorldService.SetLockerOccupant(id, player.UserId);
		(player.Character :: Model):PivotTo(locker.holdCFrame)
		setHidden(player, id)
		deps.SecurityService.ResetMovement(player)
		effect({ kind = "LockerEntered", userId = player.UserId, position = locker.position })
	end)
end

local function requestSearch(player: Player, id: string)
	local problem = actorProblem(player, "TimeKeeper")
	if problem then
		return reject(player, problem)
	end
	local locker = deps.WorldService.GetLocker(id)
	local root = rootOf(player) :: BasePart
	if not locker then
		return reject(player, Protocol.Codes.UnknownTarget)
	end
	if horizontal(root.Position, locker.exitCFrame.Position) > 5.5 then
		return reject(player, Protocol.Codes.OutOfRange)
	end
	local token = claim(player, "Search")
	local matchId = deps.MatchService.CurrentMatchId()
	channelSlow(player, config.SearchTime)
	effect({ kind = "LockerSearch", position = locker.position, duration = config.SearchTime })
	task.delay(config.SearchTime, function()
		release(player, token)
		if not deps.MatchService.IsCurrentMatch(matchId) or deps.StatusEffectService.IsRestrained(player) then
			return
		end
		local occupantId = objects.lockers[id]
		local occupant = if occupantId then Players:GetPlayerByUserId(occupantId) else nil
		if not occupant then
			deps.NetworkService.Notify({ player }, Protocol.NotifyKinds.Toast, "Empty.", "Info", 1.5)
			return
		end
		leave(occupant, true)
		deps.StatusEffectService.Apply(occupant, {
			key = "searched",
			kind = "Stun",
			magnitude = 1,
			duration = config.SearchStun,
			source = "Search",
		})
		deps.MatchService.NotifyDamage(occupant)
		deps.MatchService.GetDirector():strike(occupant.UserId, player.UserId, now())
		deps.NetworkService.Notify({ occupant }, Protocol.NotifyKinds.Warning, "Found! Run!", "Danger", 2)
	end)
end

---------------------------------------------------------------------------
-- Binding and lifecycle
---------------------------------------------------------------------------

local function guard(fn: (Player, string) -> (), id: string): (Player) -> ()
	return function(player: Player)
		if not deps.NetworkService.Allow(player, "SurvivalPrompt") then
			return
		end
		if not deps.SecurityService.ValidatePosition(player) then
			return reject(player, Protocol.Codes.OutOfRange)
		end
		fn(player, id)
	end
end

-- Binds prompts for the freshly built world and resets furniture state.
function InteractionService.BindWorld()
	for player in table.clone(hidden) do
		setHidden(player, nil)
	end
	table.clear(busy)
	local specs = {}
	for id, handle in deps.WorldService.GetObstacles() do
		table.insert(specs, { id = id, kind = handle.kind })
		if handle.kind == "Rail" then
			handle.prompts.Vault.Triggered:Connect(guard(requestVault, id))
		elseif handle.kind == "Barrier" then
			handle.prompts.Drop.Triggered:Connect(guard(requestDrop, id))
			handle.prompts.Vault.Triggered:Connect(guard(requestVault, id))
			handle.prompts.Break.Triggered:Connect(guard(requestBreak, id))
		else
			handle.prompts.Toggle.Triggered:Connect(guard(requestDoor, id))
		end
	end
	local lockerIds = {}
	for id, locker in deps.WorldService.GetLockers() do
		table.insert(lockerIds, id)
		locker.prompts.Hide.Triggered:Connect(guard(requestHide, id))
		locker.prompts.Search.Triggered:Connect(guard(requestSearch, id))
		locker.prompts.Leave.Triggered:Connect(function(player: Player)
			if hidden[player] == id and deps.NetworkService.Allow(player, "SurvivalPrompt") then
				leave(player, false)
			end
		end)
	end
	objects = WorldObjects.new(specs, lockerIds)
	deps.WorldService.ResetFurniture()
end

function InteractionService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		if hidden[player] then
			local lockerId = objects:leaveLocker(player.UserId)
			if lockerId then
				deps.WorldService.SetLockerOccupant(lockerId, nil)
			end
			hidden[player] = nil
		end
	end)
end

function InteractionService.Start()
	InteractionService.BindWorld()
	deps.MatchService.GetDirector().events:Connect(function(name: string, payload: any)
		if name == "MatchStarted" then
			InteractionService.BindWorld()
		elseif name == "MatchResolved" or name == "MatchCleanup" then
			for player in table.clone(hidden) do
				leave(player, false)
			end
			table.clear(busy)
		elseif name == "PlayerEliminated" or name == "PlayerExtracted" or name == "ParticipantLeft" then
			local player = Players:GetPlayerByUserId(payload.userId)
			if player and hidden[player] then
				leave(player, false)
			end
		end
	end)
end

return InteractionService
