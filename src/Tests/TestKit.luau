--!strict
-- Minimal BDD-style test kit that runs identically under Lune (tools/run-tests.luau) and inside
-- Roblox Studio (TestRunner.server.luau). Specs are ModuleScripts returning `function(t) ... end`.

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, epsilon: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toContain: (expected: any) -> (),
	toThrow: () -> (),
}

export type Context = {
	describe: (name: string, fn: () -> ()) -> (),
	it: (name: string, fn: () -> ()) -> (),
	expect: (value: any) -> Expectation,
}

export type Failure = { name: string, message: string }
export type Report = { passed: number, failed: number, failures: { Failure } }

local TestKit = {}

local function render(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TestKit.expect(actual: any): Expectation
	local e = {} :: any
	function e.toBe(expected: any)
		if actual ~= expected then
			error(`expected {render(actual)} to be {render(expected)}`, 2)
		end
	end
	function e.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error(`expected {render(actual)} to deep-equal {render(expected)}`, 2)
		end
	end
	function e.toBeNear(expected: number, epsilon: number?)
		local eps = epsilon or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			error(`expected {render(actual)} to be within {eps} of {expected}`, 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(`expected {render(actual)} to be truthy`, 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(`expected {render(actual)} to be falsy`, 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(`expected {render(actual)} to be nil`, 2)
		end
	end
	function e.toBeGreaterThan(expected: number)
		if type(actual) ~= "number" or not (actual > expected) then
			error(`expected {render(actual)} > {expected}`, 2)
		end
	end
	function e.toBeLessThan(expected: number)
		if type(actual) ~= "number" or not (actual < expected) then
			error(`expected {render(actual)} < {expected}`, 2)
		end
	end
	function e.toContain(expected: any)
		if type(actual) ~= "table" or table.find(actual, expected) == nil then
			error(`expected table to contain {render(expected)}`, 2)
		end
	end
	function e.toThrow()
		if type(actual) ~= "function" then
			error("toThrow expects a function", 2)
		end
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end
	return e :: Expectation
end

-- Runs a list of { name, spec } entries and returns a report. `log` receives progress lines.
function TestKit.run(specs: { { name: string, spec: (Context) -> () } }, log: (string) -> ()): Report
	local report: Report = { passed = 0, failed = 0, failures = {} }
	for _, entry in specs do
		local prefix: { string } = { entry.name }
		local ctx = {} :: any
		function ctx.describe(name: string, fn: () -> ())
			table.insert(prefix, name)
			fn()
			table.remove(prefix)
		end
		function ctx.it(name: string, fn: () -> ())
			local fullName = table.concat(prefix, " › ") .. " › " .. name
			local outcome = table.pack(xpcall(fn, function(message)
				return tostring(message) .. "\n" .. debug.traceback(nil, 2)
			end))
			local ok, err = outcome[1], outcome[2]
			if ok then
				report.passed += 1
			else
				report.failed += 1
				table.insert(report.failures, { name = fullName, message = tostring(err) })
				log(`  ✗ {fullName}\n    {err}`)
			end
		end
		ctx.expect = TestKit.expect
		local outcome = table.pack(pcall(entry.spec, ctx :: Context))
		local ok, err = outcome[1], outcome[2]
		if not ok then
			report.failed += 1
			table.insert(report.failures, { name = entry.name .. " (load)", message = tostring(err) })
			log(`  ✗ {entry.name} failed to load: {err}`)
		end
	end
	return report
end

return TestKit
