--!strict
-- Builds (and caches) the ten course definitions of a week. Challenge i sits in its own slot
-- of the world, SLOT_SPACING studs to the east of the one before, so players on different
-- challenges never see or touch each other's hazards.

local CourseKit = require(script.Parent.CourseKit)

local Courses = {}

Courses.SLOT_SPACING = 400

local cache: { [string]: { any } } = {}

function Courses.forWeek(week: any): { any }
	local cached = cache[week.Id]
	if cached then
		return cached
	end
	local courses = {}
	for index, def in week.Challenges do
		local kit = CourseKit.new({
			Id = week.Id .. "C" .. index,
			Index = index,
			Name = def.Name,
			Intro = def.Intro,
			New = def.New,
			RoundTime = def.RoundTime,
			Sign = def.Sign,
			Origin = Vector3.new((index - 1) * Courses.SLOT_SPACING, 0, 0),
		})
		def.Build(kit)
		courses[index] = kit:finish()
	end
	cache[week.Id] = courses
	return courses
end

return Courses
