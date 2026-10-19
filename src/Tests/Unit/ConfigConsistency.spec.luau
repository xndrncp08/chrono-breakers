--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local ServerConfig = require(game:GetService("ServerScriptService").Server.ServerConfig)
local RoleConfig = require(ReplicatedStorage.Shared.Config.RoleConfig)
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)

return function(t: any)
	t.describe("Configuration consistency", function()
		t.it("registers every remote exactly once and names match the registry keys", function()
			local seen: { [string]: boolean } = {}
			for _, spec in RemoteNames.Specs do
				t.expect(seen[spec.Name]).toBeNil()
				seen[spec.Name] = true
				if spec.Direction == "ClientToServer" then
					t.expect((ServerConfig.RateLimits :: any)[spec.Name] ~= nil).toBe(true)
				end
				t.expect((RemoteNames :: any)[spec.Name]).toBe(spec.Name)
			end
		end)

		t.it("has a player-facing message for every rejection code", function()
			for code in Protocol.Codes :: any do
				if code ~= "Ok" then
					t.expect(Protocol.CodeMessages[code] ~= nil).toBe(true)
				end
			end
		end)

		t.it("keeps the design-contract defaults from the brief", function()
			t.expect(GameConfig.MatchDuration).toBe(600)
			t.expect(GameConfig.ExtractionWindow).toBe(60)
			t.expect(GameConfig.MaxPlayers).toBe(5)
			t.expect(TerminalConfig.RequiredHacks).toBe(3)
			t.expect(TerminalConfig.HackDuration).toBe(15)
			t.expect(TerminalConfig.MaxInteractionDistance).toBe(12)
			t.expect(TerminalConfig.PromptActivationDistance <= TerminalConfig.MaxInteractionDistance).toBe(true)
			local freeze = AbilityConfig.Abilities.TimeFreeze
			t.expect(freeze.Duration).toBe(10)
			t.expect(freeze.Radius * 2).toBe(30)
			t.expect(freeze.SlowMagnitude).toBe(0.7)
		end)

		t.it("gives every role ability a definition with the matching role", function()
			for roleId, role in RoleConfig.Roles :: any do
				for _, abilityId in role.Abilities do
					local definition = AbilityConfig.get(abilityId)
					t.expect(definition ~= nil).toBe(true)
					t.expect((definition :: any).Role).toBe(roleId)
				end
			end
		end)

		t.it("keeps Keeper bindings distinct and leaves X free for portal prompts", function()
			local keys: { [string]: boolean } = {}
			for _, id in AbilityConfig.KeeperAbilityOrder do
				local definition = AbilityConfig.get(id)
				assert(definition, "missing ability")
				t.expect(keys[definition.GamepadKey]).toBeNil()
				t.expect(definition.GamepadKey == "ButtonX").toBe(false)
				keys[definition.GamepadKey] = true
			end
		end)

		t.it("links every gadget item to an Infiltrator ability and owns the defaults", function()
			for _, item in ItemConfig.list() do
				if item.Slot == "Gadget" then
					local ability = AbilityConfig.get(item.AbilityId :: string)
					t.expect(ability ~= nil).toBe(true)
					t.expect((ability :: any).Role).toBe("Infiltrator")
				elseif item.Slot == "Trail" then
					t.expect(item.Color ~= nil).toBe(true)
				end
				t.expect(item.Cost >= 0).toBe(true)
			end
			for slot, itemId in ItemConfig.DefaultEquipped :: any do
				local item = ItemConfig.get(itemId)
				t.expect(item ~= nil).toBe(true)
				t.expect((item :: any).Slot).toBe(slot)
				t.expect((item :: any).DefaultOwned).toBe(true)
			end
		end)
	end)
end
