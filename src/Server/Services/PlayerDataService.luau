--!strict
-- PlayerDataService: profile lifecycle on top of ProfileStore (session-locked DataStore access).
--
-- Policy (docs/DATA_SCHEMA.md):
--   * Profiles load on join. While loading, the player can be in the lobby but owns default data.
--   * If loading fails (locked elsewhere, DataStore errors, or a newer schema), the player keeps
--     playing in an UNSAVED session: defaults are used, nothing is written, and the UI says so.
--   * Dirty profiles autosave periodically; profiles save + release on leave and on shutdown.
--   * In Studio without DataStore API access, an in-memory store is used (clearly logged).
-- Profile contents are never logged and never accepted from clients.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameTypes = require(ReplicatedStorage.Shared.Types.GameTypes)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local MemoryDataStore = require(script.Parent.Parent.Core.MemoryDataStore)
local Progression = require(script.Parent.Parent.Core.Progression)
local ProfileSchema = require(script.Parent.Parent.Core.ProfileSchema)
local ProfileStore = require(script.Parent.Parent.Core.ProfileStore)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

type Profile = ProfileSchema.Profile
type SessionState = "Loading" | "Loaded" | "Unsaved" | "Released"

type Session = {
	profile: Profile,
	token: string?,
	closing: boolean,
	state: SessionState,
	dirty: boolean,
	saving: boolean,
	lastSavedAt: number,
}

local PlayerDataService = {}
PlayerDataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player>

local config = ServerConfig.Persistence
local sessions: { [Player]: Session } = {}
local store: ProfileStore.ProfileStore? = nil
local network: any = nil
local usingMemoryStore = false
local shuttingDown = false

local function log(message: string)
	warn(message)
end

local function createStore(): ProfileStore.ProfileStore
	local adapter: any
	local jobId = if game.JobId ~= "" then game.JobId else `studio-{HttpService:GenerateGUID(false)}`
	local ok, dataStore = pcall(function()
		return DataStoreService:GetDataStore(config.DataStoreName)
	end)
	if ok and RunService:IsStudio() and config.StudioMemoryFallback then
		-- Probe API access in Studio only; live servers always use the real DataStore.
		local probeOk = pcall(function()
			(dataStore :: DataStore):GetAsync("__probe")
		end)
		if not probeOk then
			ok = false
		end
	end
	if ok then
		adapter = dataStore
	elseif RunService:IsStudio() and config.StudioMemoryFallback then
		warn(
			"[PlayerDataService] DataStore API unavailable in Studio; using an in-memory store. Progress will NOT persist."
		)
		usingMemoryStore = true
		adapter = MemoryDataStore.new()
	else
		error(`[PlayerDataService] DataStore unavailable: {dataStore}`)
	end
	return ProfileStore.new({
		adapter = adapter,
		jobId = jobId,
		now = os.time,
		sleep = function(seconds: number)
			task.wait(seconds)
		end,
		keyPrefix = config.KeyPrefix,
		maxAttempts = config.MaxAttempts,
		baseBackoff = config.BaseBackoff,
		maxBackoff = config.MaxBackoff,
		lockTimeout = config.LockTimeout,
		log = log,
	})
end

function PlayerDataService.BuildSnapshot(player: Player): GameTypes.ProfileSnapshot
	local session = sessions[player]
	if not session then
		local defaults = ProfileSchema.defaults()
		return {
			loaded = false,
			persistent = false,
			currency = 0,
			owned = defaults.OwnedItems,
			equipped = defaults.Equipped,
			stats = defaults.Stats :: any,
			settings = defaults.Settings :: any,
		}
	end
	local p = session.profile
	return {
		loaded = session.state ~= "Loading",
		persistent = session.state == "Loaded" and not usingMemoryStore,
		currency = p.ChronosScrap,
		owned = table.clone(p.OwnedItems),
		equipped = table.clone(p.Equipped),
		stats = table.clone(p.Stats :: any),
		settings = table.clone(p.Settings :: any),
		progression = Progression.snapshot(p.Progression, os.time()),
		perks = table.clone(p.Perks),
	}
end

function PlayerDataService.SendSnapshot(player: Player)
	if network then
		network.FireClient(RemoteNames.ProfileSnapshot, player, PlayerDataService.BuildSnapshot(player))
	end
end

local function saveSession(player: Player, release: boolean)
	local session = sessions[player]
	if not session or not store or session.state ~= "Loaded" then
		return
	end
	if session.saving then
		if not release then
			return
		end
		-- Serialise the leave/shutdown save behind an in-flight autosave so the release lands last.
		while session.saving do
			task.wait(0.1)
		end
		if session.state ~= "Loaded" then
			return
		end
	end
	session.saving = true
	session.dirty = false
	local status = (store :: ProfileStore.ProfileStore):save(player.UserId, session.profile, release, session.token)
	session.saving = false
	if status ~= "Saved" then
		session.dirty = true
		warn(`[PlayerDataService] save for user {player.UserId} returned {status}`)
		if status == "LockLost" then
			-- Another server owns this profile now; stop writing to avoid clobbering it.
			session.state = "Unsaved"
			PlayerDataService.SendSnapshot(player)
		end
	end
	if status == "Saved" then
		session.lastSavedAt = os.clock()
		if release then
			session.state = "Released"
		end
	end
end

local function loadProfile(player: Player)
	local session: Session = {
		token = nil,
		closing = false,
		profile = ProfileSchema.defaults(),
		state = "Loading",
		dirty = false,
		saving = false,
		lastSavedAt = os.clock(),
	}
	sessions[player] = session
	PlayerDataService.SendSnapshot(player)

	local status, profile, token = (store :: ProfileStore.ProfileStore):load(player.UserId)
	if player.Parent ~= Players then
		-- Left while loading: release the lock we may have just taken.
		if status == "Loaded" then
			(store :: ProfileStore.ProfileStore):release(player.UserId, token)
		end
		sessions[player] = nil
		return
	end
	if status == "Loaded" and profile then
		session.profile = profile
		session.token = token
		session.state = "Loaded"
	else
		session.state = "Unsaved"
		warn(`[PlayerDataService] profile for user {player.UserId} unavailable ({status}); unsaved session`)
		if network then
			network.Notify(
				{ player },
				"Warning",
				"Your profile couldn't be loaded. You can play, but progress won't be saved this session.",
				"Warning",
				8
			)
		end
	end
	PlayerDataService.SendSnapshot(player)
	PlayerDataService.ProfileLoaded:Fire(player)
end

function PlayerDataService.Init(deps: { [string]: any })
	network = deps.NetworkService
	store = createStore()
end

function PlayerDataService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end)
	for _, player in Players:GetPlayers() do
		if not sessions[player] then
			task.spawn(loadProfile, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			session.closing = true
		end
		if shuttingDown then
			return
		end
		task.spawn(function()
			saveSession(player, true)
			sessions[player] = nil
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(config.AutosaveInterval)
			for player, session in sessions do
				-- Clean sessions still save occasionally to refresh the session lock before it goes stale.
				local lockAging = os.clock() - session.lastSavedAt > config.LockTimeout / 2
				if (session.dirty or lockAging) and session.state == "Loaded" then
					task.spawn(saveSession, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player, session in sessions do
			if session.state == "Loaded" then
				session.closing = true
				pending += 1
				task.spawn(function()
					saveSession(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + config.ShutdownTimeout
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function PlayerDataService.IsUsingMemoryStore(): boolean
	return usingMemoryStore
end

function PlayerDataService.GetState(player: Player): SessionState?
	local session = sessions[player]
	return if session then session.state else nil
end

-- Read-only view; callers must not mutate the returned table. Use Mutate for changes.
function PlayerDataService.GetProfile(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function PlayerDataService.IsPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.state == "Loaded" and not usingMemoryStore
end

-- Applies a server-side mutation and returns (applied, callbackResult). The profile is marked dirty
-- and a fresh snapshot is sent to the owner.
function PlayerDataService.Mutate(player: Player, mutator: (Profile) -> any): (boolean, any)
	local session = sessions[player]
	if not session or session.closing or session.state == "Loading" or session.state == "Released" then
		return false, nil
	end
	local result = mutator(session.profile)
	session.dirty = true
	PlayerDataService.SendSnapshot(player)
	return true, result
end

-- Requests an early save (e.g. after a reward payout) without waiting for autosave.
function PlayerDataService.SaveSoon(player: Player)
	local session = sessions[player]
	if session and session.state == "Loaded" and session.dirty then
		task.spawn(saveSession, player, false)
	end
end

return PlayerDataService
