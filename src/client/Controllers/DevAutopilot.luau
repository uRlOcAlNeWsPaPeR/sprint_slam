--!strict
-- Studio-only QA bot. It drives the real input path (stick vector, jump, dash, slide,
-- flight steering, Slam Dash) along the course's BotRoute so full runs can be verified
-- end to end, server scoring included. Enable from the Studio client:
--   game.Players.LocalPlayer:SetAttribute("Autopilot", true)       -- run once per restart
--   game.Players.LocalPlayer:SetAttribute("AutopilotLoop", true)   -- restart after results
--   game.Players.LocalPlayer:SetAttribute("AutopilotStyle", "Crawl") -- how it paces the run:
--     Sprint (default) | Crawl (~45 st/s, no dash) | LateBurst (crawl, then sprint the slam
--     runway) | Coast (sprint, then ease off on the slam runway to aim)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CourseController = require(script.Parent.CourseController)
local DashController = require(script.Parent.DashController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local SlamController = require(script.Parent.SlamController)

local DevAutopilot = {}

local course: any = nil
local index = 1
local previousPoint = Vector3.zero
local driving = false

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zero
end

-- World direction → ControlModule-style stick vector relative to the camera.
local function toStick(direction: Vector3): Vector3
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	return Vector3.new(direction:Dot(right), 0, -direction:Dot(look))
end

function DevAutopilot.init(activeCourse: any)
	course = activeCourse
end

function DevAutopilot.isEnabled(): boolean
	return RunService:IsStudio() and Players.LocalPlayer:GetAttribute("Autopilot") == true and course.BotRoute ~= nil
end

function DevAutopilot.shouldLoop(): boolean
	return DevAutopilot.isEnabled() and Players.LocalPlayer:GetAttribute("AutopilotLoop") == true
end

function DevAutopilot.reset()
	index = 1
	previousPoint = course.Spawn.Position
	if driving then
		InputController.setOverride(nil)
		driving = false
	end
end

function DevAutopilot.log(...: any)
	if DevAutopilot.isEnabled() then
		print("[Autopilot]", ...)
	end
end

local function drive(stick: Vector3?)
	driving = stick ~= nil
	InputController.setOverride(stick)
end

local function runStep()
	local root = MovementController.getRoot()
	local humanoid = MovementController.getHumanoid()
	if not root or not humanoid then
		return
	end
	local waypoint = course.BotRoute[index]
	if not waypoint then
		drive(toStick(course.Launch.Forward))
		return
	end
	local position = root.Position
	local toWaypoint = Vector3.new(waypoint.Position.X - position.X, 0, waypoint.Position.Z - position.Z)
	local segment = flat(waypoint.Position - previousPoint)
	local passed = segment ~= Vector3.zero and -toWaypoint:Dot(segment) > 0
	if toWaypoint.Magnitude < (waypoint.Radius or 8) or passed then
		if waypoint.Jump then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		previousPoint = waypoint.Position
		index += 1
		return
	end

	-- Pacing styles let QA compare how momentum rewards (or doesn't) different runs.
	local style = Players.LocalPlayer:GetAttribute("AutopilotStyle") or "Sprint"
	local inSlamZone = CourseController.getProgress() >= course.SlamModeDistance
	local holdBack = style == "Crawl" or (style == "LateBurst" and not inSlamZone) or (style == "Coast" and inSlamZone)
	local speedLimit = if style == "Coast" then 28 else 45
	if holdBack then
		local overLimit = MovementController.getActualSpeed() > speedLimit and MovementController.isGrounded()
		drive(if overLimit then Vector3.zero else toStick(toWaypoint.Unit))
		return
	end

	drive(toStick(toWaypoint.Unit))
	if waypoint.Slide then
		if not MovementController.isSliding() then
			MovementController.trySlide()
		end
	elseif DashController.getReadiness() >= 1 and MovementController.getActualSpeed() > 40 and MovementController.isGrounded() then
		DashController.tryDash()
	end
end

local function flightStep()
	local prediction = SlamController.getPrediction()
	if prediction.TimeToImpact <= 0 then
		return
	end
	local error = prediction.Point - course.Target.Center
	local right = course.Launch.Forward:Cross(Vector3.yAxis).Unit
	local lateral = error:Dot(right)
	drive(Vector3.new(math.clamp(-lateral / 4, -1, 1), 0, math.clamp(error.Y / 4, -1, 1)))
	if SlamController.canSlamDash() and prediction.TimeToImpact < 1.1 and error.Magnitude < 5 then
		SlamController.trySlamDash()
	end
end

-- Called by RunController each frame before movement/flight updates.
function DevAutopilot.update(state: string)
	if not DevAutopilot.isEnabled() then
		if driving then
			drive(nil)
		end
		return
	end
	if state == "Running" then
		runStep()
	elseif state == "Flight" then
		flightStep()
	elseif driving then
		drive(nil)
	end
end

return DevAutopilot
