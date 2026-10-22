-- World data sanity: the hub and course must be self-consistent before anything is built.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Courses = require(Shared.Courses)
local Geometry = require(Shared.Geometry)
local Lobby = require(Shared.Lobby)

return function(t)
	t.test("hub spawn stands on the plaza", function()
		local spawn = Lobby.Spawn.Position
		local plaza = Lobby.Plaza
		local flat = Vector3.new(spawn.X - plaza.Center.X, 0, spawn.Z - plaza.Center.Z)
		t.truthy(flat.Magnitude < plaza.Radius - 6, "spawn must be inside the plaza (not in a challenge)")
		t.truthy(spawn.Y > plaza.Center.Y, "spawn above the floor")
	end)

	t.test("exactly one live Sprint Slam portal", function()
		local live = 0
		for _, portal in Lobby.Portals do
			if portal.Active then
				t.eq(portal.Mode, "SprintSlam")
				live += 1
			end
		end
		t.eq(live, 1)
	end)

	t.test("every challenge respawns inside its own start box and finishes above its fail line", function()
		for _, challenge in Lobby.Challenges do
			t.truthy(Geometry.pointInBox(challenge.Respawn.Position, challenge.Start.CFrame, challenge.Start.Size), challenge.Name .. " respawn")
			t.truthy(challenge.Finish.CFrame.Position.Y > challenge.FailY, challenge.Name .. " finish height")
			t.truthy(challenge.FailY > Lobby.KillY, challenge.Name .. " fail line above the hub kill plane")
		end
	end)

	t.test("hub and course do not overlap", function()
		local course = Courses.get()
		local plazaNearEdge = Lobby.Plaza.Center.Z - Lobby.Plaza.Radius
		for _, platform in course.Platforms do
			local farEdge = platform.CFrame.Position.Z + platform.Size.Z / 2
			t.truthy(farEdge < plazaNearEdge - 100, platform.Name .. " too close to the hub")
		end
	end)
end
