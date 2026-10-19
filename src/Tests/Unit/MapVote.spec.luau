--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local MapVote = require(ServerScriptService.Server.Core.MapVote)
return function(t: any)
	t.it("replaces votes, rejects unknown maps and counts selected participants only", function()
		local votes: { [number]: string } = {}
		t.expect(MapVote.cast(votes, 1, "Vault")).toBe(true)
		t.expect(MapVote.cast(votes, 1, "Nexus")).toBe(true)
		t.expect(MapVote.cast(votes, 2, "Forged")).toBe(false)
		MapVote.cast(votes, 99, "Vault")
		t.expect(MapVote.select(votes, { 1, 2 }, 0)).toBe("Nexus")
	end)
	t.it("rotates zero-vote maps and ties deterministically", function()
		t.expect(MapVote.select({}, { 1, 2 }, 0)).toBe("Vault")
		t.expect(MapVote.select({}, { 1, 2 }, 1)).toBe("Metropolis")
		t.expect(MapVote.select({ [1] = "Vault", [2] = "Nexus" }, { 1, 2 }, 3)).toBe("Nexus")
	end)
end
