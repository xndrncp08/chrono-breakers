--!strict
-- Centralised optional asset manifest. Every entry may be nil (unconfigured). Gameplay never depends
-- on these assets; controllers skip playback when an entry is missing or fails to load.
--
-- Only the `rbxasset://sounds/*` paths below were verified to ship with the locally installed
-- Roblox Studio client (Contents/Resources/content/sounds). No marketplace asset ids are invented.
-- To add uploaded audio, replace nil with "rbxassetid://<id>" after uploading it to your account.

export type SoundEntry = {
	Id: string?,
	Volume: number,
	PlaybackSpeed: number?,
}

local AssetManifest = {}

AssetManifest.Sounds = table.freeze({
	UiClick = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5 } :: SoundEntry,
	UiError = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, PlaybackSpeed = 0.6 } :: SoundEntry,
	RoleReveal = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.25, PlaybackSpeed = 0.55 } :: SoundEntry,
	HackStart = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, PlaybackSpeed = 1.3 } :: SoundEntry,
	HackComplete = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.8, PlaybackSpeed = 1.8 } :: SoundEntry,
	HackInterrupted = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.7, PlaybackSpeed = 0.5 } :: SoundEntry,
	FreezeCast = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.35, PlaybackSpeed = 0.4 } :: SoundEntry,
	TrapTriggered = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.3, PlaybackSpeed = 1.4 } :: SoundEntry,
	Strike = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.6, PlaybackSpeed = 0.7 } :: SoundEntry,
	Hurt = { Id = "rbxasset://sounds/ouch.ogg", Volume = 0.6 } :: SoundEntry,
	GadgetUse = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.6, PlaybackSpeed = 1.2 } :: SoundEntry,
	ExtractionOpen = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.4, PlaybackSpeed = 0.7 } :: SoundEntry,
	Extracted = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8, PlaybackSpeed = 0.8 } :: SoundEntry,
	Countdown = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, PlaybackSpeed = 1 } :: SoundEntry,
	-- Survival cues, built from the same verified engine sounds by pitch shaping.
	Heartbeat = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.55, PlaybackSpeed = 0.3 } :: SoundEntry,
	HeartbeatSoft = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.35, PlaybackSpeed = 0.36 } :: SoundEntry,
	CalibrationCue = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.7, PlaybackSpeed = 2 } :: SoundEntry,
	CalibrationGreat = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.8, PlaybackSpeed = 2.6 } :: SoundEntry,
	CalibrationMiss = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.9, PlaybackSpeed = 1.1 } :: SoundEntry,
	Groan = { Id = "rbxasset://sounds/ouch.ogg", Volume = 0.5, PlaybackSpeed = 0.7 } :: SoundEntry,
	Vault = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.6, PlaybackSpeed = 1.15 } :: SoundEntry,
	BarrierDrop = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.7, PlaybackSpeed = 0.8 } :: SoundEntry,
	Door = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.7, PlaybackSpeed = 0.35 } :: SoundEntry,
	PodSeal = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.7, PlaybackSpeed = 0.5 } :: SoundEntry,
	Rescue = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.7, PlaybackSpeed = 1 } :: SoundEntry,
	Shockwave = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.6, PlaybackSpeed = 0.28 } :: SoundEntry,
	StrikeWindup = { Id = "rbxasset://sounds/action_falling.ogg", Volume = 0.35, PlaybackSpeed = 1.6 } :: SoundEntry,
	-- Unconfigured: no verified music track is available. The dynamic music system crossfades these
	-- layers by pursuit intensity once ids are supplied; until then music is silent.
	LobbyMusic = { Id = nil, Volume = 0.3 } :: SoundEntry,
	MatchMusic = { Id = nil, Volume = 0.3 } :: SoundEntry,
	TerrorMusic = { Id = nil, Volume = 0.35 } :: SoundEntry,
	ChaseMusic = { Id = nil, Volume = 0.45 } :: SoundEntry,
	CollapseMusic = { Id = nil, Volume = 0.45 } :: SoundEntry,
})

-- Image assets: none configured. UI uses vector-style frames, strokes, and gradients only.
AssetManifest.Images = table.freeze({})

return table.freeze(AssetManifest)
