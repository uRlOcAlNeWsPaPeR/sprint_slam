-- Weekly progression (clear in order, then free choice) and the score/time leaderboards.
-- Uses stand-in player tables and in-memory boards, never real DataStores.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Server.Services
local BoardService = require(Services.BoardService)
local ProgressService = require(Services.ProgressService)

local function player(id: number, name: string): any
	return { UserId = id, Name = name, DisplayName = name }
end

return function(t)
	BoardService.setPersistence(false)

	t.test("challenges must be cleared in order the first time", function()
		local p = player(-101, "Ordered")
		t.eq(ProgressService.clearedCount(p), 0)
		t.eq(ProgressService.unlockedCount(p), 1)
		t.eq(ProgressService.isUnlocked(p, 1), true)
		t.eq(ProgressService.isUnlocked(p, 2), false)
		t.eq(ProgressService.recordClear(p, 2), false, "cannot skip ahead")
		t.eq(ProgressService.recordClear(p, 1), true)
		t.eq(ProgressService.recordClear(p, 1), false, "replaying is not a new clear")
		t.eq(ProgressService.unlockedCount(p), 2)
		t.eq(ProgressService.isUnlocked(p, 3), false)
		ProgressService.clear(p)
	end)

	t.test("after clearing all ten, any challenge can be picked", function()
		local p = player(-102, "Finisher")
		for index = 1, 10 do
			t.eq(ProgressService.recordClear(p, index), true)
		end
		t.eq(ProgressService.allCleared(p), true)
		for index = 1, 10 do
			t.eq(ProgressService.isUnlocked(p, index), true)
		end
		t.eq(ProgressService.unlockedCount(p), 10)
		ProgressService.clear(p)
	end)

	t.test("score board is highest first, time board fastest first, bests only improve", function()
		local a, b, c = player(-201, "Ann"), player(-202, "Bo"), player(-203, "Cy")
		local weekId = "TESTW"
		t.eq(select(1, BoardService.submit(a, weekId, 1, 1000, 30000)), true)
		BoardService.submit(b, weekId, 1, 2500, 41000)
		BoardService.submit(c, weekId, 1, 1800, 25000)
		local newScore, newTime = BoardService.submit(a, weekId, 1, 900, 31000)
		t.eq(newScore, false, "a lower score is not a new best")
		t.eq(newTime, false, "a slower time is not a new best")
		local newScore2, newTime2 = BoardService.submit(a, weekId, 1, 1200, 24000)
		t.eq(newScore2, true)
		t.eq(newTime2, true)

		local scores = BoardService.top(weekId, 1, "Score", 5)
		t.eq(#scores, 3)
		t.eq(scores[1].Name, "Bo")
		t.eq(scores[1].Value, 2500)
		t.eq(scores[2].Name, "Cy")
		t.eq(scores[3].Value, 1200)
		local times = BoardService.top(weekId, 1, "Time", 5)
		t.eq(times[1].Name, "Ann")
		t.eq(times[1].Value, 24000)
		t.eq(times[2].Name, "Cy")
		t.eq(times[3].Name, "Bo")
		t.eq(BoardService.personal(a)[1].Score, 1200)
		t.eq(BoardService.personal(a)[1].TimeMs, 24000)
	end)

	t.test("boards are separate per challenge and per week", function()
		local p = player(-301, "Solo")
		BoardService.submit(p, "TESTW2", 3, 500, 50000)
		t.eq(#BoardService.top("TESTW2", 3, "Score", 5), 1)
		t.eq(#BoardService.top("TESTW2", 4, "Score", 5), 0)
		t.eq(#BoardService.top("TESTW3", 3, "Score", 5), 0)
	end)

	t.test("finalizing a week inducts each board's winner and the champion", function()
		local x, y = player(-401, "Xavi"), player(-402, "Yuki")
		local week = { Id = "TESTHOF", Title = "TEST WEEK", Challenges = { {}, {}, {} } }
		-- Xavi: best score on 1 and 2; Yuki: fastest on 1, best on 3, fastest on 2 and 3.
		BoardService.submit(x, week.Id, 1, 3000, 40000)
		BoardService.submit(y, week.Id, 1, 2000, 30000)
		BoardService.submit(x, week.Id, 2, 3000, 45000)
		BoardService.submit(y, week.Id, 2, 2500, 35000)
		BoardService.submit(x, week.Id, 3, 1000, 50000)
		BoardService.submit(y, week.Id, 3, 1500, 40000)
		BoardService.finalizeWeek(week)
		local hall = BoardService.hallOfFame({ week }, 5)
		t.eq(#hall, 1)
		local entry = hall[1]
		t.eq(entry.Winners[1].Score.Name, "Xavi")
		t.eq(entry.Winners[1].Time.Name, "Yuki")
		t.eq(entry.Winners[2].Score.Name, "Xavi")
		t.eq(entry.Winners[3].Score.Name, "Yuki")
		t.eq(entry.Champion.Name, "Yuki", "Yuki won 4 of the 6 boards")
		t.eq(entry.Champion.Wins, 4)
	end)

	t.test("a week nobody played is not inducted", function()
		local week = { Id = "TESTEMPTY", Title = "EMPTY", Challenges = { {}, {} } }
		BoardService.finalizeWeek(week)
		t.eq(#BoardService.hallOfFame({ week }, 5), 0)
	end)
end
