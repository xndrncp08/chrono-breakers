--!strict
-- CoachController: the Field Guide. Watches client state for first-time moments and shows the
-- matching CoachConfig tip once per match, while the player is still in their guided matches for
-- the current role and control hints are enabled. Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CoachConfig = require(ReplicatedStorage.Shared.Config.CoachConfig)

local ClientState = require(script.Parent.Parent.ClientState)

local CoachController = {}

local player = Players.LocalPlayer
local deps: { [string]: any } = {}
local matchId: string? = nil
local shown: { [string]: boolean } = {}
local queue: { CoachConfig.Tip } = {}
local lastShownAt = -math.huge

local function guidedRole(): string?
	local role = ClientState.currentRole()
	local profile = ClientState.get("profile")
	local settings = ClientState.get("settings")
	if not role or not profile or not ClientState.isLiveParticipant() then
		return nil
	end
	if settings and settings.ShowControlHints == false then
		return nil
	end
	return if CoachConfig.isGuided(profile.stats, role.role) then role.role else nil
end

local function flush()
	if #queue == 0 or os.clock() - lastShownAt < CoachConfig.Gap then
		return
	end
	lastShownAt = os.clock()
	deps.UIController.Coach(table.remove(queue, 1))
end

local function offer(id: string)
	if shown[id] then
		return
	end
	local role = guidedRole()
	local tip = CoachConfig.tip(role, id)
	if not tip then
		return
	end
	shown[id] = true
	if #queue < 3 then
		table.insert(queue, tip)
	end
	flush()
end

local function onSnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	if snapshot.matchId ~= matchId then
		matchId = snapshot.matchId
		table.clear(shown)
		table.clear(queue)
	end
	local phase = snapshot.phase
	if phase == "Active" then
		offer("Start")
	elseif phase == "Extraction" then
		offer("Collapse")
	elseif phase ~= "Intro" then
		table.clear(queue)
		return
	end
	local role = ClientState.currentRole()
	for _, p in snapshot.participants or {} do
		if p.role ~= "Infiltrator" or p.status ~= "Active" then
			continue
		end
		if p.userId == player.UserId then
			if p.condition == "Injured" then
				offer("Injured")
			elseif p.condition == "Downed" then
				offer("Downed")
			end
		elseif role and role.role == "Infiltrator" and p.condition == "Contained" then
			offer("AllyPod")
		elseif role and role.role == "TimeKeeper" then
			if p.condition == "Downed" then
				offer("Downed")
			elseif p.condition == "Contained" then
				offer("Contained")
			end
		end
	end
end

function CoachController.Init(injected: { [string]: any })
	deps = injected
end

function CoachController.Start()
	ClientState.changed:Connect(function(key: string, value: any)
		if key == "snapshot" then
			onSnapshot(value)
		elseif key == "calibration" and value ~= nil then
			offer("Calibration")
		elseif key == "resonance" and type(value) == "number" and value > 0.4 then
			offer("Resonance")
		elseif key == "chased" and value == true then
			offer("Chased")
		elseif key == "huntTargets" and type(value) == "table" and #value > 0 then
			offer("Chase")
		elseif key == "keeperStunnedAt" then
			offer("Stunned")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			flush()
		end
	end)
end

return CoachController
