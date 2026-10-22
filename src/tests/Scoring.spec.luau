-- Scoring, combos and geometry: the logic both client and server must agree on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local ComboTracker = require(Shared.ComboTracker)
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)
local Geometry = require(Shared.Geometry)
local ScoreFormula = require(Shared.ScoreFormula)
local ScoreService = require(ServerScriptService.Server.Services.ScoreService)

return function(t)
	t.test("matches the design example (186 bullseye → 928)", function()
		local breakdown = ScoreFormula.compute({
			Outcome = "Impact",
			ImpactSpeed = 186,
			Zone = ScoreFormula.zoneByName("BULLSEYE"),
			TimeRemaining = 25,
			ComboBonus = 120,
		})
		t.eq(breakdown.SpeedScore, 186)
		t.eq(breakdown.Multiplier, 3)
		t.eq(breakdown.TimeBonus, 250)
		t.eq(breakdown.Final, 928)
	end)

	t.test("zones by radius", function()
		t.eq(ScoreFormula.zoneForRadius(0).Name, "BULLSEYE")
		t.eq(ScoreFormula.zoneForRadius(4.5).Name, "BULLSEYE")
		t.eq(ScoreFormula.zoneForRadius(4.6).Name, "INNER")
		t.eq(ScoreFormula.zoneForRadius(15).Name, "MIDDLE")
		t.eq(ScoreFormula.zoneForRadius(29).Name, "OUTER")
		t.eq(ScoreFormula.zoneForRadius(31).Name, "MISS")
	end)

	t.test("miss keeps bonuses but no slam score", function()
		local breakdown = ScoreFormula.compute({
			Outcome = "Impact",
			ImpactSpeed = 150,
			Zone = Config.Target.Miss,
			TimeRemaining = 10,
			ComboBonus = 50,
		})
		t.eq(breakdown.Final, 150)
	end)

	t.test("time up and invalid score zero", function()
		t.eq(ScoreFormula.compute({ Outcome = "TimeUp", ImpactSpeed = 100, TimeRemaining = 5 }).Final, 0)
		t.eq(ScoreFormula.compute({ Outcome = "Invalid", ComboBonus = 300 }).Final, 0)
	end)

	t.test("combo bonus is capped", function()
		local breakdown = ScoreFormula.compute({ Outcome = "Impact", ImpactSpeed = 0, ComboBonus = 99999 })
		t.eq(breakdown.ComboBonus, Config.Score.MaxComboBonus)
	end)

	t.test("combo chain grows inside the window and resets outside", function()
		local combo = ComboTracker.new()
		local p1, m1 = combo:add("BoostPad", 0)
		t.eq(p1, 10)
		t.eq(m1, 1)
		local p2, m2 = combo:add("BoostChain", 1)
		t.eq(m2, 1.25)
		t.eq(p2, 31)
		local _, m3 = combo:add("PerfectLanding", 1 + Config.Combo.Window + 0.1)
		t.eq(m3, 1)
	end)

	t.test("combo enforces per-type intervals", function()
		local combo = ComboTracker.new()
		t.eq((combo:add("SlamDash", 0)), 20)
		t.eq((combo:add("SlamDash", 1)), 0)
		t.eq((combo:add("Bogus", 2)), 0)
	end)

	t.test("plane crossing only counts approach-side to far-side", function()
		local point = Geometry.planeCrossing(Vector3.new(0, 0, 10), Vector3.new(0, 0, -10), Vector3.zero, Vector3.zAxis)
		t.truthy(point)
		t.near((point :: Vector3).Z, 0)
		t.eq(Geometry.planeCrossing(Vector3.new(0, 0, -10), Vector3.new(0, 0, 10), Vector3.zero, Vector3.zAxis), nil)
	end)

	t.test("segment vs oriented box", function()
		local box = CFrame.new(0, 0, 0)
		t.truthy(Geometry.segmentIntersectsBox(Vector3.new(0, 0, 10), Vector3.new(0, 0, -10), box, Vector3.new(4, 4, 1)))
		t.eq(Geometry.segmentIntersectsBox(Vector3.new(5, 0, 10), Vector3.new(5, 0, -10), box, Vector3.new(4, 4, 1)), false)
	end)

	t.test("target offset measures radius in the target plane", function()
		local _, radius = Geometry.targetOffset(Vector3.new(3, 4, 7), Vector3.zero, Vector3.zAxis)
		t.near(radius, 5)
	end)

	t.test("path distance projects onto the course line", function()
		local path = Geometry.buildPath({ Vector3.zero, Vector3.new(0, 0, -100), Vector3.new(100, 0, -100) })
		t.near(Geometry.distanceAlongPath(path, Vector3.new(3, 0, -50)), 50)
		t.near(Geometry.distanceAlongPath(path, Vector3.new(40, 2, -98)), 140)
	end)

	local course = Courses.get("NeonRush")
	local target = course.Target
	local triggerPoint = target.Center + target.Normal * Config.Slam.TriggerOffset

	t.test("server caps a claimed impact speed by what it observed", function()
		local breakdown = ScoreService.scoreImpact({
			course = course,
			goTime = 0,
			launch = { Time = 25, Speed = 90 },
			serverImpact = { Point = triggerPoint, Speed = 120 },
			claim = { Point = triggerPoint, Speed = 999, LaunchTime = 25 },
			ping = 0.1,
			comboBonus = 0,
		})
		t.truthy(breakdown)
		t.eq((breakdown :: any).ImpactSpeed, math.floor(120 * Config.Validation.ImpactSpeedTolerance + 0.5))
		t.eq((breakdown :: any).Zone, "BULLSEYE")
		t.eq((breakdown :: any).TimeBonus, 200)
	end)

	t.test("server ignores a claimed hit point far from its own", function()
		local breakdown = ScoreService.scoreImpact({
			course = course,
			goTime = 0,
			launch = { Time = 30, Speed = 80 },
			serverImpact = { Point = triggerPoint + Vector3.new(0, 25, 0), Speed = 110 },
			claim = { Point = triggerPoint, Speed = 110, LaunchTime = 20 },
			ping = 0.1,
			comboBonus = 0,
		})
		t.eq((breakdown :: any).Zone, "OUTER")
		-- Launch-time claim 10 s earlier than observed is rejected.
		t.eq((breakdown :: any).TimeBonus, 150)
	end)

	t.test("unobserved impact is rejected", function()
		local breakdown, reason = ScoreService.scoreImpact({
			course = course,
			goTime = 0,
			launch = { Time = 30, Speed = 80 },
			claim = { Point = triggerPoint, Speed = 110, LaunchTime = 30 },
			ping = 0.1,
			comboBonus = 0,
		})
		t.eq(breakdown, nil)
		t.truthy(reason)
	end)

	t.test("course data is internally consistent", function()
		t.eq(#course.Checkpoints >= 2, true)
		t.truthy(course.SlamModeDistance > 0)
		local path = Geometry.buildPath(course.Path)
		t.truthy(course.SlamModeDistance < path.length)
		for _, pad in course.BoostPads do
			t.truthy(pad.Position.Y > course.KillY)
		end
	end)
end
