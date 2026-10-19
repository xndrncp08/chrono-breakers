--!strict
-- One scheduler, at most one event, bounded participant queries; no Workspace scans or touch loops.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config.AnomalyConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local AnomalyModel = require(script.Parent.Parent.Core.AnomalyModel)
local AnomalyService = {}
local deps: { [string]: any } = {}
local model: AnomalyModel.Model? = nil
local folder: Folder? = nil
local tween: Tween? = nil
local fracture: BasePart? = nil
local paused = false
local lastMembershipAt = 0
local lastPulse: { [number]: number } = {}
local portalReady: { [number]: number } = {}
local gravity: { [Player]: { root: BasePart, attachment: Attachment, force: VectorForce } } = {}
local rng = Random.new()

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function clearGravity(player: Player)
	local entry = gravity[player]
	if entry then
		entry.force:Destroy()
		entry.attachment:Destroy()
		gravity[player] = nil
	end
end
local function clearRuntime()
	if tween then
		tween:Cancel()
		tween = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	fracture = nil
	for player in gravity do
		clearGravity(player)
	end
	for _, key in { "anomalySlow", "anomalyStun", "anomalyHaste" } do
		deps.StatusEffectService.RemoveKeyFromAll(key)
	end
	table.clear(lastPulse)
	table.clear(portalReady)
end
local function part(name: string, position: Vector3, size: Vector3, color: Color3): Part
	local instance = Instance.new("Part")
	instance.Name, instance.Size = name, size
	instance.Position = position
	instance.Anchored, instance.CanCollide, instance.CanQuery, instance.CanTouch = true, false, false, false
	instance.Material, instance.Color = Enum.Material.Neon, color
	instance.Transparency, instance.CastShadow = 0.5, false
	instance.Parent = folder
	return instance
end
local function ring(position: Vector3, event: AnomalyModel.Event)
	local disk = part(
		"AnomalyBoundary",
		position + Vector3.new(0, 0.12, 0),
		Vector3.new(0.15, event.radius * 2, event.radius * 2),
		Theme.Colors.Warning
	)
	disk.Shape = Enum.PartType.Cylinder
	disk.CFrame = CFrame.new(disk.Position) * CFrame.Angles(0, 0, math.pi / 2)
	disk.Transparency = 0.8
	local gui = Instance.new("BillboardGui")
	gui.Size, gui.StudsOffsetWorldSpace = UDim2.fromOffset(250, 56), Vector3.new(0, 8, 0)
	gui.AlwaysOnTop, gui.Adornee, gui.MaxDistance = true, disk, 100
	gui.Parent = disk
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 0.2
	label.BackgroundColor3, label.TextColor3 = Theme.Colors.Background, Theme.Colors.Warning
	label.Font, label.TextSize, label.TextWrapped = Theme.Fonts.Heading, 16, true
	label.Text = (Config.Events :: any)[event.kind].Name .. "\n3 SECOND WARNING"
	label.Parent = gui
end
local function makePortal(position: Vector3, destination: Vector3, event: AnomalyModel.Event)
	local pad = part("Portal", position + Vector3.new(0, 0.4, 0), Vector3.new(8, 0.4, 8), Theme.Colors.Stable)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Traverse", "Temporal Portal"
	prompt.HoldDuration, prompt.MaxActivationDistance = 0, 6
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.E, Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = true
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player: Player)
		if not deps.NetworkService.Allow(player, "PortalPrompt") then
			return
		end
		local root = rootOf(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local t = Workspace:GetServerTimeNow()
		local current = model and model.current
		if not root or not current or current.id ~= event.id or current.state ~= "Active" or t >= current.endsAt then
			return
		end
		if
			not AnomalyModel.portalAllowed(
				deps.MatchService.GetPhase() == "Active" and deps.MatchService.IsActiveParticipant(player),
				humanoid ~= nil and humanoid.Health > 0,
				deps.StatusEffectService.IsRestrained(player),
				(root.Position - pad.Position).Magnitude,
				portalReady[player.UserId] or 0,
				t
			)
		then
			return
		end
		if not deps.WorldService.HasLineOfSight(root.Position, pad.Position + Vector3.new(0, 1, 0)) then
			return
		end
		portalReady[player.UserId] = t + Config.PortalCooldown
		deps.MatchService.CancelHack(player, "OutOfRange")
		local character = player.Character :: Model
		character:PivotTo(CFrame.new(destination + Vector3.new(0, 3, 0)))
		root.AssemblyLinearVelocity = Vector3.zero
		deps.SecurityService.ResetMovement(player)
	end)
end
local function activate(event: AnomalyModel.Event)
	if folder then
		for _, instance in folder:GetDescendants() do
			if instance:IsA("TextLabel") then
				instance.Text = (Config.Events :: any)[event.kind].Name
					.. "\nACTIVE — "
					.. tostring(math.ceil(event.endsAt - event.activatesAt))
					.. "s"
			end
		end
	end
	if event.kind == "Portal" then
		makePortal(event.position, event.destination, event)
		makePortal(event.destination, event.position, event)
	elseif event.kind == "Fracture" then
		local wall = part(
			"TimelineFracture",
			event.position + Vector3.new(0, 6, 0),
			Vector3.new(14, 12, 1),
			Theme.Colors.Temporal
		)
		wall.Material, wall.Transparency = Enum.Material.ForceField, 0.25
		fracture = wall
	elseif event.kind == "Rewind" then
		local block =
			part("RewindingCover", event.position + Vector3.new(0, 3, 0), Vector3.new(8, 6, 4), Theme.Colors.Stable)
		-- Holographic cover blocks sight, but cannot crush or carry player-owned characters.
		block.CanQuery = true
		local rewind = TweenService:Create(
			block,
			TweenInfo.new(
				(event.endsAt - event.activatesAt) / 2,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut,
				0,
				true
			),
			{ Position = block.Position + Vector3.new(6, 0, 0) }
		)
		tween = rewind
		rewind:Play()
	elseif event.kind == "Stasis" then
		for i = 1, 5 do
			local fragment = part(
				"FrozenFragment",
				event.position + Vector3.new((i - 3) * 3, 4 + i % 2 * 2, 0),
				Vector3.new(1.5, 1.5, 1.5),
				Theme.Colors.Temporal
			)
			fragment.Orientation = Vector3.new(i * 20, i * 30, 45)
		end
	end
end
function AnomalyService.Init(injected: { [string]: any })
	deps = injected
	Players.PlayerRemoving:Connect(function(player)
		clearGravity(player)
		portalReady[player.UserId] = nil
		lastPulse[player.UserId] = nil
	end)
end
function AnomalyService.Snapshot(): any
	local event = model and model.current
	return if event then table.clone(event) else nil
end
function AnomalyService.BeginMatch(matchId: string)
	AnomalyService.EndMatch()
	model = AnomalyModel.new(matchId, deps.WorldService.GetMap().anomalySites, Workspace:GetServerTimeNow(), function(n)
		return rng:NextInteger(1, n)
	end)
end
function AnomalyService.EndMatch()
	clearRuntime()
	if model then
		model:clear()
		model = nil
	end
end
function AnomalyService.SetTestPaused(value: boolean)
	assert(RunService:IsStudio(), "test controls are Studio-only")
	paused = value
end
function AnomalyService.Tick(t: number)
	if not model or paused then
		return
	end
	if deps.MatchService.GetPhase() ~= "Active" then
		AnomalyService.EndMatch()
		return
	end
	local changed, state = model:tick(t)
	if changed and state then
		if state == "Warning" then
			clearRuntime()
			local container = Instance.new("Folder")
			container.Name = "TemporalAnomaly"
			container.Parent = deps.WorldService.GetGeometryFolder()
			folder = container
			ring(changed.position, changed)
			if changed.kind == "Portal" then
				ring(changed.destination, changed)
			end
			local definition = (Config.Events :: any)[changed.kind]
			deps.NetworkService.Notify(
				deps.MatchService.GetParticipants(),
				"Announcement",
				`{definition.Name} · {Config.Warning}s warning. {definition.Description}`,
				"Warning",
				6
			)
			deps.NetworkService.FireList(
				RemoteNames.Effect,
				deps.MatchService.GetParticipants(),
				{ kind = "Anomaly", position = changed.position, radius = changed.radius }
			)
		elseif state == "Active" then
			activate(changed)
		else
			clearRuntime()
		end
		deps.MatchService.BroadcastSnapshot()
	end
	local event = model and model.current
	if not event or event.state ~= "Active" or t - lastMembershipAt < Config.MembershipInterval then
		return
	end
	lastMembershipAt = t
	local affected: { [Player]: boolean } = {}
	local wallClear = true
	for _, player in deps.MatchService.GetParticipants() do
		local root = rootOf(player)
		if root and deps.MatchService.IsActiveParticipant(player) then
			if fracture then
				local delta = root.Position - fracture.Position
				if math.abs(delta.X) < 9 and math.abs(delta.Z) < 4 then
					wallClear = false
				end
			end
			if AnomalyModel.contains(event, root.Position) then
				affected[player] = true
				local kind = event.kind
				if kind == "Gravity" then
					local entry: { root: BasePart, attachment: Attachment, force: VectorForce }? = gravity[player]
					if entry and entry.root ~= root then
						clearGravity(player)
						entry = nil
					end
					if not entry then
						local attachment = Instance.new("Attachment")
						attachment.Name, attachment.Parent = "GravityFlux", root
						local force = Instance.new("VectorForce")
						force.Attachment0, force.RelativeTo, force.ApplyAtCenterOfMass =
							attachment, Enum.ActuatorRelativeTo.World, true
						force.Name, force.Parent = "GravityFlux", root
						entry = { root = root, attachment = attachment, force = force }
						gravity[player] = entry
					end
					assert(entry, "gravity entry missing after creation")
					entry.force.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity * 0.55, 0)
				elseif
					kind == "Distortion" or (kind == "Pulse" and deps.MatchService.GetRole(player) == "TimeKeeper")
				then
					deps.StatusEffectService.Apply(
						player,
						{ key = "anomalySlow", kind = "Slow", magnitude = 0.35, duration = 0.35, source = kind }
					)
				elseif kind == "Surge" then
					deps.StatusEffectService.Apply(
						player,
						{ key = "anomalyHaste", kind = "Haste", magnitude = 0.5, duration = 0.35, source = kind }
					)
				elseif
					(kind == "Stasis" or kind == "Pulse")
					and t - (lastPulse[player.UserId] or -math.huge) >= (if kind == "Stasis" then 2 else 1.5)
				then
					lastPulse[player.UserId] = t
					if kind == "Stasis" then
						deps.StatusEffectService.Apply(
							player,
							{ key = "anomalyStun", kind = "Stun", magnitude = 1, duration = 0.35, source = kind }
						)
					elseif not deps.StatusEffectService.IsInvulnerable(player) then
						local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0 then
							deps.MatchService.NotifyDamage(player)
							humanoid:TakeDamage(8)
						end
					end
				end
			end
		end
	end
	for player in gravity do
		if not affected[player] then
			clearGravity(player)
		end
	end
	if fracture and wallClear then
		fracture.CanCollide, fracture.CanQuery = true, true
	end
end
return AnomalyService
