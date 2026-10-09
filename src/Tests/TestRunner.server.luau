--!strict
-- Studio test entry point. Present only in the test place built from test.project.json, never in
-- the production project. Runs every spec under Tests/Unit and Tests/Integration and prints a
-- summary to the Output window.

local TestKit = require(script.Parent.TestKit)

local specs: { { name: string, spec: (TestKit.Context) -> () } } = {}
for _, folderName in { "Unit", "Integration" } do
	local folder = script.Parent:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(specs, { name = `{folderName}/{child.Name}`, spec = (require :: any)(child) })
			end
		end
	end
end
table.sort(specs, function(a, b)
	return a.name < b.name
end)

local report = TestKit.run(specs, print)
local summary = `[Tests] {report.passed} passed, {report.failed} failed`
if report.failed > 0 then
	warn(summary)
else
	print(summary)
end
