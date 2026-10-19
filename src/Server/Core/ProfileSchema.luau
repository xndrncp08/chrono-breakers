--!strict
-- Versioned player profile schema: defaults, migrations, and reconciliation (sanitisation).
-- See docs/DATA_SCHEMA.md. Every field has a safe default; anything malformed is replaced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local PerkConfig = require(ReplicatedStorage.Shared.Config.PerkConfig)
local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
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
	HackAssists: number,
	KeeperWins: number,
	InfiltratorMatches: number,
	Rescues: number,
	Resyncs: number,
	Patches: number,
	Containments: number,
	Downs: number,
	GreatCalibrations: number,
}

export type ChallengePeriod = { Period: number, Progress: { [string]: number }, Claimed: { [string]: boolean } }
export type Progression = {
	XP: number,
	Mastery: { [string]: number },
	Milestones: { [string]: boolean },
	Daily: ChallengePeriod,
	Weekly: ChallengePeriod,
}
export type Profile = {
	SchemaVersion: number,
	ChronosScrap: number,
	OwnedItems: { [string]: boolean },
	Equipped: { [string]: string },
	Stats: Stats,
	Settings: Settings,
	RecentMatchIds: { string },
	Progression: Progression,
	-- Perk loadouts: class id or "TimeKeeper" -> up to PerkConfig.Slots perk ids.
	Perks: { [string]: { string } },
}

local ProfileSchema = {}

ProfileSchema.CURRENT_VERSION = 4

ProfileSchema.STAT_KEYS = table.freeze({
	"MatchesPlayed",
	"Wins",
	"Losses",
	"TerminalsHacked",
	"Extractions",
	"Eliminations",
	"KeeperMatches",
	"HackAssists",
	"KeeperWins",
	"InfiltratorMatches",
	"Rescues",
	"Resyncs",
	"Patches",
	"Containments",
	"Downs",
	"GreatCalibrations",
})

-- Every perk loadout key a profile may hold.
ProfileSchema.LOADOUT_KEYS = table.freeze((function(): { string }
	local keys = table.clone(ClassConfig.Order :: any) :: { string }
	table.insert(keys, "TimeKeeper")
	return keys
end)())

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
		Progression = {
			XP = 0,
			Mastery = {},
			Milestones = {},
			Daily = { Period = -1, Progress = {}, Claimed = {} },
			Weekly = { Period = -1, Progress = {}, Claimed = {} },
		},
		Perks = {},
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
	[2] = function(data: { [string]: any })
		data.SchemaVersion = 3
	end,
	-- v4 (Survival Protocol): perk loadouts and survival stats. Absent fields take safe defaults.
	[3] = function(data: { [string]: any })
		if type(data.Perks) ~= "table" then
			data.Perks = {}
		end
		data.SchemaVersion = 4
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
				stats[key] = math.min(1000000000, math.floor(value))
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

	local function whole(value: any, cap: number): number
		return if isFinite(value) then math.clamp(math.floor(value), 0, cap) else 0
	end
	if type(raw.Progression) == "table" then
		local progress = raw.Progression
		profile.Progression.XP = whole(progress.XP, ProgressionConfig.MaxXP)
		if type(progress.Mastery) == "table" then
			for _, id in ClassConfig.Order do
				profile.Progression.Mastery[id] = whole(progress.Mastery[id], ProgressionConfig.MaxXP)
			end
			profile.Progression.Mastery.TimeKeeper = whole(progress.Mastery.TimeKeeper, ProgressionConfig.MaxXP)
		end
		if type(progress.Milestones) == "table" then
			for id, definition in ProgressionConfig.Milestones :: any do
				if progress.Milestones[id] == true then
					profile.Progression.Milestones[id] = true
					profile.OwnedItems[definition.Item] = true
				end
			end
		end
		for _, kind in { "Daily", "Weekly" } do
			local source = progress[kind]
			if type(source) == "table" then
				local target = (profile.Progression :: any)[kind]
				target.Period = if isFinite(source.Period)
					then math.clamp(math.floor(source.Period), -1, 1000000000)
					else -1
				local pool: { any } = if kind == "Daily" then ProgressionConfig.Daily else ProgressionConfig.Weekly
				for _, definition in pool do
					if type(source.Progress) == "table" then
						target.Progress[definition.Id] = whole(source.Progress[definition.Id], definition.Target)
					end
					if type(source.Claimed) == "table" and source.Claimed[definition.Id] == true then
						target.Claimed[definition.Id] = true
					end
				end
			end
		end
	end

	-- Perks are reconciled after progression so unlocks are judged on sanitised values.
	if type(raw.Perks) == "table" then
		local progress = { xp = profile.Progression.XP, mastery = profile.Progression.Mastery }
		for _, key in ProfileSchema.LOADOUT_KEYS do
			local source = raw.Perks[key]
			if type(source) == "table" then
				local list: { string } = {}
				for _, id in source do
					local definition = if type(id) == "string" then PerkConfig.get(id) else nil
					if
						definition
						and #list < PerkConfig.Slots
						and not table.find(list, id)
						and PerkConfig.isUnlocked(definition, key, progress)
					then
						table.insert(list, id)
					end
				end
				if #list > 0 then
					profile.Perks[key] = list
				end
			end
		end
	end

	return profile
end

-- Loadout key used when this profile plays as `role`.
function ProfileSchema.loadoutKey(profile: Profile, role: string): string
	return if role == "TimeKeeper" then "TimeKeeper" else profile.Equipped.Class or "Ghost"
end

return table.freeze(ProfileSchema)
