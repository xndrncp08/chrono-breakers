--!strict
-- Full-screen connecting / connection-failed overlay driven by ClientState.connection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Create = require(script.Parent.Parent.Components.Create)
local Style = require(script.Parent.Parent.Components.Style)

local ConnectionOverlay = {}

function ConnectionOverlay.new(parent: Instance)
	local root = Create("Frame", {
		Name = "ConnectionOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0,
		ZIndex = 50,
		Active = true,
		Parent = parent,
	}, { Style.gradient(Theme.Colors.Background, Theme.Colors.Surface) })
	local title = Style.text({
		Text = string.upper(GameConfig.GameTitle),
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		Color = Theme.Colors.Stable,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0.9, 0, 0, 44),
		XAlign = Enum.TextXAlignment.Center,
		Parent = root,
	})
	title.ZIndex = 51
	local status = Style.text({
		Text = "Connecting to the vault…",
		TextSize = Theme.TextSize.Body,
		Color = Theme.Colors.TextSecondary,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.9, 0, 0, 48),
		XAlign = Enum.TextXAlignment.Center,
		Parent = root,
	})
	status.ZIndex = 51

	ClientState.observe("connection", function(state)
		if state == "Ready" then
			root.Visible = false
		elseif state == "Failed" then
			root.Visible = true
			status.Text = "Couldn't reach the game server. Please rejoin the experience."
			status.TextColor3 = Theme.Colors.Danger
		else
			root.Visible = true
			status.Text = "Connecting to the vault…"
			status.TextColor3 = Theme.Colors.TextSecondary
		end
	end)
end

return ConnectionOverlay
