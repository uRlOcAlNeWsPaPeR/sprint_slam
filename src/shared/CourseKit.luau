--!strict
-- Builds a complete challenge course (the same data shape the server builder and client
-- controllers read) from a short list of tested segments, so a week of 10 challenges is
-- 10 recipes rather than 10 hand-placed layouts. The course runs straight along -Z from
-- `Origin`; every feature is placed relative to the last floor segment.
--
--   local kit = CourseKit.new({ Id = "W1C2", Name = "DANGER ZONE", Origin = Vector3.new(400, 0, 0) })
--   kit:start()
--   kit:run(300)
--   kit:deathBlocks(80, { { -11, 10 }, { 11, 10 } })
--   kit:checkpoint(120)
--   ...
--   local course = kit:finish()
--
-- The kit also writes a BotRoute (lane choices, jumps, slides, blink-wave waits) that the
-- Studio QA bot follows, which doubles as proof the course can be completed.

local Config = require(script.Parent.Config)
local Geometry = require(script.Parent.Geometry)

local THICKNESS = 2
local FORWARD = Vector3.new(0, 0, -1)
local RUNWAY_WIDTH = 36
local SLAM_WIDTH = 40
local SLAM_RUNWAY_LENGTH = 140
local RAMP_LENGTH = 43
local RAMP_RISE = 20
local FLIGHT_DISTANCE = 160

local CourseKit = {}
CourseKit.__index = CourseKit

export type Spec = {
	Id: string,
	Name: string,
	Origin: Vector3,
	Index: number?,
	Width: number?,
	Intro: string?,
	New: string?,
	RoundTime: number?,
	Sign: string?,
}

export type Kit = typeof(setmetatable(
	{} :: {
		spec: Spec,
		course: any,
		width: number,
		x: number,
		y: number,
		z: number,
		last: { z0: number, len: number, y0: number, y1: number }?,
		lowest: number,
		path: { Vector3 },
		slamPathIndex: number,
		counters: { [string]: number },
	},
	CourseKit
))

local function interpolate(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function CourseKit.new(spec: Spec): Kit
	local self = setmetatable({
		spec = spec,
		course = nil :: any,
		width = spec.Width or RUNWAY_WIDTH,
		x = spec.Origin.X,
		y = spec.Origin.Y,
		z = spec.Origin.Z,
		last = nil,
		lowest = spec.Origin.Y,
		path = {},
		slamPathIndex = 0,
		counters = {},
	}, CourseKit)
	self.course = {
		Id = spec.Id,
		Index = spec.Index or 1,
		DisplayName = spec.Name,
		Intro = spec.Intro or "",
		New = spec.New,
		RoundTime = spec.RoundTime or 60,
		Origin = spec.Origin,
		Platforms = {},
		Ramps = {},
		Walls = {},
		BoostPads = {},
		JumpPads = {},
		BoostRings = {},
		MovingObstacles = {},
		Pillars = {},
		Hazards = {},
		Arches = {},
		Signs = {},
		Checkpoints = {},
		ShortcutGates = {},
		BotRoute = {},
		Path = {},
	}
	return self
end

local function count(self: Kit, key: string): number
	self.counters[key] = (self.counters[key] or 0) + 1
	return self.counters[key]
end

function CourseKit.yAt(self: Kit, off: number): number
	local last = self.last
	assert(last, "place a floor segment first")
	return interpolate(last.y0, last.y1, math.clamp(off / last.len, 0, 1))
end

-- True while the last segment is a downhill ramp (the bot slides it).
function CourseKit.onRamp(self: Kit): boolean
	local last = self.last
	return last ~= nil and last.y1 ~= last.y0
end

function CourseKit.zAt(self: Kit, off: number): number
	local last = self.last
	assert(last, "place a floor segment first")
	return last.z0 - off
end

local function route(self: Kit, waypoint: any)
	table.insert(self.course.BotRoute, waypoint)
end

local function pathPoint(self: Kit, y: number?, z: number?)
	table.insert(self.path, Vector3.new(self.x, y or self.y, z or self.z))
end

local function floor(self: Kit, name: string, len: number, width: number, style: string?)
	table.insert(self.course.Platforms, {
		Name = name,
		CFrame = CFrame.new(self.x, self.y - THICKNESS / 2, self.z - len / 2),
		Size = Vector3.new(width, THICKNESS, len),
		Style = style or "Floor",
		EdgeAxis = "Z",
	})
end

local function sideWalls(self: Kit, name: string, len: number, width: number)
	for _, side in { -1, 1 } do
		table.insert(self.course.Walls, {
			Name = name .. (if side < 0 then "L" else "R"),
			CFrame = CFrame.new(self.x + side * (width / 2 + 0.5), self.y + 1.5, self.z - len / 2),
			Size = Vector3.new(1, 3, len),
		})
	end
end

-- Start pad: the spawn, the start line and the first checkpoint (always checkpoint 1).
function CourseKit.start(self: Kit): Kit
	local course = self.course
	local z0 = self.z
	floor(self, "StartPad", 60, 44, "FloorAlt")
	local spawnPosition = Vector3.new(self.x, self.y + 3.5, z0 - 12)
	course.Spawn = CFrame.lookAt(spawnPosition, spawnPosition + FORWARD * 88)
	course.StartLine = CFrame.new(self.x, self.y + 0.06, z0 - 20)
	table.insert(course.Checkpoints, {
		Name = "Start",
		CFrame = CFrame.new(self.x, self.y + 5, z0 - 12),
		Size = Vector3.new(44, 20, 20),
		Respawn = course.Spawn,
	})
	if self.spec.Sign then
		table.insert(course.Signs, {
			Text = self.spec.Sign,
			CFrame = CFrame.new(self.x, self.y + 24, z0 - 40) * CFrame.Angles(0, math.pi, 0),
			Size = Vector2.new(44, 7),
			Accent = "Cyan",
		})
	end
	pathPoint(self, self.y, z0 - 12)
	self.last = { z0 = z0, len = 60, y0 = self.y, y1 = self.y }
	self.z -= 60
	pathPoint(self)
	return self
end

-- Flat floor `len` long with glass side walls and an arch every 40 studs.
function CourseKit.run(self: Kit, len: number): Kit
	local z0 = self.z
	local n = count(self, "run")
	floor(self, "Run" .. n, len, self.width)
	sideWalls(self, "RunWall" .. n, len, self.width)
	for off = 40, len - 20, 40 do
		table.insert(self.course.Arches, { Position = Vector3.new(self.x, self.y, z0 - off), Width = self.width + 4, Height = 18, Accent = "Cyan" })
	end
	self.last = { z0 = z0, len = len, y0 = self.y, y1 = self.y }
	self.z -= len
	pathPoint(self)
	return self
end

-- A jump gap: the bot jumps at the near edge. Keep gaps at 18 studs or less.
function CourseKit.gap(self: Kit, len: number): Kit
	assert(self.last, "a gap needs floor before it")
	route(self, { Position = Vector3.new(self.x, self.y, self.z - 1.2), Jump = true, Radius = 1.4 })
	self.course.Gaps = self.course.Gaps or {}
	table.insert(self.course.Gaps, { Z0 = self.z, Length = len, Y = self.y })
	self.z -= len
	route(self, { Position = Vector3.new(self.x, self.y, self.z - 6), Radius = 4 })
	pathPoint(self)
	self.last = nil
	return self
end

-- Downhill ramp (the player slides it for speed). Features can still be placed on it.
function CourseKit.down(self: Kit, len: number, drop: number): Kit
	local z0 = self.z
	local n = count(self, "down")
	local x = self.x
	table.insert(self.course.Ramps, {
		Name = "Downhill" .. n,
		From = Vector3.new(x, self.y, z0),
		To = Vector3.new(x, self.y - drop, z0 - len),
		Width = self.width - 4,
		Thickness = THICKNESS,
		Walls = true,
	})
	for off = 40, len - 10, 40 do
		table.insert(self.course.Arches, { Position = Vector3.new(x, self.y - drop * off / len, z0 - off), Width = self.width, Height = 16, Accent = "Cyan" })
	end
	self.last = { z0 = z0, len = len, y0 = self.y, y1 = self.y - drop }
	self.y -= drop
	self.lowest = math.min(self.lowest, self.y)
	self.z -= len
	route(self, { Position = Vector3.new(x, self.y, self.z + 4), Slide = true, Radius = 5 })
	pathPoint(self)
	return self
end

-- A checkpoint `off` studs into the last floor segment. The respawn point is 10 studs
-- further on, so keep off + 10 inside the segment and clear of hazards.
function CourseKit.checkpoint(self: Kit, off: number): Kit
	local last = self.last :: any
	assert(last and off + 10 <= last.len, "checkpoint needs 10 studs of floor after it")
	local z = self:zAt(off)
	local y = self:yAt(off)
	local respawn = Vector3.new(self.x, self:yAt(off + 10) + 3.5, z - 10)
	table.insert(self.course.Checkpoints, {
		Name = "Checkpoint" .. #self.course.Checkpoints,
		CFrame = CFrame.new(self.x, y + 15, z),
		Size = Vector3.new(self.width + 28, 50, 8),
		Respawn = CFrame.lookAt(respawn, respawn + FORWARD),
	})
	return self
end

function CourseKit.boost(self: Kit, off: number, dx: number?, size: Vector3?): Kit
	table.insert(self.course.BoostPads, {
		Position = Vector3.new(self.x + (dx or 0), self:yAt(off), self:zAt(off)),
		Forward = FORWARD,
		Size = size or Vector3.new(10, 0.4, 14),
	})
	return self
end

-- Death blocks across the floor at `off`; blocks are { centerX, width }. The widest gap
-- between them is the lane the bot uses (the tests demand at least 8 studs).
function CourseKit.deathBlocks(self: Kit, off: number, blocks: { { number } }): Kit
	local y, z = self:yAt(off), self:zAt(off)
	local half = self.width / 2
	local spans = {}
	for _, block in blocks do
		table.insert(self.course.Hazards, {
			Type = "Kill",
			CFrame = CFrame.new(self.x + block[1], y + 2.5, z),
			Size = Vector3.new(block[2], 5, 4),
		})
		table.insert(spans, { block[1] - block[2] / 2, block[1] + block[2] / 2 })
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local bestWidth, bestCenter, cursor = -math.huge, 0, -half
	for _, span in spans do
		if span[1] - cursor > bestWidth then
			bestWidth, bestCenter = span[1] - cursor, (span[1] + cursor) / 2
		end
		cursor = math.max(cursor, span[2])
	end
	if half - cursor > bestWidth then
		bestWidth, bestCenter = half - cursor, (half + cursor) / 2
	end
	self.course.Lanes = self.course.Lanes or {}
	table.insert(self.course.Lanes, { Z = z, Width = bestWidth })
	route(self, { Position = Vector3.new(self.x + bestCenter, y, z), Radius = 3.5, Slide = self:onRamp() })
	return self
end

-- A laser bar spanning the floor; lit for OnFraction of every Period seconds.
function CourseKit.laser(self: Kit, off: number, period: number, phase: number?, onFraction: number?): Kit
	table.insert(self.course.Hazards, {
		Type = "Laser",
		CFrame = CFrame.new(self.x, self:yAt(off) + 3, self:zAt(off)),
		Size = Vector3.new(self.width, 4, 0.6),
		Period = period,
		OnFraction = onFraction or 0.5,
		Phase = phase or 0,
	})
	return self
end

-- A floor-height spinning bar; negative speed spins the other way.
function CourseKit.spinner(self: Kit, off: number, length: number, speed: number): Kit
	table.insert(self.course.Hazards, {
		Type = "Spinner",
		Center = Vector3.new(self.x, self:yAt(off), self:zAt(off)),
		Length = length,
		Thickness = 1.2,
		Height = 1.5,
		Speed = speed * Config.Hazards.SpinnerSpeedScale,
		Phase = 0,
	})
	return self
end

-- A block sweeping side to side across the floor.
function CourseKit.mover(self: Kit, off: number, period: number, phase: number?, amplitude: number?): Kit
	table.insert(self.course.MovingObstacles, {
		CFrame = CFrame.new(self.x, self:yAt(off) + 3, self:zAt(off)),
		Size = Vector3.new(8, 6, 4),
		Axis = Vector3.xAxis,
		Amplitude = amplitude or 11,
		Period = period,
		Phase = phase or 0,
	})
	return self
end

function CourseKit.pillars(self: Kit, off: number, offsets: { number }): Kit
	for _, dx in offsets do
		table.insert(self.course.Pillars, {
			CFrame = CFrame.new(self.x + dx, self:yAt(off) + 5, self:zAt(off)),
			Size = Vector3.new(4, 10, 4),
		})
	end
	return self
end

-- A pillar slalom: `rows` rows of three pillars, `spacing` studs apart. Gaps sit at x = ±6,
-- so the bot weaves between them, switching sides every row.
function CourseKit.weave(self: Kit, off: number, rows: number, spacing: number): Kit
	local side = 1
	for row = 0, rows - 1 do
		local at = off + row * spacing
		self:pillars(at, { -12, 0, 12 })
		route(self, { Position = Vector3.new(self.x + 6 * side, self:yAt(at), self:zAt(at)), Radius = 2.5, Slide = self:onRamp() })
		side = -side
	end
	return self
end

-- A wave of blink floors, `segments` long (20 studs each), lit one after another at 50 st/s.
-- The segments ARE the floor here; place a run before and after it.
function CourseKit.blinkWave(self: Kit, segments: number): Kit
	local segmentLength = 20
	local z0 = self.z
	self.course.BlinkWaves = self.course.BlinkWaves or {}
	table.insert(self.course.BlinkWaves, { Z0 = z0, SegmentLength = segmentLength, Count = segments })
	route(self, { Position = Vector3.new(self.x, self.y, z0 + 4), Radius = 4, WaitForBlinkWave = true })
	for k = 0, segments - 1 do
		table.insert(self.course.Hazards, {
			Type = "Blink",
			Wave = #self.course.BlinkWaves,
			Slot = k,
			CFrame = CFrame.new(self.x, self.y - THICKNESS / 2, z0 - segmentLength * (k + 0.5)),
			Size = Vector3.new(self.width - 8, THICKNESS, segmentLength),
			Period = 2.5,
			OnFraction = 0.6,
			Phase = -0.4 * k / 2.5,
		})
	end
	self.z -= segments * segmentLength
	route(self, { Position = Vector3.new(self.x, self.y, self.z - 6), Radius = 6, MaxSpeed = 52 })
	pathPoint(self)
	self.last = nil
	return self
end

-- The slam runway, launch ramp and target. Always the last call; returns the course data.
function CourseKit.finish(self: Kit): any
	local course = self.course
	local x, y = self.x, self.y
	local z0 = self.z
	self.slamPathIndex = #self.path + 1
	pathPoint(self)

	floor(self, "SlamRunway", SLAM_RUNWAY_LENGTH, SLAM_WIDTH, "FloorAlt")
	sideWalls(self, "SlamWall", SLAM_RUNWAY_LENGTH, SLAM_WIDTH)
	self.last = { z0 = z0, len = SLAM_RUNWAY_LENGTH, y0 = y, y1 = y }
	self:boost(35, 0)
	self:boost(80, -10)
	self:boost(80, 10)
	self:boost(122, 0)
	for _, off in { 20, 60, 100 } do
		table.insert(course.Arches, { Position = Vector3.new(x, y, z0 - off), Width = SLAM_WIDTH + 4, Height = 20, Accent = "Orange" })
	end

	local rampFrom = Vector3.new(x, y, z0 - SLAM_RUNWAY_LENGTH)
	local lipZ = z0 - SLAM_RUNWAY_LENGTH - RAMP_LENGTH
	local lipY = y + RAMP_RISE
	table.insert(course.Ramps, {
		Name = "LaunchRamp",
		From = rampFrom,
		To = Vector3.new(x, lipY, lipZ),
		Width = 26,
		Thickness = THICKNESS,
		Walls = true,
	})
	table.insert(course.Signs, {
		Text = "SLAM ZONE",
		CFrame = CFrame.new(x, y + 28, z0 - 2) * CFrame.Angles(0, math.pi, 0),
		Size = Vector2.new(40, 8),
		Accent = "Orange",
	})

	local targetZ = lipZ - FLIGHT_DISTANCE
	local targetY = lipY + 29
	course.Launch = { Position = Vector3.new(x, lipY, lipZ), Forward = FORWARD, HalfWidth = 16, HeightRange = 14 }
	course.Target = {
		Center = Vector3.new(x, targetY, targetZ),
		Normal = Vector3.new(0, 0, 1),
		WallSize = Vector2.new(240, 240),
		WallCenterY = lipY + 36,
	}
	table.insert(course.Signs, {
		Text = "SPRINT SLAM",
		CFrame = CFrame.new(x, targetY + 51, targetZ + 0.5) * CFrame.Angles(0, math.pi, 0),
		Size = Vector2.new(120, 18),
		Accent = "Orange",
	})
	course.PitFloorY = lipY - 84
	course.KillY = self.lowest - 34

	route(self, { Position = Vector3.new(x, y, z0 - SLAM_RUNWAY_LENGTH), Radius = 8 })
	route(self, { Position = Vector3.new(x, lipY, lipZ - 20), Radius = 8 })

	-- Features add their waypoints as they are placed, so put the whole route in course
	-- order (further down -Z comes later; ties keep insertion order).
	local ordered = {}
	for index, waypoint in course.BotRoute do
		table.insert(ordered, { index = index, waypoint = waypoint })
	end
	table.sort(ordered, function(a, b)
		local za, zb = a.waypoint.Position.Z, b.waypoint.Position.Z
		if za ~= zb then
			return za > zb
		end
		return a.index < b.index
	end)
	course.BotRoute = {}
	for _, entry in ordered do
		table.insert(course.BotRoute, entry.waypoint)
	end

	pathPoint(self, y, z0 - SLAM_RUNWAY_LENGTH)
	pathPoint(self, lipY, lipZ)
	course.Path = self.path
	local pathInfo = Geometry.buildPath(self.path)
	course.SlamModeDistance = pathInfo.cumulative[self.slamPathIndex]
	course.PathLength = pathInfo.length
	course.Length = math.abs(z0 - self.spec.Origin.Z)
	return course
end

return CourseKit
