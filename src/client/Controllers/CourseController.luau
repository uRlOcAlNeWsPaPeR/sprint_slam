--!strict
-- Client side of the Sprint Slam course: pads, rings and moving obstacles (via
-- Interactables), plus the kill plane, course progress and the launch lip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Geometry = require(Shared.Geometry)
local Signal = require(Shared.Signal)

local Interactables = require(script.Parent.Interactables)

local CourseController = {}

CourseController.Combo = Signal.new()
CourseController.Launched = Signal.new()
CourseController.FellOut = Signal.new()

local course: any = nil
local path: Geometry.PathInfo? = nil
local interactables: Interactables.Interactables? = nil
local previousPosition: Vector3? = nil
local progressDistance = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

function CourseController.init(activeCourse: any)
	course = activeCourse
	path = Geometry.buildPath(course.Path)
	interactables = Interactables.new(course, workspace:WaitForChild("Course"), function(eventType)
		CourseController.Combo:Fire(eventType)
	end)
end

function CourseController.getCourse(): any
	return course
end

function CourseController.resetRun()
	if interactables then
		interactables:reset()
	end
	previousPosition = nil
	progressDistance = 0
end

function CourseController.animate()
	if interactables then
		interactables:animate(now())
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
	local previous = previousPosition or position
	previousPosition = position

	if position.Y < course.KillY then
		previousPosition = nil
		CourseController.FellOut:Fire()
		return
	end

	if interactables then
		interactables:update(root, previous, now())
	end

	if path then
		progressDistance = Geometry.distanceAlongPath(path, position)
	end

	if checkLaunch(previous, position) then
		CourseController.Launched:Fire()
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
