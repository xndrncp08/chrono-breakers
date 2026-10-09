--!strict
-- Versioned player profile schema: defaults, migrations, and reconciliation (sanitisation).
-- See docs/DATA_SCHEMA.md. Every field has a safe default; anything malformed is replaced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)

export type Settings = {
	SfxVolume: number,
	UiVolume: number,
	MusicVolume: number,
	ReducedMotion: boolean,
	UIScale: number,
	ShowControlHints: boolean,
}

export type Stats = {
	MatchesPlayed: number,
	Wins: number,
	Losses: number,
	TerminalsHacked: number,
	Extractions: number,
	Eliminations: number,
	KeeperMatches: number,
	InfiltratorMatches: number,
}

export type Profile = {
	SchemaVersion: number,
	ChronosScrap: number,
	OwnedItems: { [string]: boolean },
	Equipped: { [string]: string },
	Stats: Stats,
	Settings: Settings,
	RecentMatchIds: { string },
}

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = 2

ProfileSchema.STAT_KEYS = table.freeze({
	"MatchesPlayed",
	"Wins",
	"Losses",
	"TerminalsHacked",
	"Extractions",
	"Eliminations",
	"KeeperMatches",
	"InfiltratorMatches",
})

-- Setting validators: key -> { kind, min, max, default }
ProfileSchema.SETTINGS = table.freeze({
	SfxVolume = table.freeze({ kind = "number", min = 0, max = 1, default = 0.8 }),
	UiVolume = table.freeze({ kind = "number", min = 0, max = 1, default = 0.7 }),
	MusicVolume = table.freeze({ kind = "number", min = 0, max = 1, default = 0.5 }),
	ReducedMotion = table.freeze({ kind = "boolean", default = false }),
	UIScale = table.freeze({ kind = "number", min = 0.8, max = 1.25, default = 1 }),
	ShowControlHints = table.freeze({ kind = "boolean", default = true }),
})

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function ProfileSchema.defaultSettings(): Settings
	local settings = {} :: any
	for key, spec in ProfileSchema.SETTINGS :: any do
		settings[key] = spec.default
	end
	return settings :: Settings
end

function ProfileSchema.defaults(): Profile
	local owned: { [string]: boolean } = {}
	for id, item in ItemConfig.Items :: any do
		if item.DefaultOwned then
			owned[id] = true
		end
	end
	local stats = {} :: any
	for _, key in ProfileSchema.STAT_KEYS do
		stats[key] = 0
	end
	return {
		SchemaVersion = ProfileSchema.CURRENT_VERSION,
		ChronosScrap = 0,
		OwnedItems = owned,
		Equipped = table.clone(ItemConfig.DefaultEquipped :: any),
		Stats = stats :: Stats,
		Settings = ProfileSchema.defaultSettings(),
		RecentMatchIds = {},
	}
end

-- Sanitises one setting value; returns nil when invalid.
function ProfileSchema.sanitizeSetting(key: string, value: any): any
	local spec = (ProfileSchema.SETTINGS :: any)[key]
	if spec == nil then
		return nil
	end
	if spec.kind == "number" then
		if not isFinite(value) then
			return nil
		end
		return math.clamp(value, spec.min, spec.max)
	elseif spec.kind == "boolean" then
		if type(value) ~= "boolean" then
			return nil
		end
		return value
	end
	return nil
end

-- Migrations upgrade a raw table from version N to N+1 in place.
-- v1 (initial prototype schema): { Scrap: number, Volume: number, Items: {string} }
ProfileSchema.MIGRATIONS = table.freeze({
	[1] = function(data: { [string]: any })
		if data.ChronosScrap == nil and isFinite(data.Scrap) then
			data.ChronosScrap = data.Scrap
		end
		data.Scrap = nil
		if type(data.Settings) ~= "table" then
			data.Settings = {}
		end
		if isFinite(data.Volume) and data.Settings.SfxVolume == nil then
			data.Settings.SfxVolume = data.Volume
		end
		data.Volume = nil
		if type(data.Items) == "table" and data.OwnedItems == nil then
			local owned = {}
			for _, id in data.Items do
				if type(id) == "string" then
					owned[id] = true
				end
			end
			data.OwnedItems = owned
		end
		data.Items = nil
		data.SchemaVersion = 2
	end,
} :: { [number]: (data: { [string]: any }) -> () })

-- Returns (profile, status) where status is "Ok", "New", or "FutureVersion".
-- On "FutureVersion" the returned profile must NOT be saved (a newer server owns the format).
function ProfileSchema.migrate(raw: any): (Profile, string)
	if type(raw) ~= "table" then
		return ProfileSchema.defaults(), "New"
	end
	local data = raw :: { [string]: any }
	local version = if isFinite(data.SchemaVersion) then math.floor(data.SchemaVersion) else 1
	if version > ProfileSchema.CURRENT_VERSION then
		return ProfileSchema.defaults(), "FutureVersion"
	end
	while version < ProfileSchema.CURRENT_VERSION do
		local step = ProfileSchema.MIGRATIONS[version]
		if step == nil then
			break
		end
		step(data)
		version += 1
	end
	data.SchemaVersion = ProfileSchema.CURRENT_VERSION
	return ProfileSchema.reconcile(data), "Ok"
end

-- Builds a fully valid profile from possibly-malformed data.
function ProfileSchema.reconcile(raw: { [string]: any }): Profile
	local profile = ProfileSchema.defaults()

	if isFinite(raw.ChronosScrap) then
		profile.ChronosScrap = math.clamp(math.floor(raw.ChronosScrap), 0, RewardConfig.MaxCurrency)
	end

	if type(raw.OwnedItems) == "table" then
		for id, owned in raw.OwnedItems do
			if type(id) == "string" and owned == true and ItemConfig.get(id) ~= nil then
				profile.OwnedItems[id] = true
			end
		end
	end

	if type(raw.Equipped) == "table" then
		for _, slot in ItemConfig.Slots do
			local id = raw.Equipped[slot]
			if type(id) == "string" then
				local item = ItemConfig.get(id)
				if item and item.Slot == slot and profile.OwnedItems[id] then
					profile.Equipped[slot] = id
				end
			end
		end
	end

	if type(raw.Stats) == "table" then
		local stats = profile.Stats :: any
		for _, key in ProfileSchema.STAT_KEYS do
			local value = raw.Stats[key]
			if isFinite(value) and value >= 0 then
				stats[key] = math.floor(value)
			end
		end
	end

	if type(raw.Settings) == "table" then
		local settings = profile.Settings :: any
		for key in ProfileSchema.SETTINGS :: any do
			local value = ProfileSchema.sanitizeSetting(key, raw.Settings[key])
			if value ~= nil then
				settings[key] = value
			end
		end
	end

	if type(raw.RecentMatchIds) == "table" then
		for _, id in raw.RecentMatchIds do
			if type(id) == "string" and #id <= 64 then
				table.insert(profile.RecentMatchIds, id)
			end
		end
		while #profile.RecentMatchIds > RewardConfig.RecentMatchHistorySize do
			table.remove(profile.RecentMatchIds, 1)
		end
	end

	return profile
end

return table.freeze(ProfileSchema)
