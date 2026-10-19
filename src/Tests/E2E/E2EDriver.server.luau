--!strict
-- In-engine end-to-end playtest driver (TEST PLACE ONLY; enabled by the RunE2E attribute that
-- test.project.json sets on ServerScriptService.Tests). Start a Studio Play session (F5) with ONE
-- player: the driver plays two complete matches through the real services, real character, real
-- remotes, and real ProximityPrompts, and prints "[E2E] PASS/FAIL ..." lines plus a summary.
-- Results are read through Roblox Studio MCP (get_output_logs on the play server peer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Safe = require(ReplicatedStorage.Shared.Modules.Safe)

local testsFolder = script.Parent.Parent
if not RunService:IsStudio() or testsFolder:GetAttribute("RunE2E") ~= true then
	return
end

local channel = Instance.new("RemoteEvent")
channel.Name = "E2EChannel"
local replies: { [number]: any } = {}
local helloPlayers: { Player } = {}
channel.OnServerEvent:Connect(function(player: Player, message: any)
	if type(message) ~= "table" then
		return
	end
	if message.hello then
		if not table.find(helloPlayers, player) then
			table.insert(helloPlayers, player)
		end
	elseif type(message.id) == "number" then
		replies[message.id] = message
	end
end)
channel.Parent = ReplicatedStorage

local Server = ServerScriptService:WaitForChild("Server")
local function req(path: { string }): any
	local node: Instance = Server
	for _, name in path do
		node = node:WaitForChild(name)
	end
	return (require :: any)(node)
end
local MatchService = req({ "Services", "MatchService" })
local StatusEffectService = req({ "Services", "StatusEffectService" })
local WorldService = req({ "Services", "WorldService" })
local AbilityService = req({ "Services", "AbilityService" })
local AnomalyService = req({ "Services", "AnomalyService" })
AnomalyService.SetTestPaused(true)
local PlayerDataService = req({ "Services", "PlayerDataService" })
local FreezeZone = req({ "Components", "FreezeZone" })
local TemporalTrap = req({ "Components", "TemporalTrap" })
local PlacementRules = req({ "Core", "PlacementRules" })
local MapValidator = req({ "World", "MapValidator" })
local ClassConfig = require(ReplicatedStorage.Shared.Config.ClassConfig)
local Economy = req({ "Core", "Economy" })

local passed, failed = 0, 0
local function check(name: string, condition: boolean, detail: any?)
	if condition then
		passed += 1
		print(`[E2E] PASS {name}`)
	else
		failed += 1
		warn(`[E2E] FAIL {name} :: {tostring(detail)}`)
	end
end

local function waitFor(predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local ok, result = pcall(predicate)
		if ok and result then
			return true
		end
		task.wait(0.1)
	end
	return false
end

local nextId = 0
local function client(player: Player, cmd: string, args: any?, timeout: number?): any
	nextId += 1
	local id = nextId
	channel:FireClient(player, { id = id, cmd = cmd, args = args })
	local ok = waitFor(function()
		return replies[id] ~= nil
	end, timeout or 10)
	if not ok then
		return nil
	end
	local reply = replies[id]
	replies[id] = nil
	return if reply.ok then reply.data else { error = reply.data }
end

local function codes(results: any): { string }
	local list = {}
	for _, r in results or {} do
		table.insert(list, tostring(r.code))
	end
	return list
end

local function hasCode(results: any, code: string): boolean
	return table.find(codes(results), code) ~= nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function baseline(player: Player): number
	if not MatchService.IsInMatch(player) then
		return 16
	end
	local class = ClassConfig.get(MatchService.GetMatchClass(player))
	return if class then class.WalkSpeed else 17
end

local function near(a: number?, b: number, eps: number?): boolean
	return a ~= nil and math.abs(a - b) <= (eps or 0.05)
end

local function terminalSpec(id: string): any
	for _, t in WorldService.GetMap().terminals do
		if t.id == id then
			return t
		end
	end
	return nil
end

local function moveTo(player: Player, position: Vector3)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(position))
		req({ "Services", "SecurityService" }).ResetMovement(player)
	end
end

local function moveToTerminal(player: Player, id: string)
	local spec = terminalSpec(id)
	moveTo(player, MapValidator.interactionPoint(spec))
	task.wait(0.4)
end

local function terminalState(id: string): string?
	local snap = MatchService.GetDirector():publicTerminal(id)
	return snap and snap.state
end

local function hackToCompletion(player: Player, id: string, label: string)
	moveToTerminal(player, id)
	local pressed = client(player, "prompt", { terminal = `Terminal_{id}` })
	check(`{label}: prompt pressed via ProximityPrompt`, pressed == "pressed", pressed)
	check(
		`{label}: server started the hack`,
		waitFor(function()
			return terminalState(id) == "Hacking"
		end, 3),
		terminalState(id)
	)
	check(
		`{label}: terminal completes after ~15 s`,
		waitFor(function()
			return terminalState(id) == "Completed"
		end, 20),
		terminalState(id)
	)
end

local function runMatchOne(player: Player)
	local d = MatchService.GetDirector()
	local profileBefore = PlayerDataService.GetProfile(player)
	local scrapBefore = profileBefore and profileBefore.ChronosScrap or 0

	-- 1. Lobby state
	local humanoid = humanoidOf(player)
	local root = rootOf(player)
	check("lobby: character spawned", humanoid ~= nil and root ~= nil)
	check(
		"lobby: spawned in the lobby area",
		root ~= nil and (root :: BasePart).Position.Z > 250,
		root and root.Position
	)
	check(
		"lobby: baseline walk speed 16",
		humanoid ~= nil and near((humanoid :: Humanoid).WalkSpeed, 16),
		humanoid and humanoid.WalkSpeed
	)
	local character = player.Character :: Model
	local healthScript = character:FindFirstChild("Health")
	check("lobby: default Health regen script replaced", healthScript ~= nil and healthScript:IsA("Script"))
	local snap = client(player, "snapshot")
	check("client: connected and booted", snap and snap.connection == "Ready", snap and snap.connection)
	check("client: lobby visible, HUD hidden", snap and snap.ui_Lobby == true and snap.ui_Hud == false, snap)
	check(
		"layout: lobby has no clipped or offscreen elements",
		snap ~= nil and snap.layoutIssues ~= nil and #snap.layoutIssues == 0,
		snap and { viewport = snap.viewport, issues = snap.layoutIssues }
	)
	check("client: connection overlay hidden", snap and snap.ui_ConnectionOverlay == false)
	check("client: profile snapshot received", snap and type(snap.currency) == "number")

	-- 2. Queue (+ invalid queue payloads)
	local bad = client(player, "fire", { remote = "QueueRequest", args = { "Hack" } })
	check("queue: unknown action rejected InvalidPayload", hasCode(bad, "InvalidPayload"), codes(bad))
	local join = client(player, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("queue: join accepted", join and join[1] and join[1].ok == true, codes(join))
	local dup = client(player, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("queue: duplicate join rejected AlreadyQueued", hasCode(dup, "AlreadyQueued"), codes(dup))
	snap = client(player, "snapshot")
	check("client: queue state shows queued", snap and snap.queued == true)

	-- 3. Intermission -> Intro (Studio solo: keeperless, 5 s intermission)
	check(
		"match: intermission started",
		waitFor(function()
			return d:getPhase() == "Intermission" or d:getPhase() == "Intro"
		end, 5),
		d:getPhase()
	)
	check(
		"match: intro started",
		waitFor(function()
			return d:getPhase() == "Intro"
		end, 12),
		d:getPhase()
	)
	check(
		"match: player is an Infiltrator (solo, keeperless)",
		d:getRole(player.UserId) == "Infiltrator",
		d:getRole(player.UserId)
	)
	check(
		"match: respawned at an Infiltrator spawn",
		waitFor(function()
			local r = rootOf(player)
			return r ~= nil and r.Position.Z > 55 and r.Position.Z < 85 and r.Position.X < -50
		end, 8),
		rootOf(player) and (rootOf(player) :: BasePart).Position
	)
	check(
		"match: held in place during intro",
		waitFor(function()
			local h = humanoidOf(player)
			return h ~= nil and h.WalkSpeed == 0
		end, 3),
		humanoidOf(player) and (humanoidOf(player) :: Humanoid).WalkSpeed
	)
	snap = client(player, "snapshot")
	check("client: role reveal visible during intro", snap and snap.ui_RoleReveal == true, snap and snap.ui_RoleReveal)
	check("client: role received as Infiltrator", snap and snap.role == "Infiltrator", snap and snap.role)

	-- 4. Active
	check(
		"match: active phase",
		waitFor(function()
			return d:getPhase() == "Active"
		end, 12),
		d:getPhase()
	)
	check(
		"match: movement restored to 16 after intro",
		waitFor(function()
			local h = humanoidOf(player)
			return h ~= nil and near(h.WalkSpeed, baseline(player))
		end, 2),
		humanoidOf(player) and (humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check("match: spawn protection active", StatusEffectService.IsInvulnerable(player))
	check(
		"world: terminals available with prompts enabled",
		waitFor(function()
			for _, t in WorldService.GetTerminals() do
				if t.model:GetAttribute("State") ~= "Available" or not t.prompt.Enabled then
					return false
				end
			end
			return true
		end, 2)
	)
	snap = client(player, "snapshot")
	check("client: HUD visible, lobby hidden", snap and snap.ui_Hud == true and snap.ui_Lobby == false, snap)
	check("client: core PlayerList hidden (squad panel owns top-right)", snap and snap.corePlayerList == false)
	check(
		"layout: HUD has no clipped or offscreen elements",
		snap ~= nil and snap.layoutIssues ~= nil and #snap.layoutIssues == 0,
		snap and { viewport = snap.viewport, issues = snap.layoutIssues }
	)
	check("client: role reveal dismissed", snap and snap.ui_RoleReveal == false)
	check(
		"client: one gadget slot in the ability bar",
		snap and snap.ui_abilitySlots == 2,
		snap and snap.ui_abilitySlots
	)

	-- 5. Server authority: illegal/invalid requests from the real client
	local r1 = client(player, "fire", { remote = "AbilityRequest", args = { "ChronoStrike" } })
	check("authority: Infiltrator cannot use Chrono Strike (WrongRole)", hasCode(r1, "WrongRole"), codes(r1))
	local r2 = client(
		player,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", { ["$nanVector"] = true } } :: { any } }
	)
	check("authority: NaN target rejected (InvalidPayload)", hasCode(r2, "InvalidPayload"), codes(r2))
	local r3 = client(player, "fire", {
		remote = "AbilityRequest",
		args = { "Stabilizer", { ["$nil"] = true }, { ["$nil"] = true }, "extra" } :: { any },
	})
	check("authority: extra arguments rejected (InvalidPayload)", hasCode(r3, "InvalidPayload"), codes(r3))
	local r4 = client(player, "fire", { remote = "AbilityRequest", args = { "PhaseDash" } })
	check("authority: unequipped gadget rejected (NotOwned)", hasCode(r4, "NotOwned"), codes(r4))
	local r5 = client(player, "fire", { remote = "ShopRequest", args = { "Purchase", "PhaseDash" } })
	check("authority: shop locked during a live match (InMatch)", hasCode(r5, "InMatch"), codes(r5))
	local okHack, hackCode = MatchService.RequestHack(player, "ArchiveTerminal")
	check(
		"authority: hack from spawn rejected OutOfRange (server-measured)",
		not okHack and hackCode == "OutOfRange",
		hackCode
	)
	local okForged, forgedCode = MatchService.RequestHack(player, "ForgedTerminal")
	check("authority: forged terminal id rejected", not okForged and forgedCode == "UnknownTarget", forgedCode)

	-- 6. Gadget: Stabilizer (equipped by default) + server cooldown
	local g1 = client(player, "fire", { remote = "AbilityRequest", args = { "Stabilizer" } })
	check("gadget: Stabilizer accepted", g1 and g1[1] and g1[1].ok == true, codes(g1))
	check("gadget: slow immunity applied", StatusEffectService.Has(player, "SlowImmunity"))
	local g2 = client(player, "fire", { remote = "AbilityRequest", args = { "Stabilizer" } })
	check("gadget: immediate re-use rejected OnCooldown", hasCode(g2, "OnCooldown"), codes(g2))
	snap = client(player, "snapshot")
	check(
		"client: ability cooldown mirrored",
		snap and snap.abilityReadyAt and (snap.abilityReadyAt.Stabilizer or 0) > Workspace:GetServerTimeNow(),
		snap and snap.abilityReadyAt
	)
	StatusEffectService.Remove(player, "stabilizer") -- clear immunity before the slow tests

	-- 7. Rate limiting on the real remote
	local burst = client(player, "burst", { remote = "AbilityRequest", args = { "Stabilizer" }, count = 20 }, 15)
	check("security: request burst is rate limited", burst and table.find(burst, "RateLimited") ~= nil, burst)

	-- 8. Time-Freeze Zone + overlap on the real Humanoid (component + StatusEffectService)
	local here = (rootOf(player) :: BasePart).Position
	local function zone(id: string, duration: number)
		return FreezeZone.new({
			id = id,
			center = Vector3.new(here.X, 0, here.Z),
			radius = 15,
			telegraph = 0.3,
			duration = duration,
			slowMagnitude = 0.7,
			membershipInterval = 0.2,
			linger = 0.35,
			startedAt = Workspace:GetServerTimeNow(),
			parent = WorldService.GetRuntimeFolder(),
			getTargets = function()
				return { player }
			end,
			applySlow = function(victim, key, magnitude, duration2)
				StatusEffectService.Apply(
					victim,
					{ key = key, kind = "Slow", magnitude = magnitude, duration = duration2, source = "TimeFreeze" }
				)
			end,
			removeKeyFromAll = StatusEffectService.RemoveKeyFromAll,
		})
	end
	local zoneA, zoneB = zone("e2eA", 1.5), zone("e2eB", 3.5)
	local zoneRunning = true
	task.spawn(function()
		while zoneRunning do
			local t = Workspace:GetServerTimeNow()
			if not zoneA:isDestroyed() and zoneA:update(t) then
				zoneA:destroy()
			end
			if not zoneB:isDestroyed() and zoneB:update(t) then
				zoneB:destroy()
			end
			task.wait(0.1)
		end
	end)
	check(
		"freeze: telegraph does not slow immediately",
		near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player)),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check(
		"freeze: 70% slow applied from baseline (4.8)",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player) * 0.3)
		end, 2),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	task.wait(1.5) -- zone A expired, zone B still active
	check(
		"freeze: overlapping zones do not stack; slow persists after one expires",
		near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player) * 0.3),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	snap = client(player, "snapshot")
	check("client: slowed status mirrored", snap and snap.slowed == true)
	check(
		"freeze: speed restored to exactly 16 after all zones end",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player))
		end, 4),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	zoneRunning = false
	zoneA:destroy()
	zoneB:destroy()

	-- 9. Hack, interruption by range, progress retention
	moveToTerminal(player, "ArchiveTerminal")
	local pressed = client(player, "prompt", { terminal = "Terminal_ArchiveTerminal" })
	check("hack: prompt pressed", pressed == "pressed", pressed)
	check(
		"hack: server started Archive hack",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Hacking"
		end, 3),
		terminalState("ArchiveTerminal")
	)
	task.wait(1)
	snap = client(player, "snapshot")
	check("client: hack panel visible while hacking", snap and snap.ui_HackPanel == true, snap and snap.ui_HackPanel)
	check(
		"layout: HUD while hacking has no clipped or offscreen elements",
		snap ~= nil and snap.layoutIssues ~= nil and #snap.layoutIssues == 0,
		snap and { viewport = snap.viewport, issues = snap.layoutIssues }
	)
	task.wait(4)
	moveTo(player, here) -- walk away (teleport) out of range
	check(
		"hack: leaving range interrupts",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Interrupted"
		end, 2),
		terminalState("ArchiveTerminal")
	)
	local progress = (MatchService.GetDirector():publicTerminal("ArchiveTerminal") :: any).progress
	check("hack: progress retained after interruption (~33%)", progress > 0.25 and progress < 0.5, progress)
	check(
		"hack: terminal re-available after lockout",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Available"
		end, 3),
		terminalState("ArchiveTerminal")
	)

	-- 10. Temporal Trap stuns (interrupting the hack via Restrained) on the real Humanoid
	moveToTerminal(player, "ArchiveTerminal")
	client(player, "prompt", { terminal = "Terminal_ArchiveTerminal" })
	waitFor(function()
		return terminalState("ArchiveTerminal") == "Hacking"
	end, 3)
	local trapPos = (rootOf(player) :: BasePart).Position
	local trap = TemporalTrap.new({
		id = "e2eTrap",
		position = Vector3.new(trapPos.X, 0, trapPos.Z),
		armingTime = 0.2,
		triggerRadius = 4,
		lifetime = 30,
		placedAt = Workspace:GetServerTimeNow(),
		parent = WorldService.GetRuntimeFolder(),
		getTargets = function()
			return { player }
		end,
		onTriggered = function(_, victim)
			StatusEffectService.Apply(
				victim,
				{ key = "trap:e2e:stun", kind = "Stun", magnitude = 1, duration = 1.25, source = "TemporalTrap" }
			)
			StatusEffectService.Apply(
				victim,
				{ key = "trap:e2e:slow", kind = "Slow", magnitude = 0.4, duration = 3.75, source = "TemporalTrap" }
			)
		end,
	})
	local triggered = waitFor(function()
		return trap:update(Workspace:GetServerTimeNow())
	end, 3)
	trap:destroy()
	check("trap: triggers on the Infiltrator", triggered)
	check(
		"trap: stun sets speed 0",
		near((humanoidOf(player) :: Humanoid).WalkSpeed, 0),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check(
		"trap: stun interrupts hacking (Restrained)",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Interrupted"
		end, 2),
		terminalState("ArchiveTerminal")
	)
	check(
		"trap: after stun, 40% slow (9.6)",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player) * 0.6)
		end, 3),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check(
		"trap: speed restored to 16",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, baseline(player))
		end, 4),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)

	-- 11. Placement validation against the real vault geometry
	local function place(caster: Vector3, target: any, range: number): string
		local _, code = PlacementRules.validateGroundTarget({
			casterPosition = caster,
			eyePosition = caster + Vector3.new(0, 1.5, 0),
			target = target,
			maxRange = range,
			boundsMin = WorldService.GetMap().boundsMin,
			boundsMax = WorldService.GetMap().boundsMax,
			castDown = WorldService.CastDown,
			lineOfSight = WorldService.HasLineOfSight,
		})
		return code
	end
	local caster = Vector3.new(0, 3, 20)
	check(
		"placement: open floor accepted",
		place(caster, Vector3.new(0, 0.5, 30), 70) == "Ok",
		place(caster, Vector3.new(0, 0.5, 30), 70)
	)
	check(
		"placement: behind the Chrono Core rejected (NoLineOfSight)",
		place(caster, Vector3.new(0, 0, -20), 70) == "NoLineOfSight",
		place(caster, Vector3.new(0, 0, -20), 70)
	)
	check(
		"placement: through a partition wall rejected",
		place(caster, Vector3.new(20, 0, 50), 70) == "NoLineOfSight",
		place(caster, Vector3.new(20, 0, 50), 70)
	)
	check(
		"placement: outside the vault rejected",
		place(Vector3.new(-40, 3, 20), Vector3.new(-95, 0, 20), 70) == "OutOfBounds",
		place(Vector3.new(-40, 3, 20), Vector3.new(-95, 0, 20), 70)
	)
	check(
		"placement: mid-air rejected",
		place(caster, Vector3.new(0, 30, 30), 70) == "InvalidPlacement",
		place(caster, Vector3.new(0, 30, 30), 70)
	)
	check(
		"placement: beyond cast range rejected",
		place(caster, Vector3.new(0, 0, 89), 18) == "OutOfRange",
		place(caster, Vector3.new(0, 0, 89), 18)
	)

	-- 12. Complete all three terminals -> extraction
	check(
		"hack: Archive resumable after interruptions",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Available"
		end, 3),
		terminalState("ArchiveTerminal")
	)
	hackToCompletion(player, "ArchiveTerminal", "Archive")
	hackToCompletion(player, "ReactorTerminal", "Reactor")
	hackToCompletion(player, "ObservatoryTerminal", "Observatory")
	check(
		"extraction: phase entered after 3 hacks",
		waitFor(function()
			return d:getPhase() == "Extraction"
		end, 3),
		d:getPhase()
	)
	local gate = (Workspace :: any).ChronoBreakers.Vault.Static.BreachGate :: BasePart
	check("extraction: gate opened (non-colliding)", gate:GetAttribute("Open") == true and gate.CanCollide == false)
	snap = client(player, "snapshot")
	check("client: extraction visible in HUD", snap and snap.phase == "Extraction")

	-- 13. Extract -> resolution -> rewards
	moveTo(player, WorldService.GetMap().extractionCenter)
	check(
		"extraction: player extracted after channel",
		waitFor(function()
			local p = d:getParticipant(player.UserId)
			return p ~= nil and p.status == "Extracted"
		end, 6)
	)
	check(
		"result: match resolved",
		waitFor(function()
			return d:getPhase() == "Resolving"
		end, 3),
		d:getPhase()
	)
	local result = d.session and d.session.result
	check(
		"result: Infiltrators win by extraction",
		result and result.winner == "Infiltrators" and result.reason == "Extracted",
		result and result.reason
	)
	snap = client(player, "snapshot")
	check("client: results screen visible", snap and snap.ui_Results == true, snap and snap.ui_Results)
	check(
		"layout: results has no clipped or offscreen elements",
		snap ~= nil and snap.layoutIssues ~= nil and #snap.layoutIssues == 0,
		snap and { viewport = snap.viewport, issues = snap.layoutIssues }
	)
	check(
		"client: victory with reward breakdown",
		snap and snap.result and snap.result.won == true and snap.result.lines >= 3,
		snap and snap.result
	)
	local expected = 20 + 50 + 3 * 15 + 40
	check(
		`rewards: payout = {expected}`,
		snap and snap.result and snap.result.total == expected,
		snap and snap.result and snap.result.total
	)
	local profile = PlayerDataService.GetProfile(player)
	check(
		"rewards: profile credited exactly once",
		profile and profile.ChronosScrap == scrapBefore + expected,
		profile and profile.ChronosScrap
	)
	local matchId = result and result.matchId
	req({ "Services", "RewardService" }).GrantMatchRewards(result)
	check(
		"rewards: duplicate resolution does not pay twice",
		profile and profile.ChronosScrap == scrapBefore + expected,
		profile and profile.ChronosScrap
	)

	-- 14. Return to lobby + cleanup
	check(
		"lifecycle: back to WaitingForPlayers",
		waitFor(function()
			return d:getPhase() == "WaitingForPlayers"
		end, 25),
		d:getPhase()
	)
	check("lifecycle: session cleared", d.session == nil)
	check("lifecycle: stale match id rejected", not MatchService.IsCurrentMatch(matchId))
	check(
		"cleanup: runtime folder empty",
		#WorldService.GetRuntimeFolder():GetChildren() == 0,
		#WorldService.GetRuntimeFolder():GetChildren()
	)
	local zones, traps = AbilityService.CountRuntime()
	check("cleanup: no zones/traps tracked", zones == 0 and traps == 0)
	check(
		"cleanup: terminals reset to Locked",
		(function()
			for _, t in WorldService.GetTerminals() do
				if t.model:GetAttribute("State") ~= "Locked" or t.prompt.Enabled then
					return false
				end
			end
			return true
		end)()
	)
	check("cleanup: gate closed again", gate:GetAttribute("Open") == false and gate.CanCollide == true)
	check(
		"lifecycle: player back in the lobby",
		waitFor(function()
			local r = rootOf(player)
			return r ~= nil and r.Position.Z > 250
		end, 8),
		rootOf(player) and (rootOf(player) :: BasePart).Position
	)
	snap = client(player, "snapshot")
	check("client: lobby shown again after the match", snap and snap.ui_Lobby == true and snap.ui_Hud == false, snap)
	check(
		"client: currency updated in UI state",
		snap and snap.currency == scrapBefore + expected,
		snap and snap.currency
	)
end

local function walkSpeed(player: Player): number?
	local h = humanoidOf(player)
	return h and h.WalkSpeed
end

local function runMatchTwo(player: Player)
	local d = MatchService.GetDirector()
	local profile = PlayerDataService.GetProfile(player)
	local scrapBefore = profile and profile.ChronosScrap or 0
	local join = client(player, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("match 2: re-queue accepted", join and join[1] and join[1].ok == true, codes(join))
	check(
		"match 2: active",
		waitFor(function()
			return d:getPhase() == "Active"
		end, 30),
		d:getPhase()
	)
	check("match 2: new match id", d.session ~= nil)
	local snap2 = client(player, "snapshot")
	check(
		"client: match 1 results closed once match 2 role arrived (Continue never pressed)",
		snap2 and snap2.ui_Results == false and snap2.ui_Hud == true,
		snap2 and { results = snap2.ui_Results, hud = snap2.ui_Hud }
	)
	StatusEffectService.Apply(
		player,
		{ key = "e2eLongSlow", kind = "Slow", magnitude = 0.7, duration = 30, source = "E2E" }
	)
	check(
		"match 2: long slow active before death (4.8)",
		waitFor(function()
			return near(walkSpeed(player), baseline(player) * 0.3)
		end, 2),
		walkSpeed(player)
	)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Health = 0
	end
	check(
		"match 2: death eliminates the Infiltrator",
		waitFor(function()
			local p = d:getParticipant(player.UserId)
			return p ~= nil and p.status == "Eliminated"
		end, 3)
	)
	check(
		"match 2: resolves AllEliminated",
		waitFor(function()
			return d.session ~= nil and d.session.result ~= nil and d.session.result.reason == "AllEliminated"
		end, 3)
	)
	local snap: any = nil
	check(
		"match 2: defeat result received by client",
		waitFor(function()
			snap = client(player, "snapshot")
			return snap ~= nil and snap.result ~= nil and snap.result.reason == "AllEliminated"
		end, 6),
		snap and snap.result
	)
	check(
		"match 2: defeat pays participation only (20)",
		snap and snap.result and snap.result.won == false and snap.result.total == 20,
		snap and snap.result
	)
	check(
		"match 2: profile credited +20 separately",
		waitFor(function()
			local p = PlayerDataService.GetProfile(player)
			return p ~= nil and p.ChronosScrap == scrapBefore + 20
		end, 3)
	)
	check(
		"match 2: eliminated player respawns in the lobby",
		waitFor(function()
			local r = rootOf(player)
			local h = humanoidOf(player)
			return r ~= nil and h ~= nil and h.Health > 0 and r.Position.Z > 250
		end, 10),
		rootOf(player) and (rootOf(player) :: BasePart).Position
	)
	check(
		"match 2: death while slowed respawns at baseline 16",
		waitFor(function()
			return near(walkSpeed(player), 16)
		end, 3),
		walkSpeed(player)
	)
	check(
		"match 2: lifecycle completes",
		waitFor(function()
			return d:getPhase() == "WaitingForPlayers" and d.session == nil
		end, 25),
		d:getPhase()
	)
	check(
		"match 2: no lingering status effects",
		StatusEffectService.CountEffects() == 0,
		StatusEffectService.CountEffects()
	)
end

local function moveFacing(player: Player, position: Vector3, lookAt: Vector3)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z)))
		req({ "Services", "SecurityService" }).ResetMovement(player)
	end
end

local function runMultiplayer(a: Player, b: Player)
	local d = MatchService.GetDirector()

	-- 1. Economy through the real shop remote (both players, before queueing)
	for _, p in { a, b } do
		PlayerDataService.Mutate(p, function(profile)
			return Economy.grant(profile, 400)
		end)
		local before = (PlayerDataService.GetProfile(p) :: any).ChronosScrap
		local buy = client(p, "fire", { remote = "ShopRequest", args = { "Purchase", "EchoScanner" } })
		check(`shop[{p.Name}]: purchase Echo Scanner accepted`, buy and buy[1] and buy[1].ok == true, codes(buy))
		local after = (PlayerDataService.GetProfile(p) :: any).ChronosScrap
		check(`shop[{p.Name}]: cost 250 deducted once`, after == before - 250, `{before} -> {after}`)
		local again = client(p, "fire", { remote = "ShopRequest", args = { "Purchase", "EchoScanner" } })
		check(`shop[{p.Name}]: re-purchase rejected AlreadyOwned`, hasCode(again, "AlreadyOwned"), codes(again))
		local poor = client(p, "fire", { remote = "ShopRequest", args = { "Purchase", "TrailGold" } })
		check(
			`shop[{p.Name}]: unaffordable item rejected, no charge`,
			hasCode(poor, "InsufficientFunds") and (PlayerDataService.GetProfile(p) :: any).ChronosScrap == after,
			codes(poor)
		)
		local equip = client(p, "fire", { remote = "ShopRequest", args = { "Equip", "EchoScanner" } })
		check(`shop[{p.Name}]: equip accepted`, equip and equip[1] and equip[1].ok == true, codes(equip))
		local snap = client(p, "snapshot")
		check(
			`client[{p.Name}]: loadout mirrored (owned + equipped)`,
			snap and snap.owned and snap.owned.EchoScanner == true and snap.equipped.Gadget == "EchoScanner",
			snap and snap.equipped
		)
	end

	-- 2. Two-player minimum (Studio solo matches are disabled with 2 players in the server)
	local joinA = client(a, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("queue: first player joins", joinA and joinA[1] and joinA[1].ok == true, codes(joinA))
	task.wait(3)
	check("queue: one queued player waits (minimum 2)", d:getPhase() == "WaitingForPlayers", d:getPhase())
	local joinB = client(b, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("queue: second player joins", joinB and joinB[1] and joinB[1].ok == true, codes(joinB))
	check(
		"match: intermission starts at 2 players",
		waitFor(function()
			return d:getPhase() == "Intermission"
		end, 3),
		d:getPhase()
	)
	check(
		"match: intro after 15 s intermission",
		waitFor(function()
			return d:getPhase() == "Intro"
		end, 20),
		d:getPhase()
	)

	-- 3. Roles
	local roleA, roleB = d:getRole(a.UserId), d:getRole(b.UserId)
	check(
		"roles: exactly one Time-Keeper and one Infiltrator",
		(roleA == "TimeKeeper") ~= (roleB == "TimeKeeper") and roleA ~= nil and roleB ~= nil,
		`{roleA}/{roleB}`
	)
	local keeper = if roleA == "TimeKeeper" then a else b
	local infiltrator = if keeper == a then b else a
	check(
		"spawn: Keeper placed in the Sanctum",
		waitFor(function()
			local r = rootOf(keeper)
			return r ~= nil and r.Position.Z < -60 and math.abs(r.Position.X) < 15
		end, 8),
		rootOf(keeper) and (rootOf(keeper) :: BasePart).Position
	)
	check(
		"spawn: Infiltrator placed in the Spawn Bay",
		waitFor(function()
			local r = rootOf(infiltrator)
			return r ~= nil and r.Position.Z > 55 and r.Position.X < -50
		end, 8),
		rootOf(infiltrator) and (rootOf(infiltrator) :: BasePart).Position
	)
	local ks = client(keeper, "snapshot")
	local is = client(infiltrator, "snapshot")
	check(
		"client: Keeper sees role reveal as TimeKeeper",
		ks and ks.role == "TimeKeeper" and ks.ui_RoleReveal == true,
		ks and ks.role
	)
	check(
		"client: Infiltrator sees role reveal as Infiltrator",
		is and is.role == "Infiltrator" and is.ui_RoleReveal == true,
		is and is.role
	)

	-- 4. Active: Keeper release hold, Infiltrator spawn protection
	check(
		"match: active",
		waitFor(function()
			return d:getPhase() == "Active"
		end, 12),
		d:getPhase()
	)
	task.wait(0.5)
	check("keeper: held in the Sanctum after Active begins", near(walkSpeed(keeper), 0), walkSpeed(keeper))
	check("infiltrator: free to move (16)", near(walkSpeed(infiltrator), baseline(infiltrator)), walkSpeed(infiltrator))
	check("infiltrator: spawn protection", StatusEffectService.IsInvulnerable(infiltrator))
	local heldCast = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(0, 0, -60) } :: { any } }
	)
	check("keeper: abilities rejected while held (Restrained)", hasCode(heldCast, "Restrained"), codes(heldCast))
	ks = client(keeper, "snapshot")
	is = client(infiltrator, "snapshot")
	check("client: Keeper ability bar has 4 slots", ks and ks.ui_abilitySlots == 4, ks and ks.ui_abilitySlots)
	check(
		"client: Infiltrator ability bar has gadget and class skill slots",
		is and is.ui_abilitySlots == 2,
		is and is.ui_abilitySlots
	)
	check(
		"replication: both clients see both participants",
		ks
			and is
			and ks.participants[tostring(infiltrator.UserId)] == "Infiltrator:Active"
			and is.participants[tostring(keeper.UserId)] == "TimeKeeper:Active",
		ks and ks.participants
	)

	-- 5. Echo Scanner (equipped gadget) reveals the Keeper
	local echo = client(infiltrator, "fire", { remote = "AbilityRequest", args = { "EchoScanner" } })
	check("gadget: Echo Scanner accepted", echo and echo[1] and echo[1].ok == true, codes(echo))
	check("gadget: Keeper marked Revealed", StatusEffectService.Has(keeper, "Revealed"))
	local stab = client(infiltrator, "fire", { remote = "AbilityRequest", args = { "Stabilizer" } })
	check(
		"gadget: unequipped Stabilizer rejected (loadout locked at match start)",
		hasCode(stab, "NotOwned"),
		codes(stab)
	)

	check(
		"keeper: released after 10 s (speed 17)",
		waitFor(function()
			return near(walkSpeed(keeper), 17)
		end, 12),
		walkSpeed(keeper)
	)

	-- 6. Time-Freeze Zone via the real remote
	moveFacing(infiltrator, Vector3.new(0, 3, 25), Vector3.new(0, 3, 40))
	moveFacing(keeper, Vector3.new(0, 3, 12), Vector3.new(0, 3, 25))
	task.wait(0.5)
	local far = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(80, 0, 80) } :: { any } }
	)
	check("freeze: target beyond range rejected", hasCode(far, "OutOfRange"), codes(far))
	local hidden = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(0, 0, -20) } :: { any } }
	)
	check(
		"freeze: target behind the Chrono Core rejected (NoLineOfSight)",
		hasCode(hidden, "NoLineOfSight"),
		codes(hidden)
	)
	local cast = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(0, 0.2, 25) } :: { any } }
	)
	check("freeze: valid cast accepted", cast and cast[1] and cast[1].ok == true, codes(cast))
	check(
		"freeze: zone instance exists",
		waitFor(function()
			local zones = AbilityService.CountRuntime()
			return zones == 1
		end, 1)
	)
	check(
		"freeze: Infiltrator slowed to 4.8 after telegraph",
		waitFor(function()
			return near(walkSpeed(infiltrator), baseline(infiltrator) * 0.3)
		end, 2),
		walkSpeed(infiltrator)
	)
	is = client(infiltrator, "snapshot")
	check("client: Infiltrator sees slowed status", is and is.slowed == true)
	local recast = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(0, 0.2, 25) } :: { any } }
	)
	check("freeze: recast rejected OnCooldown", hasCode(recast, "OnCooldown"), codes(recast))
	moveFacing(infiltrator, Vector3.new(-40, 3, 25), Vector3.new(-40, 3, 40))
	check(
		"freeze: leaving the zone restores 16",
		waitFor(function()
			return near(walkSpeed(infiltrator), baseline(infiltrator))
		end, 2),
		walkSpeed(infiltrator)
	)
	check(
		"freeze: zone expires and is cleaned up",
		waitFor(function()
			local zones = AbilityService.CountRuntime()
			return zones == 0
		end, 12)
	)

	-- 7. Temporal Trap via the real remote
	moveFacing(keeper, Vector3.new(0, 3, 12), Vector3.new(8, 3, 24))
	task.wait(0.3)
	local trap = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TemporalTrap", Vector3.new(8, 0.2, 24) } :: { any } }
	)
	check("trap: placement accepted", trap and trap[1] and trap[1].ok == true, codes(trap))
	local trap2 = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "TemporalTrap", Vector3.new(9, 0.2, 25) } :: { any } }
	)
	check("trap: second trap blocked (cooldown before spacing)", hasCode(trap2, "OnCooldown"), codes(trap2))
	task.wait(1.8) -- arming
	moveFacing(infiltrator, Vector3.new(8, 3, 24), Vector3.new(8, 3, 40))
	check(
		"trap: Infiltrator stunned (speed 0)",
		waitFor(function()
			return near(walkSpeed(infiltrator), 0)
		end, 2),
		walkSpeed(infiltrator)
	)
	check(
		"trap: consumed after triggering",
		waitFor(function()
			local _, traps = AbilityService.CountRuntime()
			return traps == 0
		end, 2)
	)
	check(
		"trap: stun -> 40% slow -> 16",
		waitFor(function()
			return near(walkSpeed(infiltrator), baseline(infiltrator))
		end, 6),
		walkSpeed(infiltrator)
	)

	-- 8. Chrono Strike: damage interrupts hacking, three strikes eliminate, credit to Keeper
	moveToTerminal(infiltrator, "ArchiveTerminal")
	local pressed = client(infiltrator, "prompt", { terminal = "Terminal_ArchiveTerminal" })
	check("strike: Infiltrator started a hack", pressed == "pressed" and waitFor(function()
		return terminalState("ArchiveTerminal") == "Hacking"
	end, 3), terminalState("ArchiveTerminal"))
	ks = client(keeper, "snapshot")
	check(
		"replication: Keeper client sees the terminal being hacked",
		ks and ks.terminalStates.ArchiveTerminal == "Hacking",
		ks and ks.terminalStates
	)
	local ipos = (rootOf(infiltrator) :: BasePart).Position
	local kpos = ipos + Vector3.new(0, 0, 4)
	moveFacing(keeper, kpos, ipos)
	task.wait(0.3)
	local aim = Vector3.new(ipos.X - kpos.X, 0, ipos.Z - kpos.Z).Unit
	local hit1 = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "ChronoStrike", { ["$nil"] = true }, aim } :: { any }, collect = 0.6 }
	)
	local quick = client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "ChronoStrike", { ["$nil"] = true }, aim } :: { any }, collect = 0.3 }
	)
	check("strike: cooldown enforced", hasCode(quick, "OnCooldown"), codes(quick))

	check("strike: accepted", hit1 and hit1[1] and hit1[1].ok == true, codes(hit1))
	check(
		"strike: 34 damage applied",
		waitFor(function()
			local h = humanoidOf(infiltrator)
			return h ~= nil and near(h.Health, h.MaxHealth - 34, 0.5)
		end, 1),
		humanoidOf(infiltrator) and (humanoidOf(infiltrator) :: Humanoid).Health
	)
	check(
		"strike: damage interrupted the hack",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Interrupted"
		end, 1),
		terminalState("ArchiveTerminal")
	)
	task.wait(1.3)
	client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "ChronoStrike", { ["$nil"] = true }, aim } :: { any }, collect = 0.3 }
	)
	task.wait(1.3)
	client(
		keeper,
		"fire",
		{ remote = "AbilityRequest", args = { "ChronoStrike", { ["$nil"] = true }, aim } :: { any }, collect = 0.3 }
	)
	check(
		"elimination: third strike eliminates the Infiltrator",
		waitFor(function()
			local p = d:getParticipant(infiltrator.UserId)
			return p ~= nil and p.status == "Eliminated"
		end, 3)
	)
	local result = d.session and d.session.result
	check(
		"result: Time-Keeper wins AllEliminated",
		result ~= nil and result.winner == "TimeKeeper" and result.reason == "AllEliminated",
		result and result.reason
	)
	check(
		"result: elimination credited to the Keeper",
		result ~= nil and result.participants[keeper.UserId].eliminations == 1
	)
	local kr, ir: any = nil, nil
	check(
		"result: both clients received their results",
		waitFor(function()
			kr = client(keeper, "snapshot")
			ir = client(infiltrator, "snapshot")
			return kr.result ~= nil
				and ir.result ~= nil
				and kr.result.matchId == result.matchId
				and ir.result.matchId == result.matchId
		end, 6)
	)
	check(
		"rewards: Keeper victory = 20 + 50 + 20",
		kr and kr.result and kr.result.won == true and kr.result.total == 90,
		kr and kr.result
	)
	check(
		"rewards: Infiltrator defeat = participation 20",
		ir and ir.result and ir.result.won == false and ir.result.total == 20,
		ir and ir.result
	)
	check(
		"cleanup: runtime emptied at resolution",
		#WorldService.GetRuntimeFolder():GetChildren() == 0,
		#WorldService.GetRuntimeFolder():GetChildren()
	)
	check(
		"lifecycle: returns to WaitingForPlayers",
		waitFor(function()
			return d:getPhase() == "WaitingForPlayers" and d.session == nil
		end, 30),
		d:getPhase()
	)

	-- 9. Disconnect mid-match: the Infiltrator leaves during Active
	local qa = client(a, "fire", { remote = "QueueRequest", args = { "Join" } })
	local qb = client(b, "fire", { remote = "QueueRequest", args = { "Join" } })
	check("match 2: both re-queued", qa and qa[1] and qa[1].ok and qb and qb[1] and qb[1].ok, `{codes(qa)} {codes(qb)}`)
	check(
		"match 2: active",
		waitFor(function()
			return d:getPhase() == "Active"
		end, 35),
		d:getPhase()
	)
	local leaver = nil :: Player?
	for _, p in { a, b } do
		if d:getRole(p.UserId) == "Infiltrator" then
			leaver = p
		end
	end
	local stayer = if leaver == a then b else a
	local scrapBefore = (PlayerDataService.GetProfile(stayer) :: any).ChronosScrap
	if leaver then
		moveToTerminal(leaver, "ReactorTerminal")
		client(leaver, "prompt", { terminal = "Terminal_ReactorTerminal" })
		waitFor(function()
			return terminalState("ReactorTerminal") == "Hacking"
		end, 3)
		-- Leave a live zone and an armed trap in the world when the match resolves.
		check(
			"match 2: Keeper released",
			waitFor(function()
				return near(walkSpeed(stayer), 17)
			end, 12),
			walkSpeed(stayer)
		)
		moveFacing(stayer, Vector3.new(0, 3, 12), Vector3.new(0, 3, 25))
		task.wait(0.3)
		local liveZone = client(
			stayer,
			"fire",
			{ remote = "AbilityRequest", args = { "TimeFreeze", Vector3.new(0, 0.2, 25) } :: { any } }
		)
		local liveTrap = client(
			stayer,
			"fire",
			{ remote = "AbilityRequest", args = { "TemporalTrap", Vector3.new(8, 0.2, 24) } :: { any } }
		)
		local zonesLive, trapsLive = AbilityService.CountRuntime()
		check(
			"match 2: zone and trap live before resolution",
			zonesLive == 1 and trapsLive == 1,
			{ zones = zonesLive, traps = trapsLive, zone = codes(liveZone), trap = codes(liveTrap) }
		)
		local leaverId = leaver.UserId
		leaver:Kick("E2E disconnect test")
		check(
			"disconnect: hack interrupted when the hacker leaves",
			waitFor(function()
				return terminalState("ReactorTerminal") ~= "Hacking"
			end, 3),
			terminalState("ReactorTerminal")
		)
		check(
			"disconnect: resolves InfiltratorsLeft for the Keeper",
			waitFor(function()
				return d.session ~= nil and d.session.result ~= nil and d.session.result.reason == "InfiltratorsLeft"
			end, 3)
		)
		local zonesAfter, trapsAfter = AbilityService.CountRuntime()
		check(
			"cleanup: live zone and trap destroyed at resolution",
			zonesAfter == 0 and trapsAfter == 0 and #WorldService.GetRuntimeFolder():GetChildren() == 0,
			{ zones = zonesAfter, traps = trapsAfter, runtime = #WorldService.GetRuntimeFolder():GetChildren() }
		)
		check(
			"disconnect: departed player recorded as disconnected (ineligible for rewards)",
			d.session.result.participants[leaverId].connected == false
				and req({ "Core", "RewardCalculator" }).compute(
						d.session.result,
						d.session.result.participants[leaverId]
					).eligible
					== false
		)
		check(
			"disconnect: staying Keeper paid the win",
			waitFor(function()
				local p = PlayerDataService.GetProfile(stayer)
				return p ~= nil and p.ChronosScrap == scrapBefore + 70
			end, 3),
			(PlayerDataService.GetProfile(stayer) :: any).ChronosScrap - scrapBefore
		)
		check(
			"disconnect: lifecycle recovers to WaitingForPlayers",
			waitFor(function()
				return d:getPhase() == "WaitingForPlayers"
			end, 30),
			d:getPhase()
		)
	end
end

-- 3-5 players: one Keeper, simultaneous hacks, one-terminal-per-hacker, teammate resume, a mid-match
-- disconnect that does not end the match, a full extraction win with consistent rewards, Keeper
-- rotation in the next match, and the Keeper leaving.
local function runSquad(players: { Player })
	local d = MatchService.GetDirector()
	local RewardCalculator = req({ "Core", "RewardCalculator" })
	local n = #players
	for _, p in players do
		local r = client(p, "fire", { remote = "QueueRequest", args = { "Join" } })
		check(`squad: {p.Name} queued`, r and r[1] and r[1].ok == true, codes(r))
	end
	check(
		`squad: {n}-player match active`,
		waitFor(function()
			return d:getPhase() == "Active"
		end, 45),
		d:getPhase()
	)
	local keeper: Player? = nil
	local infiltrators: { Player } = {}
	local keepers = 0
	for _, p in players do
		local role = d:getRole(p.UserId)
		if role == "TimeKeeper" then
			keepers += 1
			keeper = p
		elseif role == "Infiltrator" then
			table.insert(infiltrators, p)
		end
	end
	check(
		"squad: exactly one Keeper, everyone else an Infiltrator",
		keepers == 1 and #infiltrators == n - 1,
		{ keepers = keepers, infiltrators = #infiltrators }
	)
	if keeper == nil or #infiltrators < 2 then
		return
	end
	local mismatched = {}
	for _, p in players do
		local snap = client(p, "snapshot")
		if not snap or snap.role ~= d:getRole(p.UserId) or snap.ui_Hud ~= true then
			table.insert(mismatched, p.Name)
		end
	end
	check("squad: every client mirrors its own role and shows the HUD", #mismatched == 0, mismatched)
	local matchId = (d.session :: any).matchId
	local a, b = infiltrators[1], infiltrators[2]

	-- Simultaneous hacks on two terminals.
	moveToTerminal(a, "ArchiveTerminal")
	moveToTerminal(b, "ReactorTerminal")
	local pressedA, pressedB = nil, nil
	task.spawn(function()
		pressedA = client(a, "prompt", { terminal = "Terminal_ArchiveTerminal" })
	end)
	pressedB = client(b, "prompt", { terminal = "Terminal_ReactorTerminal" })
	check(
		"squad: two terminals hacked simultaneously",
		waitFor(function()
			return terminalState("ArchiveTerminal") == "Hacking" and terminalState("ReactorTerminal") == "Hacking"
		end, 3),
		{
			a = pressedA,
			b = pressedB,
			archive = terminalState("ArchiveTerminal"),
			reactor = terminalState("ReactorTerminal"),
		}
	)
	local okSecond, codeSecond = MatchService.RequestHack(b, "ArchiveTerminal")
	check(
		"squad: one terminal per hacker (AlreadyHacking)",
		not okSecond and codeSecond == "AlreadyHacking",
		codeSecond
	)
	if infiltrators[3] then
		moveToTerminal(infiltrators[3], "ArchiveTerminal")
		local okBusy, codeBusy = MatchService.RequestHack(infiltrators[3], "ArchiveTerminal")
		check("squad: one assistant can join the primary hacker", okBusy, codeBusy)
		MatchService.CancelHack(infiltrators[3], "Cancelled")
	end

	-- A walks away mid-hack; progress is retained for a teammate.
	task.wait(5)
	moveTo(a, WorldService.GetMap().extractionCenter)
	check(
		"squad: walking away interrupts with progress retained",
		waitFor(function()
			local t = d:publicTerminal("ArchiveTerminal")
			return t ~= nil and t.state ~= "Hacking" and t.progress > 0.2
		end, 2),
		d:publicTerminal("ArchiveTerminal")
	)

	-- A starts Observatory, then disconnects mid-hack; the match must continue.
	task.wait(1.6)
	moveToTerminal(a, "ObservatoryTerminal")
	client(a, "prompt", { terminal = "Terminal_ObservatoryTerminal" })
	waitFor(function()
		return terminalState("ObservatoryTerminal") == "Hacking"
	end, 3)
	task.wait(2)
	local leaverId = a.UserId
	a:Kick("E2E squad disconnect test")
	check(
		"squad: disconnect interrupts the leaver's hack",
		waitFor(function()
			return terminalState("ObservatoryTerminal") ~= "Hacking"
		end, 3),
		terminalState("ObservatoryTerminal")
	)
	check("squad: match continues after one Infiltrator leaves", waitFor(function()
		local p = d:getParticipant(leaverId)
		return p ~= nil and p.status == "Disconnected"
	end, 3) and d:getPhase() == "Active", d:getPhase())

	-- B finishes Reactor, then resumes Archive and Observatory from the retained progress.
	check(
		"squad: Reactor completes",
		waitFor(function()
			return terminalState("ReactorTerminal") == "Completed"
		end, 20),
		terminalState("ReactorTerminal")
	)
	for _, id in { "ArchiveTerminal", "ObservatoryTerminal" } do
		local before = (d:publicTerminal(id) :: any).progress
		waitFor(function()
			return terminalState(id) == "Available"
		end, 3)
		moveToTerminal(b, id)
		client(b, "prompt", { terminal = `Terminal_{id}` })
		check(`squad: teammate resumes {id} from {math.floor(before * 100)}%`, before > 0 and waitFor(function()
			local t = d:publicTerminal(id)
			return t ~= nil and t.state == "Hacking" and t.hackerUserId == b.UserId
		end, 3), d:publicTerminal(id))
		check(
			`squad: {id} completes`,
			waitFor(function()
				return terminalState(id) == "Completed"
			end, 20),
			terminalState(id)
		)
	end
	check(
		"squad: extraction opens",
		waitFor(function()
			return d:getPhase() == "Extraction"
		end, 2),
		d:getPhase()
	)
	local scrapBefore: { [number]: number } = {}
	for _, p in Players:GetPlayers() do
		scrapBefore[p.UserId] = (PlayerDataService.GetProfile(p) :: any).ChronosScrap
	end
	local others = {}
	for i = 3, #infiltrators do
		table.insert(others, infiltrators[i])
	end
	moveTo(b, WorldService.GetMap().extractionCenter)
	for _, p in others do
		moveTo(p, WorldService.GetMap().extractionCenter)
	end
	check(
		"squad: Infiltrators win by extraction",
		waitFor(function()
			local r = d.session and d.session.result
			return r ~= nil and r.reason == "Extracted" and r.winner == "Infiltrators"
		end, 10),
		d.session and d.session.result and d.session.result.reason
	)
	local result = (d.session :: any).result
	check(
		"squad: leaver recorded as disconnected and ineligible",
		result.participants[leaverId].connected == false
			and RewardCalculator.compute(result, result.participants[leaverId]).eligible == false
	)
	local inconsistent = {}
	for _, p in Players:GetPlayers() do
		local expected = RewardCalculator.compute(result, result.participants[p.UserId]).total
		local snap: any = nil
		local ok = waitFor(function()
			snap = client(p, "snapshot")
			local profile = PlayerDataService.GetProfile(p) :: any
			return snap ~= nil
				and snap.result ~= nil
				and snap.result.matchId == matchId
				and snap.result.total == expected
				and profile.ChronosScrap == scrapBefore[p.UserId] + expected
		end, 6)
		if not ok then
			table.insert(inconsistent, { name = p.Name, expected = expected, got = snap and snap.result })
		end
	end
	check("squad: every remaining client got one consistent, paid result", #inconsistent == 0, inconsistent)
	check(
		"squad: lifecycle returns to WaitingForPlayers",
		waitFor(function()
			return d:getPhase() == "WaitingForPlayers" and d.session == nil
		end, 30),
		d:getPhase()
	)

	-- Next match: the Keeper rotates to someone who has not held the role yet.
	local previousKeeper = keeper
	for _, p in Players:GetPlayers() do
		client(p, "fire", { remote = "QueueRequest", args = { "Join" } })
	end
	check(
		"squad: match 2 active",
		waitFor(function()
			return d:getPhase() == "Active"
		end, 45),
		d:getPhase()
	)
	local newKeeper: Player? = nil
	for _, p in Players:GetPlayers() do
		if d:getRole(p.UserId) == "TimeKeeper" then
			newKeeper = p
		end
	end
	check(
		"squad: Keeper rotated away from the previous Keeper",
		newKeeper ~= nil and newKeeper ~= previousKeeper,
		newKeeper and newKeeper.Name
	)
	if newKeeper then
		newKeeper:Kick("E2E squad keeper-leave test")
		check(
			"squad: Keeper leaving gives the Infiltrators the win",
			waitFor(function()
				local r = d.session and d.session.result
				return r ~= nil and r.reason == "KeeperLeft" and r.winner == "Infiltrators"
			end, 3),
			d.session and d.session.result and d.session.result.reason
		)
	end
	check(
		"squad: lifecycle recovers to WaitingForPlayers",
		waitFor(function()
			return d:getPhase() == "WaitingForPlayers" and d.session == nil
		end, 30),
		d:getPhase()
	)
	check(
		"squad: no lingering status effects",
		StatusEffectService.CountEffects() == 0,
		StatusEffectService.CountEffects()
	)
end

task.spawn(function()
	print("[E2E] driver waiting for players (1 player = solo suite, 2 = multiplayer, 3-5 = squad)")
	local ready = waitFor(function()
		local ok = pcall(function()
			return MatchService.GetDirector()
		end)
		return ok and #helloPlayers >= 1 and (helloPlayers[1] :: Player).Character ~= nil
	end, 120)
	if not ready then
		warn("[E2E] SKIPPED: no player joined")
		return
	end
	-- Give the other Studio test clients time to join (and say hello) before choosing the suite.
	waitFor(function()
		return #helloPlayers >= 2
	end, 8)
	waitFor(function()
		return #helloPlayers >= #Players:GetPlayers()
	end, 15)
	task.wait(2) -- let ClientReady/state sync settle
	local count = #Players:GetPlayers()
	local mode = if count >= 3 and #helloPlayers >= 3
		then "squad"
		elseif count == 2 and #helloPlayers >= 2 then "multiplayer"
		else "solo"
	-- Precondition: every player idle in the lobby. Manual input (e.g. clicking Join Queue) during
	-- the run invalidates the suite, so abort clearly instead of reporting misleading failures.
	local director = MatchService.GetDirector()
	for _, p in helloPlayers do
		if director.queue:contains(p.UserId) or director:getParticipant(p.UserId) ~= nil then
			local summary =
				`[E2E] {mode}: ABORTED — {p.Name} was already queued or in a match (manual input during the test?)`
			ReplicatedStorage:SetAttribute("E2ESummary", summary)
			warn(summary)
			return
		end
	end
	print(`[E2E] starting {mode} suite with {#helloPlayers} player(s)`)
	if mode == "solo" then
		local player = helloPlayers[1] :: Player
		local ok, err = Safe.call(runMatchOne, player)
		if not ok then
			check("match 1 completed without driver errors", false, err)
		end
		ok, err = Safe.call(runMatchTwo, player)
		if not ok then
			check("match 2 completed without driver errors", false, err)
		end
	elseif mode == "squad" then
		for _, p in helloPlayers do
			waitFor(function()
				return p.Character ~= nil
			end, 10)
		end
		local ok, err = Safe.call(runSquad, table.clone(helloPlayers))
		if not ok then
			check("squad suite completed without driver errors", false, err)
		end
	else
		for _, p in helloPlayers do
			waitFor(function()
				return p.Character ~= nil
			end, 10)
		end
		local ok, err = Safe.call(runMultiplayer, helloPlayers[1] :: Player, helloPlayers[2] :: Player)
		if not ok then
			check("multiplayer suite completed without driver errors", false, err)
		end
	end
	local summary = `[E2E] {mode}: {passed} passed, {failed} failed`
	ReplicatedStorage:SetAttribute("E2ESummary", summary)
	if failed > 0 then
		warn(summary)
	else
		print(summary)
	end
end)
