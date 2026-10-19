--!strict
-- CharacterService: spawn placement, character setup (health, movement baseline, cosmetic trail),
-- reset-button policy, and death forwarding. Where a character spawns is decided by MatchService
-- (authoritative role/status); this service only executes it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local RoleConfig = require(ReplicatedStorage.Shared.Config.RoleConfig)
local Safe = require(ReplicatedStorage.Shared.Modules.Safe)

local CharacterService = {}

local deps: { [string]: any } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function disconnectCharacter(player: Player)
	local list = characterConnections[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function applyTrail(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in { "ChronoTrail", "ChronoTrailTop", "ChronoTrailBottom" } do
		local existing = root:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local trailId = deps.InventoryService.GetEquipped(player, "Trail")
	local item = if trailId then ItemConfig.get(trailId) else nil
	if not item or not item.Color then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "ChronoTrailTop"
	a0.Position = Vector3.new(0, 0.8, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "ChronoTrailBottom"
	a1.Position = Vector3.new(0, -0.8, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "ChronoTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(item.Color :: Color3)
	trail.Transparency = NumberSequence.new(0.45, 1)
	trail.Lifetime = 0.35
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = root
end

-- CharacterAdded fires before the character is parented to Workspace (verified in Studio via MCP:
-- Parent is nil at the event, Workspace one frame later). Wait for parenting, but give up if the
-- character was replaced or removed in the meantime.
local PARENT_TIMEOUT = 10

local function waitForParenting(player: Player, character: Model): boolean
	local deadline = os.clock() + PARENT_TIMEOUT
	while not character:IsDescendantOf(workspace) do
		if player.Character ~= character or os.clock() > deadline then
			return false
		end
		task.wait()
	end
	return true
end

local function onCharacterAdded(player: Player, character: Model)
	disconnectCharacter(player)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or not waitForParenting(player, character) then
		return
	end

	local placement = deps.MatchService.ResolveSpawn(player)
	local roleId: string? = placement.role
	local role = if roleId then RoleConfig.get(roleId) else nil
	local class = if roleId == "Infiltrator" then ClassConfig.get(deps.MatchService.GetMatchClass(player)) else nil
	local maxHealth = if class then class.MaxHealth elseif role then role.MaxHealth else RoleConfig.Lobby.MaxHealth
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.UseJumpPower = true
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer

	-- Defer the pivot one frame so the default spawn placement doesn't override it.
	task.defer(function()
		if character:IsDescendantOf(game) then
			character:PivotTo(placement.cframe)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			deps.SecurityService.ResetMovement(player)
		end
	end)

	deps.StatusEffectService.SetBaseline(player, roleId)
	deps.StatusEffectService.Reapply(player)
	applyTrail(player, character)

	local connections = {}
	table.insert(
		connections,
		humanoid.Died:Connect(function()
			deps.StatusEffectService.ClearAll(player)
			deps.MatchService.OnCharacterDied(player)
		end)
	)
	characterConnections[player] = connections
end

function CharacterService.Init(injected: { [string]: any })
	deps = injected
end

function CharacterService.Start()
	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(disconnectCharacter)
end

-- Spawns a fresh character; MatchService.ResolveSpawn decides where it lands.
function CharacterService.Respawn(player: Player)
	if player.Parent ~= Players then
		return
	end
	task.spawn(function()
		local ok, err = Safe.call(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[CharacterService] LoadCharacter failed for user {player.UserId}: {err}`)
		end
	end)
end

-- Save original visual values so cleanup restores custom avatars exactly.
function CharacterService.SetCloaked(player: Player, cloaked: boolean)
	local character = player.Character
	if not character or character:GetAttribute("ChronoCloaked") == cloaked then
		return
	end
	character:SetAttribute("ChronoCloaked", cloaked)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			local visual = part :: any
			if cloaked then
				part:SetAttribute("ChronoTransparency", visual.Transparency)
				visual.Transparency = 0.96
			else
				local previous = part:GetAttribute("ChronoTransparency")
				if type(previous) == "number" then
					visual.Transparency = previous
					part:SetAttribute("ChronoTransparency", nil)
				end
			end
		elseif part:IsA("Trail") then
			if cloaked then
				part:SetAttribute("ChronoEnabled", part.Enabled)
				part.Enabled = false
			else
				local previous = part:GetAttribute("ChronoEnabled")
				if type(previous) == "boolean" then
					part.Enabled = previous
					part:SetAttribute("ChronoEnabled", nil)
				end
			end
		end
	end
end

-- Refreshes cosmetics after a loadout change.
function CharacterService.RefreshCosmetics(player: Player)
	local character = player.Character
	if character then
		applyTrail(player, character)
	end
end

return CharacterService
