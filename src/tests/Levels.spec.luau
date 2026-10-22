-- Levels and hub challenges must be beatable. These checks use the same jump physics and
-- hazard timing the game uses; the Studio autopilot then proves it by actually doing it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)
local Geometry = require(Shared.Geometry)
local HazardMath = require(Shared.HazardMath)
local Lobby = require(Shared.Lobby)

local GRAVITY = 196.2
local JUMP_SPEED = math.sqrt(2 * GRAVITY * Config.Movement.JumpHeight)

-- Seconds a jump stays at or above `rise` studs (nil if it can't get that high).
local function timeAbove(rise: number): number?
	local disc = JUMP_SPEED * JUMP_SPEED - 2 * GRAVITY * rise
	if disc < 0 then
		return nil
	end
	return (JUMP_SPEED + math.sqrt(disc)) / GRAVITY
end

return function(t)
	local course = Courses.get("NeonRush")

	t.test("five levels, each introducing a new hazard type after the first", function()
		t.eq(#course.Levels, 5)
		local seen = {}
		for _, def in course.Hazards do
			t.truthy(def.Level >= 2 and def.Level <= 5, "hazard level in range")
			seen[def.Level] = seen[def.Level] or def.Type
		end
		t.eq(seen[2], "Kill")
		t.eq(seen[3], "Laser")
		t.eq(seen[4], "Spinner")
		t.eq(seen[5], "Blink")
	end)

	t.test("every death block leaves a lane at least 8 studs wide", function()
		for _, def in course.Hazards do
			if def.Type == "Kill" then
				local base = def.CFrame.Position
				for _, platform in course.Platforms do
					local inside = Geometry.pointInBox(Vector3.new(base.X, platform.CFrame.Position.Y, base.Z), platform.CFrame, platform.Size)
					if inside then
						local leftGap = (base.X - def.Size.X / 2) - (platform.CFrame.Position.X - platform.Size.X / 2)
						local rightGap = (platform.CFrame.Position.X + platform.Size.X / 2) - (base.X + def.Size.X / 2)
						t.truthy(math.max(leftGap, rightGap) >= 8, "death block at " .. tostring(base) .. " blocks its platform")
					end
				end
			end
		end
	end)

	t.test("no checkpoint respawns you on top of a hazard", function()
		for _, checkpoint in course.Checkpoints do
			local spot = checkpoint.Respawn.Position
			for _, def in course.Hazards do
				if def.Type == "Kill" or def.Type == "Laser" then
					t.truthy(not Geometry.pointInBox(spot, def.CFrame, def.Size, Vector3.new(10, 5, 10)), checkpoint.Name .. " respawn is next to a " .. def.Type)
				elseif def.Type == "Spinner" then
					local reach = def.Length / 2 + 4
					t.truthy(Vector3.new(spot.X - def.Center.X, 0, spot.Z - def.Center.Z).Magnitude > reach, checkpoint.Name .. " respawn is inside a spinner's sweep")
				end
			end
		end
	end)

	t.test("lasers stay dark long enough to cross", function()
		for _, def in course.Hazards do
			if def.Type == "Laser" then
				t.truthy((1 - def.OnFraction) * def.Period >= 0.8, "laser off-window")
			end
		end
	end)

	t.test("the blink wave carries a runner at 40-70 st/s across the S-bend", function()
		local segments = {}
		for _, def in course.Hazards do
			if def.Type == "Blink" then
				table.insert(segments, def)
			end
		end
		t.eq(#segments, 5)
		local startX = segments[1].CFrame.Position.X - segments[1].Size.X / 2
		for _, speed in { 40, 50, 60, 70 } do
			local carried = false
			-- Leave the corner at some moment in the first cycle; at least one must work.
			for departure = 0, 2.5, 0.05 do
				local ok = true
				for _, def in segments do
					local x0 = def.CFrame.Position.X - def.Size.X / 2
					for x = x0, x0 + def.Size.X, 2 do
						if not HazardMath.isOn(def, departure + (x - startX) / speed) then
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
			t.truthy(carried, "no departure works at " .. speed .. " st/s")
		end
	end)

	local function challenge(name: string): any
		for _, def in Lobby.Challenges do
			if def.Name == name then
				return def
			end
		end
		error("missing challenge " .. name)
	end

	t.test("SKY TOWER: every step is reachable at walking pace", function()
		local steps = {}
		for _, platform in Lobby.Platforms do
			if string.sub(platform.Name, 1, 9) == "TowerStep" or platform.Name == "TowerTop" then
				table.insert(steps, platform)
			end
		end
		t.eq(#steps, 15)
		for i = 1, #steps - 1 do
			local a, b = steps[i], steps[i + 1]
			local topA = a.CFrame.Position.Y + a.Size.Y / 2
			local topB = b.CFrame.Position.Y + b.Size.Y / 2
			local airtime = timeAbove(topB - topA)
			t.truthy(airtime, "step " .. i .. " too high")
			local centers = Vector3.new(b.CFrame.Position.X - a.CFrame.Position.X, 0, b.CFrame.Position.Z - a.CFrame.Position.Z).Magnitude
			local gap = centers - a.Size.X / 2 - b.Size.X / 2
			-- At 24 st/s the jump must clear the gap and come down before overshooting.
			local reach = 24 * (airtime :: number)
			t.truthy(reach >= gap + 1, "step " .. i .. " gap " .. gap .. " vs reach " .. reach)
		end
		t.truthy(challenge("SKY TOWER").BotRoute ~= nil)
	end)

	t.test("DASH GAPS: every gap is jumpable, and no deck is overshot at pad speed", function()
		local names = { "GapsStart", "Gap1", "Gap2", "GapsFinish" }
		local byName = {}
		for _, platform in Lobby.Platforms do
			byName[platform.Name] = platform
		end
		-- Takeoff speed on each deck, starting from a standing respawn: run-up then +20 from
		-- each deck's boost pad (stacking toward the overspeed cap as they chain).
		local speedAt = { 65, 83, 93 }
		for i = 1, #names - 1 do
			local a, b = byName[names[i]], byName[names[i + 1]]
			local takeoff = a.CFrame.Position.X + a.Size.X / 2
			local nearEdge = b.CFrame.Position.X - b.Size.X / 2
			local farEdge = b.CFrame.Position.X + b.Size.X / 2
			local rise = b.CFrame.Position.Y - a.CFrame.Position.Y
			local airtime = timeAbove(rise) :: number
			local reach = math.min(speedAt[i], Config.Movement.OverspeedCap) * airtime
			if names[i + 1] == "GapsFinish" then
				-- Final jump: boost ring (+16) and an air dash (~+9), applied mid-flight.
				reach += (Config.Course.BoostRingSpeed + Config.Dash.Retain) * airtime * 0.5
			end
			t.truthy(takeoff + reach >= nearEdge + 1, names[i] .. " -> " .. names[i + 1] .. " falls short")
			t.truthy(names[i + 1] == "GapsFinish" or takeoff + reach <= farEdge - 1, names[i] .. " -> " .. names[i + 1] .. " overshoots")
		end
	end)

	t.test("BEAM RUN: each sweeper leaves the beam clear for long enough to pass", function()
		for _, def in Lobby.MovingObstacles do
			-- Fraction of the cycle the block is clear of the 4-stud beam (with body margin).
			local clearSamples, total = 0, 200
			for i = 0, total - 1 do
				local x = math.sin((i / total) * math.pi * 2) * def.Amplitude
				if math.abs(x) > def.Size.X / 2 + 1.4 then
					clearSamples += 1
				end
			end
			local clearSeconds = clearSamples / total * def.Period
			t.truthy(clearSeconds >= 0.6, "sweeper clear time " .. clearSeconds)
		end
	end)
end
