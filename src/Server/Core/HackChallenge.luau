--!strict
-- Challenges accelerate the safe server-timed channel; failure risks saved progress.
export type Challenge = {
	nonce: number,
	mode: string,
	prompt: string,
	answer: number,
	opensAt: number,
	closesAt: number,
	expiresAt: number,
	used: boolean,
}
local HackChallenge = {}
function HackChallenge.new(mode: string, nonce: number, now: number, seed: number, difficulty: number): Challenge
	local answer = (seed - 1) % 3 + 1
	local prompt = ""
	local opensAt, closesAt = now + 0.6, now + 8
	if mode == "Sequence" then
		prompt = `{answer} → {answer % 3 + 1} → {(answer + 1) % 3 + 1} → ?`
	elseif mode == "Cipher" then
		local a = seed % 2 + 1
		local b = (answer - a - 1) % 3 + 1
		prompt = `ROUTE ({a} + {b}) on a 1–3 cycle (4 → 1)`
	else
		mode = "Timing"
		prompt = "LOCK while the server timing window is open"
		answer = 1
		opensAt = now + 1.8
		closesAt = opensAt + math.max(0.55, 1 - difficulty * 0.15)
	end
	return {
		nonce = nonce,
		mode = mode,
		prompt = prompt,
		answer = answer,
		opensAt = opensAt,
		closesAt = closesAt,
		expiresAt = now + 8,
		used = false,
	}
end
function HackChallenge.respond(challenge: Challenge, nonce: number, answer: number, now: number): (boolean, string)
	if challenge.used or nonce ~= challenge.nonce then
		return false, "StaleRequest"
	end
	if now < challenge.opensAt and challenge.mode ~= "Timing" then
		return false, "TooEarly"
	end
	if now >= challenge.expiresAt then
		return false, "StaleRequest"
	end
	challenge.used = true
	if
		answer ~= challenge.answer
		or (challenge.mode == "Timing" and (now < challenge.opensAt or now > challenge.closesAt))
	then
		return false, "ChallengeFailed"
	end
	return true, "Ok"
end
function HackChallenge.public(challenge: Challenge): any
	return {
		nonce = challenge.nonce,
		mode = challenge.mode,
		prompt = challenge.prompt,
		opensAt = challenge.opensAt,
		closesAt = challenge.closesAt,
		expiresAt = challenge.expiresAt,
	}
end
return table.freeze(HackChallenge)
