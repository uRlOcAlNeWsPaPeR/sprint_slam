--!strict
-- Pure scoring math shared by the server (authoritative) and client (instant preview).
--   ImpactPower = ImpactSpeed² ÷ PowerDivisor          (impact energy: speed counts twice)
--   SlamScore   = round(ImpactPower × ZoneMultiplier)
--   Final       = SlamScore + TimeBonus + ComboBonus
--   Coins       = SlamScore ÷ CoinDivisor

local Config = require(script.Parent.Config)

export type Zone = { Name: string, Radius: number?, Multiplier: number }

export type Breakdown = {
	Outcome: string, -- "Impact" | "TimeUp" | "Invalid"
	Momentum: number,
	ImpactSpeed: number,
	ImpactPower: number,
	Zone: string,
	Multiplier: number,
	SlamScore: number,
	TimeRemaining: number,
	TimeBonus: number,
	ComboBonus: number,
	Final: number,
	Coins: number,
}

local ScoreFormula = {}

function ScoreFormula.zoneForRadius(radius: number): Zone
	for _, zone in Config.Target.Zones do
		if radius <= zone.Radius then
			return zone
		end
	end
	return Config.Target.Wall
end

function ScoreFormula.zoneByName(name: string): Zone
	for _, zone in Config.Target.Zones do
		if zone.Name == name then
			return zone
		end
	end
	return Config.Target.Wall
end

function ScoreFormula.impactPower(impactSpeed: number): number
	return math.floor(impactSpeed * impactSpeed / Config.Score.PowerDivisor + 0.5)
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
	Momentum: number?,
}): Breakdown
	local zone = input.Zone or Config.Target.Wall
	local impactSpeed = math.max(input.ImpactSpeed or 0, 0)
	local timeRemaining = math.max(input.TimeRemaining or 0, 0)

	local breakdown: Breakdown = {
		Outcome = input.Outcome,
		Momentum = math.floor((input.Momentum or 0) + 0.5),
		ImpactSpeed = math.floor(impactSpeed + 0.5),
		ImpactPower = 0,
		Zone = zone.Name,
		Multiplier = 0,
		SlamScore = 0,
		TimeRemaining = timeRemaining,
		TimeBonus = 0,
		ComboBonus = 0,
		Final = 0,
		Coins = 0,
	}
	if input.Outcome ~= "Impact" then
		return breakdown
	end

	breakdown.ImpactPower = ScoreFormula.impactPower(impactSpeed)
	breakdown.Multiplier = zone.Multiplier
	breakdown.SlamScore = math.floor(breakdown.ImpactPower * zone.Multiplier + 0.5)
	breakdown.TimeBonus = ScoreFormula.timeBonus(timeRemaining)
	breakdown.ComboBonus = math.clamp(math.floor(input.ComboBonus or 0), 0, Config.Score.MaxComboBonus)
	breakdown.Final = breakdown.SlamScore + breakdown.TimeBonus + breakdown.ComboBonus
	breakdown.Coins = math.floor(breakdown.SlamScore / Config.Score.CoinDivisor)
	return breakdown
end

return ScoreFormula
