--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HackChallenge = require(ServerScriptService.Server.Core.HackChallenge)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

return function(t: any)
	t.describe("Calibration Pulses", function()
		t.it("publishes the arc but never the judging window", function()
			local check = HackChallenge.new("Timing", 9, 10, 2, 0)
			local public = HackChallenge.public(check)
			t.expect(public.nonce).toBe(9)
			t.expect(public.arcWidth).toBe(check.arcWidth)
			t.expect(public.opensAt).toBeNil()
			t.expect(public.closesAt).toBeNil()
			t.expect(check.startAt).toBeNear(10 + SurvivalConfig.Calibration.Warning)
		end)

		t.it("grades Great at the leading edge, Good later, and Miss outside the arc", function()
			local great = HackChallenge.new("Timing", 1, 0, 1, 0)
			t.expect(select(3, HackChallenge.respond(great, 1, great.opensAt + 0.001, great.opensAt + 0.01)))
				.toBe("Great")
			local good = HackChallenge.new("Timing", 2, 0, 1, 0)
			local late = good.greatUntil + (good.closesAt - good.greatUntil) / 2
			t.expect(select(3, HackChallenge.respond(good, 2, late, late))).toBe("Good")
			local miss = HackChallenge.new("Timing", 3, 0, 1, 0)
			local ok, code, grade = HackChallenge.respond(miss, 3, miss.opensAt - 0.05, miss.opensAt - 0.05)
			t.expect(ok).toBe(false)
			t.expect(code).toBe("ChallengeFailed")
			t.expect(grade).toBe("Miss")
		end)

		t.it("rejects wrong nonces, replays and presses after expiry", function()
			local check = HackChallenge.new("Cipher", 4, 0, 3, 1)
			t.expect(select(2, HackChallenge.respond(check, 5, check.opensAt, check.opensAt))).toBe("StaleRequest")
			t.expect((HackChallenge.respond(check, 4, check.opensAt, check.opensAt))).toBe(true)
			t.expect(select(2, HackChallenge.respond(check, 4, check.opensAt, check.opensAt))).toBe("StaleRequest")
			local stale = HackChallenge.new("Cipher", 6, 0, 3, 1)
			local after = stale.expiresAt + SurvivalConfig.Calibration.LatencyAllowance + 0.01
			t.expect(HackChallenge.isExpired(stale, after)).toBe(true)
			t.expect(select(2, HackChallenge.respond(stale, 6, stale.opensAt, after))).toBe("StaleRequest")
		end)

		t.it("forgives bounded latency but never trusts rewound or future press times", function()
			local honest = HackChallenge.new("Timing", 7, 0, 1, 0)
			local arrival = honest.closesAt + 0.1
			t.expect(select(3, HackChallenge.respond(honest, 7, honest.opensAt + 0.001, arrival))).toBe("Great")
			local rewound = HackChallenge.new("Timing", 8, 0, 1, 0)
			t.expect(select(3, HackChallenge.respond(rewound, 8, rewound.opensAt, rewound.closesAt + 1))).toBe("Miss")
			local future = HackChallenge.new("Timing", 9, 0, 1, 0)
			local early = future.opensAt - 0.2
			t.expect(select(3, HackChallenge.respond(future, 9, future.opensAt + 0.01, early))).toBe("Miss")
		end)

		t.it("shrinks the arc with breached terminals down to the minimum, scaled by flavour", function()
			local config = SurvivalConfig.Calibration
			t.expect(HackChallenge.arcWidth("Timing", 0)).toBe(config.BaseArc)
			t.expect(HackChallenge.arcWidth("Timing", 2)).toBe(config.BaseArc - 2 * config.ArcShrinkPerTerminal)
			t.expect(HackChallenge.arcWidth("Timing", 99)).toBe(config.MinArc)
			t.expect(HackChallenge.arcWidth("Sequence", 0)).toBeGreaterThan(HackChallenge.arcWidth("Cipher", 0))
			t.expect(HackChallenge.new("Unknown", 1, 0, 1, 0).mode).toBe("Timing")
		end)
	end)
end
