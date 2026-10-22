--!strict
-- THE HUB: the lobby every player spawns into. Pure data, like a course: the server builds
-- it, and the client reads it for portals, parkour challenges, pads and obstacles.
--
--                     [COMING SOON]  [SPRINT SLAM]  [COMING SOON]        (portals, north)
--   SKY TOWER  ◀── bridge ──  ( PLAZA · spawn )  ── bridge ──▶  DASH GAPS
--   (spiral climb)                    │                          (boost + dash gaps)
--                                  BEAM RUN (beams, sweepers, jump pad), south

local ORIGIN = Vector3.new(0, 0, 420)
local THICKNESS = 2

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local spawnPosition = at(0, 3.5, 14)

local lobby = {
	Id = "Hub",
	DisplayName = "THE HUB",
	Origin = ORIGIN,
	Spawn = CFrame.lookAt(spawnPosition, spawnPosition + Vector3.new(0, 0, -1)),
	KillY = -40,
	Plaza = { Center = ORIGIN, Radius = 64 },
	Islands = {},
	Columns = {},
	Platforms = {},
	Walls = {},
	BoostPads = {},
	JumpPads = {},
	BoostRings = {},
	MovingObstacles = {},
	Arches = {},
	Signs = {},
	Portals = {},
	Challenges = {},
	Halo = { Center = at(0, 46, 0), Radius = 22 },
}

local function floor(name: string, x0: number, x1: number, z0: number, z1: number, topY: number, opts: any?)
	local options = opts or {}
	table.insert(lobby.Platforms, {
		Name = name,
		CFrame = CFrame.new(at((x0 + x1) / 2, topY - THICKNESS / 2, (z0 + z1) / 2)),
		Size = Vector3.new(math.abs(x1 - x0), THICKNESS, math.abs(z1 - z0)),
		Style = options.Style or "Floor",
		EdgeAxis = options.EdgeAxis or "Z",
	})
end

local function boostPad(position: Vector3, forward: Vector3, size: Vector3?)
	table.insert(lobby.BoostPads, { Position = position, Forward = forward, Size = size or Vector3.new(8, 0.4, 10) })
end

local function movingBlock(position: Vector3, axis: Vector3, amplitude: number, period: number, phase: number)
	table.insert(lobby.MovingObstacles, {
		CFrame = CFrame.new(position),
		Size = Vector3.new(3, 5, 3),
		Axis = axis,
		Amplitude = amplitude,
		Period = period,
		Phase = phase,
	})
end

local function facing(position: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(toward.X, position.Y, toward.Z))
end

local function sign(text: string, position: Vector3, toward: Vector3, size: Vector2, accent: string?, body: boolean?)
	table.insert(lobby.Signs, {
		Text = text,
		CFrame = facing(position, toward),
		Size = size,
		Accent = accent or "Cyan",
		Body = body,
		Backing = body,
	})
end

-- Portals stand on the plaza's north edge and face the spawn. Walking into an active one
-- asks the server to start that mode.
local function portal(mode: string?, title: string, subtitle: string, base: Vector3, accent: string)
	local radius = 12
	local center = base + Vector3.new(0, radius + 1.5, 0)
	local frame = facing(center, spawnPosition)
	table.insert(lobby.Portals, {
		Mode = mode,
		Active = mode ~= nil,
		Title = title,
		Subtitle = subtitle,
		Base = base,
		Radius = radius,
		Frame = frame,
		Accent = accent,
		Trigger = { CFrame = frame, Size = Vector3.new(radius * 2 - 2, radius * 2 - 1, 8) },
	})
end

-- Challenges time from leaving the start box to reaching the finish box. Falling below
-- FailY sends you back to Respawn. BotRoute is the Studio QA bot's line through it, which
-- doubles as proof the challenge can be completed (Jump/Dash on arrival, MaxSpeed caps).
local function challenge(def: any)
	table.insert(lobby.Challenges, def)
end

-- Plaza -----------------------------------------------------------------------------------
table.insert(lobby.Islands, { Name = "Plaza", Top = ORIGIN, Radius = 64, Thickness = 4, Rings = { 24, 44 } })
portal("SprintSlam", "SPRINT SLAM", "RUN.  BOOST.  SLAM.", at(0, 0, -48), "Orange")
portal(nil, "COMING SOON", "NEW MODE", at(-36, 0, -40), "Muted")
portal(nil, "COMING SOON", "NEW MODE", at(36, 0, -40), "Muted")
for _, angle in { 45, 135, 225, 315 } do
	local a = math.rad(angle)
	table.insert(lobby.Columns, { Base = at(math.cos(a) * 58, 0, math.sin(a) * 58), Radius = 1.6, Height = 30, Accent = "Cyan" })
end
sign(
	"HOW TO PLAY\n\nWASD  run     SPACE  jump\nSHIFT  dash     CTRL  slide\n\nWalk into the portal to play\nR  restart a challenge\nL  back to the hub",
	at(-40, 9, 8),
	spawnPosition,
	Vector2.new(20, 14),
	"Cyan",
	true
)

-- SKY TOWER (west): spiral climb around a central column, out over the void ----------------
do
	local center = at(-110, 0, 0)
	floor("TowerBridge", -98, -60, -5, 5, 0, { EdgeAxis = "X" })
	table.insert(lobby.Islands, { Name = "TowerIsland", Top = center, Radius = 16, Thickness = 4 })
	table.insert(lobby.Columns, { Base = center, Radius = 4.5, Height = 64, Accent = "Cyan", Solid = true })
	local radius = 26
	local stepCenters = {}
	for step = 0, 14 do
		local angle = math.rad(30 + 28 * step)
		local spot = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		stepCenters[step] = spot
		local half = if step == 14 then 7 else 3.5
		local local3 = spot - ORIGIN
		floor(
			if step == 14 then "TowerTop" else "TowerStep" .. step,
			local3.X - half,
			local3.X + half,
			local3.Z - half,
			local3.Z + half,
			3 + 4 * step,
			{ Style = if step == 14 then "FloorAlt" else "Floor" }
		)
	end
	local topAngle = math.rad(30 + 28 * 14)
	local top = center + Vector3.new(math.cos(topAngle) * radius, 59, math.sin(topAngle) * radius)
	local firstAngle = math.rad(30)
	local first = center + Vector3.new(math.cos(firstAngle) * radius, 0, math.sin(firstAngle) * radius)
	local respawn = center + Vector3.new(6, 3.5, 4)
	-- Bot line: take off 2.5 studs past each step's center toward the next one, at walking
	-- pace. Rise 4, gap ~5.6 studs: a jump stays above +4 for ~0.38 s, which covers 2-11 studs
	-- at 22-24 st/s, so every landing falls inside the 7-stud step.
	local route = { { Position = at(-62, 0, 0), MaxSpeed = 30 } }
	local toFirst = (first - center).Unit
	table.insert(route, { Position = center + toFirst * 13.5, Jump = true, Radius = 1.5, MaxSpeed = 26 })
	for step = 0, 13 do
		local here, nextCenter = stepCenters[step], stepCenters[step + 1]
		local direction = Vector3.new(nextCenter.X - here.X, 0, nextCenter.Z - here.Z).Unit
		table.insert(route, { Position = here + direction * 2.5, Jump = true, Radius = 1.2, MaxSpeed = 24 })
	end
	table.insert(route, { Position = stepCenters[14], MaxSpeed = 20 })
	challenge({
		Name = "SKY TOWER",
		Start = { CFrame = CFrame.new(center + Vector3.new(0, 4, 0)), Size = Vector3.new(34, 10, 34) },
		Finish = { CFrame = CFrame.new(top + Vector3.new(0, 4, 0)), Size = Vector3.new(14, 8, 14) },
		Respawn = facing(respawn, first),
		FailY = -20,
		BotRoute = route,
	})
	table.insert(lobby.Arches, { CFrame = CFrame.new(at(-70, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0), Width = 14, Height = 14, Accent = "Cyan" })
	sign("SKY TOWER", at(-70, 17, 0), ORIGIN, Vector2.new(18, 4), "Cyan")
	sign("DROP OFF TO RETURN", top + Vector3.new(0, 6, 0), center, Vector2.new(14, 2.5), "Orange")
end

-- DASH GAPS (east): three long landing decks sized for the speed the pads give you. Each
-- jump is longer than the last; the final one climbs 4 studs over 42 and needs the pad, the
-- ring and an air dash.
do
	local east = Vector3.new(1, 0, 0)
	floor("GapsBridge", 60, 80, -5, 5, 0, { EdgeAxis = "X" })
	-- The start deck is long so a respawned player has a full run-up to the first gap.
	floor("GapsStart", 80, 130, -6, 6, 0, { EdgeAxis = "X", Style = "FloorAlt" })
	boostPad(at(120, 0, 0), east)
	floor("Gap1", 156, 188, -6, 6, 0, { EdgeAxis = "X" })
	boostPad(at(178, 0, 0), east)
	floor("Gap2", 218, 248, -6, 6, 0, { EdgeAxis = "X" })
	boostPad(at(240, 0, 0), east)
	table.insert(lobby.BoostRings, { Position = at(269, 9, 0), Normal = -east, Radius = 5 })
	floor("GapsFinish", 290, 320, -8, 8, 4, { EdgeAxis = "X", Style = "FloorAlt" })
	table.insert(lobby.Walls, { Name = "GapsBackstop", CFrame = CFrame.new(at(320.5, 9, 0)), Size = Vector3.new(1, 10, 16) })
	challenge({
		Name = "DASH GAPS",
		Start = { CFrame = CFrame.new(at(91, 4, 0)), Size = Vector3.new(22, 10, 12) }, -- back of the deck
		Finish = { CFrame = CFrame.new(at(305, 8, 0)), Size = Vector3.new(30, 8, 16) },
		Respawn = CFrame.lookAt(at(84, 3.5, 0), at(200, 3.5, 0)),
		FailY = -20,
		-- Take off at each deck's far edge; air-dash over the last gap.
		BotRoute = {
			{ Position = at(62, 0, 0) },
			{ Position = at(84, 0, 0) },
			{ Position = at(127, 0, 0), Jump = true, Radius = 1.5 },
			{ Position = at(185, 0, 0), Jump = true, Radius = 1.5 },
			{ Position = at(245, 0, 0), Jump = true, Dash = true, Radius = 1.5 },
			{ Position = at(305, 0, 0), Radius = 4 },
		},
	})
	table.insert(lobby.Arches, { CFrame = CFrame.new(at(70, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0), Width = 14, Height = 14, Accent = "Orange" })
	sign("DASH GAPS", at(70, 17, 0), ORIGIN, Vector2.new(18, 4), "Orange")
end

-- BEAM RUN (south): narrow beams under sweeping blocks, then a jump pad to the finish -----
do
	local south = Vector3.new(0, 0, 1)
	floor("BeamStart", -6, 6, 60, 76, 0, { Style = "FloorAlt" })
	floor("Beam1", -2, 2, 76, 136, 0, { Style = "Beam" })
	movingBlock(at(0, 2.5, 96), Vector3.xAxis, 5, 1.8, 0)
	movingBlock(at(0, 2.5, 118), Vector3.xAxis, 5, 2.2, 0.4)
	floor("BeamRest", -6, 6, 136, 148, 0)
	floor("Beam2", -2, 2, 148, 208, 0, { Style = "Beam" })
	movingBlock(at(0, 2.5, 166), Vector3.xAxis, 5, 1.6, 0.2)
	movingBlock(at(0, 2.5, 188), Vector3.xAxis, 5, 2.0, 0.7)
	floor("BeamPad", -7, 7, 208, 222, 0)
	table.insert(lobby.JumpPads, {
		Position = at(0, 0, 216),
		Size = Vector3.new(8, 0.4, 8),
		UpVelocity = 105,
		MinForwardSpeed = 40,
		Forward = south,
	})
	floor("BeamFinish", -10, 10, 230, 262, 18, { Style = "FloorAlt" })
	table.insert(lobby.Walls, { Name = "BeamBackstop", CFrame = CFrame.new(at(0, 23, 262.5)), Size = Vector3.new(20, 10, 1) })
	challenge({
		Name = "BEAM RUN",
		Start = { CFrame = CFrame.new(at(0, 4, 71)), Size = Vector3.new(12, 10, 10) },
		Finish = { CFrame = CFrame.new(at(0, 22, 246)), Size = Vector3.new(20, 8, 32) },
		Respawn = CFrame.lookAt(at(0, 3.5, 70), at(0, 3.5, 200)),
		FailY = -20,
		-- Straight down the beams; the bot waits for each sweeper to clear before passing it.
		BotRoute = {
			{ Position = at(0, 0, 58) },
			{ Position = at(0, 0, 136) },
			{ Position = at(0, 0, 148) },
			{ Position = at(0, 0, 208) },
			{ Position = at(0, 0, 216), Radius = 2 },
			{ Position = at(0, 0, 246) },
		},
	})
	table.insert(lobby.Arches, { CFrame = CFrame.new(at(0, 0, 70)), Width = 16, Height = 14, Accent = "Cyan" })
	sign("BEAM RUN", at(0, 17, 70), ORIGIN, Vector2.new(18, 4), "Cyan")
end

return lobby
