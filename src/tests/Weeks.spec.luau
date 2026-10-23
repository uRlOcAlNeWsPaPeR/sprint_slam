-- The weekly set must be fair and finishable. These checks use the game's own jump physics
-- and hazard timing; the Studio autopilot then proves it by actually playing every challenge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)
local Geometry = require(Shared.Geometry)
local HazardMath = require(Shared.HazardMath)
local Weeks = require(Shared.Weeks)

local GRAVITY = 196.2
local JUMP_SPEED = math.sqrt(2 * GRAVITY * Config.Movement.JumpHeight)
local FLAT_AIRTIME = 2 * JUMP_SPEED / GRAVITY

return function(t)
	local week = Weeks.current(os.time())
	local courses = Courses.forWeek(week)

	t.test("the week is released on a Sunday at 00:00 UTC", function()
		t.eq(week.StartsAt % 86400, 0)
		local day = week.StartsAt // 86400
		t.eq((day + 4) % 7, 0, "1970-01-01 was a Thursday; 0 = Sunday")
		t.eq(Weeks.endsAt(week), week.StartsAt + Weeks.WEEK_SECONDS)
	end)

	t.test("exactly ten uniquely named challenges, each in its own slot", function()
		t.eq(#courses, Weeks.CHALLENGES_PER_WEEK)
		local ids, names = {}, {}
		for index, course in courses do
			t.truthy(not ids[course.Id] and not names[course.DisplayName], "duplicate challenge " .. course.Id)
			ids[course.Id], names[course.DisplayName] = true, true
			t.near(course.Origin.X, (index - 1) * Courses.SLOT_SPACING)
			t.truthy(Courses.SLOT_SPACING >= course.Target.WallSize.X + 100, "slots must clear the 240-wide slam wall")
		end
	end)

	t.test("every challenge is complete: spawn, checkpoints, launch, target, route", function()
		for _, course in courses do
			local name = course.DisplayName
			t.truthy(course.Spawn and course.StartLine and course.Launch and course.Target, name .. " missing parts")
			t.truthy(#course.Checkpoints >= 4, name .. " needs 4+ checkpoints")
			t.truthy(course.SlamModeDistance > 0 and course.SlamModeDistance < course.PathLength, name .. " slam mode distance")
			t.truthy(#course.BotRoute >= 3, name .. " bot route")
		end
	end)

	t.test("this week's challenges are a bit longer than the old single course (1100+ studs)", function()
		for _, course in courses do
			t.truthy(course.Length >= 1100, course.DisplayName .. " is only " .. course.Length .. " studs")
		end
	end)

	t.test("the round timer allows a 40 st/s average, and the last challenge is the longest allowance", function()
		for _, course in courses do
			t.truthy(course.RoundTime >= course.Length / 40, course.DisplayName .. " RoundTime " .. course.RoundTime)
		end
		t.truthy(courses[10].RoundTime >= courses[1].RoundTime)
		t.truthy(courses[10].Length >= courses[1].Length, "challenge 10 should be at least as long as challenge 1")
	end)

	t.test("every gap can be jumped from a modest 40 st/s run-up", function()
		for _, course in courses do
			for _, gap in course.Gaps or {} do
				t.truthy(gap.Length <= 18 and gap.Length <= 0.8 * 40 * FLAT_AIRTIME, course.DisplayName .. " gap " .. gap.Length)
			end
		end
	end)

	t.test("every death block row leaves a lane at least 8 studs wide", function()
		local rows = 0
		for _, course in courses do
			for _, lane in course.Lanes or {} do
				rows += 1
				t.truthy(lane.Width >= 8, course.DisplayName .. " lane " .. lane.Width)
			end
		end
		t.truthy(rows >= 10)
	end)

	t.test("lasers stay dark at least 0.8 s", function()
		for _, course in courses do
			for _, def in course.Hazards do
				if def.Type == "Laser" then
					t.truthy((1 - def.OnFraction) * def.Period >= 0.8, course.DisplayName .. " laser off-window")
				end
			end
		end
	end)

	t.test("no checkpoint respawns you on or beside a hazard", function()
		for _, course in courses do
			for _, checkpoint in course.Checkpoints do
				local spot = checkpoint.Respawn.Position
				for _, def in course.Hazards do
					if def.Type == "Kill" or def.Type == "Laser" then
						t.truthy(not Geometry.pointInBox(spot, def.CFrame, def.Size, Vector3.new(10, 5, 10)), course.DisplayName .. " " .. checkpoint.Name .. " beside a " .. def.Type)
					elseif def.Type == "Spinner" then
						local flat = Vector3.new(spot.X - def.Center.X, 0, spot.Z - def.Center.Z).Magnitude
						t.truthy(flat > def.Length / 2 + 4 or math.abs(spot.Y - def.Center.Y) > 8, course.DisplayName .. " " .. checkpoint.Name .. " in a spinner's sweep")
					end
				end
			end
		end
	end)

	t.test("checkpoints are never more than 450 studs apart", function()
		for _, course in courses do
			local previous = course.Spawn.Position.Z
			for _, checkpoint in course.Checkpoints do
				t.truthy(math.abs(previous - checkpoint.CFrame.Position.Z) <= 450, course.DisplayName .. " checkpoint gap")
				previous = math.min(previous, checkpoint.CFrame.Position.Z)
			end
			t.truthy(math.abs(previous - course.Launch.Position.Z) <= 450 + 183, course.DisplayName .. " last checkpoint to launch")
		end
	end)

	t.test("blink waves carry a runner at 40-70 st/s", function()
		local waves = 0
		for _, course in courses do
			for waveIndex, wave in course.BlinkWaves or {} do
				waves += 1
				local segments = {}
				for _, def in course.Hazards do
					if def.Type == "Blink" and def.Wave == waveIndex then
						table.insert(segments, def)
					end
				end
				t.eq(#segments, wave.Count)
				for _, speed in { 40, 50, 60, 70 } do
					local carried = false
					for departure = 0, 2.5, 0.05 do
						local ok = true
						for _, def in segments do
							local near = def.CFrame.Position.Z + def.Size.Z / 2
							for z = near, near - def.Size.Z, -2 do
								if not HazardMath.isOn(def, departure + (wave.Z0 - z) / speed) then
									ok = false
									break
								end
							end
							if not ok then
								break
							end
						end
						if ok then
							carried = true
							break
						end
					end
					t.truthy(carried, course.DisplayName .. " wave " .. waveIndex .. " at " .. speed .. " st/s")
				end
			end
		end
		t.truthy(waves >= 3)
	end)

	t.test("every sweeping block leaves the lane clear long enough to pass", function()
		local checked = 0
		for _, course in courses do
			for _, def in course.MovingObstacles do
				checked += 1
				local clear, total = 0, 200
				for i = 0, total - 1 do
					local x = math.sin((i / total) * math.pi * 2) * def.Amplitude
					-- Any gap of 10+ studs between the block and a wall counts as passable.
					if def.Amplitude + def.Size.X / 2 < 15 or math.abs(x) > def.Size.X / 2 + 1.4 then
						clear += 1
					end
				end
				t.truthy(clear / total * def.Period >= 0.5 or def.Amplitude + def.Size.X / 2 < 15, course.DisplayName .. " sweeper")
			end
		end
		t.truthy(checked >= 10)
	end)

	t.test("the bot route runs in course order and ends past the launch lip", function()
		for _, course in courses do
			local lastZ = math.huge
			for _, waypoint in course.BotRoute do
				t.truthy(waypoint.Position.Z <= lastZ + 1e-6, course.DisplayName .. " route out of order")
				lastZ = waypoint.Position.Z
			end
			t.truthy(lastZ < course.Launch.Position.Z, course.DisplayName .. " route stops short of the lip")
		end
	end)

	t.test("the challenges ramp up: each of the first five introduces a new hazard type", function()
		local introduced = {}
		for index = 1, 5 do
			for _, def in courses[index].Hazards do
				if not introduced[def.Type] then
					introduced[def.Type] = index
				end
			end
		end
		t.eq(introduced.Kill, 2)
		t.eq(introduced.Laser, 3)
		t.eq(introduced.Spinner, 4)
		t.eq(introduced.Blink, 5)
		t.eq(#courses[1].Hazards, 0, "challenge 1 is hazard-free")
	end)
end
