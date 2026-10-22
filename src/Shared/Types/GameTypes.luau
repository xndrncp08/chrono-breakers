--!strict
-- Shared type vocabulary used by server, client, and network payloads.

export type Phase =
	"WaitingForPlayers"
	| "Intermission"
	| "RoleAssignment"
	| "Intro"
	| "Active"
	| "Extraction"
	| "Resolving"
	| "ReturningToLobby"

export type Role = "TimeKeeper" | "Infiltrator"

-- Status of a match participant. "Disconnected" participants are never eligible for rewards.
export type ParticipantStatus = "Active" | "Eliminated" | "Extracted" | "Disconnected"

export type TerminalState = "Locked" | "Available" | "Hacking" | "Interrupted" | "Completed"

export type Team = "TimeKeeper" | "Infiltrators"

export type ResolutionReason =
	"Extracted" -- at least one Infiltrator extracted
	| "AllEliminated" -- every Infiltrator was eliminated (none extracted)
	| "TimeExpired" -- match timer ran out before extraction began
	| "ExtractionFailed" -- extraction window closed with nobody extracted
	| "KeeperLeft" -- Time-Keeper disconnected
	| "InfiltratorsLeft" -- every remaining Infiltrator disconnected
	| "Aborted" -- match could not continue (e.g. everyone left)

-- Public per-participant info broadcast to all clients.
-- Integrity ladder (SurvivalConfig): Healthy/Injured are free; Downed/Contained are not.
export type Condition = "Healthy" | "Injured" | "Downed" | "Contained"

export type PublicParticipant = {
	classId: string?,
	userId: number,
	name: string,
	role: Role,
	status: ParticipantStatus,
	condition: Condition?,
	stage: number?, -- times contained
	heal: number?, -- Patch progress 0..1
	revive: number?, -- Re-sync progress 0..1
	bleedoutAt: number?,
	podId: string?,
	podRemaining: number?,
	podDuration: number?,
	feedback: number?, -- anti-camp feedback 0..1
	enduranceUntil: number?,
	action: string?, -- current survival channel
}

export type PublicTerminal = {
	id: string,
	name: string,
	state: TerminalState,
	progress: number, -- 0..1, presentation only
	hackerUserId: number?,
	assistants: { number }?,
	regressing: boolean?,
	mode: string?,
	difficulty: number?,
}

export type MatchSnapshot = {
	mapId: string?,
	mapName: string?,
	condition: string?, -- Timeline Condition id (ConditionConfig)
	mapVotes: { [string]: string }?,
	anomaly: {
		id: string,
		kind: string,
		position: Vector3,
		destination: Vector3,
		radius: number,
		activatesAt: number,
		endsAt: number,
		state: string,
	}?,
	version: number,
	matchId: string?,
	phase: Phase,
	phaseEndsAt: number?, -- workspace:GetServerTimeNow() based
	requiredHacks: number,
	completedHacks: number,
	participants: { PublicParticipant },
	terminals: { PublicTerminal },
	extractionActive: boolean,
	collapse: { endsAt: number?, gateOpen: boolean, relays: { [string]: number }, tier: string }?,
	rift: { site: string? }?,
	queueCount: number,
	minPlayers: number,
	maxPlayers: number,
}

export type RewardLine = { label: string, amount: number }

export type MatchResultPayload = {
	matchId: string,
	winner: Team?, -- nil when the match was aborted
	reason: ResolutionReason,
	yourRole: Role?,
	yourStatus: ParticipantStatus?,
	won: boolean,
	rewards: { RewardLine },
	rewardTotal: number,
	rewardsSaved: boolean,
	xp: number?,
	progressionRewards: { string }?,
	stats: {
		hacks: number,
		eliminations: number,
		extracted: boolean,
		rescues: number?,
		revives: number?,
		heals: number?,
		downs: number?,
		containments: number?,
		greats: number?,
	},
	participants: { PublicParticipant },
}

export type ProfileSnapshot = {
	loaded: boolean,
	persistent: boolean, -- false when data could not be loaded and the session is unsaved
	currency: number,
	owned: { [string]: boolean },
	equipped: { [string]: string },
	stats: { [string]: number },
	settings: { [string]: any },
	progression: any?,
	perks: { [string]: { string } }?,
}

return {}
