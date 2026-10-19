--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)
local Theme = require(ReplicatedStorage.Shared.Config.Theme)
local ClientState = require(script.Parent.Parent.Parent.ClientState)
local Net = require(script.Parent.Parent.Parent.Net)
local Button = require(script.Parent.Parent.Components.Button)
local Create = require(script.Parent.Parent.Components.Create)
local Modal = require(script.Parent.Parent.Components.Modal)
local Style = require(script.Parent.Parent.Components.Style)

local DeploymentScreen = {}
function DeploymentScreen.new(parent: Instance)
	local modal = Modal.new({
		Name = "Deployment",
		Title = "Deployment / Map ballot",
		Width = 760,
		Height = 620,
		Parent = parent,
	})
	local scroll = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = modal.Body,
	})
	Style.list(Enum.FillDirection.Vertical, 12).Parent = scroll
	Style.text({
		Text = "Join the queue to vote. Only the next match's participants count; ties rotate fairly.",
		Size = UDim2.new(1, -8, 0, 48),
		TextSize = Theme.TextSize.Small,
		Parent = scroll,
	})
	local buttons: { [string]: Button.Button } = {}
	for index, id in MapConfig.Order do
		local definition = (MapConfig.Maps :: any)[id]
		local card =
			Style.panel({ Size = UDim2.new(1, -8, 0, 112), LayoutOrder = index, Padding = 12, Parent = scroll })
		Style.text({
			Text = definition.Description,
			Size = UDim2.new(1, -190, 1, 0),
			TextSize = Theme.TextSize.Small,
			Parent = card,
		})
		buttons[id] = Button.new({
			Text = definition.Name,
			Style = "Secondary",
			Size = UDim2.new(0, 178, 1, 0),
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			OnActivated = function()
				Net.send(RemoteNames.MapVoteRequest, id)
			end,
			Parent = card,
		})
	end
	local function render()
		local snapshot = ClientState.get("snapshot")
		local queue = ClientState.get("queue")
		local voting = snapshot
			and (snapshot.phase == "WaitingForPlayers" or snapshot.phase == "Intermission")
			and queue
			and queue.queued
		local votes = if snapshot then snapshot.mapVotes or {} else {}
		local mine = votes[tostring(game:GetService("Players").LocalPlayer.UserId)]
		for id, button in buttons do
			local count = 0
			for _, vote in votes do
				if vote == id then
					count += 1
				end
			end
			button:SetText(
				`{(MapConfig.Maps :: any)[id].Name}\n{count} votes{if mine == id then " · YOUR VOTE" else ""}`
			)
			button:SetStyle(if mine == id then "Primary" else "Secondary")
			button:SetEnabled(voting == true)
		end
	end
	ClientState.changed:Connect(function(key: string)
		if key == "snapshot" or key == "queue" then
			render()
		end
	end)
	local self = { Modal = modal }
	function self.Open()
		render()
		modal:Open()
	end
	return self
end
return DeploymentScreen
