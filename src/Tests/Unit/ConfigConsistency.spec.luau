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
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)

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
			t.expect(GameConfig.ExtractionWindow).toBe(SurvivalConfig.Endgame.CollapseDuration)
			t.expect(GameConfig.MaxPlayers).toBe(5)
			t.expect(TerminalConfig.RequiredHacks).toBe(4)
			t.expect(TerminalConfig.HackDuration).toBe(40)
			t.expect(TerminalConfig.MaxInteractionDistance).toBe(12)
			t.expect(TerminalConfig.PromptActivationDistance <= TerminalConfig.MaxInteractionDistance).toBe(true)
			local freeze = AbilityConfig.Abilities.TimeFreeze
			t.expect(freeze.Duration).toBe(10)
			t.expect(freeze.Radius * 2).toBe(30)
			t.expect(freeze.SlowMagnitude).toBe(0.7)
		end)

		t.it("keeps the pursuit speed ladder fair: Keeper > runner, sprinter > Keeper, crawl is slow", function()
			local keeper = RoleConfig.Roles.TimeKeeper.WalkSpeed
			local sprint = 1 + SurvivalConfig.Stamina.SprintHaste
			for id, class in ClassConfig.Classes do
				assert(keeper > class.WalkSpeed * 1.08, id .. " outruns the Keeper without sprinting")
				assert(class.WalkSpeed * sprint > keeper, id .. " cannot gain ground while sprinting")
				assert(class.WalkSpeed * (1 - SurvivalConfig.Integrity.CrawlSlow) < 4, id .. " crawls too fast")
			end
			-- Even full Hunt Momentum never makes an Infiltrator's sprint pointless.
			t.expect(keeper * (1 + SurvivalConfig.Chase.MomentumMax) < 15 * sprint + 0.5).toBe(true)
			local scaling = SurvivalConfig.Objectives.SquadScaling
			t.expect(#scaling).toBe(4)
			for i = 2, #scaling do
				t.expect(scaling[i] > scaling[i - 1]).toBe(true)
			end
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
