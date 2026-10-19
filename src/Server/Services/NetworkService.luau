--!strict
-- NetworkService: creates every remote from the shared registry (RemoteNames.Specs) and is the only
-- place client->server events are received. Each handler is wrapped with per-player/per-action rate
-- limiting, an error boundary, and violation reporting. Handlers must still validate their payloads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local RateLimiter = require(script.Parent.Parent.Core.RateLimiter)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

type Handler = (player: Player, ...any) -> ()

local NetworkService = {}

local remotes: { [string]: RemoteEvent } = {}
local limiter = RateLimiter.new(ServerConfig.RateLimits :: any)
local security: any = nil
local initialized = false

local function now(): number
	return os.clock()
end

function NetworkService.Init(deps: { [string]: any })
	assert(not initialized, "NetworkService initialised twice")
	initialized = true
	security = deps.SecurityService

	local existing = ReplicatedStorage:FindFirstChild(RemoteNames.FolderName)
	if existing then
		-- Never trust a pre-existing folder (could come from a stale place file); rebuild it.
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = RemoteNames.FolderName
	for _, spec in RemoteNames.Specs do
		local remote = Instance.new(spec.Kind) :: any
		remote.Name = spec.Name
		remote.Parent = folder
		remotes[spec.Name] = remote
	end
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		limiter:removePlayer(player.UserId)
	end)
end

function NetworkService.Get(name: string): RemoteEvent
	local remote = remotes[name]
	assert(remote, `NetworkService: unknown remote {name}`)
	return remote
end

-- Registers the single handler for a client->server remote. `rateKey` defaults to the remote name.
function NetworkService.OnRequest(name: string, handler: Handler, rateKey: string?)
	local remote = NetworkService.Get(name)
	local key = rateKey or name
	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:allow(player.UserId, key, now()) then
			security.Report(player, "RateLimited", name)
			if limiter:allow(player.UserId, "RateNotice", now()) then
				NetworkService.Reject(player, name, Protocol.Codes.RateLimited)
			end
			return
		end
		local args = table.pack(...)
		local ok, err = Safe.call(function()
			handler(player, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn(`[NetworkService] handler {name} errored for user {player.UserId}: {err}`)
		end
	end)
end

-- Rate-limit check for non-remote inputs (e.g. ProximityPrompt triggers).
function NetworkService.Allow(player: Player, key: string): boolean
	if limiter:allow(player.UserId, key, now()) then
		return true
	end
	security.Report(player, "RateLimited", key)
	return false
end

function NetworkService.FireClient(name: string, player: Player, payload: any)
	if player.Parent ~= Players then
		return
	end
	NetworkService.Get(name):FireClient(player, payload)
end

function NetworkService.FireAll(name: string, payload: any)
	NetworkService.Get(name):FireAllClients(payload)
end

function NetworkService.FireList(name: string, players: { Player }, payload: any)
	local remote = NetworkService.Get(name)
	for _, player in players do
		if player.Parent == Players then
			remote:FireClient(player, payload)
		end
	end
end

function NetworkService.Reject(player: Player, action: string, code: string)
	NetworkService.FireClient(RemoteNames.ActionResult, player, {
		action = action,
		ok = false,
		code = code,
		message = Protocol.messageFor(code),
	})
end

function NetworkService.Accept(player: Player, action: string, extra: { [string]: any }?)
	local payload: { [string]: any } = { action = action, ok = true, code = Protocol.Codes.Ok }
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	NetworkService.FireClient(RemoteNames.ActionResult, player, payload)
end

function NetworkService.Notify(players: { Player }, kind: string, text: string, severity: string?, duration: number?)
	NetworkService.FireList(RemoteNames.Notify, players, {
		kind = kind,
		text = text,
		severity = severity or "Info",
		duration = duration,
	})
end

return NetworkService
