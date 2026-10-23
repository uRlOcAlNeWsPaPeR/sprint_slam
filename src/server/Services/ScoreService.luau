--!strict
-- Authoritative scoring. Reconciles the client's impact claim with what the server saw,
-- re-tallies combos under server rules, and tracks per-session personal bests.
-- (Phase 3 moves bests to DataStores.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Momentum = require(Shared.Momentum)
local ScoreFormula = require(Shared.ScoreFormula)

local V = Config.Validation

local ScoreService = {}

type Best = { Score: number, Splits: { number }, Breakdown: any }
local bests: { [string]: Best } = {} -- keyed "userId:level"

local function bestKey(player: Player, level: number): string
	return player.UserId .. ":" .. level
end

-- Highest impact speed reachable from the momentum the server measured, with an early
-- Slam Dash and tolerance for the client's slightly different measurement.
function ScoreService.impactSpeedCap(serverMomentum: number): number
	local momentum = serverMomentum * V.MomentumTolerance + V.MomentumSlack
	return Momentum.impactSpeed(Momentum.launchSpeed(momentum), Config.Slam.SlamDashMaxBonus)
end

local function boosterPositions(course: any, kind: string): { Vector3 }
	local points = {}
	if kind == "BoostPads" or kind == "Boosters" then
		for _, pad in course.BoostPads do
			table.insert(points, pad.Position)
		end
	end
	if kind == "BoostRings" or kind == "Boosters" then
		for _, ring in course.BoostRings do
			table.insert(points, ring.Position)
		end
	end
	return points
end

-- Returns points awarded (0 when rejected).
function ScoreService.tryCombo(session: any, eventType: string, now: number, fromServer: boolean): number
	local def = Config.Combo.Events[eventType]
	if not def then
		return 0
	end
	if def.ServerOnly and not fromServer then
		return 0
	end
	if def.Near then
		local points = boosterPositions(session.course, def.Near)
		if not session.validator:wasNear(points, now, V.NearDistance, V.NearLookback) then
			return 0
		end
	end
	local awarded = session.combo:add(eventType, now)
	return awarded
end

export type ImpactInputs = {
	course: any,
	roundTime: number,
	goTime: number,
	launch: { Time: number, Momentum: number },
	serverImpact: { Point: Vector3, Speed: number }?,
	claim: { Point: Vector3, Speed: number, LaunchTime: number }?,
	extrapolated: { Point: Vector3, Speed: number }?,
	ping: number,
	comboBonus: number,
}

-- Returns the breakdown, or nil plus a reason when the impact cannot be verified.
function ScoreService.scoreImpact(inputs: ImpactInputs): (ScoreFormula.Breakdown?, string?)
	local serverImpact = inputs.serverImpact or inputs.extrapolated
	if not serverImpact then
		return nil, "impact not observed"
	end
	local claim = inputs.claim

	local point = serverImpact.Point
	if claim and (claim.Point - serverImpact.Point).Magnitude <= V.ImpactPointTolerance then
		point = claim.Point
	end

	local cap = ScoreService.impactSpeedCap(inputs.launch.Momentum)
	local speed = math.min(serverImpact.Speed, cap)
	if claim then
		speed = math.min(claim.Speed, serverImpact.Speed * V.ImpactSpeedTolerance, cap)
	end

	local launchTime = inputs.launch.Time
	if claim then
		local earliest = launchTime - (inputs.ping + 0.1)
		if claim.LaunchTime >= earliest and claim.LaunchTime <= launchTime then
			launchTime = claim.LaunchTime
		end
	end
	local roundTime = inputs.roundTime
	local timeRemaining = math.clamp(inputs.goTime + roundTime - launchTime, 0, roundTime)

	local target = inputs.course.Target
	local _, radius = Geometry.targetOffset(point, target.Center, target.Normal)
	local breakdown = ScoreFormula.compute({
		Outcome = "Impact",
		ImpactSpeed = speed,
		Zone = ScoreFormula.zoneForRadius(radius),
		TimeRemaining = timeRemaining,
		ComboBonus = inputs.comboBonus,
		Momentum = inputs.launch.Momentum,
	})
	return breakdown, nil
end

function ScoreService.getBest(player: Player, level: number): Best?
	return bests[bestKey(player, level)]
end

-- Best score per level for the level select, e.g. { [1] = 2684, [3] = 1900 }.
function ScoreService.levelBests(player: Player, levelCount: number): { [string]: number }
	local result = {}
	for level = 1, levelCount do
		local best = bests[bestKey(player, level)]
		if best then
			result[tostring(level)] = best.Score
		end
	end
	return result
end

function ScoreService.recordRun(player: Player, level: number, breakdown: ScoreFormula.Breakdown, splits: { number }): boolean
	if breakdown.Outcome ~= "Impact" then
		return false
	end
	local key = bestKey(player, level)
	local best = bests[key]
	if best and best.Score >= breakdown.Final then
		return false
	end
	bests[key] = { Score = breakdown.Final, Splits = table.clone(splits), Breakdown = breakdown }
	return true
end

function ScoreService.clear(player: Player)
	local prefix = player.UserId .. ":"
	for key in bests do
		if string.sub(key, 1, #prefix) == prefix then
			bests[key] = nil
		end
	end
end

return ScoreService
