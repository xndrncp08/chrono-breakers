--!strict
-- StatusEffectService: owns every player's StatusEffects and their movement baseline. It is the only
-- code that writes Humanoid.WalkSpeed / JumpPower. Movement is recomputed from the role baseline on
-- every change, so overlapping or expiring effects can never compound or leave a stale value.
-- Effects are cleared on death, character replacement, match end, and departure.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local RoleConfig = require(ReplicatedStorage.Shared.Config.RoleConfig)

local StatusEffects = require(script.Parent.Parent.Core.StatusEffects)

local StatusEffectService = {}

type Entry = {
	effects: StatusEffects.StatusEffects,
	baseWalk: number,
	baseJump: number,
	lastSentSignature: string,
}

local entries: { [Player]: Entry } = {}
local network: any = nil
local deps: { [string]: any } = {}

local TICK = 0.1

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getEntry(player: Player): Entry
	local entry = entries[player]
	if not entry then
		entry = {
			effects = StatusEffects.new(),
			baseWalk = RoleConfig.Lobby.WalkSpeed,
			baseJump = RoleConfig.Lobby.JumpPower,
			lastSentSignature = "",
		}
		entries[player] = entry
	end
	return entry :: Entry
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function apply(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	local t = now()
	local movement = entry.effects:compute(entry.baseWalk, entry.baseJump, t)
	local humanoid = getHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		humanoid.UseJumpPower = true
		humanoid.WalkSpeed = movement.walkSpeed
		humanoid.JumpPower = movement.jumpPower
	end

	if deps.CharacterService then
		deps.CharacterService.SetCloaked(player, entry.effects:has("Cloaked", t))
	end
	local list = {}
	for _, effect in entry.effects:list() do
		if t < effect.expiresAt then
			table.insert(list, { kind = effect.kind, expiresAt = effect.expiresAt, source = effect.source })
		end
	end
	local signature = table.concat({
		tostring(movement.slowed),
		tostring(movement.stunned),
		tostring(movement.rooted),
		tostring(movement.hasted),
		tostring(movement.slowImmune),
		tostring(movement.invulnerable),
		table.concat(
			(function(): { string }
				local keys = {}
				for _, effect in list do
					table.insert(keys, `{effect.kind}:{effect.source}`)
				end
				return keys
			end)(),
			","
		),
	}, "|")
	if signature ~= entry.lastSentSignature and network then
		entry.lastSentSignature = signature
		network.FireClient(RemoteNames.StatusUpdate, player, {
			kind = "Movement",
			slowed = movement.slowed,
			stunned = movement.stunned,
			rooted = movement.rooted,
			hasted = movement.hasted,
			slowImmune = movement.slowImmune,
			invulnerable = movement.invulnerable,
			effects = list,
		})
	end
end

function StatusEffectService.Init(injected: { [string]: any })
	deps = injected
	network = deps.NetworkService
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
	end)
end

function StatusEffectService.Start()
	task.spawn(function()
		while true do
			task.wait(TICK)
			local t = now()
			for player, entry in entries do
				if entry.effects:prune(t) then
					apply(player)
				end
			end
		end
	end)
end

-- Sets the movement baseline from a role ("TimeKeeper" | "Infiltrator") or the lobby defaults.
function StatusEffectService.SetBaseline(player: Player, roleId: string?)
	local entry = getEntry(player)
	local role = if roleId then RoleConfig.get(roleId) else nil
	if role then
		local class = if roleId == "Infiltrator" then ClassConfig.get(deps.MatchService.GetMatchClass(player)) else nil
		entry.baseWalk = if class then class.WalkSpeed else role.WalkSpeed
		entry.baseJump = role.JumpPower
	else
		entry.baseWalk = RoleConfig.Lobby.WalkSpeed
		entry.baseJump = RoleConfig.Lobby.JumpPower
	end
	apply(player)
end

export type ApplyParams = {
	key: string,
	kind: StatusEffects.EffectKind,
	magnitude: number,
	duration: number,
	source: string,
}

function StatusEffectService.Apply(player: Player, params: ApplyParams)
	if player.Parent ~= Players then
		return
	end
	local entry = getEntry(player)
	entry.effects:add({
		key = params.key,
		kind = params.kind,
		magnitude = params.magnitude,
		expiresAt = now() + math.max(0, params.duration),
		source = params.source,
	})
	apply(player)
end

function StatusEffectService.Remove(player: Player, key: string)
	local entry = entries[player]
	if entry and entry.effects:remove(key) then
		apply(player)
	end
end

function StatusEffectService.RemoveKeyFromAll(key: string)
	for player, entry in entries do
		if entry.effects:remove(key) then
			apply(player)
		end
	end
end

function StatusEffectService.Cleanse(player: Player, kinds: { StatusEffects.EffectKind }): number
	local entry = entries[player]
	if not entry then
		return 0
	end
	local removed = entry.effects:removeKinds(kinds)
	if removed > 0 then
		apply(player)
	end
	return removed
end

function StatusEffectService.ClearAll(player: Player)
	local entry = entries[player]
	if entry then
		entry.effects:clear()
		apply(player)
	end
end

function StatusEffectService.Has(player: Player, kind: StatusEffects.EffectKind): boolean
	local entry = entries[player]
	return entry ~= nil and entry.effects:has(kind, now())
end

function StatusEffectService.IsRestrained(player: Player): boolean
	local entry = entries[player]
	if not entry then
		return false
	end
	local movement = entry.effects:compute(entry.baseWalk, entry.baseJump, now())
	return movement.stunned or movement.rooted
end

function StatusEffectService.IsInvulnerable(player: Player): boolean
	return StatusEffectService.Has(player, "Invulnerable")
end

-- Expected maximum horizontal speed (used by movement sanity checks).
function StatusEffectService.GetMaxSpeed(player: Player): number
	local entry = getEntry(player)
	local movement = entry.effects:compute(entry.baseWalk, entry.baseJump, now())
	return movement.walkSpeed
end

-- Re-applies the computed movement to a freshly spawned character.
function StatusEffectService.Reapply(player: Player)
	apply(player)
end

function StatusEffectService.CountEffects(): number
	local n = 0
	for _, entry in entries do
		n += entry.effects:count()
	end
	return n
end

return StatusEffectService
