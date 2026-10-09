--!strict
-- ObjectiveService: binds the physical terminals to the authoritative MatchDirector.
--   * ProximityPrompt triggers are only *requests*: they are rate-limited and forwarded to
--     MatchService.RequestHack, where role, phase, alive, restraint, range, and concurrency are
--     validated server-side. Prompt completion never completes an objective by itself.
--   * Mirrors authoritative terminal state onto the terminal visuals (screen colour, prompt).
--   * Handles the ObjectiveRequest remote ("Cancel").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)
local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

local Validate = require(script.Parent.Parent.Core.Validate)

local ObjectiveService = {}

local deps: { [string]: any } = {}

function ObjectiveService.Init(injected: { [string]: any })
	deps = injected
end

local function onPromptTriggered(player: Player, terminalId: string)
	if not deps.NetworkService.Allow(player, "HackPrompt") then
		return
	end
	local ok, code = deps.MatchService.RequestHack(player, terminalId)
	if not ok then
		if code == Protocol.Codes.OutOfRange or code == Protocol.Codes.WrongRole then
			deps.SecurityService.Report(player, "InvalidHack", code)
		end
		deps.NetworkService.Reject(player, "HackStart", code)
	end
	-- Success is acknowledged by MatchService when the director emits HackStarted.
end

local function handleObjectiveRequest(player: Player, action: any, ...: any)
	if select("#", ...) > 0 or not Validate.isOneOf(action, Protocol.ObjectiveActions) then
		deps.SecurityService.Report(player, "InvalidPayload", "ObjectiveRequest")
		deps.NetworkService.Reject(player, "Objective", Protocol.Codes.InvalidPayload)
		return
	end
	if action == Protocol.ObjectiveActions.Cancel then
		if not deps.MatchService.CancelHack(player, "Cancelled") then
			deps.NetworkService.Reject(player, "Objective", Protocol.Codes.UnknownTarget)
		end
	end
end

function ObjectiveService.Start()
	for _, terminal in deps.WorldService.GetTerminals() do
		local terminalId = terminal.id
		terminal.prompt.Triggered:Connect(function(player: Player)
			onPromptTriggered(player, terminalId)
		end)
	end
	deps.NetworkService.OnRequest(RemoteNames.ObjectiveRequest, handleObjectiveRequest)
	ObjectiveService.ResetVisuals()
end

-- Mirrors one authoritative terminal snapshot onto its world visuals.
function ObjectiveService.OnTerminalChanged(terminal: { id: string, state: string })
	deps.WorldService.SetTerminalVisual(terminal.id, terminal.state, terminal.state == "Available")
end

function ObjectiveService.ResetVisuals()
	for _, terminal in deps.WorldService.GetTerminals() do
		deps.WorldService.SetTerminalVisual(terminal.id, "Locked", false)
	end
end

return ObjectiveService
