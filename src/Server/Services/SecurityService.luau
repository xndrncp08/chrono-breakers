--!strict
-- SecurityService: proportionate exploit telemetry. Records rejected/invalid requests per player in
-- a sliding window and logs summaries (user id + violation kinds only — no other personal data).
-- Also runs a light movement sanity check for match participants. By default it never punishes
-- automatically; ServerConfig.Security.KickOnFlood can enable a kick for extreme request floods.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Safe = require(ReplicatedStorage.Shared.Modules.Safe)

local ServerConfig = require(script.Parent.Parent.ServerConfig)

local SecurityService = {}

type Record = { times: { number }, kinds: { [string]: number }, lastSummaryAt: number }

local records: { [Player]: Record } = {}
local config = ServerConfig.Security
local movementSamples: { [Player]: { root: BasePart, position: Vector3, at: number } } = {}
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
	table.insert(record.times, now)
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

local function checkMovement()
	local matchService = deps.MatchService
	local statusService = deps.StatusEffectService
	if not matchService or not statusService then
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and matchService.IsActiveParticipant(player) then
			local sample = movementSamples[player]
			if sample and sample.root == root then
				local dt = now - sample.at
				local horizontal =
					Vector3.new(root.Position.X - sample.position.X, 0, root.Position.Z - sample.position.Z)
				local maxSpeed = statusService.GetMaxSpeed(player)
				local allowed = maxSpeed * dt * config.MovementTolerance + config.MovementSlack
				if horizontal.Magnitude > allowed then
					SecurityService.Report(
						player,
						"Movement",
						string.format("%.1f studs in %.2fs", horizontal.Magnitude, dt)
					)
				end
			end
			movementSamples[player] = { root = root, position = root.Position, at = now }
		else
			movementSamples[player] = nil
		end
	end
end

-- Teleports by the server must reset the movement baseline to avoid false positives.
function SecurityService.ResetMovement(player: Player)
	movementSamples[player] = nil
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
