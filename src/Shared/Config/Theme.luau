--!strict
-- Design tokens: the single source for colours, typography, spacing, radii, motion, and world
-- palette. UI and world-building code must reference these tokens instead of literal values.

local Theme = {}

Theme.Colors = table.freeze({
	-- Foundations
	Background = Color3.fromRGB(8, 11, 20),
	Surface = Color3.fromRGB(14, 19, 34),
	SurfaceRaised = Color3.fromRGB(22, 29, 50),
	SurfaceHover = Color3.fromRGB(30, 40, 68),
	Border = Color3.fromRGB(52, 66, 104),
	BorderStrong = Color3.fromRGB(88, 110, 168),
	Overlay = Color3.fromRGB(2, 4, 10),

	-- Text
	TextPrimary = Color3.fromRGB(236, 243, 255),
	TextSecondary = Color3.fromRGB(160, 176, 210),
	TextMuted = Color3.fromRGB(104, 118, 152),
	TextOnAccent = Color3.fromRGB(4, 14, 22),

	-- Semantic
	Stable = Color3.fromRGB(64, 232, 255), -- cyan: objectives, progress, Infiltrators
	StableDim = Color3.fromRGB(22, 96, 120),
	Temporal = Color3.fromRGB(255, 72, 196), -- magenta: temporal instability, Time-Keeper
	TemporalDim = Color3.fromRGB(110, 28, 88),
	Danger = Color3.fromRGB(255, 84, 84),
	Warning = Color3.fromRGB(255, 196, 72),
	Success = Color3.fromRGB(96, 240, 156),
	Locked = Color3.fromRGB(96, 104, 128),
	Violet = Color3.fromRGB(156, 112, 255),
})

-- World palette (Parts). Keys are referenced by MapLayout box colour tokens.
Theme.World = table.freeze({
	Floor = Color3.fromRGB(26, 30, 44),
	FloorAccent = Color3.fromRGB(28, 120, 150),
	Wall = Color3.fromRGB(38, 44, 66),
	Cover = Color3.fromRGB(52, 60, 86),
	Shelf = Color3.fromRGB(44, 52, 80),
	Pillar = Color3.fromRGB(60, 70, 102),
	TrimCyan = Color3.fromRGB(64, 232, 255),
	Danger = Color3.fromRGB(255, 72, 196),
	Gate = Color3.fromRGB(255, 72, 196),
	TerminalBody = Color3.fromRGB(30, 36, 56),
	ExtractionPad = Color3.fromRGB(96, 240, 156),
	PodGlass = Color3.fromRGB(150, 120, 255),
	PodFrame = Color3.fromRGB(34, 30, 58),
	Rift = Color3.fromRGB(196, 150, 255),
})

-- Integrity ladder colours (HUD cards, markers, pods).
Theme.ConditionColors = table.freeze({
	Healthy = Color3.fromRGB(96, 240, 156),
	Injured = Color3.fromRGB(255, 196, 72),
	Downed = Color3.fromRGB(255, 84, 84),
	Contained = Color3.fromRGB(156, 112, 255),
	Eliminated = Color3.fromRGB(104, 118, 152),
	Extracted = Color3.fromRGB(64, 232, 255),
})

Theme.TerminalStateColors = table.freeze({
	Locked = Color3.fromRGB(96, 104, 128),
	Available = Color3.fromRGB(64, 232, 255),
	Hacking = Color3.fromRGB(255, 196, 72),
	Interrupted = Color3.fromRGB(255, 84, 84),
	Completed = Color3.fromRGB(96, 240, 156),
})

Theme.RoleColors = table.freeze({
	TimeKeeper = Color3.fromRGB(255, 72, 196),
	Infiltrator = Color3.fromRGB(64, 232, 255),
})

Theme.Fonts = table.freeze({
	Display = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.Code,
})

Theme.Atmospheres = table.freeze({
	["Chronos Vault"] = { Ambient = Color3.fromRGB(46, 52, 84), Fog = Color3.fromRGB(10, 14, 28), Clock = 0 },
	["Fractured Metropolis"] = { Ambient = Color3.fromRGB(64, 42, 88), Fog = Color3.fromRGB(24, 10, 38), Clock = 20 },
	["The Forgotten Laboratory"] = { Ambient = Color3.fromRGB(40, 72, 76), Fog = Color3.fromRGB(8, 24, 28), Clock = 1 },
	["Temporal Nexus"] = { Ambient = Color3.fromRGB(62, 42, 104), Fog = Color3.fromRGB(20, 8, 40), Clock = 0 },
})

-- Text sizes (pixels before UIScale). Minimum body size keeps mobile readability.
Theme.TextSize = table.freeze({
	Hero = 54,
	Title = 32,
	Heading = 22,
	Body = 17,
	Small = 14,
	Micro = 12,
})

Theme.Spacing = table.freeze({
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
	XXL = 36,
})

Theme.Radius = table.freeze({
	S = UDim.new(0, 6),
	M = UDim.new(0, 10),
	L = UDim.new(0, 16),
	Pill = UDim.new(1, 0),
})

Theme.Stroke = table.freeze({
	Thin = 1,
	Regular = 1.5,
	Strong = 2.5,
})

Theme.Transparency = table.freeze({
	Panel = 0.12,
	PanelSoft = 0.3,
	Overlay = 0.35,
	Glow = 0.55,
})

-- Motion durations in seconds. ReducedMotion collapses these to 0 at the call sites.
Theme.Motion = table.freeze({
	Fast = 0.12,
	Normal = 0.22,
	Slow = 0.45,
	Reveal = 0.8,
})

-- Minimum touch target (px) for buttons on touch devices.
Theme.MinTouchTarget = 60

return table.freeze(Theme)
