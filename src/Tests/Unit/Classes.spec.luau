--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local AbilityRules = require(ServerScriptService.Server.Core.AbilityRules)
local ProfileSchema = require(ServerScriptService.Server.Core.ProfileSchema)
local Economy = require(ServerScriptService.Server.Core.Economy)
return function(t: any)
	t.it("gives every class a free equip and distinct skill, with bounded trade-offs", function()
		local profile = ProfileSchema.defaults()
		local skills: { [string]: boolean } = {}
		for _, id in ClassConfig.Order do
			local class = ClassConfig.get(id) :: ClassConfig.Definition
			t.expect(profile.OwnedItems[id]).toBe(true)
			t.expect((Economy.equip(profile, id))).toBe(true)
			t.expect(profile.Equipped.Class).toBe(id)
			t.expect(skills[class.AbilityId]).toBeNil()
			skills[class.AbilityId] = true
			t.expect((AbilityConfig.get(class.AbilityId) :: any).Role).toBe("Infiltrator")
			t.expect(class.MaxHealth <= 100 and class.WalkSpeed <= 17 and class.HackSpeed <= 1.15).toBe(true)
		end
	end)
	t.it("rejects other class skills while allowing the locked class and gadget", function()
		local context: any = {
			abilityId = "Mend",
			phase = "Active",
			role = "Infiltrator",
			participantActive = true,
			alive = true,
			restrained = false,
			cooldownReady = true,
			equippedGadget = "Stabilizer",
			classAbility = "Veil",
		}
		t.expect(select(2, AbilityRules.checkCaster(context))).toBe("NotOwned")
		context.abilityId = "Veil"
		t.expect((AbilityRules.checkCaster(context))).toBe(true)
		context.abilityId = "Stabilizer"
		t.expect((AbilityRules.checkCaster(context))).toBe(true)
		context.currentMatchId = "new"
		context.matchId = "old"
		t.expect(select(2, AbilityRules.checkCaster(context))).toBe("StaleRequest")
		context.matchId = "new"
		context.cooldownReady = false
		t.expect(select(2, AbilityRules.checkCaster(context))).toBe("OnCooldown")
	end)
end
