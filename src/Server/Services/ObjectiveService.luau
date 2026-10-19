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

local function handleObjectiveRequest(player: Player, action: any, matchId: any, ...: any)
	if
		select("#", ...) > 0
		or not Validate.isOneOf(action, Protocol.ObjectiveActions)
		or not Validate.isShortString(matchId, 64)
	then
		deps.SecurityService.Report(player, "InvalidPayload", "ObjectiveRequest")
		deps.NetworkService.Reject(player, "Objective", Protocol.Codes.InvalidPayload)
		return
	end
	if not deps.MatchService.IsCurrentMatch(matchId) then
		deps.NetworkService.Reject(player, "Objective", Protocol.Codes.StaleRequest)
		return
	end
	if action == Protocol.ObjectiveActions.Cancel then
		if not deps.MatchService.CancelHack(player, "Cancelled") then
			deps.NetworkService.Reject(player, "Objective", Protocol.Codes.UnknownTarget)
		end
	end
end

function ObjectiveService.BindTerminals()
	for _, terminal in deps.WorldService.GetTerminals() do
		local terminalId = terminal.id
		terminal.prompt.Triggered:Connect(function(player: Player)
			onPromptTriggered(player, terminalId)
		end)
	end
end

local function handleChallenge(player: Player, matchId: any, terminalId: any, nonce: any, answer: any, ...: any)
	if
		select("#", ...) > 0
		or not Validate.isShortString(matchId, 64)
		or not Validate.isShortString(terminalId, 32)
		or not Validate.isInteger(nonce, 1, 1000000)
		or not Validate.isInteger(answer, 1, 3)
	then
		deps.SecurityService.Report(player, "InvalidPayload", "HackChallenge")
		deps.NetworkService.Reject(player, "Challenge", Protocol.Codes.InvalidPayload)
		return
	end
	local ok, code = deps.MatchService
		.GetDirector()
		:respondChallenge(player.UserId, matchId, terminalId, nonce, answer, workspace:GetServerTimeNow())
	if ok then
		deps.NetworkService.Accept(player, "Challenge")
	else
		deps.NetworkService.Reject(player, "Challenge", code)
	end
end

function ObjectiveService.Start()
	ObjectiveService.BindTerminals()
	deps.NetworkService.OnRequest(RemoteNames.HackChallengeRequest, handleChallenge)
	deps.NetworkService.OnRequest(RemoteNames.ObjectiveRequest, handleObjectiveRequest)
	ObjectiveService.ResetVisuals()
end

-- Mirrors one authoritative terminal snapshot onto its world visuals.
function ObjectiveService.OnTerminalChanged(terminal: { id: string, state: string })
	deps.WorldService.SetTerminalVisual(
		terminal.id,
		terminal.state,
		terminal.state == "Available" or terminal.state == "Hacking"
	)
end

function ObjectiveService.ResetVisuals()
	for _, terminal in deps.WorldService.GetTerminals() do
		deps.WorldService.SetTerminalVisual(terminal.id, "Locked", false)
	end
end

return ObjectiveService
