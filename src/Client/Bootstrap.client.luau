--!strict
-- Client entry point. Order: controllers Init (no network) -> wait for server remotes (with a
-- visible connecting state and a failure state) -> state sync -> controllers Start -> ClientReady,
-- which asks the server for a full state refresh (also used after respawns/late joins).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local ClientState = require(script.Parent.ClientState)
local Net = require(script.Parent.Net)
local StateSync = require(script.Parent.StateSync)

local player = Players.LocalPlayer
if player:GetAttribute("ChronoClientBooted") then
	return
end
player:SetAttribute("ChronoClientBooted", true)

local Controllers = script.Parent.Controllers
local ORDER = {
	"AudioController",
	"InputController",
	"CameraController",
	"UIController",
	"EffectsController",
	"InteractionController",
}

local registry: { [string]: any } = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	if not module then
		error(`[ClientBootstrap] missing controller {name}`)
	end
	registry[name] = (require :: any)(module)
end

for _, name in ORDER do
	local controller = registry[name]
	if type(controller.Init) == "function" then
		controller.Init(registry)
	end
end

if not Net.waitForRemotes(30) then
	ClientState.set("connection", "Failed")
	warn("[ClientBootstrap] server remotes did not appear; is the server bootstrap running?")
	return
end

StateSync.Start(registry)
for _, name in ORDER do
	local controller = registry[name]
	if type(controller.Start) == "function" then
		controller.Start(registry)
	end
end

registry.InputController.SetFeedbackHandler(function(code: string)
	registry.UIController.HandleActionResult({ ok = false, action = "Ability", code = code })
end)

ClientState.set("connection", "Ready")
Net.send(RemoteNames.ClientReady)
