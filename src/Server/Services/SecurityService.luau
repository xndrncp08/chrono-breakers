--!strict
-- SecurityService: proportionate exploit telemetry. Records rejected/invalid requests per player in
-- a sliding window and logs summaries (user id + violation kinds only — no other personal data).
-- Also runs a light movement sanity check for match participants. By default it never punishes
-- automatically; ServerConfig.Security.KickOnFlood can enable a kick for extreme request floods.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Modules.Safe)

local MovementRules = require(script.Parent.Parent.Core.MovementRules)
local Validate = require(script.Parent.Parent.Core.Validate)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

local SecurityService = {}

type Record = { times: { number }, kinds: { [string]: number }, lastSummaryAt: number }

local records: { [Player]: Record } = {}
local config = ServerConfig.Security
local movementSamples: { [Player]: { root: BasePart, position: Vector3, cframe: CFrame, at: number, speed: number } } =
	{}
local deps: { [string]: any } = {}

local function getRecord(player: Player): Record
	local record = records[player]
	if not record then
		record = { times = {}, kinds = {}, lastSummaryAt = -math.huge }
		records[player] = record
	end
	return record :: Record
end

function SecurityService.Report(player: Player, kind: string, detail: string?)
	local now = os.clock()
	local record = getRecord(player)
	if #record.times < config.FloodKickThreshold then
		table.insert(record.times, now)
	end
	record.kinds[kind] = (record.kinds[kind] or 0) + 1
	while #record.times > 0 and now - record.times[1] > config.ViolationWindow do
		table.remove(record.times, 1)
	end
	local count = #record.times
	if count >= config.ViolationLogThreshold and now - record.lastSummaryAt > config.ViolationWindow then
		record.lastSummaryAt = now
		local parts = {}
		for k, n in record.kinds do
			table.insert(parts, `{k}={n}`)
		end
		warn(
			`[Security] user {player.UserId}: {count} violations in {config.ViolationWindow}s ({table.concat(
				parts,
				", "
			)}); last={detail or kind}`
		)
	end
	if config.KickOnFlood and count >= config.FloodKickThreshold then
		player:Kick("Too many invalid requests.")
	end
end

function SecurityService.GetViolationCount(player: Player): number
	local record = records[player]
	return if record then #record.times else 0
end

function SecurityService.ResetMovement(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		movementSamples[player] = {
			root = root,
			position = root.Position,
			cframe = root.CFrame,
			at = os.clock(),
			speed = deps.StatusEffectService.GetMaxSpeed(player),
		}
	else
		movementSamples[player] = nil
	end
end

-- Also called at gameplay boundaries so a teleport between periodic samples cannot claim objectives.
function SecurityService.ValidatePosition(player: Player): boolean
	local phase = deps.MatchService.GetPhase()
	if (phase ~= "Active" and phase ~= "Extraction") or not deps.MatchService.IsActiveParticipant(player) then
		return true
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local sample = movementSamples[player]
	local map = deps.WorldService.GetMap()
	local t = os.clock()
	local speed = deps.StatusEffectService.GetMaxSpeed(player)
	local valid = Validate.isFiniteVector3(root.Position)
		and MovementRules.valid(
			root.Position,
			root.Position,
			0,
			0,
			map.boundsMin - Vector3.new(3, 4, 3),
			map.boundsMax + Vector3.new(3, 8, 3),
			1,
			0
		)
	if valid and sample and sample.root == root then
		valid = MovementRules.valid(
			sample.position,
			root.Position,
			t - sample.at,
			math.max(speed, sample.speed),
			map.boundsMin - Vector3.new(3, 4, 3),
			map.boundsMax + Vector3.new(3, 8, 3),
			config.MovementTolerance,
			config.MovementSlack
		)
	end
	if not valid then
		SecurityService.Report(player, "Movement", "invalid displacement or vault bounds")
		if sample and sample.root == root and player.Character then
			player.Character:PivotTo(sample.cframe)
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		elseif player.Character then
			player.Character:PivotTo(deps.MatchService.ResolveSpawn(player).cframe)
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			SecurityService.ResetMovement(player)
		end
		return false
	end
	if not sample or sample.root ~= root or t - sample.at >= config.MovementCheckInterval then
		SecurityService.ResetMovement(player)
	end
	return true
end

local function checkMovement()
	for _, player in Players:GetPlayers() do
		if deps.MatchService.IsActiveParticipant(player) then
			SecurityService.ValidatePosition(player)
		else
			movementSamples[player] = nil
		end
	end
end

function SecurityService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		movementSamples[player] = nil
	end)
end

function SecurityService.Start()
	task.spawn(function()
		while true do
			task.wait(config.MovementCheckInterval)
			local ok, err = Safe.call(checkMovement)
			if not ok then
				warn(`[Security] movement check failed: {err}`)
			end
		end
	end)
end

return SecurityService
