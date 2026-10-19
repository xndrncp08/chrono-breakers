--!strict
-- CameraController: spectating for players who are out of the match (eliminated/extracted or simply
-- in the lobby while a match runs). Cycles through living match participants; restores the local
-- character as camera subject when spectating stops or the target disappears.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Net = require(script.Parent.Parent.Net)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local CameraController = {}

local player = Players.LocalPlayer
local cinematic: Tween? = nil
local cinematicMode: string? = nil
local introSeen: string? = nil
local generation = 0
local function reduced(): boolean
	local settings = ClientState.get("settings")
	return settings ~= nil and settings.ReducedMotion == true
end
local function stopCinematic()
	generation += 1
	if cinematic then
		cinematic:Cancel()
		cinematic = nil
	end
	if cinematicMode then
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		cinematicMode = nil
	end
end
local function playCinematic(mode: string, from: CFrame, to: CFrame, duration: number)
	if reduced() then
		return
	end
	stopCinematic()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	cinematicMode = mode
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = from
	cinematic = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = to }
	)
	local current = cinematic :: Tween
	current:Play()
end

local function candidates(): { number }
	local snapshot = ClientState.get("snapshot")
	local list: { number } = {}
	if not snapshot then
		return list
	end
	local me = ClientState.myParticipant()
	for _, p in snapshot.participants do
		if me and me.role == "Infiltrator" and p.role ~= "Infiltrator" then
			continue
		end
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
	stopCinematic()
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
		if cinematicMode ~= "Intro" then
			stopCinematic()
		end
		task.defer(applySubject)
	end)
	ClientState.changed:Connect(function(key: string)
		if key == "settings" and reduced() then
			stopCinematic()
			applySubject()
		end
		if key == "snapshot" or key == "role" then
			local snapshot = ClientState.get("snapshot")
			local role = ClientState.currentRole()
			if snapshot and role and snapshot.phase == "Intro" and introSeen ~= snapshot.matchId then
				introSeen = snapshot.matchId
				local duration = math.max(0.1, (snapshot.phaseEndsAt or ClientState.now()) - ClientState.now())
				playCinematic(
					"Intro",
					CFrame.lookAt(Vector3.new(95, 65, 110), Vector3.new(0, 4, 0)),
					CFrame.lookAt(Vector3.new(60, 38, 72), Vector3.new(0, 4, 0)),
					duration
				)
			elseif cinematicMode == "Intro" and (not snapshot or snapshot.phase ~= "Intro") then
				stopCinematic()
				applySubject()
			end
			if
				snapshot
				and (snapshot.phase == "Resolving" or snapshot.phase == "ReturningToLobby")
				and cinematicMode == "Extraction"
			then
				stopCinematic()
				applySubject()
			end
		end
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

function CameraController.Start()
	Net.on(RemoteNames.Effect, function(payload: any)
		if type(payload) ~= "table" or payload.kind ~= "PlayerExtracted" or payload.userId ~= player.UserId then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local camera = Workspace.CurrentCamera
		if root and camera then
			playCinematic(
				"Extraction",
				camera.CFrame,
				CFrame.lookAt(root.Position + Vector3.new(12, 10, 12), root.Position),
				0.8
			)
			local token = generation
			task.delay(1.1, function()
				if token == generation then
					stopCinematic()
					applySubject()
				end
			end)
		end
	end)
end

return CameraController
