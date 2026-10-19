--!strict
local Config = {}
Config.MaxXP = 1000000000
Config.LevelStep = 125
Config.MaxLevel = 100
Config.XP = table.freeze({ Participation = 80, Win = 60, Hack = 25, Assist = 15, Elimination = 30, Extraction = 40 })
Config.Daily = table.freeze({
	{ Id = "Deploy", Name = "Complete two heists", Stat = "MatchesPlayed", Target = 2, Scrap = 30, XP = 100 },
	{ Id = "Breach", Name = "Breach three terminals", Stat = "TerminalsHacked", Target = 3, Scrap = 40, XP = 150 },
	{ Id = "Escape", Name = "Extract once", Stat = "Extractions", Target = 1, Scrap = 35, XP = 120 },
	{ Id = "Teamwork", Name = "Assist two terminal breaches", Stat = "HackAssists", Target = 2, Scrap = 35, XP = 120 },
})
Config.Weekly = table.freeze({
	{ Id = "Veteran", Name = "Complete ten heists", Stat = "MatchesPlayed", Target = 10, Scrap = 150, XP = 500 },
	{
		Id = "Technician",
		Name = "Breach fifteen terminals",
		Stat = "TerminalsHacked",
		Target = 15,
		Scrap = 180,
		XP = 600,
	},
	{ Id = "Warden", Name = "Catch eight Infiltrators", Stat = "Eliminations", Target = 8, Scrap = 180, XP = 600 },
	{ Id = "Victories", Name = "Win six heists", Stat = "Wins", Target = 6, Scrap = 160, XP = 550 },
})
Config.Milestones = table.freeze({
	FirstEscape = { Name = "Timeline Breaker", Stat = "Extractions", Target = 1, Item = "TitleBreaker" },
	VaultWarden = { Name = "Vault Warden", Stat = "KeeperWins", Target = 5, Item = "TitleWarden" },
	Veteran = { Name = "Temporal Veteran", Stat = "MatchesPlayed", Target = 20, Item = "TitleVeteran" },
	RiftWalker = { Name = "Rift Walker", Stat = "Level", Target = 10, Item = "TrailRift" },
})
function Config.level(xp: number): number
	return math.clamp(
		1 + math.floor((math.sqrt(1 + 8 * math.max(0, xp) / Config.LevelStep) - 1) / 2),
		1,
		Config.MaxLevel
	)
end
function Config.threshold(level: number): number
	return Config.LevelStep * (level - 1) * level / 2
end
function Config.period(kind: string, now: number): number
	return if kind == "Daily" then math.floor(now / 86400) else math.floor((now + 3 * 86400) / 604800)
end
function Config.challenges(kind: string, period: number): { any }
	local pool = if kind == "Daily" then Config.Daily else Config.Weekly
	return { pool[period % #pool + 1], pool[(period + 1) % #pool + 1] }
end
return table.freeze(Config)
