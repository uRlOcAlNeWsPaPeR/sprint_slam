--!strict
-- WEEK 1: ten challenges, released Sunday 25 Oct 2026 (00:00 UTC). Every challenge is a
-- CourseKit recipe, a bit longer than the old single course. Players clear them in order the
-- first time, then replay any of them to improve their best score and fastest time.
--
-- Hazard patterns for death blocks, as { centerX, width } lists on a 36-wide floor:
--   CENTER  one block in the middle (lanes left and right)
--   SPLIT   two blocks, a 12-wide lane in the middle
--   LEFT    one wide block on the left (lane on the right)
--   RIGHT   one wide block on the right (lane on the left)

local CENTER = { { 0, 12 } }
local SPLIT = { { -11, 10 }, { 11, 10 } }
local LEFT = { { -9, 18 } }
local RIGHT = { { 9, 18 } }

local ROUND_TIME = 60

local function challenge(def: any)
	def.RoundTime = def.RoundTime or ROUND_TIME
	return def
end

local week = {
	Id = "W1",
	Number = 1,
	Title = "WEEK 1",
	StartsAt = 1792886400, -- Sunday 2026-10-25 00:00 UTC
	Challenges = {},
}

local challenges = week.Challenges

table.insert(
	challenges,
	challenge({
		Name = "NEON RUSH",
		Intro = "Boost, jump, slide - then slam the target.",
		Sign = "RUN.  BOOST.  SLAM.",
		Build = function(kit)
			kit:start()
			kit:run(220):boost(55, -9):boost(110, 9):boost(165, 0):checkpoint(100)
			kit:gap(14)
			kit:run(200):boost(50, 0):checkpoint(110)
			kit:down(150, 36):checkpoint(60)
			kit:run(220):boost(60, 0):checkpoint(110)
			kit:gap(16)
			kit:run(220):boost(80, 0):checkpoint(100)
			kit:gap(16)
			kit:run(200):boost(60, 0)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "DANGER ZONE",
		New = "DEATH BLOCKS",
		Intro = "Red blocks are lethal: touch one and you respawn at the last checkpoint.",
		Build = function(kit)
			kit:start()
			kit:run(260):deathBlocks(70, CENTER):deathBlocks(130, SPLIT):deathBlocks(190, LEFT):checkpoint(100)
			kit:gap(14)
			kit:run(260):deathBlocks(60, RIGHT):deathBlocks(120, SPLIT):deathBlocks(190, LEFT):checkpoint(90)
			kit:down(150, 36):deathBlocks(50, SPLIT):deathBlocks(110, CENTER):checkpoint(80)
			kit:run(240):deathBlocks(60, LEFT):deathBlocks(130, CENTER):checkpoint(95)
			kit:gap(16)
			kit:run(240):deathBlocks(70, SPLIT):deathBlocks(150, RIGHT)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "LASER GRID",
		New = "LASER GATES",
		Intro = "Lasers blink on and off. Cross while they're dark - or jump them.",
		Build = function(kit)
			kit:start()
			kit:run(260):laser(70, 2.0, 0):laser(130, 2.2, 0.3):laser(190, 1.8, 0.6):checkpoint(100)
			kit:gap(14)
			kit:run(260):laser(60, 2.0, 0.5):laser(120, 2.4, 0):laser(180, 2.0, 0.25):checkpoint(90)
			kit:down(150, 36):laser(70, 1.8, 0.6):laser(120, 2.0, 0.1):checkpoint(30)
			kit:run(240):laser(60, 2.2, 0.4):laser(120, 1.8, 0):laser(180, 2.0, 0.7):checkpoint(90)
			kit:gap(16)
			kit:run(240):laser(70, 2.0, 0.2):laser(150, 2.4, 0.6)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "SPIN CYCLE",
		New = "SPINNERS",
		Intro = "Spinning bars sweep the floor. Jump them or get knocked away.",
		Build = function(kit)
			kit:start()
			kit:run(260):spinner(90, 28, 2.2):spinner(190, 28, -2.6):checkpoint(130)
			kit:gap(14)
			kit:run(260):spinner(70, 30, 2.4):spinner(150, 30, -2.4):spinner(220, 30, 2.8):checkpoint(110)
			kit:down(150, 36):spinner(100, 28, -2.2):checkpoint(40)
			kit:run(240):spinner(60, 30, 2.6):spinner(130, 30, -2.8):spinner(200, 30, 3.0):checkpoint(95)
			kit:gap(16)
			kit:run(240):spinner(80, 32, 2.4):spinner(170, 32, -3.0)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "BLINK OUT",
		New = "BLINK FLOORS",
		Intro = "Floors flash in a wave. Wait for it, then ride it at about 50.",
		Build = function(kit)
			kit:start()
			kit:run(200):checkpoint(100)
			kit:blinkWave(5)
			kit:run(160):checkpoint(70)
			kit:gap(14)
			kit:run(200):checkpoint(100)
			kit:blinkWave(6)
			kit:run(160):checkpoint(70)
			kit:down(150, 36):checkpoint(30)
			kit:run(220):checkpoint(100)
			kit:blinkWave(5)
			kit:run(160)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "PILLAR PUNCH",
		New = "PILLAR FIELDS",
		Intro = "Weave between the pillars - hitting one costs you speed.",
		Build = function(kit)
			kit:start()
			kit:run(260):weave(60, 6, 24):checkpoint(30)
			kit:gap(14)
			kit:run(280):weave(50, 7, 24):checkpoint(30)
			kit:down(150, 36):weave(40, 4, 24):checkpoint(15)
			kit:run(260):weave(50, 6, 28):checkpoint(20)
			kit:gap(16)
			kit:run(240):weave(50, 5, 28):checkpoint(190)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "SWEEP SHOT",
		New = "SWEEPERS",
		Intro = "Blocks sweep across the track. Time your run through them.",
		Build = function(kit)
			kit:start()
			kit:run(300):mover(70, 2.6, 0):mover(120, 2.6, 0.5):mover(170, 2.2, 0.25):mover(230, 2.0, 0.75):checkpoint(40)
			kit:gap(14)
			kit:run(300):mover(60, 2.4, 0):mover(110, 2.4, 0.5):mover(170, 2.0, 0.3):mover(240, 2.2, 0.8):checkpoint(30)
			kit:down(150, 36):mover(50, 2.2, 0.2):mover(100, 2.0, 0.6):checkpoint(15)
			kit:run(260):mover(60, 2.0, 0):mover(110, 2.2, 0.5):mover(170, 1.8, 0.25):checkpoint(30)
			kit:gap(16)
			kit:run(240):mover(70, 2.0, 0.1):mover(130, 2.2, 0.6):mover(190, 1.8, 0.35):checkpoint(200)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "DEATH SLALOM",
		New = "DEATH BLOCK SLALOMS",
		Intro = "Dodge left, dodge right - death blocks alternate down the slope.",
		Build = function(kit)
			kit:start()
			kit:run(200):checkpoint(100)
			kit:down(200, 48):checkpoint(20):deathBlocks(70, LEFT):deathBlocks(110, RIGHT):deathBlocks(150, LEFT):deathBlocks(190, RIGHT)
			kit:run(160):checkpoint(60)
			kit:gap(16)
			kit:run(240):deathBlocks(60, RIGHT):deathBlocks(100, LEFT):deathBlocks(140, RIGHT):deathBlocks(180, LEFT):checkpoint(30)
			kit:down(160, 40):checkpoint(20):deathBlocks(60, LEFT):deathBlocks(100, RIGHT):deathBlocks(140, LEFT)
			kit:run(200):deathBlocks(60, SPLIT):deathBlocks(120, CENTER)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "GAUNTLET",
		New = "COMBOS",
		Intro = "Lasers, spinners, blocks and sweepers - all in one run.",
		Build = function(kit)
			kit:start()
			kit:run(280):laser(70, 2.0, 0):spinner(130, 28, 2.4):deathBlocks(190, SPLIT):mover(245, 2.4, 0.3):checkpoint(95)
			kit:gap(14)
			kit:run(280):mover(60, 2.2, 0):laser(110, 2.2, 0.4):spinner(170, 30, -2.6):laser(230, 1.8, 0.2):checkpoint(80)
			kit:down(150, 36):deathBlocks(60, LEFT):deathBlocks(110, RIGHT):checkpoint(15)
			kit:run(280):spinner(60, 30, 2.8):deathBlocks(120, SPLIT):laser(180, 2.0, 0.5):mover(235, 2.0, 0.6):checkpoint(20)
			kit:gap(16)
			kit:run(260):laser(70, 2.0, 0.3):deathBlocks(130, CENTER):spinner(200, 30, -2.8):checkpoint(100)
		end,
	})
)

table.insert(
	challenges,
	challenge({
		Name = "GRAND SLAM",
		New = "EVERYTHING",
		Intro = "The week's final test: every hazard, one long run. Give it everything.",
		RoundTime = 75,
		Build = function(kit)
			kit:start()
			kit:run(240):boost(30, 0):weave(60, 4, 24):checkpoint(20)
			kit:gap(16)
			kit:run(200):laser(60, 2.0, 0):laser(120, 2.2, 0.4):checkpoint(150)
			kit:run(160)
			kit:down(160, 40):checkpoint(15):deathBlocks(50, LEFT):deathBlocks(100, RIGHT)
			kit:run(220):spinner(60, 30, 2.4):spinner(130, 30, -2.6):checkpoint(160)
			kit:blinkWave(5)
			kit:run(180):mover(50, 2.2, 0):mover(100, 2.0, 0.5):checkpoint(20)
			kit:gap(16)
			kit:run(220):deathBlocks(60, SPLIT):laser(130, 2.0, 0.3):deathBlocks(180, CENTER):checkpoint(95)
			kit:down(150, 36):checkpoint(15):spinner(60, 28, 2.2):laser(110, 2.0, 0.5)
			kit:run(220):weave(40, 5, 24):checkpoint(15)
			kit:gap(16)
			kit:run(200):mover(60, 2.0, 0):deathBlocks(120, LEFT):laser(170, 2.2, 0.2)
		end,
	})
)

return week
