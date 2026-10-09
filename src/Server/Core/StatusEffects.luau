--!strict
-- Centralised, non-compounding status effects for one character.
--
-- Movement is ALWAYS derived from the role baseline, never from the character's current speed:
--   speed = base * (1 - strongestSlow) * (1 + strongestHaste)        (0 if stunned or rooted)
--
-- Stacking rules (documented in docs/GAME_DESIGN.md):
--   * Effects are keyed by `key`. Re-applying the same key replaces it (refresh), never stacks.
--   * Different keys of the same kind do not add: the strongest magnitude wins.
--   * Expiry of one effect never removes another; each key expires independently.
--   * SlowImmunity suppresses Slow and Stun while active (it does not remove them; if immunity ends
--     first, a longer slow resumes). Cleanse removes existing Slow/Stun entries explicitly.
--   * Root (used to hold the Time-Keeper at match start) is not affected by immunity.
--   * Invulnerable marks spawn protection (damage is rejected by CombatService).

export type EffectKind = "Slow" | "Stun" | "Root" | "Haste" | "SlowImmunity" | "Invulnerable" | "Revealed"

export type Effect = {
	key: string,
	kind: EffectKind,
	magnitude: number,
	expiresAt: number,
	source: string,
}

export type Movement = {
	walkSpeed: number,
	jumpPower: number,
	slowed: boolean,
	stunned: boolean,
	rooted: boolean,
	hasted: boolean,
	slowImmune: boolean,
	invulnerable: boolean,
}

export type StatusEffects = {
	add: (self: StatusEffects, effect: Effect) -> (),
	remove: (self: StatusEffects, key: string) -> boolean,
	removeKinds: (self: StatusEffects, kinds: { EffectKind }) -> number,
	prune: (self: StatusEffects, now: number) -> boolean,
	has: (self: StatusEffects, kind: EffectKind, now: number) -> boolean,
	compute: (self: StatusEffects, baseWalkSpeed: number, baseJumpPower: number, now: number) -> Movement,
	nextExpiry: (self: StatusEffects) -> number?,
	list: (self: StatusEffects) -> { Effect },
	clear: (self: StatusEffects) -> (),
	count: (self: StatusEffects) -> number,
}

local StatusEffects = {}

StatusEffects.MAX_SLOW = 0.95
StatusEffects.MAX_HASTE = 2

local function sanitizeMagnitude(kind: EffectKind, magnitude: number): number
	if magnitude ~= magnitude then
		return 0
	end
	if kind == "Slow" then
		return math.clamp(magnitude, 0, StatusEffects.MAX_SLOW)
	elseif kind == "Haste" then
		return math.clamp(magnitude, 0, StatusEffects.MAX_HASTE)
	end
	return math.clamp(magnitude, 0, 1)
end

function StatusEffects.new(): StatusEffects
	local effects: { [string]: Effect } = {}
	local self = {} :: any

	function self:add(effect: Effect)
		effects[effect.key] = {
			key = effect.key,
			kind = effect.kind,
			magnitude = sanitizeMagnitude(effect.kind, effect.magnitude),
			expiresAt = effect.expiresAt,
			source = effect.source,
		}
	end

	function self:remove(key: string): boolean
		if effects[key] then
			effects[key] = nil
			return true
		end
		return false
	end

	function self:removeKinds(kinds: { EffectKind }): number
		local removed = 0
		for key, effect in effects do
			if table.find(kinds, effect.kind) then
				effects[key] = nil
				removed += 1
			end
		end
		return removed
	end

	function self:prune(now: number): boolean
		local changed = false
		for key, effect in effects do
			if now >= effect.expiresAt then
				effects[key] = nil
				changed = true
			end
		end
		return changed
	end

	function self:has(kind: EffectKind, now: number): boolean
		for _, effect in effects do
			if effect.kind == kind and now < effect.expiresAt then
				return true
			end
		end
		return false
	end

	function self:compute(baseWalkSpeed: number, baseJumpPower: number, now: number): Movement
		local slow, haste = 0, 0
		local stunned, rooted, immune, invulnerable = false, false, false, false
		for _, effect in effects do
			if now < effect.expiresAt then
				if effect.kind == "SlowImmunity" then
					immune = true
				elseif effect.kind == "Invulnerable" then
					invulnerable = true
				end
			end
		end
		for _, effect in effects do
			if now < effect.expiresAt then
				local kind = effect.kind
				if kind == "Slow" and not immune then
					slow = math.max(slow, effect.magnitude)
				elseif kind == "Haste" then
					haste = math.max(haste, effect.magnitude)
				elseif kind == "Stun" and not immune then
					stunned = true
				elseif kind == "Root" then
					rooted = true
				end
			end
		end
		local walkSpeed = baseWalkSpeed * (1 - slow) * (1 + haste)
		local jumpPower = baseJumpPower
		if stunned or rooted then
			walkSpeed = 0
			jumpPower = 0
		end
		return {
			walkSpeed = walkSpeed,
			jumpPower = jumpPower,
			slowed = slow > 0,
			stunned = stunned,
			rooted = rooted,
			hasted = haste > 0,
			slowImmune = immune,
			invulnerable = invulnerable,
		}
	end

	function self:nextExpiry(): number?
		local soonest: number? = nil
		for _, effect in effects do
			if soonest == nil or effect.expiresAt < soonest then
				soonest = effect.expiresAt
			end
		end
		return soonest
	end

	function self:list(): { Effect }
		local out: { Effect } = {}
		for _, effect in effects do
			table.insert(out, table.clone(effect))
		end
		table.sort(out, function(a, b)
			return a.key < b.key
		end)
		return out
	end

	function self:clear()
		table.clear(effects)
	end

	function self:count(): number
		local n = 0
		for _ in effects do
			n += 1
		end
		return n
	end

	return self :: StatusEffects
end

return StatusEffects
