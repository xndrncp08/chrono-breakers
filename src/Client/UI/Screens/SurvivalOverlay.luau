--!strict
-- Survival overlay: pursuit vignette (Temporal Resonance / chase), Desynced and In-Stasis banners,
-- the current survival channel, stamina, Endurance and the Keeper's Hunt Momentum. Pure
-- presentation of server state plus the client-computed Resonance intensity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)

export type SurvivalOverlay = {
	Update: (self: SurvivalOverlay, reducedMotion: boolean) -> (),
	SetVisible: (self: SurvivalOverlay, visible: boolean) -> (),
	ActionVisible: (self: SurvivalOverlay) -> boolean,
}

local SurvivalOverlay = {}

local ACTION_LABEL: { [string]: string } = {
	Revive = "RE-SYNCING",
	Heal = "PATCHING",
	Rescue = "RESCUING",
	Contain = "PHASE-LOCKING",
	Overload = "OVERLOADING",
	Relay = "POWERING RELAY",
	Rift = "RIFT",
}

local function participant(userId: any): any
	local snapshot = ClientState.get("snapshot")
	if not snapshot or type(userId) ~= "number" then
		return nil
	end
	for _, p in snapshot.participants do
		if p.userId == userId then
			return p
		end
	end
	return nil
end

function SurvivalOverlay.new(parent: Instance): SurvivalOverlay
	local root = Create("Frame", {
		Name = "SurvivalOverlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = parent,
	}) :: Frame

	-- Vignette: four edge gradients whose opacity follows Resonance and chase state.
	local edges: { Frame } = {}
	local function edge(name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number)
		local frame = Create("Frame", {
			Name = name,
			Size = size,
			Position = position,
			AnchorPoint = anchor,
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.Colors.Danger,
			BackgroundTransparency = 1,
			Parent = root,
		}, {
			Create("UIGradient", {
				Rotation = rotation,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}) :: Frame
		table.insert(edges, frame)
	end
	edge("Top", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), Vector2.zero, 90)
	edge("Bottom", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90)
	edge("Left", UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), Vector2.zero, 0)
	edge("Right", UDim2.fromScale(0.16, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180)

	local pursued = Style.text({
		Name = "Pursued",
		Text = "◉ PURSUED",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.Danger,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(260, 24),
		XAlign = Enum.TextXAlignment.Center,
		Parent = root,
	})

	-- Threat indicator: a chevron on an ellipse around the screen centre pointing at an off-screen
	-- Keeper (ClientState "threat"); it turns solid red when a strike is winding up nearby.
	local threatArrow = Style.text({
		Name = "ThreatArrow",
		Text = "▲",
		Font = Theme.Fonts.Display,
		TextSize = 34,
		Color = Theme.Colors.Danger,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		XAlign = Enum.TextXAlignment.Center,
		Parent = root,
	})
	threatArrow.Visible = false

	-- Desynced / In Stasis banner
	local banner = Style.panel({
		Name = "StateBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(380, 108),
		Color = Theme.Colors.Background,
		Transparency = 0.2,
		Padding = Theme.Spacing.M,
		Parent = root,
	})
	banner.Visible = false
	local bannerTitle = Style.text({
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		Size = UDim2.new(1, 0, 0, 34),
		XAlign = Enum.TextXAlignment.Center,
		Parent = banner,
	})
	local bannerDetail = Style.text({
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 38),
		XAlign = Enum.TextXAlignment.Center,
		Parent = banner,
	})
	local bannerBar =
		ProgressBar.new({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 66), Parent = banner })

	-- Current channel
	local actionPanel = Style.panel({
		Name = "ActionPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -186),
		Size = UDim2.fromOffset(320, 60),
		Color = Theme.Colors.Background,
		Transparency = 0.15,
		StrokeColor = Theme.Colors.Stable,
		Padding = Theme.Spacing.S,
		Parent = root,
	})
	actionPanel.Visible = false
	local actionLabel = Style.text({
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		Color = Theme.Colors.Stable,
		Size = UDim2.new(1, 0, 0, 18),
		Wrapped = false,
		Parent = actionPanel,
	})
	local actionBar =
		ProgressBar.new({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 24), Parent = actionPanel })

	-- Stamina (Infiltrators) and Hunt Momentum (Keeper)
	local stamina = ProgressBar.new({
		Size = UDim2.fromOffset(180, 6),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -114),
		Color = Theme.Colors.Stable,
		Parent = root,
	})
	local chips = Style.text({
		Name = "SurvivalChips",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(360, 18),
		XAlign = Enum.TextXAlignment.Center,
		RichText = true,
		Parent = root,
	})

	local self = {} :: any

	function self:SetVisible(visible: boolean)
		root.Visible = visible
	end

	function self:ActionVisible(): boolean
		return actionPanel.Visible
	end

	function self:Update(reducedMotion: boolean)
		local now = ClientState.now()
		local role = ClientState.currentRole()
		local isKeeper = role ~= nil and role.role == "TimeKeeper"
		local me = ClientState.myParticipant()
		local condition = ClientState.myCondition()
		local chased = ClientState.get("chased") == true

		-- Vignette
		local resonance = if isKeeper then 0 else ClientState.get("resonance") or 0
		local beat = ClientState.get("lastHeartbeat") or 0
		local pulse = if reducedMotion then 0 else math.max(0, 1 - (os.clock() - beat) / 0.35)
		local intensity =
			math.clamp(math.max(resonance * 0.55, if chased then 0.7 else 0) + pulse * 0.2 * resonance, 0, 1)
		local tintColor = if condition == "Contained" then Theme.Colors.Violet else Theme.Colors.Danger
		for _, frame in edges do
			frame.BackgroundTransparency = 1 - intensity * 0.6
			frame.BackgroundColor3 = tintColor
		end
		pursued.Visible = chased and not isKeeper

		local threat = ClientState.get("threat")
		local strikeWarn = os.clock() - (ClientState.get("strikeWarnAt") or -10) < 0.5
		if threat and not isKeeper and condition ~= "Contained" then
			-- angle 0 = ahead (top of screen); x grows to the right
			threatArrow.Position =
				UDim2.fromScale(0.5 + math.sin(threat.angle) * 0.36, 0.5 - math.cos(threat.angle) * 0.36)
			threatArrow.Rotation = math.deg(threat.angle)
			threatArrow.TextTransparency = if strikeWarn then 0 else 0.55 - 0.45 * threat.strength
			threatArrow.TextSize = if strikeWarn and not reducedMotion then 42 else 34
			threatArrow.Visible = true
		else
			threatArrow.Visible = false
		end

		-- State banner
		if condition == "Downed" and me then
			banner.Visible = true
			bannerTitle.Text = "DESYNCED"
			bannerTitle.TextColor3 = Theme.ConditionColors.Downed
			local left = if me.bleedoutAt then math.max(0, me.bleedoutAt - now) else 0
			bannerDetail.Text = if me.revive and me.revive > 0
				then `Re-sync {math.floor(me.revive * 100)}% — stay with your ally`
				else `Crawl to cover. Allies can Re-sync you. Phase-Lock in {math.ceil(left)}s`
			bannerBar:Set(
				if me.revive and me.revive > 0 then me.revive else left / SurvivalConfig.Integrity.BleedoutTime,
				if me.revive and me.revive > 0 then Theme.Colors.Success else Theme.ConditionColors.Downed
			)
		elseif condition == "Contained" and me then
			banner.Visible = true
			local stages = #SurvivalConfig.Containment.StageDurations + 1
			bannerTitle.Text = `IN STASIS · {me.stage or 1}/{stages}`
			bannerTitle.TextColor3 = Theme.ConditionColors.Contained
			local feedback = if me.feedback and me.feedback > 0
				then ` · Keeper camping: release {math.floor(me.feedback * 100)}%`
				else ""
			bannerDetail.Text = `{math.max(0, me.podRemaining or 0)}s until erasure{feedback}`
			bannerBar:Set((me.podRemaining or 0) / math.max(1, me.podDuration or 1), Theme.ConditionColors.Contained)
		else
			banner.Visible = false
		end

		-- Current channel
		local action = ClientState.get("action")
		if action then
			local fraction = 0
			if action.duration and action.startedAt then
				fraction = (now - action.startedAt) / action.duration
			elseif action.action == "Relay" then
				local snapshot = ClientState.get("snapshot")
				fraction = if snapshot and snapshot.collapse then snapshot.collapse.relays[action.target] or 0 else 0
			else
				local target = participant(action.target)
				fraction = if target then (if action.action == "Heal" then target.heal else target.revive) or 0 else 0
			end
			local target = participant(action.target)
			local suffix = if target then ` {target.name}` else ""
			actionLabel.Text = `{ACTION_LABEL[action.action] or action.action}{suffix} · {math.floor(
				math.clamp(fraction, 0, 1) * 100
			)}%   (cancel: C / B)`
			actionBar:Set(fraction, Theme.Colors.Stable)
			actionPanel.Visible = true
		else
			actionPanel.Visible = false
		end

		-- Stamina, Endurance, Momentum
		local parts = {}
		local staminaState = ClientState.get("stamina")
		stamina.Instance.Visible = not isKeeper
			and staminaState ~= nil
			and condition ~= "Downed"
			and condition ~= "Contained"
		if staminaState then
			stamina:Set(
				staminaState.value,
				if staminaState.exhausted
					then Theme.Colors.Danger
					elseif staminaState.sprinting then Theme.Colors.Warning
					else Theme.Colors.Stable
			)
			if staminaState.exhausted and not isKeeper then
				table.insert(parts, `<font color="#{Theme.Colors.Danger:ToHex()}">EXHAUSTED</font>`)
			end
		end
		if me and me.enduranceUntil and me.enduranceUntil > now then
			table.insert(
				parts,
				`<font color="#{Theme.Colors.Success:ToHex()}">◆ ENDURANCE {math.ceil(me.enduranceUntil - now)}s</font>`
			)
		end
		local momentum = ClientState.get("momentum") or 0
		if isKeeper and momentum > 0 then
			table.insert(
				parts,
				`<font color="#{Theme.Colors.Temporal:ToHex()}">» HUNT MOMENTUM +{math.floor(momentum * 100 + 0.5)}%</font>`
			)
		end
		if isKeeper and #(ClientState.get("huntTargets") or {}) > 0 then
			table.insert(parts, `<font color="#{Theme.Colors.Warning:ToHex()}">◉ IN PURSUIT</font>`)
		end
		chips.Text = table.concat(parts, "   ")
	end

	return self :: SurvivalOverlay
end

return SurvivalOverlay
