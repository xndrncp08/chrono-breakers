-- Verify the actual production artifact, independently of the source project configuration.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local path = process.args[1] or "build/game.rbxl"
local bytes = fs.readFile(path)
local place = roblox.deserializePlace(bytes)
local server = place:GetService("ServerScriptService")
assert(not server:FindFirstChild("Tests"), "production contains Tests")
assert(server.LoadStringEnabled == false, "production enables LoadStringEnabled")
local starter = place:GetService("StarterPlayer").StarterPlayerScripts
assert(not starter:FindFirstChild("E2EClient"), "production contains E2EClient")
assert(server.Server.Services:FindFirstChild("AnomalyService"), "anomaly service missing from production")
local count = 0
for _, instance in place:GetDescendants() do
	if instance:IsA("LuaSourceContainer") then
		assert(not string.find(instance.Name, "E2E", 1, true), "test script in production: " .. instance:GetFullName())
		luau.load(instance.Source, { debugName = instance:GetFullName() })
		count += 1
	end
end
assert(count > 0, "production has no scripts")
print(
	`Production artifact verified: {count} scripts compile; test code absent; LoadStringEnabled=false; {#bytes} bytes`
)
