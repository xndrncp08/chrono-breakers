--!strict
-- Maps message severities to theme colours and short text icons (never colour alone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Config.Theme)

local Severity = {}

local COLORS: { [string]: Color3 } = {
	Info = Theme.Colors.TextSecondary,
	Stable = Theme.Colors.Stable,
	Temporal = Theme.Colors.Temporal,
	Danger = Theme.Colors.Danger,
	Warning = Theme.Colors.Warning,
	Success = Theme.Colors.Success,
}

local ICONS: { [string]: string } = {
	Info = "•",
	Stable = "◆",
	Temporal = "◈",
	Danger = "✕",
	Warning = "!",
	Success = "✓",
}

function Severity.color(severity: string?): Color3
	return COLORS[severity or "Info"] or COLORS.Info
end

function Severity.icon(severity: string?): string
	return ICONS[severity or "Info"] or ICONS.Info
end

return Severity
