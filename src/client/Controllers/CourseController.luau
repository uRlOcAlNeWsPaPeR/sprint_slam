--!strict
-- Client side of the Sprint Slam course: pads, rings and moving obstacles (via
-- Interactables), level hazards (via Hazards), the kill plane, progress and the launch lip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Signal = require(Shared.Signal)

local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local Hazards = require(script.Parent.Hazards)
local Interactables = require(script.Parent.Interactables)
local MovementController = require(script.Parent.MovementController)
local Sfx = require(script.Parent.Sfx)

local CourseController = {}

CourseController.Combo = Signal.new()
CourseController.Launched = Signal.new()
CourseController.FellOut = Signal.new()
CourseController.Zapped = Signal.new() -- touched a death block or live laser

local course: any = nil
local path: Geometry.PathInfo? = nil
local interactables: Interactables.Interactables? = nil
local hazards: Hazards.Hazards? = nil
local built: { [string]: { interactables: Interactables.Interactables, hazards: Hazards.Hazards, path: Geometry.PathInfo } } = {}
local previousPosition: Vector3? = nil
local progressDistance = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Points the controller at one challenge's course (built under workspace.Courses).
function CourseController.setCourse(newCourse: any)
	course = newCourse
	local entry = built[newCourse.Id]
	if not entry then
		local root = workspace:WaitForChild("Courses"):WaitForChild(newCourse.Id)
		entry = {
			interactables = Interactables.new(newCourse, root, function(eventType)
				CourseController.Combo:Fire(eventType)
			end),
			hazards = Hazards.new(newCourse, root),
			path = Geometry.buildPath(newCourse.Path),
		}
		built[newCourse.Id] = entry
	end
	interactables = entry.interactables
	hazards = entry.hazards
	path = entry.path
	previousPosition = nil
	progressDistance = 0
end

function CourseController.getHazards(): Hazards.Hazards?
	return hazards
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
	local t = now()
	if interactables then
		interactables:animate(t)
	end
	if hazards then
		hazards:animate(t)
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

	local t = now()
	if hazards then
		local contact, push, def = hazards:check(position, t)
		if contact == "Kill" then
			previousPosition = nil
			CourseController.Zapped:Fire(def, position, t)
			return
		elseif contact == "Bonk" and push then
			MovementController.bonk(push)
			Sfx.play("Bonk", 0.7, 1.4)
			CameraController.shake(0.5)
			EffectsController.burst(Config.Palette.Orange, 18)
		end
	end
	if interactables then
		interactables:update(root, previous, t)
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
