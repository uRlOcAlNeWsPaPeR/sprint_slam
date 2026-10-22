--!strict
-- Pure scoring math shared by the server (authoritative) and client (instant preview).
-- Final = round(ImpactSpeed × SpeedScorePerStud × ZoneMultiplier) + TimeBonus + ComboBonus

local Config = require(script.Parent.Config)

export type Zone = { Name: string, Radius: number?, Multiplier: number }

export type Breakdown = {
	Outcome: string, -- "Impact" | "TimeUp" | "Invalid"
	ImpactSpeed: number,
	SpeedScore: number,
	Zone: string,
	Multiplier: number,
	TimeRemaining: number,
	TimeBonus: number,
	ComboBonus: number,
	Final: number,
}

local ScoreFormula = {}

function ScoreFormula.zoneForRadius(radius: number): Zone
	for _, zone in Config.Target.Zones do
		if radius <= zone.Radius then
			return zone
		end
	end
	return Config.Target.Miss
end

function ScoreFormula.zoneByName(name: string): Zone
	for _, zone in Config.Target.Zones do
		if zone.Name == name then
			return zone
		end
	end
	return Config.Target.Miss
end

function ScoreFormula.timeBonus(timeRemaining: number): number
	return math.floor(math.max(timeRemaining, 0) * Config.Score.TimeBonusPerSecond + 0.5)
end

function ScoreFormula.compute(input: {
	Outcome: string,
	ImpactSpeed: number?,
	Zone: Zone?,
	TimeRemaining: number?,
	ComboBonus: number?,
}): Breakdown
	local outcome = input.Outcome
	local zone = input.Zone or Config.Target.Miss
	local impactSpeed = math.floor((input.ImpactSpeed or 0) + 0.5)
	local timeRemaining = math.max(input.TimeRemaining or 0, 0)
	local comboBonus = math.clamp(math.floor(input.ComboBonus or 0), 0, Config.Score.MaxComboBonus)

	local breakdown: Breakdown = {
		Outcome = outcome,
		ImpactSpeed = impactSpeed,
		SpeedScore = math.floor(impactSpeed * Config.Score.SpeedScorePerStud + 0.5),
		Zone = zone.Name,
		Multiplier = zone.Multiplier,
		TimeRemaining = timeRemaining,
		TimeBonus = ScoreFormula.timeBonus(timeRemaining),
		ComboBonus = comboBonus,
		Final = 0,
	}

	if outcome ~= "Impact" then
		breakdown.SpeedScore = 0
		breakdown.TimeBonus = 0
		breakdown.ComboBonus = 0
		breakdown.Multiplier = 0
		return breakdown
	end

	local slam = math.floor(breakdown.SpeedScore * zone.Multiplier + 0.5)
	local bonuses = breakdown.TimeBonus + breakdown.ComboBonus
	if zone.Multiplier <= 0 and not Config.Score.MissKeepsBonuses then
		bonuses = 0
	end
	breakdown.Final = slam + bonuses
	return breakdown
end

return ScoreFormula
