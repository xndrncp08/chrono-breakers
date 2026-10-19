--!strict
-- Squad cards: every Infiltrator's integrity, stasis stage, timers and current activity. Both roles
-- see the same public information (the Keeper plans around it; Infiltrators coordinate with it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local SurvivalConfig = require(ReplicatedStorage.Shared.Config.SurvivalConfig)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)

export type SquadPanel = {
	Instance: Frame,
	Render: (self: SquadPanel) -> (),
	SetCompact: (self: SquadPanel, compact: boolean) -> (),
}

type Card = {
	frame: Frame,
	accent: Frame,
	name: TextLabel,
	state: TextLabel,
	pips: { Frame },
	bar: ProgressBar.ProgressBar,
}

local SquadPanel = {}

local STAGES = #SurvivalConfig.Containment.StageDurations + 1

local ACTION_TEXT: { [string]: string } = {
	Revive = "Re-syncing",
	Heal = "Patching",
	Rescue = "Rescuing",
	Relay = "Powering relay",
	Rift = "At the rift",
}

local function describe(p: any, now: number, chasedIds: { number }): (string, Color3, number?, Color3?)
	if p.status == "Eliminated" then
		return "✕ ERASED", Theme.ConditionColors.Eliminated, nil, nil
	elseif p.status == "Extracted" then
		return "⇪ ESCAPED", Theme.ConditionColors.Extracted, nil, nil
	elseif p.status == "Disconnected" then
		return "… LEFT", Theme.Colors.TextMuted, nil, nil
	end
	local condition = p.condition or "Healthy"
	local label = string.upper(SurvivalConfig.ConditionNames[condition] or condition)
	local color = (Theme.ConditionColors :: any)[condition] or Theme.Colors.TextPrimary
	if condition == "Contained" and p.podRemaining and p.podDuration then
		local feedback = if p.feedback and p.feedback > 0 then " · feedback" else ""
		return `{label} {math.max(0, p.podRemaining)}s{feedback}`, color, p.podRemaining / p.podDuration, color
	elseif condition == "Downed" then
		if p.revive and p.revive > 0 then
			return `{label} · re-sync {math.floor(p.revive * 100)}%`, color, p.revive, Theme.Colors.Success
		end
		local left = if p.bleedoutAt then math.max(0, math.ceil(p.bleedoutAt - now)) else 0
		return `{label} {left}s`,
			color,
			if p.bleedoutAt then left / SurvivalConfig.Integrity.BleedoutTime else nil,
			color
	end
	local extra = ""
	if table.find(chasedIds, p.userId) then
		extra = " · PURSUED"
	elseif p.action and ACTION_TEXT[p.action] then
		extra = ` · {ACTION_TEXT[p.action]}`
	end
	if condition == "Injured" and p.heal and p.heal > 0 then
		return `{label} · patch {math.floor(p.heal * 100)}%{extra}`, color, p.heal, Theme.Colors.Success
	end
	return label .. extra, color, nil, nil
end

function SquadPanel.new(parent: Instance): SquadPanel
	local panel = Style.panel({
		Name = "Squad",
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = Theme.Spacing.S,
		Color = Theme.Colors.Background,
		Transparency = 0.3,
		Parent = parent,
	})
	Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS).Parent = panel
	local heading = Style.text({
		Text = "SQUAD",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Micro,
		Color = Theme.Colors.TextSecondary,
		LayoutOrder = 0,
		Parent = panel,
	})
	local cards: { [number]: Card } = {}
	local compact = false

	local function makeCard(): Card
		local frame = Create("Frame", {
			Name = "Card",
			BackgroundColor3 = Theme.Colors.Surface,
			BackgroundTransparency = 0.25,
			Size = UDim2.new(1, 0, 0, 50),
			Parent = panel,
		}, { Style.corner(Theme.Radius.S) }) :: Frame
		local accent = Create("Frame", {
			Name = "Accent",
			Size = UDim2.new(0, 4, 1, -8),
			Position = UDim2.fromOffset(4, 4),
			BorderSizePixel = 0,
			Parent = frame,
		}, { Style.corner(Theme.Radius.Pill) }) :: Frame
		local name = Style.text({
			TextSize = Theme.TextSize.Small,
			Font = Theme.Fonts.Heading,
			Size = UDim2.new(1, -70, 0, 18),
			Position = UDim2.fromOffset(14, 3),
			Wrapped = false,
			Parent = frame,
		})
		local state = Style.text({
			TextSize = Theme.TextSize.Micro,
			Font = Theme.Fonts.Heading,
			Size = UDim2.new(1, -20, 0, 14),
			Position = UDim2.fromOffset(14, 21),
			Wrapped = false,
			Parent = frame,
		})
		local pips: { Frame } = {}
		for i = 1, STAGES do
			pips[i] = Create("Frame", {
				Name = `Pip{i}`,
				Size = UDim2.fromOffset(9, 9),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6 - (STAGES - i) * 13, 0, 7),
				BorderSizePixel = 0,
				Parent = frame,
			}, { Style.corner(Theme.Radius.Pill) :: Instance, Style.stroke(Theme.Colors.Border, 1, 0.2) }) :: Frame
		end
		local bar = ProgressBar.new({
			Size = UDim2.new(1, -22, 0, 6),
			Position = UDim2.new(0, 14, 1, -10),
			Parent = frame,
		})
		return { frame = frame, accent = accent, name = name, state = state, pips = pips, bar = bar }
	end

	local self = { Instance = panel } :: any

	function self:SetCompact(value: boolean)
		compact = value
		panel.Size = UDim2.fromOffset(if compact then 190 else 250, 0)
	end

	function self:Render()
		local snapshot = ClientState.get("snapshot")
		if not snapshot then
			return
		end
		local now = ClientState.now()
		local chasedIds: { number } = {}
		if ClientState.get("chased") then
			table.insert(chasedIds, Players.LocalPlayer.UserId)
		end
		for _, id in ClientState.get("huntTargets") or {} do
			table.insert(chasedIds, id)
		end
		local seen: { [number]: boolean } = {}
		local free, total = 0, 0
		for index, p in snapshot.participants do
			if p.role ~= "Infiltrator" then
				continue
			end
			total += 1
			if
				p.status == "Active" and (p.condition == nil or p.condition == "Healthy" or p.condition == "Injured")
			then
				free += 1
			end
			seen[p.userId] = true
			local card = cards[p.userId] or makeCard()
			cards[p.userId] = card
			card.frame.LayoutOrder = index
			local class = ClassConfig.get(p.classId)
			local you = if p.userId == Players.LocalPlayer.UserId then " (you)" else ""
			card.name.Text = `{TableUtil.truncate(p.name, if compact then 9 else 14)}{you}`
			card.accent.BackgroundColor3 = if class then class.Color else Theme.Colors.Stable
			local text, color, fraction, barColor = describe(p, now, chasedIds)
			card.state.Text = if compact then string.sub(text, 1, 22) else text
			card.state.TextColor3 = color
			card.frame.BackgroundTransparency = if p.status == "Active" then 0.25 else 0.6
			for i, pip in card.pips do
				pip.BackgroundColor3 = if (p.stage or 0) >= i then Theme.Colors.Danger else Theme.Colors.Surface
			end
			card.bar.Instance.Visible = fraction ~= nil
			if fraction then
				card.bar:Set(fraction, barColor)
			end
		end
		heading.Text = `SQUAD · {free} FREE / {total}`
		for userId, card in cards do
			if not seen[userId] then
				card.frame:Destroy()
				cards[userId] = nil
			end
		end
	end

	return self :: SquadPanel
end

return SquadPanel
