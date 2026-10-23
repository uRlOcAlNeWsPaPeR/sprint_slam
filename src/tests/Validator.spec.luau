-- Server-side run measurement: impact speed must not be fooled by the hit-stop slow-down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Courses = require(Shared.Courses)
local Weeks = require(Shared.Weeks)
local RunValidator = require(ServerScriptService.Server.Services.RunValidator)

return function(t)
	local course = Courses.forWeek(Weeks.current(os.time()))[1]
	local toward = Vector3.new(0, 0, -1)

	local function validatorWith(zs: { number }, step: number)
		local validator = RunValidator.new(course)
		for index, z in zs do
			table.insert(validator.samples, { t = 10 + (index - 1) * step, p = Vector3.new(0, 0, z) })
		end
		return validator
	end

	t.test("peak velocity reads the real flight speed, ignoring a slow-down at the very end", function()
		-- 100 st/s for a second, then the runner is frozen: the last samples barely move.
		local zs, z = {}, 0
		for _ = 1, 20 do
			table.insert(zs, z)
			z -= 5 -- 5 studs per 0.05 s = 100 st/s
		end
		table.insert(zs, z - 1)
		table.insert(zs, z - 1.5)
		table.insert(zs, z - 1.7)
		local validator = validatorWith(zs, 0.05)
		local peak = validator:peakVelocity(0.25, 0.5, toward)
		t.truthy(peak >= 95 and peak <= 105, "peak " .. peak)
		-- The plain trailing average is dragged down by the freeze.
		local trailing = validator:windowVelocity(0.3) :: Vector3
		t.truthy(-trailing.Z < 80, "trailing " .. -trailing.Z)
	end)

	t.test("peak velocity never reads faster than the fastest window it saw", function()
		local zs, z = {}, 0
		for _ = 1, 12 do
			table.insert(zs, z)
			z -= 3 -- 60 st/s
		end
		local validator = validatorWith(zs, 0.05)
		local peak = validator:peakVelocity(0.25, 0.5, toward)
		t.truthy(peak <= 61 and peak >= 59, "peak " .. peak)
	end)

	t.test("no samples read as zero speed", function()
		t.eq(RunValidator.new(course):peakVelocity(0.25, 0.5, toward), 0)
	end)
end
