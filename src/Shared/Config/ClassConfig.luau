--!strict
-- Infiltrator classes. Every class is free; each trades one strength for a weakness and brings a
-- skill (F / Y) that complements the others. Durability is the shared integrity ladder
-- (SurvivalConfig); MaxHealth only scales the presentational health bar.
export type Definition = {
	Name: string,
	Description: string,
	Passive: string,
	AbilityId: string,
	WalkSpeed: number,
	MaxHealth: number,
	HackSpeed: number,
	HealSpeed: number, -- Patch / Re-sync speed multiplier
	VaultSpeed: number, -- Breach Rail / barrier vault speed multiplier
	StaminaScale: number, -- sprint stamina pool multiplier
	BarrierStunScale: number, -- Stasis Barrier stun duration multiplier
	Quiet: boolean, -- leaves no residue while walking and muffles Resonance cues
	Color: Color3,
}
local ClassConfig = {}
ClassConfig.Order = table.freeze({ "Ghost", "Engineer", "ChronoMedic", "Phantom", "Disruptor" })
ClassConfig.Classes = table.freeze({
	Ghost = {
		Name = "Ghost",
		Description = "Veil hides you from scans for 5s. Quiet and quick; hacking or damage breaks stealth.",
		Passive = "Quiet Steps: no residue while walking; the Keeper's Resonance cues reach you sooner.",
		AbilityId = "Veil",
		WalkSpeed = 15.5,
		MaxHealth = 80,
		HackSpeed = 1,
		HealSpeed = 0.9,
		VaultSpeed = 1,
		StaminaScale = 1,
		BarrierStunScale = 1,
		Quiet = true,
		Color = Color3.fromRGB(160, 170, 255),
	},
	Engineer = {
		Name = "Engineer",
		Description = "Hack 15% faster; Overclock boosts hacking another 50% for 6s. Slower rotations.",
		Passive = "Field Tuning: terminals and relays respond 15% faster to you.",
		AbilityId = "Overclock",
		WalkSpeed = 14.5,
		MaxHealth = 100,
		HackSpeed = 1.15,
		HealSpeed = 1,
		VaultSpeed = 0.9,
		StaminaScale = 0.9,
		BarrierStunScale = 1,
		Quiet = false,
		Color = Color3.fromRGB(255, 196, 72),
	},
	ChronoMedic = {
		Name = "Chrono Medic",
		Description = "Mend surges Patch and Re-sync progress for allies in sight. Patches 40% faster.",
		Passive = "Triage: Patch and Re-sync 40% faster.",
		AbilityId = "Mend",
		WalkSpeed = 15,
		MaxHealth = 95,
		HackSpeed = 1,
		HealSpeed = 1.4,
		VaultSpeed = 1,
		StaminaScale = 1,
		BarrierStunScale = 1,
		Quiet = false,
		Color = Color3.fromRGB(96, 240, 156),
	},
	Phantom = {
		Name = "Phantom",
		Description = "Slipstream grants a 1.5s speed burst. Vaults faster with deeper stamina; hacks 10% slower.",
		Passive = "Free Runner: vaults 35% faster and has 25% more stamina.",
		AbilityId = "Slipstream",
		WalkSpeed = 15.5,
		MaxHealth = 85,
		HackSpeed = 0.9,
		HealSpeed = 1,
		VaultSpeed = 1.35,
		StaminaScale = 1.25,
		BarrierStunScale = 1,
		Quiet = false,
		Color = Color3.fromRGB(64, 232, 255),
	},
	Disruptor = {
		Name = "Disruptor",
		Description = "Disruption Pulse disarms traps, cleanses allies and breaks a nearby Phase-Lock. Hack 5% slower.",
		Passive = "Overcharge: Stasis Barriers you drop stun 30% longer.",
		AbilityId = "EMP",
		WalkSpeed = 15,
		MaxHealth = 100,
		HackSpeed = 0.95,
		HealSpeed = 1,
		VaultSpeed = 1,
		StaminaScale = 1,
		BarrierStunScale = 1.3,
		Quiet = false,
		Color = Color3.fromRGB(255, 72, 196),
	},
} :: { [string]: Definition })
function ClassConfig.get(id: string?): Definition?
	return if id then ClassConfig.Classes[id] else nil
end
return table.freeze(ClassConfig)
