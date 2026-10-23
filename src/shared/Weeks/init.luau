--!strict
-- The weekly schedule. A week is a module under Weeks/ with a StartsAt (a Sunday, 00:00
-- UTC) and ten challenges; releasing next week means adding WeekN and listing it here.
-- Until the first week's start the game runs Week 1 as a preview; once the latest listed
-- week has started it stays current until a newer one is added.

local Weeks = {}

Weeks.WEEK_SECONDS = 7 * 24 * 60 * 60
Weeks.CHALLENGES_PER_WEEK = 10

-- Oldest first.
local list = {
	require(script.Week1),
}

function Weeks.all(): { any }
	return list
end

function Weeks.get(weekId: string): any?
	for _, week in list do
		if week.Id == weekId then
			return week
		end
	end
	return nil
end

-- The week that is live at `now` (unix seconds).
function Weeks.current(now: number): any
	local live = list[1]
	for _, week in list do
		if week.StartsAt <= now then
			live = week
		end
	end
	return live
end

-- Unix time the given week ends (when the next one is due; one week after it starts by
-- default).
function Weeks.endsAt(week: any): number
	for index, candidate in list do
		if candidate == week then
			local nextWeek = list[index + 1]
			return if nextWeek then nextWeek.StartsAt else week.StartsAt + Weeks.WEEK_SECONDS
		end
	end
	return week.StartsAt + Weeks.WEEK_SECONDS
end

-- Weeks that finished before `now`, i.e. every listed week older than the current one.
function Weeks.finishedBefore(now: number): { any }
	local current = Weeks.current(now)
	local finished = {}
	for _, week in list do
		if week.StartsAt < current.StartsAt then
			table.insert(finished, week)
		end
	end
	return finished
end

return Weeks
