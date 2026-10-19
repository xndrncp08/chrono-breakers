--!strict
-- EffectsController: client-side presentation of server Effect events and local status. Effects are
-- purely cosmetic and short-lived (cleaned with Debris); ReducedMotion disables shakes, pulses, and
-- screen tints but keeps every gameplay-relevant cue (rings, highlights, colours, sounds).

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Net)

local EffectsController = {}

local player = Players.LocalPlayer
local deps: { [string]: any } = {}
local effectsFolder: Folder? = nil
local tint: ColorCorrectionEffect? = nil
local shakeUntil = 0
local shakeMagnitude = 0

local KINDS = Protocol.EffectKinds

local function reducedMotion(): boolean
	local settings = ClientState.get("settings")
	return settings ~= nil and settings.ReducedMotion == true
end

local function ring(position: Vector3, radius: number, color: Color3, duration: number, grow: boolean?)
	local part = Instance.new("Part")
	part.Name = "FxRing"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.3
	local startRadius = if grow and not reducedMotion() then radius * 0.2 else radius
	part.Size = Vector3.new(0.12, startRadius * 2, startRadius * 2)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = effectsFolder
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, duration + 0.1)
end

local function beam(position: Vector3, color: Color3, height: number, duration: number)
	local part = Instance.new("Part")
	part.Name = "FxBeam"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.25
	part.Size = Vector3.new(2, height, 2)
	part.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0))
	part.Parent = effectsFolder
	TweenService:Create(part, TweenInfo.new(duration), { Transparency = 1, Size = Vector3.new(0.2, height, 0.2) })
		:Play()
	Debris:AddItem(part, duration + 0.1)
end

local function highlight(target: Instance, color: Color3, duration: number)
	local h = Instance.new("Highlight")
	h.Name = "FxHighlight"
	h.FillColor = color
	h.FillTransparency = 0.6
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = target
	h.Parent = effectsFolder
	Debris:AddItem(h, duration)
end

local function flash(color: Color3, duration: number)
	if reducedMotion() or not tint then
		return
	end
	local t = tint :: ColorCorrectionEffect
	t.TintColor = color
	TweenService:Create(t, TweenInfo.new(duration), { TintColor = Color3.new(1, 1, 1) }):Play()
end

local function shake(magnitude: number, duration: number)
	if reducedMotion() then
		return
	end
	shakeMagnitude = magnitude
	shakeUntil = os.clock() + duration
end

local function characterOf(userId: number?): Model?
	if userId == nil then
		return nil
	end
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.Character else nil
end

local function localRole(): string?
	local role = ClientState.get("role")
	return if role then role.role else nil
end

local function onEffect(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local audio = deps.AudioController
	if kind == "TeamPing" then
		local snapshot = ClientState.get("snapshot")
		if not snapshot or payload.matchId ~= snapshot.matchId then
			return
		end
		ring(payload.position - Vector3.new(0, 2.8, 0), 5, Theme.Colors.Stable, payload.duration, true)
		local anchor = Instance.new("Part")
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency, anchor.Size, anchor.Position = 1, Vector3.one, payload.position
		anchor.Parent = effectsFolder
		local gui = Instance.new("BillboardGui")
		gui.Size, gui.AlwaysOnTop, gui.Adornee, gui.StudsOffsetWorldSpace =
			UDim2.fromOffset(250, 48), true, anchor, Vector3.new(0, 5, 0)
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size, label.BackgroundColor3, label.BackgroundTransparency =
			UDim2.fromScale(1, 1), Theme.Colors.Background, 0.2
		label.Text, label.TextColor3, label.Font, label.TextSize, label.TextWrapped =
			payload.label, Theme.Colors.Stable, Theme.Fonts.Heading, 14, true
		label.Parent = gui
		Debris:AddItem(anchor, payload.duration)
		deps.UIController.Toast(payload.label, "Stable", 3)
	elseif kind == "Anomaly" then
		ring(payload.position, payload.radius, Theme.Colors.Warning, 3, true)
		audio.Play("FreezeCast")
	elseif kind == "Tracking" then
		local target = characterOf(payload.userId)
		if target then
			highlight(target, Theme.Colors.Warning, payload.duration or 3)
		end
	elseif kind == KINDS.FreezeTelegraph then
		ring(payload.position, payload.radius, Theme.Colors.Warning, 0.75, true)
		audio.Play("FreezeCast")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and localRole() == "Infiltrator" then
			local d =
				Vector3.new(root.Position.X - payload.position.X, 0, root.Position.Z - payload.position.Z).Magnitude
			if d <= payload.radius + 2 then
				deps.UIController.Toast("Temporal collapse incoming — move!", "Danger", 2)
			end
		end
	elseif kind == KINDS.FreezeActive then
		ring(payload.position, 16, Theme.Colors.Temporal, 0.6, false)
	elseif kind == KINDS.FreezeEnd then
		ring(payload.position, 15, Theme.Colors.TemporalDim, 0.5, false)
	elseif kind == KINDS.TrapPlaced then
		ring(payload.position, payload.radius, Theme.Colors.Temporal, 0.8, true)
	elseif kind == KINDS.TrapTriggered then
		ring(payload.position, 6, Theme.Colors.Temporal, 0.7, true)
		audio.Play("TrapTriggered")
		if payload.userId == player.UserId then
			flash(Theme.Colors.Temporal, 0.8)
			shake(0.35, 0.4)
		elseif localRole() == "TimeKeeper" then
			local victim = characterOf(payload.userId)
			if victim then
				highlight(victim, Theme.Colors.Temporal, payload.duration or 3)
			end
		end
	elseif kind == KINDS.Strike then
		if payload.position and payload.direction then
			local origin = payload.position + payload.direction * 4
			local slash = Instance.new("Part")
			slash.Name = "FxSlash"
			slash.Anchored = true
			slash.CanCollide = false
			slash.CanQuery = false
			slash.CanTouch = false
			slash.CastShadow = false
			slash.Material = Enum.Material.Neon
			slash.Color = Theme.Colors.Temporal
			slash.Transparency = 0.2
			slash.Size = Vector3.new(7, 0.2, 1.2)
			slash.CFrame = CFrame.lookAt(origin, origin + payload.direction) * CFrame.Angles(0, math.rad(90), 0)
			slash.Parent = effectsFolder
			TweenService:Create(slash, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			Debris:AddItem(slash, 0.3)
		end
		audio.Play("Strike")
	elseif kind == KINDS.Hit then
		if payload.userId == player.UserId then
			flash(Theme.Colors.Danger, 0.5)
			shake(0.5, 0.25)
			audio.Play("Hurt")
		elseif payload.position then
			ring(payload.position - Vector3.new(0, 2.5, 0), 3, Theme.Colors.Danger, 0.35, true)
		end
	elseif kind == KINDS.GadgetUsed then
		if payload.position then
			ring(payload.position - Vector3.new(0, 2.8, 0), 6, Theme.Colors.Stable, 0.6, true)
		end
		if payload.userId == player.UserId then
			audio.Play("GadgetUse")
		end
	elseif kind == KINDS.Reveal then
		local duration = payload.duration or 4
		local keeper = characterOf(payload.keeperUserId)
		if keeper then
			highlight(keeper, Theme.Colors.Temporal, duration)
		end
		for _, position in payload.traps or {} do
			ring(position, 4, Theme.Colors.Warning, duration, false)
		end
		deps.UIController.Toast("Echo scan: Time-Keeper revealed", "Stable", 2)
	elseif kind == KINDS.ExtractionOpened then
		audio.Play("ExtractionOpen")
		if payload.position then
			beam(payload.position, Theme.Colors.Success, 80, 2.5)
		end
	elseif kind == KINDS.PlayerExtracted then
		local character = characterOf(payload.userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			beam(root.Position - Vector3.new(0, 3, 0), Theme.Colors.Success, 40, 1.2)
		end
		audio.Play("Extracted")
	elseif kind == KINDS.PlayerEliminated then
		local character = characterOf(payload.userId)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			ring(root.Position - Vector3.new(0, 2.8, 0), 8, Theme.Colors.Danger, 0.8, true)
		end
	elseif kind == KINDS.TerminalCompleted then
		if payload.position then
			beam(payload.position, Theme.Colors.Success, 30, 1.5)
		end
		audio.Play("HackComplete")
	end
end

local function updateStatusTint(movement: any)
	if not tint then
		return
	end
	local t = tint :: ColorCorrectionEffect
	if reducedMotion() or type(movement) ~= "table" then
		t.Saturation = 0
		t.TintColor = Color3.new(1, 1, 1)
		return
	end
	if movement.stunned then
		t.Saturation = -0.6
	elseif movement.slowed then
		t.Saturation = -0.35
	else
		t.Saturation = 0
	end
end

function EffectsController.Init(injected: { [string]: any })
	deps = injected
	local folder = Instance.new("Folder")
	folder.Name = "ChronoClientEffects"
	folder.Parent = Workspace
	effectsFolder = folder
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ChronoClientTint"
	cc.Parent = Lighting
	tint = cc
end

function EffectsController.Start()
	Net.on(RemoteNames.Effect, onEffect)
	ClientState.observe("movement", updateStatusTint)
	ClientState.observe("settings", function()
		updateStatusTint(ClientState.get("movement"))
	end)
	RunService.RenderStepped:Connect(function()
		if os.clock() < shakeUntil then
			local camera = Workspace.CurrentCamera
			if camera then
				local m = shakeMagnitude
				camera.CFrame = camera.CFrame
					* CFrame.Angles(math.rad((math.random() - 0.5) * m), math.rad((math.random() - 0.5) * m), 0)
			end
		end
	end)
end

return EffectsController
