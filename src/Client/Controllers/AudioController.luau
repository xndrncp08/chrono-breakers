--!strict
-- AudioController: plays optional sounds from the AssetManifest, scaled by the player's volume
-- settings. Missing or unconfigured entries are skipped silently, so gameplay never depends on audio.
--   * Play(key, { position?, volume?, pitch? }) — 2D, or 3D at a world position (spatial roll-off).
--   * SetMusicIntensity(layer, 0..1) — dynamic music: looping layers crossfade toward targets
--     (Match / Terror / Chase / Collapse). Layers without a configured id stay silent.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local AssetManifest = require(ReplicatedStorage.Shared.Config.AssetManifest)

local ClientState = require(script.Parent.Parent.ClientState)

local AudioController = {}

export type PlayOptions = { position: Vector3?, volume: number?, pitch: number?, range: number? }

local cache: { [string]: Sound } = {}
local folder: Folder? = nil
local emitters: Folder? = nil

local UI_SOUNDS: { [string]: boolean } = { UiClick = true, UiError = true, Countdown = true }
local MUSIC: { [string]: boolean } = {
	LobbyMusic = true,
	MatchMusic = true,
	TerrorMusic = true,
	ChaseMusic = true,
	CollapseMusic = true,
}
local layers: { [string]: { sound: Sound, target: number, current: number } } = {}

local function volumeFor(key: string): number
	local settings = ClientState.get("settings")
	if not settings then
		return 0.7
	end
	if UI_SOUNDS[key] then
		return settings.UiVolume or 0.7
	end
	if MUSIC[key] then
		return settings.MusicVolume or 0.5
	end
	return settings.SfxVolume or 0.8
end

local function entryFor(key: string): AssetManifest.SoundEntry?
	local entry = (AssetManifest.Sounds :: any)[key] :: AssetManifest.SoundEntry?
	if not entry or entry.Id == nil then
		return nil
	end
	return entry
end

function AudioController.Init()
	local f = Instance.new("Folder")
	f.Name = "ChronoSounds"
	f.Parent = SoundService
	folder = f
	local e = Instance.new("Folder")
	e.Name = "ChronoSoundEmitters"
	e.Parent = Workspace
	emitters = e
end

function AudioController.Play(key: string, options: PlayOptions?)
	local entry = entryFor(key)
	if not entry then
		return
	end
	local volume = entry.Volume * volumeFor(key) * (if options and options.volume then options.volume else 1)
	if volume <= 0 then
		return
	end
	local pitch = (entry.PlaybackSpeed or 1) * (if options and options.pitch then options.pitch else 1)
	if options and options.position then
		-- One-shot 3D emitter so distance and direction carry information (e.g. a missed calibration).
		local anchor = Instance.new("Part")
		anchor.Name = key
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Position = options.position
		local sound = Instance.new("Sound")
		sound.SoundId = entry.Id :: string
		sound.Volume = volume
		sound.PlaybackSpeed = pitch
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = options.range or 140
		sound.Parent = anchor
		anchor.Parent = emitters
		sound:Play()
		Debris:AddItem(anchor, 4)
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
	local s = sound :: Sound
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.TimePosition = 0
	s:Play()
end

-- Sets the target loudness (0..1) of a looping music layer; the controller crossfades toward it.
function AudioController.SetMusicIntensity(key: string, intensity: number)
	local layer = layers[key]
	if not layer then
		local entry = entryFor(key)
		if not entry then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = entry.Id :: string
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = folder
		layer = { sound = sound, target = 0, current = 0 }
		layers[key] = layer
	end
	(layer :: any).target = math.clamp(intensity, 0, 1)
end

function AudioController.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		for key, layer in layers do
			local entry = entryFor(key)
			local step = dt / 1.2 -- ~1.2 s full crossfade
			if layer.current < layer.target then
				layer.current = math.min(layer.target, layer.current + step)
			elseif layer.current > layer.target then
				layer.current = math.max(layer.target, layer.current - step)
			end
			local volume = layer.current * (if entry then entry.Volume else 0) * volumeFor(key)
			layer.sound.Volume = volume
			if volume > 0 and not layer.sound.IsPlaying then
				layer.sound:Play()
			elseif volume <= 0 and layer.sound.IsPlaying then
				layer.sound:Stop()
			end
		end
	end)
end

return AudioController
