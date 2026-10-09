--!strict
-- Tiny result helpers for validation pipelines: functions return (ok, code) pairs so callers can
-- forward the rejection code to the client without throwing.

local Result = {}

export type Outcome = { ok: boolean, code: string }

function Result.ok(): Outcome
	return { ok = true, code = "Ok" }
end

function Result.err(code: string): Outcome
	return { ok = false, code = code }
end

return table.freeze(Result)
