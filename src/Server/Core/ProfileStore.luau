--!strict
-- Session-locked profile persistence over a DataStore-like adapter (UpdateAsync only).
--
-- Record layout stored under "<prefix><userId>":
--   { Data = <Profile>, Lock = { JobId = string, Time = number }? }
--
-- * load: acquires the session lock atomically inside UpdateAsync. If another live server holds a
--   fresh lock, waits with bounded backoff; a lock older than `lockTimeout` is considered stale (that
--   server crashed) and is taken over. Returns "Loaded", "Locked", "Error", or "FutureVersion".
-- * save: writes only while this server still owns the lock ("LockLost" otherwise, never clobbering
--   another server's data). `release = true` clears the lock.
-- * Transient adapter errors are retried with exponential backoff, bounded by `maxAttempts`.
-- No method ever logs profile contents.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

local ProfileSchema = require(script.Parent.ProfileSchema)

export type Adapter = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
}

export type Options = {
	adapter: Adapter,
	jobId: string,
	now: () -> number,
	sleep: (seconds: number) -> (),
	keyPrefix: string?,
	maxAttempts: number?,
	baseBackoff: number?,
	maxBackoff: number?,
	lockTimeout: number?,
	log: ((message: string) -> ())?,
}

export type LoadStatus = "Loaded" | "Locked" | "Error" | "FutureVersion"
export type SaveStatus = "Saved" | "LockLost" | "Error"

export type ProfileStore = {
	keyFor: (self: ProfileStore, userId: number) -> string,
	load: (self: ProfileStore, userId: number) -> (LoadStatus, ProfileSchema.Profile?, string?),
	save: (
		self: ProfileStore,
		userId: number,
		profile: ProfileSchema.Profile,
		release: boolean,
		token: string?
	) -> SaveStatus,
	release: (self: ProfileStore, userId: number, token: string?) -> SaveStatus,
}

local ProfileStore = {}

function ProfileStore.new(options: Options): ProfileStore
	local adapter = options.adapter
	local prefix = options.keyPrefix or "Player_"
	local maxAttempts = options.maxAttempts or 5
	local baseBackoff = options.baseBackoff or 1
	local maxBackoff = options.maxBackoff or 8
	local lockTimeout = options.lockTimeout or 1800
	local log = options.log or function(_message: string) end

	local self = {} :: any
	local serial = 0
	local tokens: { [number]: string } = {}

	local function backoff(attempt: number)
		options.sleep(math.min(maxBackoff, baseBackoff * 2 ^ (attempt - 1)))
	end

	function self:keyFor(userId: number): string
		return prefix .. tostring(userId)
	end

	function self:load(userId: number): (LoadStatus, ProfileSchema.Profile?, string?)
		serial += 1
		local token = `{options.jobId}:{serial}`
		local key = self:keyFor(userId)
		local lastIssue: LoadStatus = "Error"
		for attempt = 1, maxAttempts do
			local lockedElsewhere = false
			local loadedData: any = nil
			local ok, err = pcall(function()
				adapter:UpdateAsync(key, function(record: any): any
					lockedElsewhere = false
					loadedData = nil
					local now = options.now()
					if type(record) == "table" and type(record.Lock) == "table" then
						local lock = record.Lock
						local fresh = type(lock.Time) == "number" and now - lock.Time < lockTimeout
						if (lock.JobId ~= options.jobId or lock.Token ~= token) and fresh then
							lockedElsewhere = true
							return nil -- cancel the write; another server owns this session
						end
					end
					local newRecord = if type(record) == "table" then record else {}
					newRecord.Lock = { JobId = options.jobId, Token = token, Time = now }
					loadedData = newRecord.Data
					return newRecord
				end)
			end)
			if not ok then
				lastIssue = "Error"
				log(`[ProfileStore] load attempt {attempt} for {key} failed: {err}`)
				if attempt < maxAttempts then
					backoff(attempt)
				end
			elseif lockedElsewhere then
				lastIssue = "Locked"
				log(`[ProfileStore] {key} is session-locked by another server (attempt {attempt})`)
				if attempt < maxAttempts then
					backoff(attempt)
				end
			else
				tokens[userId] = token
				local profile, status = ProfileSchema.migrate(TableUtil.deepCopy(loadedData))
				if status == "FutureVersion" then
					self:release(userId, token)
					return "FutureVersion", nil, nil
				end
				return "Loaded", profile, token
			end
		end
		-- Distinguish "still locked" from transient errors for the caller's messaging.
		return lastIssue, nil, nil
	end

	local function write(
		userId: number,
		profile: ProfileSchema.Profile?,
		release: boolean,
		sessionToken: string?
	): SaveStatus
		local expectedToken = sessionToken or tokens[userId]
		local key = self:keyFor(userId)
		for attempt = 1, maxAttempts do
			local lockLost = false
			local ok, err = pcall(function()
				adapter:UpdateAsync(key, function(record: any): any
					lockLost = false
					local lock = if type(record) == "table" and type(record.Lock) == "table" then record.Lock else nil
					-- Foreign lock: another server owns the session. Missing lock on a normal save: we
					-- already released it (e.g. an autosave landing after the leave-save), so writing
					-- would silently re-lock a profile whose player has gone.
					if
						(lock ~= nil and (lock.JobId ~= options.jobId or lock.Token ~= expectedToken))
						or (lock == nil and profile ~= nil)
					then
						lockLost = true
						return nil
					end
					local newRecord = if type(record) == "table" then record else {}
					if profile ~= nil then
						newRecord.Data = TableUtil.deepCopy(profile)
					end
					if release then
						newRecord.Lock = nil
					else
						newRecord.Lock = { JobId = options.jobId, Token = expectedToken, Time = options.now() }
					end
					return newRecord
				end)
			end)
			if not ok then
				log(`[ProfileStore] save attempt {attempt} for {key} failed: {err}`)
				if attempt < maxAttempts then
					backoff(attempt)
				end
			elseif lockLost then
				log(`[ProfileStore] refusing to save {key}: session lock owned by another server`)
				return "LockLost"
			else
				if release and tokens[userId] == expectedToken then
					tokens[userId] = nil
				end
				return "Saved"
			end
		end
		return "Error"
	end

	function self:save(userId: number, profile: ProfileSchema.Profile, release: boolean, token: string?): SaveStatus
		return write(userId, profile, release, token)
	end

	function self:release(userId: number, token: string?): SaveStatus
		return write(userId, nil, true, token)
	end

	return self :: ProfileStore
end

return ProfileStore
