--!strict
-- In-engine E2E client agent (TEST PLACE ONLY — mapped by test.project.json, never by
-- default.project.json). Executes commands from the server driver (src/Tests/E2E) exactly the way a
-- player's UI would — firing the real remotes and pressing the real ProximityPrompts — and reports the
-- client's mirrored state and UI visibility back over the test-only E2EChannel remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end
local channel = ReplicatedStorage:WaitForChild("E2EChannel", 30) :: RemoteEvent?
if not channel then
	return -- driver disabled; nothing to do
end
local player = Players.LocalPlayer
local clientFolder = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
local ClientState = (require :: any)(clientFolder:WaitForChild("ClientState"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Decodes argument placeholders that cannot travel over a remote as-is.
local function decode(value: any): any
	if type(value) == "table" and value["$nil"] then
		return nil
	elseif type(value) == "table" and value["$nanVector"] then
		return Vector3.new(0 / 0, 0, 0)
	elseif type(value) == "table" and value["$hugeVector"] then
		return Vector3.new(math.huge, 0, 0)
	end
	return value
end

local function isShown(gui: Instance, root: Instance): boolean
	local node: Instance? = gui
	while node and node ~= root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

local function texts(frame: Instance, root: Instance, limit: number): { string }
	local list = {}
	for _, d in frame:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and isShown(d, root) then
			table.insert(list, d.Text)
			if #list >= limit then
				break
			end
		end
	end
	return list
end

-- Layout lint for what is currently on screen: text that does not fit its box (and is not
-- deliberately truncated/scaled) and visible elements that spill outside the ScreenGui.
local function lintLayout(gui: ScreenGui): { string }
	local issues = {}
	local origin, size = gui.AbsolutePosition, gui.AbsoluteSize
	local function inScroller(d: Instance): boolean
		local node = d.Parent
		while node and node ~= gui do
			if node:IsA("ScrollingFrame") then
				return true
			end
			node = node.Parent
		end
		return false
	end
	for _, d in gui:GetDescendants() do
		if #issues >= 15 then
			break
		end
		if d:IsA("GuiObject") and isShown(d, gui) and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
			local name = d:GetFullName():gsub("^.-ChronoUI%.", "")
			if
				(d:IsA("TextLabel") or d:IsA("TextButton"))
				and d.Text ~= ""
				and not d.TextScaled
				and d.TextTruncate == Enum.TextTruncate.None
				and not d.TextFits
			then
				table.insert(issues, `clipped text: {name} "{string.sub(d.Text, 1, 40)}"`)
			end
			local rel = d.AbsolutePosition - origin
			local far = rel + d.AbsoluteSize
			if not inScroller(d) and (rel.X < -1 or rel.Y < -1 or far.X > size.X + 1 or far.Y > size.Y + 1) then
				table.insert(
					issues,
					`offscreen: {name} at {math.floor(rel.X)},{math.floor(rel.Y)} size {math.floor(d.AbsoluteSize.X)}x{math.floor(
						d.AbsoluteSize.Y
					)}`
				)
			end
		end
	end
	return issues
end

local function snapshot(): { [string]: any }
	local gui = player.PlayerGui:FindFirstChild("ChronoUI")
	local out: { [string]: any } = {
		connection = ClientState.get("connection"),
		isLive = ClientState.isLiveParticipant(),
		extraction = ClientState.get("extraction"),
	}
	local snap = ClientState.get("snapshot")
	out.phase = snap and snap.phase
	out.completedHacks = snap and snap.completedHacks
	local role = ClientState.currentRole()
	out.role = role and role.role
	local queue = ClientState.get("queue")
	out.queued = queue and queue.queued
	local movement = ClientState.get("movement") or {}
	out.slowed = movement.slowed
	out.stunned = movement.stunned
	out.rooted = movement.rooted
	out.invulnerable = movement.invulnerable
	out.corePlayerList = game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	local result = ClientState.get("result")
	if result then
		out.result = {
			matchId = result.matchId,
			winner = result.winner,
			reason = result.reason,
			won = result.won,
			total = result.rewardTotal,
			lines = #result.rewards,
		}
	end
	local profile = ClientState.get("profile")
	out.currency = profile and profile.currency
	out.owned = profile and profile.owned
	out.equipped = profile and profile.equipped
	out.terminalStates = {}
	for id, terminal in ClientState.get("terminals") or {} do
		out.terminalStates[id] = terminal.state
	end
	out.participants = {}
	for _, p in (snap and snap.participants) or {} do
		out.participants[tostring(p.userId)] = p.role .. ":" .. p.status
	end
	local abilities = ClientState.get("abilities") or {}
	out.abilityReadyAt = {}
	for id, state in abilities do
		out.abilityReadyAt[id] = state.readyAt
	end
	if gui then
		out.layoutIssues = lintLayout(gui :: ScreenGui)
		out.viewport = `{math.floor((gui :: ScreenGui).AbsoluteSize.X)}x{math.floor((gui :: ScreenGui).AbsoluteSize.Y)}`
		out.uiScale = (gui:FindFirstChildOfClass("UIScale") :: UIScale?)
			and (gui:FindFirstChildOfClass("UIScale") :: UIScale).Scale
		for _, name in { "ConnectionOverlay", "Lobby", "Hud", "RoleReveal", "Results", "Loadout", "Settings" } do
			local f = gui:FindFirstChild(name) :: GuiObject?
			out["ui_" .. name] = f ~= nil and f.Visible
		end
		local hud = gui:FindFirstChild("Hud")
		if hud then
			local hack = hud:FindFirstChild("HackPanel") :: GuiObject?
			out.ui_HackPanel = hack ~= nil and hack.Visible and (hud :: GuiObject).Visible
			local bar = hud:FindFirstChild("AbilityBar")
			local slots = 0
			if bar then
				for _, child in bar:GetChildren() do
					if child:IsA("TextButton") then
						slots += 1
					end
				end
			end
			out.ui_abilitySlots = slots
			if (hud :: GuiObject).Visible then
				out.hudTexts = texts(hud, gui, 30)
			end
		end
		local lobby = gui:FindFirstChild("Lobby")
		if lobby and (lobby :: GuiObject).Visible then
			out.lobbyTexts = texts(lobby, gui, 20)
		end
		local results = gui:FindFirstChild("Results")
		if results and (results :: GuiObject).Visible then
			out.resultsTexts = texts(results, gui, 30)
		end
	end
	return out
end

local function fire(remoteName: string, args: { any }, collectFor: number): { any }
	local collected = {}
	local conn = (remotes :: any).ActionResult.OnClientEvent:Connect(function(payload)
		table.insert(collected, { action = payload.action, ok = payload.ok, code = payload.code })
	end)
	-- Placeholders keep the argument count exact (nil holes do not survive remote serialisation).
	local count = #args
	local decoded = table.create(count)
	for i = 1, count do
		decoded[i] = decode(args[i])
	end
	local remote = remotes:FindFirstChild(remoteName) :: RemoteEvent
	remote:FireServer(table.unpack(decoded, 1, count))
	task.wait(collectFor)
	conn:Disconnect()
	return collected
end

local function pressPrompt(terminalName: string): string
	local root = workspace:FindFirstChild("ChronoBreakers")
	local terminal = root and root.Vault.Static.Terminals:FindFirstChild(terminalName)
	local prompt = terminal and terminal:FindFirstChild("HackPrompt", true) :: ProximityPrompt?
	if not prompt then
		return "missing"
	end
	-- Read Enabled BEFORE pressing: a successful hack immediately disables the prompt.
	local enabledBefore = prompt.Enabled
	prompt:InputHoldBegin()
	task.wait(0.05)
	prompt:InputHoldEnd()
	return if enabledBefore then "pressed" else "pressed-disabled"
end

channel.OnClientEvent:Connect(function(message: any)
	if type(message) ~= "table" or type(message.id) ~= "number" then
		return
	end
	local ok, data = pcall(function(): any
		local cmd = message.cmd
		local args = message.args or {}
		if cmd == "snapshot" then
			return snapshot()
		elseif cmd == "fire" then
			return fire(args.remote, args.args or {}, args.collect or 1)
		elseif cmd == "burst" then
			local collected = {}
			local conn = (remotes :: any).ActionResult.OnClientEvent:Connect(function(payload)
				table.insert(collected, payload.code)
			end)
			for _ = 1, args.count do
				(remotes:FindFirstChild(args.remote) :: RemoteEvent):FireServer(table.unpack(args.args))
			end
			task.wait(1.5)
			conn:Disconnect()
			return collected
		elseif cmd == "prompt" then
			return pressPrompt(args.terminal)
		elseif cmd == "camera" then
			-- Visual review only: frame a shot from the server (e.g. via the Studio MCP plugin).
			local cam = workspace.CurrentCamera
			if args.reset then
				cam.CameraType = Enum.CameraType.Custom
			else
				cam.CameraType = Enum.CameraType.Scriptable
				cam.CFrame = CFrame.lookAt(args.from, args.at)
			end
			return "ok"
		elseif cmd == "ui" then
			local gui = player.PlayerGui:FindFirstChild("ChronoUI") :: ScreenGui?
			if gui then
				gui.Enabled = args.enabled == true
			end
			return "ok"
		end
		return "unknown command"
	end)
	channel:FireServer({ id = message.id, ok = ok, data = data })
end)

channel:FireServer({ id = 0, hello = true })
