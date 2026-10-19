--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local ProfileSchema = require(script.Parent.ProfileSchema)
local Economy = require(script.Parent.Economy)
local Progression = {}
export type Award = {
	xp: number,
	masteryId: string?,
	timestamp: number?,
	statDeltas: { [string]: number },
	eligible: boolean,
}
-- Invoked only inside RewardLedger, after its duplicate guard and in the same non-yielding mutation.
function Progression.apply(profile: ProfileSchema.Profile, award: Award): (number, { string })
	if not award.eligible then
		return 0, {}
	end
	local progress = profile.Progression
	local bonus, notifications = 0, {}
	local xp = math.clamp(math.floor(award.xp), 0, Config.MaxXP)
	local previousLevel = Config.level(progress.XP)
	progress.XP = math.min(Config.MaxXP, progress.XP + xp)
	local mastery = award.masteryId
	if mastery and (mastery == "TimeKeeper" or ClassConfig.get(mastery)) then
		progress.Mastery[mastery] = math.min(Config.MaxXP, (progress.Mastery[mastery] or 0) + xp)
	end
	if award.timestamp then
		for _, kind in { "Daily", "Weekly" } do
			local state = (progress :: any)[kind] :: ProfileSchema.ChallengePeriod
			local period = Config.period(kind, award.timestamp)
			if period > state.Period then
				state.Period = period
				table.clear(state.Progress)
				table.clear(state.Claimed)
			end
			if period == state.Period then
				for _, challenge in Config.challenges(kind, period) do
					local amount = math.max(0, award.statDeltas[challenge.Stat] or 0)
					state.Progress[challenge.Id] =
						math.min(challenge.Target, (state.Progress[challenge.Id] or 0) + amount)
					if state.Progress[challenge.Id] >= challenge.Target and not state.Claimed[challenge.Id] then
						state.Claimed[challenge.Id] = true
						bonus += Economy.grant(profile, challenge.Scrap)
						progress.XP = math.min(Config.MaxXP, progress.XP + challenge.XP)
						table.insert(
							notifications,
							`{kind} complete: {challenge.Name} (+{challenge.Scrap} Scrap / +{challenge.XP} XP)`
						)
					end
				end
			end
		end
	end
	local level = Config.level(progress.XP)
	if level > previousLevel then
		table.insert(notifications, `Level {level} reached`)
	end
	for id, definition in Config.Milestones :: any do
		local value = if definition.Stat == "Level" then level else (profile.Stats :: any)[definition.Stat] or 0
		if value >= definition.Target and not progress.Milestones[id] then
			progress.Milestones[id] = true
			profile.OwnedItems[definition.Item] = true
			table.insert(notifications, `Unlocked: {definition.Name}`)
		end
	end
	return bonus, notifications
end
function Progression.snapshot(progress: ProfileSchema.Progression, now: number): any
	local snapshot: any = {
		xp = progress.XP,
		level = Config.level(progress.XP),
		mastery = table.clone(progress.Mastery),
		milestones = table.clone(progress.Milestones),
		challenges = {},
	}
	for _, kind in { "Daily", "Weekly" } do
		local state = (progress :: any)[kind] :: ProfileSchema.ChallengePeriod
		local period = math.max(state.Period, Config.period(kind, now))
		for _, challenge in Config.challenges(kind, period) do
			table.insert(snapshot.challenges, {
				id = challenge.Id,
				name = challenge.Name,
				kind = kind,
				target = challenge.Target,
				scrap = challenge.Scrap,
				xp = challenge.XP,
				progress = if state.Period == period then state.Progress[challenge.Id] or 0 else 0,
				claimed = state.Period == period and state.Claimed[challenge.Id] == true,
				resetsAt = if kind == "Daily" then (period + 1) * 86400 else (period + 1) * 604800 - 3 * 86400,
			})
		end
	end
	return snapshot
end
return table.freeze(Progression)
