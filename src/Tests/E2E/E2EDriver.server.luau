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
local helloFrom: Player? = nil
channel.OnServerEvent:Connect(function(player: Player, message: any)
	if type(message) ~= "table" then
		return
	end
	if message.hello then
		helloFrom = player
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
local PlayerDataService = req({ "Services", "PlayerDataService" })
local FreezeZone = req({ "Components", "FreezeZone" })
local TemporalTrap = req({ "Components", "TemporalTrap" })
local PlacementRules = req({ "Core", "PlacementRules" })
local MapValidator = req({ "World", "MapValidator" })
local MapLayout = req({ "World", "MapLayout" })

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

local function near(a: number?, b: number, eps: number?): boolean
	return a ~= nil and math.abs(a - b) <= (eps or 0.05)
end

local function terminalSpec(id: string): any
	for _, t in MapLayout.Vault.terminals do
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
			return h ~= nil and near(h.WalkSpeed, 16)
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
	check("client: role reveal dismissed", snap and snap.ui_RoleReveal == false)
	check(
		"client: one gadget slot in the ability bar",
		snap and snap.ui_abilitySlots == 1,
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
		near((humanoidOf(player) :: Humanoid).WalkSpeed, 16),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check(
		"freeze: 70% slow applied from baseline (4.8)",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, 4.8)
		end, 2),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	task.wait(1.5) -- zone A expired, zone B still active
	check(
		"freeze: overlapping zones do not stack; slow persists after one expires",
		near((humanoidOf(player) :: Humanoid).WalkSpeed, 4.8),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	snap = client(player, "snapshot")
	check("client: slowed status mirrored", snap and snap.slowed == true)
	check(
		"freeze: speed restored to exactly 16 after all zones end",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, 16)
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
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, 9.6)
		end, 3),
		(humanoidOf(player) :: Humanoid).WalkSpeed
	)
	check(
		"trap: speed restored to 16",
		waitFor(function()
			return near((humanoidOf(player) :: Humanoid).WalkSpeed, 16)
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
			boundsMin = MapLayout.Vault.boundsMin,
			boundsMax = MapLayout.Vault.boundsMax,
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
	moveTo(player, MapLayout.Vault.extractionCenter)
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

task.spawn(function()
	print("[E2E] driver waiting for a player (Studio Play, one player)")
	local ready = waitFor(function()
		local ok = pcall(function()
			return MatchService.GetDirector()
		end)
		return ok and helloFrom ~= nil and helloFrom.Character ~= nil and #Players:GetPlayers() == 1
	end, 120)
	if not ready then
		warn("[E2E] SKIPPED: needs exactly one player in a Studio Play session")
		return
	end
	local player = helloFrom :: Player
	task.wait(2) -- let ClientReady/state sync settle
	print(`[E2E] starting with {player.Name}`)
	local ok, err = Safe.call(runMatchOne, player)
	if not ok then
		check("match 1 completed without driver errors", false, err)
	end
	ok, err = Safe.call(runMatchTwo, player)
	if not ok then
		check("match 2 completed without driver errors", false, err)
	end
	local summary = `[E2E] {passed} passed, {failed} failed`
	ReplicatedStorage:SetAttribute("E2ESummary", summary)
	if failed > 0 then
		warn(summary)
	else
		print(summary)
	end
end)
