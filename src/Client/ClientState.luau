--!strict
-- Client-side view of authoritative server state. The UI renders from here; nothing in this store is
-- authoritative. Writers call ClientState.set(key, value); readers subscribe to ClientState.changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

export type AbilityState = {
	abilityId: string,
	readyAt: number,
	cooldown: number,
	active: number,
	maxActive: number?,
}

local ClientState = {}

ClientState.changed = Signal.new() :: Signal.Signal<string, any>

local values: { [string]: any } = {
	snapshot = nil, -- GameTypes.MatchSnapshot
	queue = nil, -- queue state payload
	role = nil, -- RoleAssigned payload for the current match
	profile = nil, -- GameTypes.ProfileSnapshot
	abilities = {}, -- { [abilityId]: AbilityState }
	movement = {}, -- StatusUpdate Movement payload
	extraction = 0, -- extraction channel progress 0..1
	result = nil, -- GameTypes.MatchResultPayload
	terminals = {}, -- { [terminalId]: PublicTerminal }
	inputType = "KeyboardMouse", -- "KeyboardMouse" | "Touch" | "Gamepad"
	settings = nil, -- effective settings table
	connection = "Connecting", -- "Connecting" | "Ready" | "Failed"
	modal = nil, -- name of the open modal, if any
	targeting = nil, -- abilityId being aimed, if any
	spectating = nil, -- userId being spectated, if any
	-- Survival Protocol (all presentation copies of server state)
	calibration = nil, -- { terminalId, challenge } pending Calibration Pulse for the local hacker
	calibrationResult = nil, -- { grade, at } last judged pulse
	action = nil, -- { action, target, startedAt, duration } current survival channel
	stamina = nil, -- { value 0..1, sprinting, exhausted }
	chased = false, -- the server says the Keeper is chasing the local player
	huntTargets = {}, -- Keeper: userIds currently chased
	momentum = 0, -- Keeper: Hunt Momentum bonus
	resonance = 0, -- 0..1 local Temporal Resonance intensity (client computed)
	lastHeartbeat = 0, -- os.clock() of the last heartbeat cue (drives the vignette pulse)
}

function ClientState.get(key: string): any
	return values[key]
end

function ClientState.set(key: string, value: any)
	values[key] = value
	ClientState.changed:Fire(key, value)
end

-- Fires `handler(value)` now and on every subsequent change of `key`.
function ClientState.observe(key: string, handler: (any) -> ()): () -> ()
	handler(values[key])
	local connection = ClientState.changed:Connect(function(changedKey: string, value: any)
		if changedKey == key then
			handler(value)
		end
	end)
	return function()
		connection:Disconnect()
	end
end

-- The local player's public participant entry in the current match, if any.
function ClientState.myParticipant(): any
	local snapshot = values.snapshot
	if not snapshot then
		return nil
	end
	local userId = game:GetService("Players").LocalPlayer.UserId
	for _, p in snapshot.participants do
		if p.userId == userId then
			return p
		end
	end
	return nil
end

-- The local player's integrity condition (nil outside a match).
function ClientState.myCondition(): string?
	local me = ClientState.myParticipant()
	return if me and me.status == "Active" then me.condition else nil
end

-- True when the local player can act (live participant who is not Desynced or In Stasis).
function ClientState.canAct(): boolean
	local condition = ClientState.myCondition()
	return ClientState.isLiveParticipant() and condition ~= "Downed" and condition ~= "Contained"
end

-- True while the local player is an active (not eliminated/extracted) participant of a live match.
function ClientState.isLiveParticipant(): boolean
	local snapshot = values.snapshot
	if not snapshot then
		return false
	end
	local phase = snapshot.phase
	if phase ~= "Intro" and phase ~= "Active" and phase ~= "Extraction" then
		return false
	end
	local me = ClientState.myParticipant()
	return me ~= nil and me.status == "Active"
end

-- The RoleAssigned payload if it belongs to the current match.
function ClientState.currentRole(): any
	local role = values.role
	local snapshot = values.snapshot
	if role and snapshot and snapshot.matchId == role.matchId then
		return role
	end
	return nil
end

function ClientState.now(): number
	return workspace:GetServerTimeNow()
end

return ClientState
