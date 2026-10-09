--!strict
-- Match results modal: outcome, reason, personal stats, reward breakdown (with saved/unsaved note),
-- and the final participant list. Opens automatically when the server sends MatchResult.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local TableUtil = require(ReplicatedStorage.Shared.Modules.TableUtil)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local Modal = require(script.Parent.Parent.Components.Modal)
local Style = require(script.Parent.Parent.Components.Style)

local ResultsScreen = {}

local REASON_TEXT: { [string]: string } = {
	Extracted = "The Infiltrators escaped with the Chronos tech.",
	AllEliminated = "Every Infiltrator was caught.",
	TimeExpired = "The match timer ran out before extraction.",
	ExtractionFailed = "The extraction window closed with nobody out.",
	KeeperLeft = "The Time-Keeper left the match.",
	InfiltratorsLeft = "The Infiltrators left the match.",
	Aborted = "Not enough players remained to play the match.",
}

local STATUS_TEXT: { [string]: string } = {
	Active = "Survived",
	Eliminated = "Eliminated",
	Extracted = "Extracted",
	Disconnected = "Left",
}

function ResultsScreen.new(parent: Instance, deps: { [string]: any })
	local modal = Modal.new({ Name = "Results", Title = "Match Results", Width = 640, Height = 520, Parent = parent })
	local body = modal.Body

	local headline = Style.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = body,
	})
	local reason = Style.text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.TextSecondary,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 42),
		Parent = body,
	})

	local left = Create("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(0.55, -8, 1, -140),
		Parent = body,
	}, { Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS) })
	local right = Create("Frame", {
		Name = "Players",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.55, 8, 0, 80),
		Size = UDim2.new(0.45, -8, 1, -140),
		Parent = body,
	}, { Style.list(Enum.FillDirection.Vertical, Theme.Spacing.XS) })

	local continueButton = Button.new({
		Text = "Continue",
		Style = "Primary",
		Size = UDim2.fromOffset(220, Theme.MinTouchTarget),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		OnActivated = function()
			deps.AudioController.Play("UiClick")
			modal:Close()
		end,
		Parent = body,
	})

	local function clear(frame: Instance)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function line(frame: Instance, text: string, color: Color3?, size: number?, order: number)
		Style.text({
			Text = text,
			TextSize = size or Theme.TextSize.Small,
			Color = color or Theme.Colors.TextPrimary,
			Size = UDim2.new(1, 0, 0, (size or Theme.TextSize.Small) + 8),
			Wrapped = false,
			LayoutOrder = order,
			Parent = frame,
		})
	end

	ClientState.observe("result", function(result)
		if not result then
			return
		end
		clear(left)
		clear(right)
		if result.reason == "Aborted" then
			headline.Text = "MATCH ABORTED"
			headline.TextColor3 = Theme.Colors.Warning
		elseif result.won then
			headline.Text = "VICTORY"
			headline.TextColor3 = Theme.Colors.Success
		else
			headline.Text = "DEFEAT"
			headline.TextColor3 = Theme.Colors.Danger
		end
		local winnerText = if result.winner == "Infiltrators"
			then "Infiltrators win. "
			elseif result.winner == "TimeKeeper" then "Time-Keeper wins. "
			else ""
		reason.Text = winnerText .. (REASON_TEXT[result.reason] or "")

		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		line(left, "YOUR MATCH", Theme.Colors.TextSecondary, Theme.TextSize.Micro, nextOrder())
		if result.yourRole == "Infiltrator" then
			line(left, `Terminals hacked: {result.stats.hacks}`, nil, nil, nextOrder())
			line(left, `Extracted: {if result.stats.extracted then "Yes" else "No"}`, nil, nil, nextOrder())
		elseif result.yourRole == "TimeKeeper" then
			line(left, `Eliminations: {result.stats.eliminations}`, nil, nil, nextOrder())
		end
		line(left, " ", nil, Theme.TextSize.Micro, nextOrder())
		line(left, "REWARDS", Theme.Colors.TextSecondary, Theme.TextSize.Micro, nextOrder())
		if #result.rewards == 0 then
			line(left, "No rewards for this match.", Theme.Colors.TextMuted, nil, nextOrder())
		end
		for _, reward in result.rewards do
			line(left, `+{reward.amount}  {reward.label}`, Theme.Colors.Warning, nil, nextOrder())
		end
		line(
			left,
			`Total: +{result.rewardTotal} {RewardConfig.CurrencyShort}`,
			Theme.Colors.Warning,
			Theme.TextSize.Body,
			nextOrder()
		)
		if result.rewardTotal > 0 and not result.rewardsSaved then
			line(
				left,
				"! Unsaved session — rewards won't persist.",
				Theme.Colors.Warning,
				Theme.TextSize.Micro,
				nextOrder()
			)
		end

		line(right, "PARTICIPANTS", Theme.Colors.TextSecondary, Theme.TextSize.Micro, 0)
		for index, p in result.participants do
			local color = (Theme.RoleColors :: any)[p.role] or Theme.Colors.TextPrimary
			local roleTag = if p.role == "TimeKeeper" then "KEEPER" else "INF"
			line(
				right,
				`{roleTag}  {TableUtil.truncate(p.name, 14)} · {STATUS_TEXT[p.status] or p.status}`,
				color,
				nil,
				index
			)
		end

		modal:Open()
		modal:Focus(continueButton.Instance)
	end)

	return { Modal = modal }
end

return ResultsScreen
