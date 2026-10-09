--!strict
-- CameraController: spectating for players who are out of the match (eliminated/extracted or simply
-- in the lobby while a match runs). Cycles through living match participants; restores the local
-- character as camera subject when spectating stops or the target disappears.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local CameraController = {}

local player = Players.LocalPlayer

local function candidates(): { number }
	local snapshot = ClientState.get("snapshot")
	local list: { number } = {}
	if not snapshot then
		return list
	end
	for _, p in snapshot.participants do
		if p.status == "Active" and p.userId ~= player.UserId then
			local other = Players:GetPlayerByUserId(p.userId)
			if other and other.Character and other.Character:FindFirstChildOfClass("Humanoid") then
				table.insert(list, p.userId)
			end
		end
	end
	return list
end

local function applySubject()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local target = ClientState.get("spectating")
	if target then
		local other = Players:GetPlayerByUserId(target)
		local humanoid = other and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
			return
		end
	end
	local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if own then
		camera.CameraSubject = own
	end
end

function CameraController.CanSpectate(): boolean
	return #candidates() > 0
end

function CameraController.Cycle(step: number)
	local list = candidates()
	if #list == 0 then
		CameraController.Stop()
		return
	end
	local current = ClientState.get("spectating")
	local index = if current then table.find(list, current) else nil
	local nextIndex = if index then ((index - 1 + step) % #list) + 1 else 1
	ClientState.set("spectating", list[nextIndex])
	applySubject()
end

function CameraController.Stop()
	if ClientState.get("spectating") ~= nil then
		ClientState.set("spectating", nil)
	end
	applySubject()
end

function CameraController.Init()
	player.CharacterAdded:Connect(function()
		task.defer(applySubject)
	end)
	ClientState.changed:Connect(function(key: string)
		if key == "snapshot" then
			local target = ClientState.get("spectating")
			if target and not table.find(candidates(), target) then
				-- Target was eliminated/extracted/left: move on or stop.
				if CameraController.CanSpectate() then
					CameraController.Cycle(1)
				else
					CameraController.Stop()
				end
			end
		end
	end)
end

return CameraController
