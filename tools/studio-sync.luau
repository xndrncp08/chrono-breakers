-- Run through the Studio MCP `run_luau` tool (edit peer) while tools/studio-sync.py is serving.
-- Replaces the Source of every mapped script that differs from the file on disk.
local Http = game:GetService("HttpService")
local base = "http://127.0.0.1:34999/"
local manifest = Http:JSONDecode(Http:GetAsync(base .. "manifest.json"))
local changed, missing, same = {}, {}, 0
for _, e in manifest do
	local inst: Instance? = game
	for _, name in e.path do
		inst = inst and inst:FindFirstChild(name)
	end
	if not inst or not inst:IsA("LuaSourceContainer") then
		table.insert(missing, e.file)
	else
		local src = Http:GetAsync(base .. "files/" .. e.id .. ".luau")
		if (inst :: any).Source ~= src then
			(inst :: any).Source = src
			table.insert(changed, e.file)
		else
			same += 1
		end
	end
end
return { changed = changed, missing = missing, same = same }
