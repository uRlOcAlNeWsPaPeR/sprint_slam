--!strict
-- NEON RUSH — Phase 1 course. Pure data: the server builds parts from it, and both sides
-- read it for gameplay (pads, rings, gates, launch, target). Forward is -Z.
--
--  start ─ runway (3 boost pads) ─ gap ─ split: moving blocks │ jump pad → shortcut beam + ring
--  ─ downhill speed ramp ─ S-bend (moving blocks) ─ pillar gauntlet ─ gap + timing ring
--  ─ slam runway ─ launch ramp ─▶ TARGET
--
-- Levels reuse this layout. Each of the first five adds a hazard type on top of the last:
--   1 NEON RUSH · 2 DANGER ZONE (death blocks) · 3 LASER GRID (laser gates)
--   4 SPIN CYCLE (spinners) · 5 BLINK OUT (blink floors replace the S-bend floor)

local FORWARD = Vector3.new(0, 0, -1)
local THICKNESS = 2
local SLAM_Z = -1160 -- where the slam runway begins
local LIP_Z = SLAM_Z - 183
local TARGET_Z = LIP_Z - 160

local course = {
	Id = "NeonRush",
	DisplayName = "NEON RUSH",
	KillY = -70,
	Spawn = CFrame.lookAt(Vector3.new(0, 3.5, -12), Vector3.new(0, 3.5, -100)),
	Platforms = {},
	Ramps = {},
	Walls = {},
	BoostPads = {},
	JumpPads = {},
	BoostRings = {},
	MovingObstacles = {},
	Pillars = {},
	Hazards = {}, -- level hazards; see HazardMath
	Levels = {
		{ Name = "NEON RUSH", Intro = "Boost, dash, slide - then slam the target." },
		{ Name = "DANGER ZONE", New = "DEATH BLOCKS", Intro = "Red blocks are lethal: touch one and you respawn at the last checkpoint." },
		{ Name = "LASER GRID", New = "LASER GATES", Intro = "Lasers blink on and off. Cross while they're dark - or jump them." },
		{ Name = "SPIN CYCLE", New = "SPINNERS", Intro = "Spinning bars sweep the floor. Jump them or get knocked away." },
		{ Name = "BLINK OUT", New = "BLINK FLOORS", Intro = "The S-bend floor flashes in a wave. Wait for it, then ride it at about 50." },
	},
	Arches = {},
	Signs = {},
	Checkpoints = {},
	ShortcutGates = {},
	Path = {
		Vector3.new(0, 0, -12),
		Vector3.new(0, 0, -250),
		Vector3.new(0, 0, -470),
		Vector3.new(0, -36, -620),
		Vector3.new(0, -36, -730),
		Vector3.new(128, -36, -730),
		Vector3.new(128, -36, SLAM_Z - 140),
		Vector3.new(128, -16, LIP_Z),
	},
	-- Studio QA autopilot line (DevAutopilot): gap jump, jump-pad shortcut, slide the downhill.
	-- Jump = jump on arrival; Slide = slide while heading there; Radius = arrival radius.
	BotRoute = {
		{ Position = Vector3.new(10, 0, -90) }, -- lanes clear of the level 2 death blocks
		{ Position = Vector3.new(0, 0, -140) },
		{ Position = Vector3.new(12, 0, -198) },
		{ Position = Vector3.new(6, 0, -244), Jump = true, Radius = 3 },
		{ Position = Vector3.new(6, 0, -272) },
		{ Position = Vector3.new(11, 0, -284), Radius = 4 },
		{ Position = Vector3.new(11, 20, -330) },
		{ Position = Vector3.new(11, 20, -450) },
		{ Position = Vector3.new(8, -18, -545), Slide = true },
		{ Position = Vector3.new(-8, -28.8, -590), Slide = true },
		{ Position = Vector3.new(0, -36, -612), Slide = true },
		{ Position = Vector3.new(6, -36, -700) },
		{ Position = Vector3.new(6, -36, -722), Radius = 10, WaitForBlinkWave = true },
		{ Position = Vector3.new(118, -36, -730), Radius = 10, MaxSpeed = 52 },
		{ Position = Vector3.new(128, -36, -760) },
		{ Position = Vector3.new(123.5, -36, -905) },
		{ Position = Vector3.new(123.5, -36, -1019) },
		{ Position = Vector3.new(128, -36, -1036), Jump = true, Radius = 3 },
		{ Position = Vector3.new(128, -36, -1075) },
		{ Position = Vector3.new(118, -36, -1200) }, -- left of the slam-runway death block
		{ Position = Vector3.new(118, -36, -1245) },
		{ Position = Vector3.new(128, -36, SLAM_Z - 140) },
		{ Position = Vector3.new(128, -16, LIP_Z - 20) },
	},
	SlamModeDistance = 0, -- filled below: path distance where SLAM MODE begins
	Launch = {
		Position = Vector3.new(128, -16, LIP_Z), -- top-center of the ramp lip
		Forward = FORWARD,
		HalfWidth = 16,
		HeightRange = 14,
	},
	Target = {
		Center = Vector3.new(128, 13, TARGET_Z), -- front face center
		Normal = Vector3.new(0, 0, 1), -- faces the runner
		WallSize = Vector2.new(240, 240),
		WallCenterY = 20,
	},
	PitFloorY = -100,
}

local function floor(name: string, x0: number, x1: number, z0: number, z1: number, topY: number, opts: any?)
	local options = opts or {}
	table.insert(course.Platforms, {
		Name = name,
		CFrame = CFrame.new((x0 + x1) / 2, topY - THICKNESS / 2, (z0 + z1) / 2),
		Size = Vector3.new(math.abs(x1 - x0), THICKNESS, math.abs(z1 - z0)),
		Style = options.Style or "Floor",
		EdgeAxis = options.EdgeAxis or "Z",
		UntilLevel = options.UntilLevel,
	})
end

local function wall(name: string, x: number, z0: number, z1: number, baseY: number, height: number)
	table.insert(course.Walls, {
		Name = name,
		CFrame = CFrame.new(x, baseY + height / 2, (z0 + z1) / 2),
		Size = Vector3.new(1, height, math.abs(z1 - z0)),
	})
end

local function ramp(name: string, from: Vector3, to: Vector3, width: number, walls: boolean)
	table.insert(course.Ramps, { Name = name, From = from, To = to, Width = width, Thickness = THICKNESS, Walls = walls })
end

local function boostPad(position: Vector3, size: Vector3?)
	table.insert(course.BoostPads, { Position = position, Forward = FORWARD, Size = size or Vector3.new(10, 0.4, 14) })
end

local function arch(position: Vector3, width: number, height: number, accent: string?)
	table.insert(course.Arches, { Position = position, Width = width, Height = height, Accent = accent or "Cyan" })
end

local function movingBlock(position: Vector3, size: Vector3, axis: Vector3, amplitude: number, period: number, phase: number, untilLevel: number?)
	table.insert(course.MovingObstacles, {
		CFrame = CFrame.new(position),
		Size = size,
		Axis = axis,
		Amplitude = amplitude,
		Period = period,
		Phase = phase,
		UntilLevel = untilLevel,
	})
end

local function deathBlock(center: Vector3, size: Vector3)
	table.insert(course.Hazards, { Type = "Kill", Level = 2, CFrame = CFrame.new(center), Size = size })
end

-- Full-width laser bar from 1 to 5 studs above `floorCenter`.
local function laser(floorCenter: Vector3, width: number, period: number, phase: number)
	table.insert(course.Hazards, {
		Type = "Laser",
		Level = 3,
		CFrame = CFrame.new(floorCenter + Vector3.new(0, 3, 0)),
		Size = Vector3.new(width, 4, 0.6),
		Period = period,
		OnFraction = 0.5,
		Phase = phase,
	})
end

local function spinner(floorCenter: Vector3, length: number, speed: number)
	table.insert(course.Hazards, {
		Type = "Spinner",
		Level = 4,
		Center = floorCenter,
		Length = length,
		Thickness = 1.2,
		Height = 1.5,
		Speed = speed,
		Phase = 0,
	})
end

local function pillar(x: number, z: number, baseY: number)
	local size = Vector3.new(4, 10, 4)
	table.insert(course.Pillars, { CFrame = CFrame.new(x, baseY + size.Y / 2, z), Size = size })
end

local function checkpoint(name: string, center: Vector3, size: Vector3, respawn: Vector3)
	table.insert(course.Checkpoints, {
		Name = name,
		CFrame = CFrame.new(center),
		Size = size,
		Respawn = CFrame.lookAt(respawn, respawn + FORWARD),
	})
end

-- 1. Start pad + runway ---------------------------------------------------------------
floor("StartPad", -22, 22, 0, -60, 0, { Style = "FloorAlt" })
floor("Runway", -18, 18, -60, -250, 0)
wall("RunwayWallL", -18.5, -60, -250, 0, 3)
wall("RunwayWallR", 18.5, -60, -250, 0, 3)
boostPad(Vector3.new(-9, 0, -115))
boostPad(Vector3.new(9, 0, -170))
boostPad(Vector3.new(0, 0, -225))
for z = -80, -240, -40 do
	arch(Vector3.new(0, 0, z), 40, 18)
end
table.insert(course.Signs, {
	Text = "RUN.  BOOST.  SLAM.",
	CFrame = CFrame.new(0, 24, -40) * CFrame.Angles(0, math.pi, 0),
	Size = Vector2.new(44, 7),
	Accent = "Cyan",
})

-- 2. Jump gap (z -250 → -266) -----------------------------------------------------------

-- 3. Split section: moving blocks below, shortcut beam above ---------------------------
floor("SplitDeck", -16, 16, -266, -470, 0)
movingBlock(Vector3.new(0, 3, -320), Vector3.new(8, 6, 4), Vector3.xAxis, 10, 2.6, 0)
movingBlock(Vector3.new(0, 3, -370), Vector3.new(8, 6, 4), Vector3.xAxis, 10, 2.6, 0.5)
movingBlock(Vector3.new(0, 3, -420), Vector3.new(8, 6, 4), Vector3.xAxis, 10, 2.2, 0.25)
table.insert(course.JumpPads, {
	Position = Vector3.new(11, 0, -284),
	Size = Vector3.new(8, 0.4, 8),
	UpVelocity = 105,
	MinForwardSpeed = 45,
	Forward = FORWARD,
})
floor("ShortcutBeam", 8, 14, -310, -445, 20, { Style = "Beam" })
boostPad(Vector3.new(11, 20, -365), Vector3.new(5, 0.4, 12))
table.insert(course.BoostRings, {
	Position = Vector3.new(11, 25, -455),
	Normal = -FORWARD,
	Radius = 7,
})
table.insert(course.ShortcutGates, {
	Name = "SkyBeam",
	CFrame = CFrame.new(11, 25, -400),
	Size = Vector3.new(12, 10, 6),
})
arch(Vector3.new(0, 0, -300), 36, 28)
arch(Vector3.new(0, 0, -440), 36, 28)

-- 4. Downhill speed ramp (y 0 → -36) ------------------------------------------------------
ramp("Downhill", Vector3.new(0, 0, -470), Vector3.new(0, -36, -620), 32, true)
for _, z in { -500, -530, -560, -590 } do
	local y = -36 * ((-470 - z) / 150)
	arch(Vector3.new(0, y, z), 36, 16)
end

-- 5. Flat + S-bend -------------------------------------------------------------------------
floor("BendEntry", -16, 16, -620, -742, -36)
boostPad(Vector3.new(0, -36, -665))
floor("BendLateral", 16, 116, -718, -742, -36, { EdgeAxis = "X", UntilLevel = 4 })
floor("BendCorner", 116, 140, -718, -742, -36, { EdgeAxis = "X" })
movingBlock(Vector3.new(52, -33, -730), Vector3.new(4, 6, 8), Vector3.zAxis, 7, 2.2, 0, 4)
movingBlock(Vector3.new(92, -33, -730), Vector3.new(4, 6, 8), Vector3.zAxis, 7, 2.2, 0.5, 4)
-- Level 5: the lateral floor becomes five blink segments lit in a wave travelling +X at
-- 50 st/s. Segment k is solid for 1.5 s starting 0.4·k s into each 2.5 s cycle, so a
-- runner who leaves the corner as segment 1 lights and holds ~40-70 st/s stays on solid floor.
for k = 0, 4 do
	local x0 = 16 + 20 * k
	table.insert(course.Hazards, {
		Type = "Blink",
		Level = 5,
		CFrame = CFrame.new((x0 + x0 + 20) / 2, -37, -730),
		Size = Vector3.new(20, THICKNESS, 24),
		Period = 2.5,
		OnFraction = 0.6,
		Phase = -0.4 * k / 2.5,
	})
end
floor("BendExit", 116, 140, -742, -900, -36)

-- 6. Pillar gauntlet: weave, or thread the 3-stud straight line at x ≈ 123.5 -------------
floor("Gauntlet", 104, 152, -900, -1040, -36)
for _, x in { 110, 128, 146 } do
	pillar(x, -935, -36)
	pillar(x, -1015, -36)
end
for _, x in { 119, 137 } do
	pillar(x, -975, -36)
end
arch(Vector3.new(128, -36, -920), 52, 20)
arch(Vector3.new(128, -36, -1000), 52, 20)

-- 7. Gap with a timing ring: jump late enough to pass through it at the apex ---------------
table.insert(course.BoostRings, {
	Position = Vector3.new(128, -26, -1049),
	Normal = -FORWARD,
	Radius = 3.5,
})
floor("GauntletExit", 108, 148, -1058, SLAM_Z, -36)
boostPad(Vector3.new(128, -36, -1080))

-- 8. Slam runway + launch ramp ---------------------------------------------------------------
floor("SlamRunway", 108, 148, SLAM_Z, SLAM_Z - 140, -36, { Style = "FloorAlt" })
wall("SlamWallL", 107.5, SLAM_Z, SLAM_Z - 140, -36, 3)
wall("SlamWallR", 148.5, SLAM_Z, SLAM_Z - 140, -36, 3)
boostPad(Vector3.new(128, -36, SLAM_Z - 35))
boostPad(Vector3.new(118, -36, SLAM_Z - 80))
boostPad(Vector3.new(138, -36, SLAM_Z - 80))
boostPad(Vector3.new(128, -36, SLAM_Z - 122))
for _, dz in { -20, -60, -100 } do
	arch(Vector3.new(128, -36, SLAM_Z + dz), 44, 20, "Orange")
end
ramp("LaunchRamp", Vector3.new(128, -36, SLAM_Z - 140), Vector3.new(128, -16, LIP_Z), 26, true)
table.insert(course.Signs, {
	Text = "SLAM ZONE",
	CFrame = CFrame.new(128, -8, SLAM_Z - 2) * CFrame.Angles(0, math.pi, 0),
	Size = Vector2.new(40, 8),
	Accent = "Orange",
})
table.insert(course.Signs, {
	Text = "SPRINT SLAM",
	CFrame = CFrame.new(128, 64, TARGET_Z + 0.5) * CFrame.Angles(0, math.pi, 0),
	Size = Vector2.new(120, 18),
	Accent = "Orange",
})

-- Level hazards ---------------------------------------------------------------------------------
-- Level 2 death blocks: each leaves at least a 12-stud lane open.
deathBlock(Vector3.new(0, 2.5, -90), Vector3.new(10, 5, 4))
deathBlock(Vector3.new(-12, 2.5, -140), Vector3.new(12, 5, 4))
deathBlock(Vector3.new(12, 2.5, -140), Vector3.new(12, 5, 4))
deathBlock(Vector3.new(0, 2.5, -198), Vector3.new(14, 5, 4))
deathBlock(Vector3.new(-9, -16, -545), Vector3.new(14, 6, 4)) -- downhill slalom
deathBlock(Vector3.new(9, -26.8, -590), Vector3.new(14, 6, 4))
deathBlock(Vector3.new(-8, -33.5, -700), Vector3.new(12, 5, 4))
deathBlock(Vector3.new(128, -33.5, -1215), Vector3.new(10, 5, 4)) -- splits the slam runway
-- Level 3 laser gates: on half of each cycle, staggered so they don't line up.
laser(Vector3.new(0, 0, -165), 36, 2.0, 0)
laser(Vector3.new(0, 0, -345), 32, 2.2, 0.3)
laser(Vector3.new(0, -36, -682), 32, 1.8, 0.6) -- well past the downhill respawn at -650
laser(Vector3.new(128, -36, -1100), 40, 2.0, 0.5)
-- Level 4 spinners: low bars (feet-high) you can jump.
spinner(Vector3.new(0, 0, -448), 28, 2.2)
spinner(Vector3.new(128, -36, -820), 22, -2.6)
spinner(Vector3.new(128, -36, -1130), 34, 2.0)

-- Checkpoints (index 1 is the start) ------------------------------------------------------------
checkpoint("Start", Vector3.new(0, 5, -12), Vector3.new(44, 20, 20), Vector3.new(0, 3.5, -12))
checkpoint("Split", Vector3.new(0, 15, -280), Vector3.new(64, 50, 8), Vector3.new(0, 3.5, -292))
checkpoint("Downhill", Vector3.new(0, -16, -640), Vector3.new(40, 50, 8), Vector3.new(0, -32.5, -650))
checkpoint("Bend", Vector3.new(128, -26, -790), Vector3.new(36, 30, 8), Vector3.new(128, -32.5, -800))
checkpoint("Gauntlet", Vector3.new(128, -26, -1068), Vector3.new(44, 30, 8), Vector3.new(128, -32.5, -1078))

-- SLAM MODE begins on the slam runway (path distance to SLAM_Z on the last straight).
do
	local points = course.Path
	local distance = 0
	for i = 2, 6 do
		distance += (points[i] - points[i - 1]).Magnitude
	end
	course.SlamModeDistance = distance + (-730 - SLAM_Z)
end

return course
