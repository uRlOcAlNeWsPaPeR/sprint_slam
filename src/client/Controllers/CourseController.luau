--!strict
-- Client side of the course: animates moving obstacles from server time (identical on
-- every client), and checks the runner against pads, rings, obstacles, the kill plane and
-- the launch lip using the course data, not Touched events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Signal = require(Shared.Signal)

local CameraController = require(script.Parent.CameraController)
local DashController = require(script.Parent.DashController)
local EffectsController = require(script.Parent.EffectsController)
local MovementController = require(script.Parent.MovementController)
local Sfx = require(script.Parent.Sfx)

local CourseController = {}

CourseController.Combo = Signal.new()
CourseController.Launched = Signal.new() -- (approachSpeed: number)
CourseController.FellOut = Signal.new()

local course: any = nil
local path: Geometry.PathInfo? = nil
local obstacleParts: { [number]: BasePart } = {}
local padCooldowns: { [number]: number } = {}
local jumpPadCooldowns: { [number]: number } = {}
local lastBonk = -math.huge
local previousPosition: Vector3? = nil
local progressDistance = 0

local PAD_MARGIN = Vector3.new(0.5, 3.5, 0.5)

local function now(): number
	return workspace:GetServerTimeNow()
end

function CourseController.init(activeCourse: any)
	course = activeCourse
	path = Geometry.buildPath(course.Path)
	local root = workspace:WaitForChild("Course")
	local obstacles = root:WaitForChild("Obstacles")
	for index = 1, #course.MovingObstacles do
		obstacleParts[index] = obstacles:WaitForChild("Obstacle" .. index) :: BasePart
	end
end

function CourseController.getCourse(): any
	return course
end

function CourseController.resetRun()
	table.clear(padCooldowns)
	table.clear(jumpPadCooldowns)
	previousPosition = nil
	progressDistance = 0
end

local function obstacleCFrame(def: any, t: number): CFrame
	local phase = (t / def.Period + def.Phase) * math.pi * 2
	return def.CFrame + def.Axis * (math.sin(phase) * def.Amplitude)
end

function CourseController.animate()
	local t = now()
	for index, def in course.MovingObstacles do
		local part = obstacleParts[index]
		if part then
			part.CFrame = obstacleCFrame(def, t)
		end
	end
end

local function padBox(position: Vector3, forward: Vector3): CFrame
	return CFrame.lookAt(position + Vector3.yAxis * 2, position + Vector3.yAxis * 2 + forward)
end

local function checkPads(position: Vector3, t: number)
	for index, pad in course.BoostPads do
		if (padCooldowns[index] or 0) <= t then
			local box = padBox(pad.Position, pad.Forward)
			if Geometry.pointInBox(position, box, Vector3.new(pad.Size.X, 4, pad.Size.Z), PAD_MARGIN) then
				padCooldowns[index] = t + Config.Course.BoostPadRetrigger
				MovementController.applyBoost(Config.Course.BoostPadSpeed)
				DashController.notifyBoost()
				EffectsController.boost()
				CameraController.kick(6)
				CameraController.shake(0.15)
				Sfx.play("Boost")
				CourseController.Combo:Fire("BoostPad")
			end
		end
	end

	for index, pad in course.JumpPads do
		if (jumpPadCooldowns[index] or 0) <= t then
			local box = padBox(pad.Position, pad.Forward)
			if Geometry.pointInBox(position, box, Vector3.new(pad.Size.X, 4, pad.Size.Z), PAD_MARGIN) then
				jumpPadCooldowns[index] = t + Config.Course.JumpPadRetrigger
				MovementController.launchUp(pad.UpVelocity, pad.MinForwardSpeed, pad.Forward)
				EffectsController.burst(Config.Palette.Cyan, 24)
				CameraController.shake(0.2)
				Sfx.play("Boost", 0.6, 1.2)
			end
		end
	end
end

local function checkRings(previous: Vector3, position: Vector3)
	for _, ring in course.BoostRings do
		local point = Geometry.planeCrossing(previous, position, ring.Position, ring.Normal)
		if point and (point - ring.Position).Magnitude <= ring.Radius + 1 then
			MovementController.applyBoost(Config.Course.BoostRingSpeed)
			DashController.notifyBoost()
			EffectsController.boost()
			CameraController.kick(10)
			CameraController.shake(0.25)
			Sfx.play("Boost", 0.7, 1.35)
			CourseController.Combo:Fire("BoostRing")
		end
	end
end

local function checkObstacles(root: BasePart, position: Vector3, t: number)
	if t - lastBonk < Config.Movement.BonkCooldown then
		return
	end
	for index, def in course.MovingObstacles do
		local part = obstacleParts[index]
		if part and Geometry.pointInBox(position, part.CFrame, def.Size, Vector3.new(1.4, 2.5, 1.4)) then
			lastBonk = t
			local away = position - part.Position
			-- Knock the runner out along the obstacle's sweep, plus a bit backward.
			local sweep = def.Axis * (if away:Dot(def.Axis) >= 0 then 1 else -1)
			local v = root.AssemblyLinearVelocity
			local travel = Vector3.new(v.X, 0, v.Z)
			local back = if travel.Magnitude > 1 then -travel.Unit * 0.6 else Vector3.zero
			MovementController.bonk(sweep + back)
			CameraController.shake(0.45)
			EffectsController.burst(Config.Palette.White, 16)
			return
		end
	end
end

local function checkLaunch(previous: Vector3, position: Vector3): boolean
	local launch = course.Launch
	local point = Geometry.planeCrossing(previous, position, launch.Position, -launch.Forward)
	if not point then
		return false
	end
	local offset = point - launch.Position
	local lateral = offset - launch.Forward * offset:Dot(launch.Forward)
	lateral = Vector3.new(lateral.X, 0, lateral.Z)
	return lateral.Magnitude <= launch.HalfWidth and math.abs(offset.Y) <= launch.HeightRange
end

-- Per-frame gameplay checks while a run is live.
function CourseController.update(root: BasePart)
	local position = root.Position
	local t = now()
	local previous = previousPosition or position
	previousPosition = position

	if position.Y < course.KillY then
		previousPosition = nil
		CourseController.FellOut:Fire()
		return
	end

	checkPads(position, t)
	checkRings(previous, position)
	checkObstacles(root, position, t)

	if path then
		progressDistance = Geometry.distanceAlongPath(path, position)
	end

	if checkLaunch(previous, position) then
		local v = root.AssemblyLinearVelocity
		CourseController.Launched:Fire(Vector3.new(v.X, 0, v.Z).Magnitude)
	end
end

function CourseController.forgetPosition()
	previousPosition = nil
end

function CourseController.getProgress(): (number, number)
	local length = if path then path.length else 1
	return progressDistance, length
end

return CourseController
