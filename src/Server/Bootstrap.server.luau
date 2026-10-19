--!strict
-- Server entry point. Deterministic two-phase startup (docs/ARCHITECTURE.md):
--   1. Require every service (no side effects at require time).
--   2. Init(registry) in dependency order — creates remotes, builds/validates the world, wires
--      dependencies. Any failure here is fatal and reported loudly; gameplay never starts half-built.
--   3. Start() in the same order — connects events and starts loops.
-- BootGuard (module state, not an Instance attribute) prevents double initialisation.

local BootGuard = require(script.Parent.BootGuard)

if not BootGuard.claim() then
	warn("[Bootstrap] server already booted; ignoring duplicate bootstrap")
	return
end

local Services = script.Parent.Services

local ORDER = {
	"SecurityService",
	"NetworkService",
	"WorldService",
	"StatusEffectService",
	"PlayerDataService",
	"InventoryService",
	"MatchService",
	"CharacterService",
	"ObjectiveService",
	"CombatService",
	"AbilityService",
	"AnomalyService",
	"RewardService",
}

local registry: { [string]: any } = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(`[Bootstrap] missing required service module '{name}'`)
	end
	registry[name] = (require :: any)(module)
end

local function runPhase(phase: string)
	for _, name in ORDER do
		local service = registry[name]
		local fn = service[phase]
		if type(fn) == "function" then
			local ok, err = pcall(fn, registry)
			if not ok then
				error(`[Bootstrap] {name}.{phase} failed: {err}`)
			end
		end
	end
end

local started = os.clock()
runPhase("Init")
runPhase("Start")
print(
	string.format(
		"[Bootstrap] Chrono Breakers server ready (%d services, %.0f ms)",
		#ORDER,
		(os.clock() - started) * 1000
	)
)
