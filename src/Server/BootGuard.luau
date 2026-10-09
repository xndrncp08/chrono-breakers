--!strict
-- Process-lifetime boot flag for the server bootstrap. It lives in module state (one per server Luau
-- VM), never in the DataModel: an Instance attribute would persist into Studio's edit session after
-- a Run-mode test and into any place saved afterwards, permanently blocking the next boot.

local BootGuard = { claimed = false }

-- Returns true for the first caller in this server process, false for any duplicate bootstrap.
function BootGuard.claim(): boolean
	if BootGuard.claimed then
		return false
	end
	BootGuard.claimed = true
	return true
end

return BootGuard
