--!strict
-- UIController: owns the ScreenGui, responsive scaling, and screen routing.
--   * Lobby when the local player is not an active participant of a live match; HUD when they are.
--   * Role reveal, results, loadout, settings, toasts/banners, and the connection overlay.
--   * Scale = viewport-height factor (clamped for phones) × the player's UIScale setting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Protocol = require(ReplicatedStorage.Shared.Network.Protocol)

local ClientState = require(script.Parent.Parent.ClientState)
local ConnectionOverlay = require(script.Parent.Parent.UI.Screens.ConnectionOverlay)
local Create = require(script.Parent.Parent.UI.Components.Create)
local DeploymentScreen = require(script.Parent.Parent.UI.Screens.DeploymentScreen)
local HudScreen = require(script.Parent.Parent.UI.Screens.HudScreen)
local LoadoutScreen = require(script.Parent.Parent.UI.Screens.LoadoutScreen)
local LobbyScreen = require(script.Parent.Parent.UI.Screens.LobbyScreen)
local ResultsScreen = require(script.Parent.Parent.UI.Screens.ResultsScreen)
local RoleReveal = require(script.Parent.Parent.UI.Screens.RoleReveal)
local SettingsScreen = require(script.Parent.Parent.UI.Screens.SettingsScreen)
local Toasts = require(script.Parent.Parent.UI.Screens.Toasts)

local UIController = {}

local player = Players.LocalPlayer
local deps: { [string]: any } = {}
local screenGui: ScreenGui? = nil
local uiScale: UIScale? = nil
local toasts: Toasts.Toasts? = nil
local lobby: any = nil
local hud: any = nil
local loadout: any = nil
local deployment: any = nil
local settingsScreen: any = nil
local pendingMessages: { { kind: string, text: string, severity: string?, duration: number? } } = {}

local function computeScale(): number
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local base = math.clamp(viewport.Y / 760, 0.72, 1.3)
	-- Narrow portrait screens: also respect width.
	base = math.min(base, math.max(0.6, viewport.X / 900))
	local settings = ClientState.get("settings")
	local userScale = if settings and settings.UIScale then settings.UIScale else 1
	return base * userScale
end

local function applyScale()
	if uiScale then
		uiScale.Scale = computeScale()
	end
end

local function route()
	if not lobby or not hud then
		return
	end
	local live = ClientState.isLiveParticipant()
	local snapshot = ClientState.get("snapshot")
	local me = ClientState.myParticipant()
	-- Keep the HUD through the results phase for players still in the vault.
	local showHud = live
		or (
			snapshot ~= nil
			and me ~= nil
			and me.status == "Active"
			and (snapshot.phase == "Resolving" or snapshot.phase == "ReturningToLobby")
		)
	hud.SetVisible(showHud)
	lobby.SetVisible(not showHud)
	if live and deployment then
		deployment.Modal:Close()
	end
	if live and loadout and loadout.Modal:IsOpen() then
		loadout.Modal:Close()
	end
end

function UIController.Toast(text: string, severity: string?, duration: number?)
	if toasts then
		(toasts :: Toasts.Toasts):Toast(text, severity, duration)
	else
		table.insert(pendingMessages, { kind = "Toast", text = text, severity = severity, duration = duration })
	end
end

function UIController.Announce(text: string, severity: string?, duration: number?)
	if toasts then
		(toasts :: Toasts.Toasts):Announce(text, severity, duration)
	else
		table.insert(pendingMessages, { kind = "Announcement", text = text, severity = severity, duration = duration })
	end
end

function UIController.HandleNotify(payload: any)
	if type(payload) ~= "table" or type(payload.text) ~= "string" then
		return
	end
	if payload.kind == Protocol.NotifyKinds.Announcement then
		UIController.Announce(payload.text, payload.severity, payload.duration)
	else
		UIController.Toast(payload.text, payload.severity, payload.duration)
		if payload.severity == "Danger" then
			deps.AudioController.Play("HackInterrupted")
		end
	end
end

function UIController.HandleActionResult(result: any)
	if type(result) ~= "table" then
		return
	end
	if loadout then
		loadout.OnActionResult(result)
	end
	if result.ok then
		if result.action == "Shop" then
			deps.AudioController.Play("UiClick")
			UIController.Toast(if result.shopAction == "Purchase" then "Purchased!" else "Equipped.", "Success", 2)
		elseif result.action == "HackStart" then
			deps.AudioController.Play("HackStart")
		end
		return
	end
	-- Quiet rejections that the HUD already communicates.
	if result.code == Protocol.Codes.OnCooldown and result.action == "Ability" then
		return
	end
	deps.AudioController.Play("UiError")
	UIController.Toast(result.message or Protocol.messageFor(result.code), "Warning", 2.5)
end

function UIController.OpenModal(name: string)
	if deployment then
		deployment.Modal:Close()
	end
	if loadout then
		loadout.Modal:Close()
	end
	if settingsScreen then
		settingsScreen.Modal:Close()
	end
	if name == "Deployment" and deployment then
		deployment.Open()
		return
	end
	if name == "Loadout" and loadout then
		if settingsScreen then
			settingsScreen.Modal:Close()
		end
		loadout.Open()
	elseif name == "Settings" and settingsScreen then
		if loadout then
			loadout.Modal:Close()
		end
		settingsScreen.Open()
	end
end

function UIController.Init(injected: { [string]: any })
	deps = injected
	local gui = Create("ScreenGui", {
		Name = "ChronoUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	screenGui = gui
	uiScale = Create("UIScale", { Parent = gui })
	ConnectionOverlay.new(gui)
end

function UIController.Start()
	local gui = screenGui :: ScreenGui
	-- The lobby menu and squad panel own the top-right corner; there are no leaderstats to show, and
	-- the Roblox menu's People tab still covers report/friend actions.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	lobby = LobbyScreen.new(gui, deps)
	hud = HudScreen.new(gui, deps)
	RoleReveal.new(gui, deps)
	ResultsScreen.new(gui, deps)
	loadout = LoadoutScreen.new(gui, deps)
	deployment = DeploymentScreen.new(gui)
	settingsScreen = SettingsScreen.new(gui, deps)
	toasts = Toasts.new(gui)
	for _, message in pendingMessages do
		if message.kind == "Announcement" then
			UIController.Announce(message.text, message.severity, message.duration)
		else
			UIController.Toast(message.text, message.severity, message.duration)
		end
	end
	table.clear(pendingMessages)

	ClientState.changed:Connect(function(key: string)
		if key == "snapshot" or key == "role" then
			route()
		elseif key == "settings" then
			applyScale()
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
	applyScale()
	route()
end

return UIController
