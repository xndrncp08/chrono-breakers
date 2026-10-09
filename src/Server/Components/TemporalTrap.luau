--!strict
-- TemporalTrap: a faint ground snare placed by the Time-Keeper.
--   Arming (ArmingTime) -> Armed -> Triggered (first Infiltrator within TriggerRadius) | Expired
-- On trigger the victim is stunned (interrupting any hack via the Restrained rule) and then slowed;
-- the trap is consumed. Traps are deliberately visible (semi-transparent) so attentive players can
-- avoid them, and the Echo Scanner gadget highlights them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local PlacementRules = require(script.Parent.Parent.Core.PlacementRules)

export type Params = {
	id: string,
	position: Vector3,
	armingTime: number,
	triggerRadius: number,
	lifetime: number,
	placedAt: number,
	parent: Instance,
	getTargets: () -> { Player },
	onTriggered: (trap: TemporalTrap, victim: Player) -> (),
}

export type TemporalTrap = {
	id: string,
	position: Vector3,
	state: "Arming" | "Armed" | "Triggered" | "Expired",
	update: (self: TemporalTrap, now: number) -> boolean, -- true when finished
	destroy: (self: TemporalTrap) -> (),
	getInstance: (self: TemporalTrap) -> BasePart,
}

local TemporalTrap = {}

function TemporalTrap.new(params: Params): TemporalTrap
	local destroyed = false
	local part = Instance.new("Part")
	part.Name = `TemporalTrap_{params.id}`
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(0.2, params.triggerRadius * 2, params.triggerRadius * 2)
	part.CFrame = CFrame.new(params.position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Material = Enum.Material.Neon
	part.Color = Theme.Colors.Temporal
	part.Transparency = 0.55
	part:SetAttribute("State", "Arming")
	part.Parent = params.parent

	local self = {
		id = params.id,
		position = params.position,
		state = "Arming",
	} :: any

	local armedAt = params.placedAt + params.armingTime
	local expiresAt = params.placedAt + params.lifetime

	function self:update(now: number): boolean
		if destroyed then
			return true
		end
		if now >= expiresAt then
			self.state = "Expired"
			return true
		end
		if self.state == "Arming" and now >= armedAt then
			self.state = "Armed"
			part.Transparency = 0.82
			part:SetAttribute("State", "Armed")
		end
		if self.state == "Armed" then
			for _, player in params.getTargets() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if
					root and PlacementRules.isInsideCylinder(params.position, params.triggerRadius, 5, root.Position)
				then
					self.state = "Triggered"
					part:SetAttribute("State", "Triggered")
					params.onTriggered(self, player)
					return true
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
		part:Destroy()
	end

	function self:getInstance(): BasePart
		return part
	end

	return self :: TemporalTrap
end

return TemporalTrap
