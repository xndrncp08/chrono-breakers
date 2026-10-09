--!strict
-- Client network wrapper. Waits for the server-created remotes (never creates them), exposes typed-ish
-- helpers, and reports readiness so the UI can show connecting/error states.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local Net = {}

local remotes: { [string]: RemoteEvent } = {}
local ready = false

-- Yields until every registered remote exists, or the timeout elapses. Returns success.
function Net.waitForRemotes(timeout: number): boolean
	local deadline = os.clock() + timeout
	local folder = ReplicatedStorage:WaitForChild(RemoteNames.FolderName, timeout)
	if not folder then
		return false
	end
	for _, spec in RemoteNames.Specs do
		local remaining = math.max(0.1, deadline - os.clock())
		local remote = folder:WaitForChild(spec.Name, remaining)
		if not remote or not remote:IsA("RemoteEvent") then
			return false
		end
		remotes[spec.Name] = remote :: RemoteEvent
	end
	ready = true
	return true
end

function Net.isReady(): boolean
	return ready
end

function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local remote = remotes[name]
	assert(remote, `Net.on: remote {name} not ready`)
	return remote.OnClientEvent:Connect(handler)
end

function Net.send(name: string, ...: any)
	local remote = remotes[name]
	if remote then
		remote:FireServer(...)
	end
end

return Net
