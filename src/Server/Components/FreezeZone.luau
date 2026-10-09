--!strict
-- FreezeZone: one Time-Freeze Zone instance. Lifecycle:
--   Telegraph (TelegraphDelay)  -> visible warning ring, no slow yet (counterplay: step out)
--   Active (Duration)           -> Infiltrators inside receive a refreshed Slow effect
--   Expired / Destroyed         -> visuals removed; this zone's slow is removed from everyone
-- Membership is checked at MembershipInterval against the (≤4) active Infiltrators only — no
-- world scans. Each zone uses its own status key, so overlapping zones never stack (strongest wins)
-- and one zone expiring never removes another zone's slow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local PlacementRules = require(script.Parent.Parent.Core.PlacementRules)

export type Params = {
	id: string,
	center: Vector3,
	radius: number,
	telegraph: number,
	duration: number,
	slowMagnitude: number,
	membershipInterval: number,
	linger: number,
	startedAt: number,
	parent: Instance,
	getTargets: () -> { Player },
	applySlow: (player: Player, key: string, magnitude: number, duration: number) -> (),
	removeKeyFromAll: (key: string) -> (),
}

export type FreezeZone = {
	id: string,
	center: Vector3,
	state: "Telegraph" | "Active" | "Expired",
	activatesAt: number,
	expiresAt: number,
	update: (self: FreezeZone, now: number) -> boolean, -- returns true when the zone has expired
	destroy: (self: FreezeZone) -> (),
	isDestroyed: (self: FreezeZone) -> boolean,
}

local FreezeZone = {}

local ZONE_HEIGHT = 10

function FreezeZone.new(params: Params): FreezeZone
	local key = `freeze:{params.id}`
	local destroyed = false
	local lastMembershipAt = -math.huge

	-- Visuals: a flat disc plus an outer ring, both non-colliding and non-queryable.
	local model = Instance.new("Model")
	model.Name = `FreezeZone_{params.id}`
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Size = Vector3.new(0.3, params.radius * 2, params.radius * 2)
	disc.CFrame = CFrame.new(params.center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Material = Enum.Material.ForceField
	disc.Color = Theme.Colors.Temporal
	disc.Transparency = 0.6
	disc.Parent = model
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.12, params.radius * 2 + 0.6, params.radius * 2 + 0.6)
	ring.CFrame = disc.CFrame * CFrame.new(-0.12, 0, 0)
	ring.Material = Enum.Material.Neon
	ring.Color = Theme.Colors.Warning
	ring.Transparency = 0.25
	ring.Parent = model
	local light = Instance.new("PointLight")
	light.Color = Theme.Colors.Temporal
	light.Range = params.radius * 1.4
	light.Brightness = 1.2
	light.Parent = disc
	model:SetAttribute("State", "Telegraph")
	model:SetAttribute("Radius", params.radius)
	model.Parent = params.parent

	local self = {
		id = params.id,
		center = params.center,
		state = "Telegraph",
		activatesAt = params.startedAt + params.telegraph,
		expiresAt = params.startedAt + params.telegraph + params.duration,
	} :: any

	function self:update(now: number): boolean
		if destroyed then
			return true
		end
		if now >= self.expiresAt then
			self.state = "Expired"
			return true
		end
		if self.state == "Telegraph" and now >= self.activatesAt then
			self.state = "Active"
			ring.Color = Theme.Colors.Temporal
			disc.Transparency = 0.45
			model:SetAttribute("State", "Active")
		end
		if self.state == "Active" and now - lastMembershipAt >= params.membershipInterval then
			lastMembershipAt = now
			for _, player in params.getTargets() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if
					root and PlacementRules.isInsideCylinder(params.center, params.radius, ZONE_HEIGHT, root.Position)
				then
					-- Refreshed every interval while inside; lapses shortly after leaving.
					local remaining = math.max(0, self.expiresAt - now)
					params.applySlow(player, key, params.slowMagnitude, math.min(params.linger, remaining))
				end
			end
		end
		return false
	end

	function self:destroy()
		if destroyed then
			return
		end
		destroyed = true
		self.state = "Expired"
		params.removeKeyFromAll(key)
		model:Destroy()
	end

	function self:isDestroyed(): boolean
		return destroyed
	end

	return self :: FreezeZone
end

return FreezeZone
