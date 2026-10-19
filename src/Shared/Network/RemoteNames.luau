--!strict
-- The single authoritative registry of remotes. The server creates exactly these instances under
-- ReplicatedStorage.Remotes; the client only ever waits for them. See docs/NETWORK_CONTRACT.md.

export type RemoteKind = "RemoteEvent" | "UnreliableRemoteEvent"

export type RemoteSpec = {
	Name: string,
	Kind: RemoteKind,
	Direction: "ClientToServer" | "ServerToClient",
}

local RemoteNames = {
	FolderName = "Remotes",

	-- Client -> Server
	QueueRequest = "QueueRequest",
	MapVoteRequest = "MapVoteRequest",
	PingRequest = "PingRequest",
	SprintRequest = "SprintRequest",
	HackChallengeRequest = "HackChallengeRequest",
	ObjectiveRequest = "ObjectiveRequest",
	AbilityRequest = "AbilityRequest",
	ShopRequest = "ShopRequest",
	SettingsUpdate = "SettingsUpdate",
	ClientReady = "ClientReady",

	-- Server -> Client
	MatchState = "MatchState",
	RoleAssigned = "RoleAssigned",
	TerminalUpdate = "TerminalUpdate",
	AbilityState = "AbilityState",
	StatusUpdate = "StatusUpdate",
	Notify = "Notify",
	Effect = "Effect",
	MatchResult = "MatchResult",
	ProfileSnapshot = "ProfileSnapshot",
	ActionResult = "ActionResult",
	QueueState = "QueueState",
}

RemoteNames.Specs = table.freeze({
	{ Name = "HackChallengeRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "PingRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "SprintRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "MapVoteRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "QueueRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "ObjectiveRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "AbilityRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "ShopRequest", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "SettingsUpdate", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "ClientReady", Kind = "RemoteEvent", Direction = "ClientToServer" },
	{ Name = "MatchState", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "RoleAssigned", Kind = "RemoteEvent", Direction = "ServerToClient" },
	-- Throttled per terminal (TerminalConfig.ProgressBroadcastInterval); carries state changes too,
	-- so it stays reliable.
	{ Name = "TerminalUpdate", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "AbilityState", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "StatusUpdate", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "Notify", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "Effect", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "MatchResult", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "ProfileSnapshot", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "ActionResult", Kind = "RemoteEvent", Direction = "ServerToClient" },
	{ Name = "QueueState", Kind = "RemoteEvent", Direction = "ServerToClient" },
} :: { RemoteSpec })

return table.freeze(RemoteNames)
