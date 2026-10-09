--!strict
-- AudioController: plays optional sounds from the AssetManifest, scaled by the player's volume
-- settings. Missing or unconfigured entries are skipped silently, so gameplay never depends on audio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AssetManifest = require(ReplicatedStorage.Shared.Config.AssetManifest)

local ClientState = require(script.Parent.Parent.ClientState)

local AudioController = {}

local cache: { [string]: Sound } = {}
local folder: Folder? = nil

local UI_SOUNDS: { [string]: boolean } = { UiClick = true, UiError = true, Countdown = true }

local function volumeFor(key: string): number
	local settings = ClientState.get("settings")
	if not settings then
		return 0.7
	end
	if UI_SOUNDS[key] then
		return settings.UiVolume or 0.7
	end
	if key == "LobbyMusic" or key == "MatchMusic" then
		return settings.MusicVolume or 0.5
	end
	return settings.SfxVolume or 0.8
end

function AudioController.Init()
	local f = Instance.new("Folder")
	f.Name = "ChronoSounds"
	f.Parent = SoundService
	folder = f
end

function AudioController.Play(key: string)
	local entry = (AssetManifest.Sounds :: any)[key] :: AssetManifest.SoundEntry?
	if not entry or entry.Id == nil then
		return
	end
	local sound = cache[key]
	if not sound then
		local s = Instance.new("Sound")
		s.Name = key
		s.SoundId = entry.Id :: string
		s.Parent = folder
		cache[key] = s
		sound = s
	end
	local volume = entry.Volume * volumeFor(key)
	if volume <= 0 then
		return
	end
	local s = sound :: Sound
	s.Volume = volume
	s.PlaybackSpeed = entry.PlaybackSpeed or 1
	s.TimePosition = 0
	s:Play()
end

return AudioController
