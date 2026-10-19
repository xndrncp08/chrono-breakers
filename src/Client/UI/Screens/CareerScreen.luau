--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Parent.Net)
local Create = require(script.Parent.Parent.Components.Create)
local Modal = require(script.Parent.Parent.Components.Modal)
local ProgressBar = require(script.Parent.Parent.Components.ProgressBar)
local Style = require(script.Parent.Parent.Components.Style)
local CareerScreen = {}
function CareerScreen.new(parent: Instance)
	local modal =
		Modal.new({ Name = "Career", Title = "Career / Timeline record", Width = 760, Height = 650, Parent = parent })
	local scroll = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		Parent = modal.Body,
	})
	Style.list(Enum.FillDirection.Vertical, 12).Parent = scroll
	local lastRefresh = -math.huge
	local function render()
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local profile = ClientState.get("profile")
		if not profile or not profile.progression then
			Style.text({ Text = "Loading career record…", Parent = scroll })
			return
		end
		local progress = profile.progression
		local order = 0
		local function text(value: string, color: Color3?, size: number?)
			order += 1
			return Style.text({
				Text = value,
				Color = color,
				TextSize = size or Theme.TextSize.Small,
				Size = UDim2.new(1, -12, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = scroll,
			})
		end
		text(`LEVEL {progress.level} / {progress.xp} XP`, Theme.Colors.Stable, Theme.TextSize.Heading)
		local floor = Config.threshold(progress.level)
		local ceiling = Config.threshold(progress.level + 1)
		order += 1
		local xp = ProgressBar.new({ Size = UDim2.new(1, -12, 0, 22), LayoutOrder = order, Parent = scroll })
		xp:Set(if progress.level >= Config.MaxLevel then 1 else (progress.xp - floor) / (ceiling - floor))
		xp:SetLabel(
			if progress.level >= Config.MaxLevel then "MAX LEVEL" else `{ceiling - progress.xp} XP to next level`
		)
		if not profile.persistent then
			text("UNSAVED SESSION / This record will not persist.", Theme.Colors.Warning)
		end
		local stats = profile.stats
		text(
			`CAREER / {stats.MatchesPlayed} heists · {stats.Wins} wins · {stats.Losses} losses\n{stats.TerminalsHacked} breaches · {stats.HackAssists or 0} assists · {stats.Extractions} escapes · {stats.Eliminations} captures`,
			Theme.Colors.TextPrimary
		)
		text("ACTIVE CONTRACTS / Rewards are automatic at match resolution", Theme.Colors.Warning, Theme.TextSize.Body)
		for _, challenge in progress.challenges do
			text(
				`{string.upper(challenge.kind)} / {challenge.name}   {challenge.progress}/{challenge.target}{if challenge.claimed
					then "  ✓ CLAIMED"
					else ""}\n+{challenge.scrap} Scrap · +{challenge.xp} XP · resets {os.date(
					"!%a %H:%M UTC",
					challenge.resetsAt
				)}`,
				if challenge.claimed then Theme.Colors.Success else Theme.Colors.TextSecondary
			)
		end
		text("CLASS / KEEPER MASTERY", Theme.Colors.Stable, Theme.TextSize.Body)
		local ids = table.clone(ClassConfig.Order :: { string })
		table.insert(ids, "TimeKeeper")
		for _, id in ids do
			local class = ClassConfig.get(id)
			local amount = progress.mastery[id] or 0
			text(
				`{if class then class.Name else "Time-Keeper"} / rank {Config.level(amount)} · {amount} XP`,
				if class then class.Color else Theme.Colors.Temporal
			)
		end
		text("MILESTONES / Cosmetic rewards only", Theme.Colors.Warning, Theme.TextSize.Body)
		for id, milestone in Config.Milestones :: any do
			text(
				`{if progress.milestones[id] then "✓" else "◇"} {milestone.Name} / {milestone.Target} {milestone.Stat}`,
				if progress.milestones[id] then Theme.Colors.Success else Theme.Colors.TextSecondary
			)
		end
	end
	ClientState.changed:Connect(function(key: string)
		if key == "profile" and modal:IsOpen() then
			render()
		end
	end)
	local self = { Modal = modal }
	function self.Open()
		render()
		modal:Open()
		if os.clock() - lastRefresh >= 5 then
			lastRefresh = os.clock()
			Net.send(RemoteNames.ClientReady)
		end
	end
	return self
end
return CareerScreen
