--!strict
-- TelemetryService: privacy-conscious balance telemetry. Feeds MatchTelemetry with director events,
-- chase transitions and ability uses, then logs one anonymous summary per match (no user ids or
-- names) as a JSON line, rolls a server-lifetime aggregate, and optionally sends a few headline
-- numbers to Roblox's aggregated AnalyticsService dashboards. Never affects gameplay.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Safe = require(ReplicatedStorage.Shared.Modules.Safe)

local MatchTelemetry = require(script.Parent.Parent.Core.MatchTelemetry)
local ServerConfig = require(script.Parent.Parent.ServerConfig)

local TelemetryService = {}

local deps: { [string]: any } = {}
local current: MatchTelemetry.MatchTelemetry? = nil
local history: { MatchTelemetry.Summary } = {}
local config = ServerConfig.Telemetry

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function sendAnalytics(summary: MatchTelemetry.Summary)
	-- One event set per match, attributed to a remaining participant (the API requires a player).
	local reporter = deps.MatchService.GetKeeper()
	if not reporter then
		for _, player in deps.MatchService.GetParticipants() do
			if player.Parent then
				reporter = player
				break
			end
		end
	end
	if not reporter or not reporter.Parent then
		return
	end
	local fields = {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = summary.mapId,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = summary.winner,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = `squad{summary.squad}/{summary.condition}`,
	}
	local metrics = {
		MatchDurationSec = summary.durationSec,
		KeeperWin = if summary.winner == "TimeKeeper" then 1 else 0,
		Extracted = summary.extracted,
		TerminalsBreached = summary.terminals,
		AvgChaseSec = summary.avgChaseSec,
		TunnelHits = summary.tunnelHits,
		CampReleases = summary.campReleases,
	}
	for name, value in metrics do
		local ok, err = pcall(AnalyticsService.LogCustomEvent, AnalyticsService, reporter, name, value, fields)
		if not ok then
			warn(`[TelemetryService] analytics event {name} failed: {err}`)
			return
		end
	end
end

local function onEvent(name: string, payload: any)
	local t = now()
	if name == "MatchStarted" then
		current = MatchTelemetry.new(deps.WorldService.GetMapId() or "Unknown", function(userId: number): string?
			local player = Players:GetPlayerByUserId(userId)
			return if player then deps.MatchService.GetMatchClass(player) else nil
		end, deps.PerkService.GetCondition())
	end
	local telemetry = current
	if not telemetry then
		return
	end
	telemetry:observe(name, payload, t)
	if name == "MatchResolved" then
		current = nil
		local summary = telemetry:summary(t)
		if not summary then
			return
		end
		table.insert(history, summary)
		if #history > config.HistorySize then
			table.remove(history, 1)
		end
		if config.LogSummaries then
			print(`[Telemetry] match {HttpService:JSONEncode(summary)}`)
			if #history % config.AggregateEvery == 0 then
				print(`[Telemetry] aggregate {HttpService:JSONEncode(MatchTelemetry.aggregate(history))}`)
			end
		end
		if config.AnalyticsEnabled then
			task.spawn(sendAnalytics, summary)
		end
	end
end

function TelemetryService.Chase(userId: number, started: boolean)
	if current then
		current:chase(userId, started, now())
	end
end

function TelemetryService.Ability(abilityId: string)
	if current then
		current:ability(abilityId)
	end
end

function TelemetryService.History(): { MatchTelemetry.Summary }
	return table.clone(history)
end

function TelemetryService.Init(injected: { [string]: any })
	deps = injected
end

function TelemetryService.Start()
	deps.MatchService.GetDirector().events:Connect(function(name: string, payload: any)
		local ok, err = Safe.call(onEvent, name, payload)
		if not ok then
			warn(`[TelemetryService] {name}: {err}`)
		end
	end)
end

return TelemetryService
