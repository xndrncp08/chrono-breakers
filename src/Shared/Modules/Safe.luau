--!strict
-- Error-boundary helper: runs a function in protected mode and returns (ok, errorMessage?).
-- Used at service boundaries (loops, event handlers) so one failure is logged instead of killing the
-- loop, without hiding the error.

local Safe = {}

function Safe.call(fn: (...any) -> ...any, ...: any): (boolean, string?)
	local outcome = table.pack(pcall(fn, ...))
	if outcome[1] then
		return true, nil
	end
	return false, tostring(outcome[2])
end

return table.freeze(Safe)
