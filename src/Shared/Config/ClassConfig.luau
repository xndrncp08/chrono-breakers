--!strict
export type Definition = {
	Name: string,
	Description: string,
	AbilityId: string,
	WalkSpeed: number,
	MaxHealth: number,
	HackSpeed: number,
	Color: Color3,
}
local ClassConfig = {}
ClassConfig.Order = table.freeze({ "Ghost", "Engineer", "ChronoMedic", "Phantom", "Disruptor" })
ClassConfig.Classes = table.freeze({
	Ghost = {
		Name = "Ghost",
		Description = "Veil hides you from scans for 5s. Fast but fragile; hacking or damage breaks stealth.",
		AbilityId = "Veil",
		WalkSpeed = 17,
		MaxHealth = 80,
		HackSpeed = 1,
		Color = Color3.fromRGB(160, 170, 255),
	},
	Engineer = {
		Name = "Engineer",
		Description = "Hack 15% faster; Overclock boosts hacking another 50% for 6s. Slower rotations.",
		AbilityId = "Overclock",
		WalkSpeed = 15,
		MaxHealth = 100,
		HackSpeed = 1.15,
		Color = Color3.fromRGB(255, 196, 72),
	},
	ChronoMedic = {
		Name = "Chrono Medic",
		Description = "Mend restores 28 health to nearby living allies in sight. Cannot revive eliminated teammates.",
		AbilityId = "Mend",
		WalkSpeed = 16,
		MaxHealth = 95,
		HackSpeed = 1,
		Color = Color3.fromRGB(96, 240, 156),
	},
	Phantom = {
		Name = "Phantom",
		Description = "Slipstream grants a 1.5s speed burst. High mobility, lower health and 10% slower hacking.",
		AbilityId = "Slipstream",
		WalkSpeed = 16.5,
		MaxHealth = 85,
		HackSpeed = 0.9,
		Color = Color3.fromRGB(64, 232, 255),
	},
	Disruptor = {
		Name = "Disruptor",
		Description = "EMP disarms nearby visible traps and cleanses allies. Hack 5% slower.",
		AbilityId = "EMP",
		WalkSpeed = 16,
		MaxHealth = 100,
		HackSpeed = 0.95,
		Color = Color3.fromRGB(255, 72, 196),
	},
} :: { [string]: Definition })
function ClassConfig.get(id: string?): Definition?
	return if id then ClassConfig.Classes[id] else nil
end
return table.freeze(ClassConfig)
