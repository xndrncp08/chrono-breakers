--!strict
-- Token-bucket rate limiter keyed per player and per action.

export type Rule = { capacity: number, refillPerSecond: number }

export type RateLimiter = {
	allow: (self: RateLimiter, userId: number, action: string, now: number) -> boolean,
	removePlayer: (self: RateLimiter, userId: number) -> (),
	bucketCount: (self: RateLimiter) -> number,
}

type Bucket = { tokens: number, updatedAt: number }

local RateLimiter = {}

function RateLimiter.new(rules: { [string]: Rule }, defaultRule: Rule?): RateLimiter
	local buckets: { [number]: { [string]: Bucket } } = {}
	local fallback: Rule = defaultRule or { capacity = 5, refillPerSecond = 2 }
	local self = {} :: any

	function self:allow(userId: number, action: string, now: number): boolean
		local rule = rules[action] or fallback
		local perPlayer = buckets[userId]
		if not perPlayer then
			perPlayer = {}
			buckets[userId] = perPlayer
		end
		local bucket = (perPlayer :: { [string]: Bucket })[action]
		if not bucket then
			bucket = { tokens = rule.capacity, updatedAt = now }
			(perPlayer :: { [string]: Bucket })[action] = bucket
		end
		local b = bucket :: Bucket
		local elapsed = math.max(0, now - b.updatedAt)
		b.tokens = math.min(rule.capacity, b.tokens + elapsed * rule.refillPerSecond)
		b.updatedAt = now
		if b.tokens >= 1 then
			b.tokens -= 1
			return true
		end
		return false
	end

	function self:removePlayer(userId: number)
		buckets[userId] = nil
	end

	function self:bucketCount(): number
		local n = 0
		for _ in buckets do
			n += 1
		end
		return n
	end

	return self :: RateLimiter
end

return RateLimiter
