--!strict
-- StateSync: the single place server->client payloads are ingested into ClientState. Payloads are
-- treated as untrusted shapes (type-checked) even though they come from our server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local ClientState = require(script.Parent.ClientState)
local Net = require(script.Parent.Net)

local StateSync = {}

local player = Players.LocalPlayer

local function mergeTerminals(snapshot: any)
	local terminals = table.clone(ClientState.get("terminals") or {})
	local seen: { [string]: boolean } = {}
	for _, terminal in snapshot.terminals do
		terminals[terminal.id] = terminal
		seen[terminal.id] = true
	end
	for id in terminals do
		if not seen[id] then
			terminals[id] = nil
		end
	end
	ClientState.set("terminals", terminals)
end

function StateSync.Start(deps: { [string]: any })
	local lastVersion = -1
	local lastMatchId: string? = nil

	Net.on(RemoteNames.MatchState, function(snapshot: any)
		if type(snapshot) ~= "table" or type(snapshot.phase) ~= "string" then
			return
		end
		if snapshot.matchId ~= lastMatchId then
			lastMatchId = snapshot.matchId
			lastVersion = -1
			-- New match (or back to lobby): forget per-match client state.
			ClientState.set("abilities", {})
			ClientState.set("extraction", 0)
		end
		if type(snapshot.version) == "number" and snapshot.version < lastVersion then
			return -- stale snapshot
		end
		lastVersion = snapshot.version or lastVersion
		ClientState.set("snapshot", snapshot)
		mergeTerminals(snapshot)
	end)

	Net.on(RemoteNames.TerminalUpdate, function(payload: any)
		if type(payload) ~= "table" or type(payload.terminal) ~= "table" then
			return
		end
		local snapshot = ClientState.get("snapshot")
		if snapshot and payload.matchId ~= snapshot.matchId then
			return
		end
		local terminals = table.clone(ClientState.get("terminals") or {})
		terminals[payload.terminal.id] = payload.terminal
		ClientState.set("terminals", terminals)
	end)

	Net.on(RemoteNames.RoleAssigned, function(payload: any)
		if type(payload) == "table" and type(payload.role) == "string" then
			ClientState.set("role", payload)
		end
	end)

	Net.on(RemoteNames.QueueState, function(payload: any)
		if type(payload) == "table" then
			ClientState.set("queue", payload)
		end
	end)

	Net.on(RemoteNames.ProfileSnapshot, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		ClientState.set("profile", payload)
		if type(payload.settings) == "table" then
			ClientState.set("settings", table.clone(payload.settings))
		end
	end)

	Net.on(RemoteNames.AbilityState, function(payload: any)
		if type(payload) ~= "table" or type(payload.abilities) ~= "table" then
			return
		end
		local snapshot = ClientState.get("snapshot")
		if snapshot and payload.matchId ~= snapshot.matchId then
			return
		end
		local map = {}
		for _, state in payload.abilities do
			if type(state) == "table" and type(state.abilityId) == "string" then
				map[state.abilityId] = state
			end
		end
		ClientState.set("abilities", map)
	end)

	Net.on(RemoteNames.StatusUpdate, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "Movement" then
			ClientState.set("movement", payload)
		elseif payload.kind == "Extraction" and type(payload.progress) == "number" then
			local snapshot = ClientState.get("snapshot")
			if snapshot and payload.matchId ~= snapshot.matchId then
				return
			end
			ClientState.set("extraction", payload.progress)
		end
	end)

	Net.on(RemoteNames.MatchResult, function(payload: any)
		if type(payload) == "table" and type(payload.matchId) == "string" then
			ClientState.set("result", payload)
		end
	end)

	Net.on(RemoteNames.Notify, function(payload: any)
		deps.UIController.HandleNotify(payload)
	end)

	Net.on(RemoteNames.ActionResult, function(payload: any)
		deps.UIController.HandleActionResult(payload)
	end)

	player.CharacterAdded:Connect(function()
		ClientState.set("extraction", 0)
	end)
end

return StateSync
