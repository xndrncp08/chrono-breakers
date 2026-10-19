--!strict
-- Test harness: a MatchDirector wired to a fully controllable fake world and an event recorder.

local ServerScriptService = game:GetService("ServerScriptService")
local MatchDirector = require(ServerScriptService.Server.Core.MatchDirector)

local Harness = {}

Harness.TERMINALS = {
	{ id = "T1", name = "Terminal One" },
	{ id = "T2", name = "Terminal Two" },
	{ id = "T3", name = "Terminal Three" },
}

function Harness.config(overrides: { [string]: any }?): MatchDirector.DirectorConfig
	local c: any = {
		minPlayers = 2,
		maxPlayers = 5,
		intermissionDuration = 10,
		soloIntermissionDuration = 3,
		introDuration = 5,
		matchDuration = 600,
		extractionWindow = 60,
		extractionChannelTime = 3,
		resultsDuration = 10,
		returnToLobbyDuration = 3,
		requiredHacks = 3,
		hackDuration = 15,
		maxInteractionDistance = 12,
		interruptLockout = 1.5,
		retainProgressOnInterrupt = true,
		progressBroadcastInterval = 0.25,
		allowKeeperless = false,
	}
	if overrides then
		for k, v in overrides do
			c[k] = v
		end
	end
	return c
end

export type Harness = {
	director: MatchDirector.MatchDirector,
	now: number,
	events: { { name: string, payload: any } },
	alive: { [number]: boolean },
	restrained: { [number]: boolean },
	eligible: { [number]: boolean },
	distance: { [number]: { [string]: number } },
	inZone: { [number]: boolean },
	advance: (self: Harness, seconds: number, step: number?) -> (),
	count: (self: Harness, name: string) -> number,
	last: (self: Harness, name: string) -> any,
	queueAll: (self: Harness, userIds: { number }) -> (),
	startMatch: (self: Harness, userIds: { number }) -> (),
	keeper: (self: Harness) -> number,
	infiltrators: (self: Harness) -> { number },
	placeAt: (self: Harness, userId: number, terminalId: string) -> (),
	hack: (self: Harness, userId: number, terminalId: string) -> (),
}

function Harness.new(overrides: { [string]: any }?): Harness
	local self = {
		now = 0,
		events = {},
		alive = {},
		restrained = {},
		eligible = {},
		distance = {},
		inZone = {},
	} :: any

	local idCounter = 0
	self.director = MatchDirector.new({
		config = Harness.config(overrides),
		terminals = Harness.TERMINALS,
		prepareMatch = if overrides then overrides.prepareMatch else nil,
		now = 0,
		newMatchId = function()
			idCounter += 1
			return `match-{idCounter}`
		end,
		randomIndex = function(_: number)
			return 1
		end,
		world = {
			isEligibleForMatch = function(userId: number)
				return self.eligible[userId] ~= false
			end,
			isAlive = function(userId: number)
				return self.alive[userId] ~= false
			end,
			isRestrained = function(userId: number)
				return self.restrained[userId] == true
			end,
			distanceToTerminal = function(userId: number, terminalId: string)
				local d = self.distance[userId]
				return if d then d[terminalId] else 50
			end,
			isInExtractionZone = function(userId: number)
				return self.inZone[userId] == true
			end,
			getName = function(userId: number)
				return `Player{userId}`
			end,
		},
	})

	self.director.events:Connect(function(name: string, payload: any)
		table.insert(self.events, { name = name, payload = payload })
	end)

	function self:advance(seconds: number, step: number?)
		local dt = step or 0.1
		local target = self.now + seconds
		while self.now < target - 1e-9 do
			self.now = math.min(target, self.now + dt)
			self.director:tick(self.now)
		end
	end

	function self:count(name: string): number
		local n = 0
		for _, e in self.events do
			if e.name == name then
				n += 1
			end
		end
		return n
	end

	function self:last(name: string): any
		for i = #self.events, 1, -1 do
			if self.events[i].name == name then
				return self.events[i].payload
			end
		end
		return nil
	end

	function self:queueAll(userIds: { number })
		for _, userId in userIds do
			self.director.queue:join(userId)
		end
	end

	-- Queues players and advances through Intermission + Intro into Active.
	function self:startMatch(userIds: { number })
		self:queueAll(userIds)
		self:advance(0.1)
		local c = self.director.config
		local intermission = if c.allowKeeperless and #userIds < c.minPlayers
			then c.soloIntermissionDuration
			else c.intermissionDuration
		self:advance(intermission + 0.2)
		self:advance(c.introDuration + 0.2)
		assert(self.director:getPhase() == "Active", `expected Active, got {self.director:getPhase()}`)
	end

	function self:keeper(): number
		local session = self.director.session :: any
		return session.keeperUserId
	end

	function self:infiltrators(): { number }
		local list = {}
		local session = self.director.session :: any
		for _, userId in session.order do
			if session.participants[userId].role == "Infiltrator" then
				table.insert(list, userId)
			end
		end
		return list
	end

	function self:placeAt(userId: number, terminalId: string)
		self.distance[userId] = { [terminalId] = 5 }
	end

	-- Places the user at the terminal, starts the hack, and runs it to completion.
	function self:hack(userId: number, terminalId: string)
		self:placeAt(userId, terminalId)
		local ok, code = self.director:requestHackStart(userId, terminalId, self.now)
		assert(ok, `hack start failed: {code}`)
		self:advance(self.director.config.hackDuration + 0.2)
	end

	return self :: Harness
end

return Harness
