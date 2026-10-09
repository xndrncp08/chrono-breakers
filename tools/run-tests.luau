-- Lune test runner. Usage (from repo root):  lune run tools/run-tests.luau [build/test.rbxl] [filter]
-- Loads the Rojo-built test place, then executes ModuleScripts from their real instance tree with a
-- minimal Roblox-like environment (script, require, game, task, Roblox datatypes). Only pure modules
-- (no engine services beyond GetService lookups) can be exercised this way; see docs/TEST_PLAN.md.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/test.rbxl"
local filter = process.args[2]

local game = roblox.deserializePlace(fs.readFile(placePath))
local moduleCache: { [any]: any } = {}
local loading: { [any]: boolean } = {}

local baseEnv = {
	game = game,
	task = task,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	warn = function(...)
		-- Keep test output readable; warnings are expected in negative-path tests.
		if process.env.TEST_VERBOSE then
			print("[warn]", ...)
		end
	end,
}

local requireModule
function requireModule(moduleScript: any): any
	if typeof(moduleScript) ~= "Instance" or not moduleScript:IsA("ModuleScript") then
		error("require expects a ModuleScript instance, got " .. tostring(moduleScript), 2)
	end
	if moduleCache[moduleScript] ~= nil then
		return moduleCache[moduleScript]
	end
	if loading[moduleScript] then
		error("circular require: " .. moduleScript:GetFullName(), 2)
	end
	loading[moduleScript] = true
	-- Lune copies the environment's raw keys (metatables are ignored), so build a flat table.
	local env = { script = moduleScript, require = requireModule }
	for key, value in baseEnv do
		env[key] = value
	end
	local chunk = luau.load(moduleScript.Source, {
		debugName = moduleScript:GetFullName(),
		environment = env,
	})
	local result = chunk()
	loading[moduleScript] = nil
	moduleCache[moduleScript] = result
	return result
end

local tests = game:GetService("ServerScriptService"):FindFirstChild("Tests")
assert(tests, "Tests folder missing; build with test.project.json")
local TestKit = requireModule(tests.TestKit)

local specs = {}
for _, folderName in { "Unit", "Integration" } do
	local folder = tests:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				local name = folderName .. "/" .. child.Name
				if filter == nil or string.find(name, filter, 1, true) then
					table.insert(specs, { name = name, spec = requireModule(child) })
				end
			end
		end
	end
end
table.sort(specs, function(a, b)
	return a.name < b.name
end)

print(string.format("Running %d spec modules from %s", #specs, placePath))
local report = TestKit.run(specs, print)
print(string.format("\n%d passed, %d failed", report.passed, report.failed))
process.exit(if report.failed > 0 then 1 else 0)
