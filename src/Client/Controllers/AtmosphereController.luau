--!strict
-- AtmosphereController: procedural character poses and environmental mood (presentation only).
--   * Poses from replicated character attributes: Desynced bodies lie prone, captives float in
--     their Stasis Pod, vaulters lean into the vault. Implemented by easing the root joint's C0 on
--     this client, so no animation assets are needed and every client sees the same pose.
--   * Light fixtures tagged ChronoFlicker stutter when the Keeper is near (temporal distortion).
--   * The Temporal Collapse thickens the atmosphere tier by tier.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)

local AtmosphereController = {}

type Pose = { motor: Motor6D, original: CFrame }

local poses: { [Motor6D]: Pose } = {}
local lightBase: { [Light]: number } = {}
local baseDensity: number? = nil
local flickerAt = 0

local TIER_DENSITY: { [string]: number } = { Stable = 0.06, Rising = 0.14, Critical = 0.24 }

local function reducedMotion(): boolean
	local settings = ClientState.get("settings")
	return settings ~= nil and settings.ReducedMotion == true
end

local function rootMotor(character: Model): Motor6D?
	local lower = character:FindFirstChild("LowerTorso")
	local motor = lower and lower:FindFirstChild("Root")
	if motor and motor:IsA("Motor6D") then
		return motor
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild("RootJoint")
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

local function targetOffset(character: Model, t: number): CFrame?
	local condition = character:GetAttribute("Condition")
	if character:GetAttribute("Vaulting") then
		return CFrame.Angles(math.rad(-25), 0, 0)
	elseif condition == "Downed" then
		return CFrame.new(0, -2.1, 0) * CFrame.Angles(math.rad(-84), 0, math.rad(4 * math.sin(t * 1.4)))
	elseif condition == "Contained" then
		local bob = if reducedMotion() then 0 else 0.22 * math.sin(t * 1.8)
		return CFrame.new(0, bob, 0) * CFrame.Angles(math.rad(6), 0, 0)
	end
	return nil
end

local function updatePoses(dt: number)
	local t = os.clock()
	local alpha = math.clamp(dt * 8, 0, 1)
	local active: { [Motor6D]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local motor = character and rootMotor(character)
		if character and motor then
			local offset = targetOffset(character, t)
			local pose = poses[motor]
			if offset and not pose then
				pose = { motor = motor, original = motor.C0 }
				poses[motor] = pose
			end
			if pose then
				active[motor] = true
				local target = if offset then pose.original * offset else pose.original
				motor.C0 = motor.C0:Lerp(target, alpha)
				if not offset and (motor.C0.Position - pose.original.Position).Magnitude < 0.02 then
					motor.C0 = pose.original
					poses[motor] = nil
				end
			end
		end
	end
	for motor in poses do
		if not active[motor] then
			poses[motor] = nil -- character gone
		end
	end
end

local function keeperPosition(): Vector3?
	local snapshot = ClientState.get("snapshot")
	if not snapshot then
		return nil
	end
	for _, p in snapshot.participants do
		if p.role == "TimeKeeper" and p.status == "Active" then
			local keeper = Players:GetPlayerByUserId(p.userId)
			local root = keeper
				and keeper.Character
				and keeper.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			return if root then root.Position else nil
		end
	end
	return nil
end

local function updateLights()
	local keeper = if ClientState.isLiveParticipant() then keeperPosition() else nil
	for _, light in CollectionService:GetTagged("ChronoFlicker") do
		if light:IsA("Light") and light.Parent and light.Parent:IsA("BasePart") then
			local base = lightBase[light]
			if base == nil then
				base = light.Brightness
				lightBase[light] = base
			end
			local near = keeper ~= nil and ((light.Parent :: BasePart).Position - keeper).Magnitude < 36
			if near and not reducedMotion() then
				light.Brightness = (base :: number) * (if math.random() < 0.35 then 0.08 else 0.6 + math.random() * 0.4)
			elseif light.Brightness ~= base then
				light.Brightness = base :: number
			end
		end
	end
	for light in lightBase do
		if light.Parent == nil then
			lightBase[light] = nil
		end
	end
end

local function updateCollapse()
	local atmosphere = Lighting:FindFirstChild("ChronoAtmosphere")
	if not atmosphere or not atmosphere:IsA("Atmosphere") then
		return
	end
	local snapshot = ClientState.get("snapshot")
	local collapse = snapshot and snapshot.phase == "Extraction" and snapshot.collapse
	if collapse then
		baseDensity = baseDensity or atmosphere.Density
		local wanted = (baseDensity :: number) + (TIER_DENSITY[collapse.tier] or 0)
		atmosphere.Density += (wanted - atmosphere.Density) * 0.2
	elseif baseDensity then
		atmosphere.Density = baseDensity :: number
		baseDensity = nil
	end
end

function AtmosphereController.Start()
	RunService.RenderStepped:Connect(function(dt)
		updatePoses(dt)
		local now = os.clock()
		if now >= flickerAt then
			flickerAt = now + 0.12
			updateLights()
			updateCollapse()
		end
	end)
end

return AtmosphereController
