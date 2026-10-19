--!strict
-- PursuitController: client-side pursuit presentation. Nothing here is authoritative; it reads
-- replicated character positions and server chase state and turns them into fear and information.
--   * Temporal Resonance: within SurvivalConfig.Chase.ResonanceRadius of the Keeper an Infiltrator
--     hears a heartbeat that quickens and sees a vignette/grade that deepens with proximity.
--   * Dynamic music intensity: terror (Resonance), chase (server says you are pursued), collapse.
--   * Keeper tracking: running Infiltrators leave short-lived temporal residue only the Keeper sees;
--     Fractured Infiltrators spark and groan (spatial) for everyone.
--   * Chase distortion: colour grade and a gentle FOV push while pursued (off with ReducedMotion).

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.ClientState)

local PursuitController = {}

local player = Players.LocalPlayer
local deps: { [string]: any } = {}
local grade: ColorCorrectionEffect? = nil
local residueFolder: Folder? = nil
local nextBeatAt = 0
local residueAt = 0
local groanAt: { [number]: number } = {}
local sparkAt: { [number]: number } = {}
local baseFov = 70
local MAX_RESIDUE = 120

local function reducedMotion(): boolean
	local settings = ClientState.get("settings")
	return settings ~= nil and settings.ReducedMotion == true
end

local function rootOf(userId: number): BasePart?
	local other = Players:GetPlayerByUserId(userId)
	local character = other and other.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function participants(): { any }
	local snapshot = ClientState.get("snapshot")
	return if snapshot then snapshot.participants else {}
end

local function keeperRoot(): BasePart?
	for _, p in participants() do
		if p.role == "TimeKeeper" and p.status == "Active" then
			return rootOf(p.userId)
		end
	end
	return nil
end

local function computeResonance(): number
	local role = ClientState.currentRole()
	if not role or role.role ~= "Infiltrator" or not ClientState.isLiveParticipant() then
		return 0
	end
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local keeper = keeperRoot()
	if not mine or not keeper then
		return 0
	end
	local class = ClassConfig.get(role.classId)
	local radius = SurvivalConfig.Chase.ResonanceRadius * (if class and class.Quiet then 1.25 else 1)
	local distance = (keeper.Position - mine.Position).Magnitude
	local raw = math.clamp(1 - distance / radius, 0, 1)
	return raw * raw * (3 - 2 * raw) -- smoothstep: gentle at the edge, urgent up close
end

local function heartbeat(resonance: number)
	local now = os.clock()
	if resonance <= 0.01 or now < nextBeatAt then
		return
	end
	local interval = 1.15 - 0.79 * resonance
	nextBeatAt = now + interval
	local audio = deps.AudioController
	audio.Play("Heartbeat", { volume = 0.35 + 0.65 * resonance })
	task.delay(0.16, function()
		audio.Play("HeartbeatSoft", { volume = 0.3 + 0.6 * resonance })
	end)
	ClientState.set("lastHeartbeat", now)
end

local function spawnResidue(position: Vector3, color: Color3)
	local folder = residueFolder :: Folder
	if #folder:GetChildren() >= MAX_RESIDUE then
		return
	end
	local mark = Instance.new("Part")
	mark.Name = "Residue"
	mark.Anchored, mark.CanCollide, mark.CanQuery, mark.CanTouch = true, false, false, false
	mark.CastShadow = false
	mark.Material = Enum.Material.Neon
	mark.Color = color
	mark.Size = Vector3.new(0.6 + math.random() * 0.8, 0.05, 0.2)
	mark.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 1.2, 0.06, (math.random() - 0.5) * 1.2))
		* CFrame.Angles(0, math.random() * math.pi, 0)
	mark.Transparency = 0.2
	mark.Parent = folder
	TweenService:Create(mark, TweenInfo.new(3.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		:Play()
	Debris:AddItem(mark, 3.6)
end

local function spark(position: Vector3)
	local folder = residueFolder :: Folder
	local fleck = Instance.new("Part")
	fleck.Name = "Spark"
	fleck.Anchored, fleck.CanCollide, fleck.CanQuery, fleck.CanTouch = true, false, false, false
	fleck.CastShadow = false
	fleck.Material = Enum.Material.Neon
	fleck.Color = Theme.ConditionColors.Injured
	fleck.Size = Vector3.new(0.25, 0.25, 0.25)
	fleck.Position = position
		+ Vector3.new((math.random() - 0.5) * 1.5, math.random() * 1.5, (math.random() - 0.5) * 1.5)
	fleck.Parent = folder
	TweenService:Create(fleck, TweenInfo.new(0.9), {
		Transparency = 1,
		Position = fleck.Position - Vector3.new(0, 2, 0),
	}):Play()
	Debris:AddItem(fleck, 1)
end

-- Keeper-only residue and everyone's Fractured cues, at ~6 Hz.
local function trackingCues(now: number)
	local role = ClientState.currentRole()
	local live = ClientState.isLiveParticipant()
	for _, p in participants() do
		if p.role ~= "Infiltrator" or p.status ~= "Active" or p.userId == player.UserId then
			continue
		end
		local root = rootOf(p.userId)
		local character = root and root.Parent
		if not root or not character or character:GetAttribute("Hidden") or character:GetAttribute("ChronoCloaked") then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local class = ClassConfig.get(p.classId)
		local threshold = if class and class.Quiet then 17 else 12
		if role and role.role == "TimeKeeper" and live and speed > threshold then
			spawnResidue(root.Position - Vector3.new(0, 2.9, 0), Theme.Colors.Temporal)
		end
		if p.condition == "Injured" then
			if now >= (sparkAt[p.userId] or 0) then
				sparkAt[p.userId] = now + 0.9 + math.random() * 0.5
				spark(root.Position)
			end
			if now >= (groanAt[p.userId] or 0) then
				groanAt[p.userId] = now + 4 + math.random() * 3
				deps.AudioController.Play("Groan", { position = root.Position, range = 60 })
			end
		end
	end
end

local function updateGrade(resonance: number, chased: boolean, dt: number)
	local g = grade :: ColorCorrectionEffect
	local camera = Workspace.CurrentCamera
	if reducedMotion() then
		g.Saturation, g.Contrast, g.TintColor = 0, 0, Color3.new(1, 1, 1)
		if camera then
			camera.FieldOfView = baseFov
		end
		return
	end
	local intensity = math.max(resonance * 0.7, if chased then 1 else 0)
	local alpha = math.clamp(dt * 3, 0, 1)
	g.Saturation += (-0.35 * intensity - g.Saturation) * alpha
	g.Contrast += (0.18 * intensity - g.Contrast) * alpha
	g.TintColor = g.TintColor:Lerp(Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 205, 215), intensity), alpha)
	if camera and ClientState.get("spectating") == nil then
		local wanted = baseFov + (if chased then 6 else 0)
		camera.FieldOfView += (wanted - camera.FieldOfView) * alpha
	end
end

local function updateMusic(resonance: number, chased: boolean)
	local audio = deps.AudioController
	local snapshot = ClientState.get("snapshot")
	local role = ClientState.currentRole()
	local live = ClientState.isLiveParticipant()
	local collapse = live and snapshot ~= nil and snapshot.phase == "Extraction"
	local keeperChasing = role ~= nil and role.role == "TimeKeeper" and #(ClientState.get("huntTargets") or {}) > 0
	local chasing = chased or keeperChasing
	audio.SetMusicIntensity("LobbyMusic", if live then 0 else 1)
	audio.SetMusicIntensity("MatchMusic", if live and not chasing and resonance < 0.3 then 0.6 else 0)
	audio.SetMusicIntensity("TerrorMusic", if live and not chasing then resonance else 0)
	audio.SetMusicIntensity("ChaseMusic", if chasing then 1 else 0)
	audio.SetMusicIntensity("CollapseMusic", if collapse and not chasing then 0.8 else 0)
end

function PursuitController.Init(injected: { [string]: any })
	deps = injected
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ChronoResonanceGrade"
	cc.Parent = Lighting
	grade = cc
	local folder = Instance.new("Folder")
	folder.Name = "ChronoResidue"
	folder.Parent = Workspace
	residueFolder = folder
end

function PursuitController.Start()
	local camera = Workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
	end
	ClientState.changed:Connect(function(key: string, value: any)
		if key == "chased" and value == true then
			deps.UIController.Toast("You're being pursued!", "Danger", 1.5)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local resonance = computeResonance()
		if math.abs(resonance - (ClientState.get("resonance") or 0)) > 0.02 then
			ClientState.set("resonance", resonance)
		end
		local chased = ClientState.get("chased") == true
		heartbeat(math.max(resonance, if chased then 0.85 else 0))
		updateGrade(resonance, chased, dt)
		local now = os.clock()
		if now >= residueAt then
			residueAt = now + 0.16
			trackingCues(now)
			updateMusic(resonance, chased)
		end
	end)
end

return PursuitController
