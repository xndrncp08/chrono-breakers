--!strict
-- Fair, explainable Time-Keeper selection.
--
-- Rule: the candidate who has gone the most matches without being Time-Keeper is chosen.
-- Ties are broken uniformly at random using the injected `randomIndex` function (deterministic in
-- tests). After a match, the chosen Keeper's counter resets to 0 and everyone else's increases.
-- Players with no history start at `NEW_PLAYER_SCORE`, so newcomers neither jump the line nor are
-- starved forever.

export type History = { [number]: number } -- userId -> matches since last being Time-Keeper

local RoleSelector = {}
RoleSelector.NEW_PLAYER_SCORE = 0

function RoleSelector.score(history: History, userId: number): number
	local value = history[userId]
	if value == nil then
		return RoleSelector.NEW_PLAYER_SCORE
	end
	return value
end

function RoleSelector.selectKeeper(
	candidates: { number },
	history: History,
	randomIndex: (n: number) -> number
): number?
	if #candidates == 0 then
		return nil
	end
	local best = -math.huge
	local tied: { number } = {}
	for _, userId in candidates do
		local s = RoleSelector.score(history, userId)
		if s > best then
			best = s
			tied = { userId }
		elseif s == best then
			table.insert(tied, userId)
		end
	end
	local index = randomIndex(#tied)
	index = math.clamp(index, 1, #tied)
	return tied[index]
end

-- Returns role map: exactly one TimeKeeper (when allowKeeperless is false), all others Infiltrators.
function RoleSelector.assign(
	candidates: { number },
	history: History,
	randomIndex: (n: number) -> number,
	allowKeeperless: boolean?
): { [number]: string }
	local roles: { [number]: string } = {}
	if #candidates == 0 then
		return roles
	end
	local keeper: number? = nil
	if not (allowKeeperless and #candidates == 1) then
		keeper = RoleSelector.selectKeeper(candidates, history, randomIndex)
	end
	for _, userId in candidates do
		roles[userId] = if userId == keeper then "TimeKeeper" else "Infiltrator"
	end
	return roles
end

function RoleSelector.recordMatch(history: History, roles: { [number]: string })
	for userId, role in roles do
		if role == "TimeKeeper" then
			history[userId] = 0
		else
			history[userId] = RoleSelector.score(history, userId) + 1
		end
	end
end

return table.freeze(RoleSelector)
