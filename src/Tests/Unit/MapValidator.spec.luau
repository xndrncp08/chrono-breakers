--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TerminalConfig = require(ReplicatedStorage.Shared.Config.TerminalConfig)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)
local MapLayout = require(ServerScriptService.Server.World.MapLayout)
local MapValidator = require(ServerScriptService.Server.World.MapValidator)

return function(t: any)
	t.describe("MapValidator", function()
		t.it("the authored Chronos Vault satisfies the map contract", function()
			local errors = MapValidator.validate(MapLayout.Vault, TerminalConfig.RequiredHacks)
			if #errors > 0 then
				error(table.concat(errors, "\n"))
			end
		end)

		t.it("validates every registered authored map", function()
			for id, map in MapLayout.Maps do
				local errors = MapValidator.validate(map, TerminalConfig.RequiredHacks)
				assert(#errors == 0, id .. ": " .. table.concat(errors, "; "))
				t.expect(#map.infiltratorSpawns).toBe(4)
			end
		end)

		t.it("keeps a route to every objective around any temporary fracture", function()
			for id, original in MapLayout.Maps do
				for _, site in original.anomalySites do
					local map = TableUtil.deepCopy(original)
					table.insert(map.boxes, {
						name = "Fracture",
						kind = "Wall",
						center = site + Vector3.new(0, 6, 0),
						size = Vector3.new(14, 12, 1),
						color = "Danger",
						material = "ForceField",
						collide = true,
					})
					local reachable = MapValidator.buildGrid(map, true).reachableFrom(map.infiltratorSpawns[1])
					for _, terminal in map.terminals do
						assert(reachable(MapValidator.interactionPoint(terminal)), id .. " fractured route blocked")
					end
					assert(reachable(map.extractionCenter), id .. " fracture blocked extraction")
				end
			end
		end)

		t.it("has exactly three distinct terminals", function()
			t.expect(#MapLayout.Vault.terminals).toBe(3)
		end)

		t.it("detects an objective sealed off by geometry", function()
			local map = TableUtil.deepCopy(MapLayout.Vault)
			local terminal = map.terminals[1]
			local point = MapValidator.interactionPoint(terminal)
			-- Box the terminal in completely.
			table.insert(map.boxes, {
				name = "Seal",
				kind = "Wall",
				center = Vector3.new(point.X, 10, point.Z + 4),
				size = Vector3.new(30, 20, 2),
				color = "Wall",
				material = "SmoothPlastic",
				collide = true,
			})
			table.insert(map.boxes, {
				name = "SealW",
				kind = "Wall",
				center = Vector3.new(point.X - 15, 10, point.Z - 5),
				size = Vector3.new(2, 20, 20),
				color = "Wall",
				material = "SmoothPlastic",
				collide = true,
			})
			table.insert(map.boxes, {
				name = "SealE",
				kind = "Wall",
				center = Vector3.new(point.X + 15, 10, point.Z - 5),
				size = Vector3.new(2, 20, 20),
				color = "Wall",
				material = "SmoothPlastic",
				collide = true,
			})
			local errors = MapValidator.validate(map, 3)
			local found = false
			for _, message in errors do
				if string.find(message, "not reachable", 1, true) then
					found = true
				end
			end
			t.expect(found).toBe(true)
		end)

		t.it("detects spawns inside walls and out-of-bounds objectives", function()
			local map = TableUtil.deepCopy(MapLayout.Vault)
			map.infiltratorSpawns[2] = Vector3.new(0, 3, 0) -- inside the Chrono Core
			map.terminals[2].position = Vector3.new(500, 2.5, 0)
			local errors = MapValidator.validate(map, 3)
			t.expect(#errors).toBeGreaterThan(1)
		end)

		t.it("detects too few terminals and duplicate ids", function()
			local map = TableUtil.deepCopy(MapLayout.Vault)
			map.terminals[2].id = map.terminals[1].id
			t.expect(#MapValidator.validate(map, 3)).toBeGreaterThan(0)
			t.expect(#MapValidator.validate(MapLayout.Vault, 4)).toBeGreaterThan(0)
		end)
	end)
end
