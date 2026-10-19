--!strict
-- InputController: one abstraction for keyboard/mouse, touch, and gamepad.
--   * Tracks the active input type (drives on-screen hints and layouts).
--   * Binds ability actions with ContextActionService (no gameplay depends on one key).
--   * Ground-targeted abilities use an aim -> confirm flow with a local reticle:
--       KBM: press the ability key to aim at the mouse, click / press again to confirm, RMB cancels.
--       Gamepad: press to aim ahead of the camera, press again or R2 to confirm, B cancels.
--       Touch: tap the ability button to aim ahead, then use the on-screen Confirm / Cancel buttons.
--   * All requests are validated by the server; the reticle colour is only a local hint.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AbilityConfig = require(ReplicatedStorage.Shared.Config.AbilityConfig)
local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Net)

local InputController = {}

local player = Players.LocalPlayer
local reticle: BasePart? = nil
local reticleConnection: RBXScriptConnection? = nil
local boundAbilities: { string } = {}
local lastAimPoint: Vector3? = nil
local lastAimValid = false
local onFeedback: ((code: string) -> ())? = nil

local CANCEL_HACK_ACTION = "ChronoCancelHack"
local CONFIRM_ACTION = "ChronoConfirmTarget"
local CANCEL_TARGET_ACTION = "ChronoCancelTarget"

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function classify(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
	then
		return "KeyboardMouse"
	end
	return nil
end

function InputController.GetInputType(): string
	return ClientState.get("inputType")
end

-- Human-readable binding hint for an ability on the current device.
function InputController.HintFor(abilityId: string): string
	local definition = AbilityConfig.get(abilityId)
	if not definition then
		return ""
	end
	local inputType = ClientState.get("inputType")
	if inputType == "Gamepad" then
		return (definition.GamepadKey :: string):gsub("Button", "")
	elseif inputType == "Touch" then
		return ""
	end
	local key = definition.KeyboardKey :: string
	if key == "MouseButton1" then
		return "LMB"
	end
	return key
end

local function raycastExcludingCharacters(origin: Vector3, direction: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local runtime = Workspace:FindFirstChild("ChronoBreakers")
	local runtimeFolder = runtime and runtime:FindFirstChild("Runtime")
	if runtimeFolder then
		table.insert(exclude, runtimeFolder)
	end
	if reticle then
		table.insert(exclude, reticle)
	end
	params.FilterDescendantsInstances = exclude
	return Workspace:Raycast(origin, direction, params)
end

-- Computes the local aim point for a ground ability; returns (point, locallyValid).
local function computeAimPoint(abilityId: string): (Vector3?, boolean)
	local root = getRoot()
	local camera = Workspace.CurrentCamera
	local definition = AbilityConfig.get(abilityId)
	if not root or not camera or not definition then
		return nil, false
	end
	local maxRange = definition.MaxCastRange :: number
	local candidate: Vector3
	if ClientState.get("inputType") == "KeyboardMouse" then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local hit = raycastExcludingCharacters(ray.Origin, ray.Direction * 400)
		candidate = if hit then hit.Position else ray.Origin + ray.Direction * maxRange
	else
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			flat = root.CFrame.LookVector
		end
		local distance = math.min(maxRange * 0.6, 24)
		candidate = root.Position + flat.Unit * distance
	end
	-- Clamp horizontally to the cast range so the reticle shows the real landing spot.
	local offset = Vector3.new(candidate.X - root.Position.X, 0, candidate.Z - root.Position.Z)
	if offset.Magnitude > maxRange then
		offset = offset.Unit * maxRange
	end
	local probeStart =
		Vector3.new(root.Position.X + offset.X, math.max(candidate.Y, root.Position.Y) + 4, root.Position.Z + offset.Z)
	local ground = raycastExcludingCharacters(probeStart, Vector3.new(0, -20, 0))
	if not ground or ground.Normal.Y < 0.7 then
		return probeStart - Vector3.new(0, 4, 0), false
	end
	local eye = root.Position + Vector3.new(0, 1.5, 0)
	local toGround = ground.Position + Vector3.new(0, 1.5, 0) - eye
	local blocker = raycastExcludingCharacters(eye, toGround)
	local visible = blocker == nil or (blocker.Position - eye).Magnitude >= toGround.Magnitude - 0.5
	return ground.Position, visible
end

local function ensureReticle(radius: number): BasePart
	if not reticle then
		local part = Instance.new("Part")
		part.Name = "ChronoReticle"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Transparency = 0.55
		reticle = part
	end
	local r = reticle :: BasePart
	r.Size = Vector3.new(0.15, radius * 2, radius * 2)
	r.Parent = Workspace
	return r
end

function InputController.CancelTargeting()
	if reticleConnection then
		reticleConnection:Disconnect()
		reticleConnection = nil
	end
	if reticle then
		reticle.Parent = nil
	end
	ContextActionService:UnbindAction(CONFIRM_ACTION)
	ContextActionService:UnbindAction(CANCEL_TARGET_ACTION)
	if ClientState.get("targeting") ~= nil then
		ClientState.set("targeting", nil)
	end
end

local function sendAbility(abilityId: string, target: Vector3?, aim: Vector3?)
	local snapshot = ClientState.get("snapshot")
	if not snapshot or not ClientState.isLiveParticipant() or ClientState.get("modal") then
		return
	end
	Net.send(RemoteNames.AbilityRequest, abilityId, target, aim, snapshot.matchId)
end

function InputController.ConfirmTargeting()
	local abilityId = ClientState.get("targeting")
	if not abilityId then
		return
	end
	local point = lastAimPoint
	local valid = lastAimValid
	InputController.CancelTargeting()
	if point == nil or not valid then
		if onFeedback then
			(onFeedback :: (string) -> ())(Protocol.Codes.InvalidPlacement)
		end
		return
	end
	sendAbility(abilityId, point, nil)
end

local function beginTargeting(abilityId: string)
	InputController.CancelTargeting()
	local definition = AbilityConfig.get(abilityId)
	if not definition then
		return
	end
	local radius = (definition.Radius or definition.TriggerRadius or 4) :: number
	local r = ensureReticle(radius)
	ClientState.set("targeting", abilityId)
	reticleConnection = RunService.RenderStepped:Connect(function()
		local point, valid = computeAimPoint(abilityId)
		lastAimPoint = point
		lastAimValid = valid
		if point then
			r.CFrame = CFrame.new(point + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
			r.Color = if valid then Theme.Colors.Temporal else Theme.Colors.Danger
		end
	end)
	ContextActionService:BindActionAtPriority(CONFIRM_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.ConfirmTargeting()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(CANCEL_TARGET_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.CancelTargeting()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonB)
end

local function strikeAim(): Vector3?
	local root = getRoot()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local direction: Vector3
	if
		ClientState.get("inputType") == "KeyboardMouse"
		and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
	then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local hit = raycastExcludingCharacters(ray.Origin, ray.Direction * 300)
		local point = if hit then hit.Position else ray.Origin + ray.Direction * 50
		direction = point - root.Position
	else
		direction = camera.CFrame.LookVector
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return root.CFrame.LookVector
	end
	return flat.Unit
end

-- Entry point used by key bindings and on-screen ability buttons alike.
function InputController.Activate(abilityId: string)
	local definition = AbilityConfig.get(abilityId)
	if not definition then
		return
	end
	if ClientState.get("targeting") == abilityId then
		InputController.ConfirmTargeting()
		return
	end
	if definition.TargetMode == "Ground" then
		beginTargeting(abilityId)
	elseif definition.TargetMode == "Direction" then
		sendAbility(abilityId, nil, strikeAim())
	else
		sendAbility(abilityId, nil, nil)
	end
end

local function unbindAbilities()
	for _, abilityId in boundAbilities do
		ContextActionService:UnbindAction(`Chrono_{abilityId}`)
	end
	table.clear(boundAbilities)
	InputController.CancelTargeting()
end

-- Binds the given ability ids to their keyboard/gamepad keys (touch uses on-screen buttons).
function InputController.BindAbilities(abilityIds: { string })
	unbindAbilities()
	for _, abilityId in abilityIds do
		local definition = AbilityConfig.get(abilityId)
		if definition then
			local keyboard = definition.KeyboardKey :: string
			local gamepad = (Enum.KeyCode :: any)[definition.GamepadKey]
			local inputs: { any } = {}
			if keyboard == "MouseButton1" then
				table.insert(inputs, Enum.UserInputType.MouseButton1)
			else
				table.insert(inputs, (Enum.KeyCode :: any)[keyboard])
			end
			if gamepad then
				table.insert(inputs, gamepad)
			end
			ContextActionService:BindAction(`Chrono_{abilityId}`, function(_, state, input)
				if
					ClientState.get("modal")
					or UserInputService:GetFocusedTextBox()
					or not ClientState.isLiveParticipant()
				then
					return Enum.ContextActionResult.Pass
				end
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				-- Let clicks on UI pass through to the UI instead of firing abilities.
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					local mouse = UserInputService:GetMouseLocation()
					local inset = GuiService:GetGuiInset()
					local playerGui = player:FindFirstChildOfClass("PlayerGui")
					local guis = if playerGui
						then playerGui:GetGuiObjectsAtPosition(mouse.X - inset.X, mouse.Y - inset.Y)
						else {}
					for _, gui in guis do
						if gui:IsA("GuiButton") and gui.Visible then
							return Enum.ContextActionResult.Pass
						end
					end
				end
				InputController.Activate(abilityId)
				return Enum.ContextActionResult.Sink
			end, false, table.unpack(inputs))
			table.insert(boundAbilities, abilityId)
		end
	end
end

function InputController.UnbindAbilities()
	unbindAbilities()
end

function InputController.CancelHack()
	local snapshot = ClientState.get("snapshot")
	if snapshot then
		Net.send(RemoteNames.ObjectiveRequest, Protocol.ObjectiveActions.Cancel, snapshot.matchId)
	end
end

function InputController.SetHackCancelBound(bound: boolean)
	if bound then
		ContextActionService:BindAction(CANCEL_HACK_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				InputController.CancelHack()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(CANCEL_HACK_ACTION)
	end
end

function InputController.SetFeedbackHandler(handler: (code: string) -> ())
	onFeedback = handler
end

function InputController.Ping()
	local snapshot = ClientState.get("snapshot")
	if snapshot and ClientState.isLiveParticipant() and not ClientState.get("modal") then
		Net.send(RemoteNames.PingRequest, snapshot.matchId)
	end
end

function InputController.Init()
	ContextActionService:BindAction("ChronoTeamPing", function(_, state)
		if
			state == Enum.UserInputState.Begin
			and ClientState.isLiveParticipant()
			and not ClientState.get("modal")
			and not UserInputService:GetFocusedTextBox()
		then
			InputController.Ping()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonR1)
	local initial = classify(UserInputService:GetLastInputType())
	if initial then
		ClientState.set("inputType", initial)
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		ClientState.set("inputType", "Touch")
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		ClientState.set("inputType", "Gamepad")
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local kind = classify(inputType)
		if kind and kind ~= ClientState.get("inputType") then
			ClientState.set("inputType", kind)
		end
	end)
end

return InputController
