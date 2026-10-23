--!strict
-- Studio-only QA bot. It drives the real input path (stick vector, jump, dash, slide,
-- flight steering, Slam Dash) along a route, so full runs can be verified end to end,
-- server scoring included. It also proves hub challenges and levels can be completed.
-- Enable from the Studio client:
--   game.Players.LocalPlayer:SetAttribute("Autopilot", true)       -- drive
--   game.Players.LocalPlayer:SetAttribute("AutopilotLoop", true)   -- restart after results
--   game.Players.LocalPlayer:SetAttribute("AutopilotLevel", 3)     -- week challenge (1-10) picked at the portal
--   game.Players.LocalPlayer:SetAttribute("AutopilotAdvance", true) -- with Loop: go on to the next challenge
--   game.Players.LocalPlayer:SetAttribute("AutopilotChallenge", "SKY TOWER") -- run a hub challenge
--   game.Players.LocalPlayer:SetAttribute("AutopilotVerbose", true) -- log every waypoint
--   game.Players.LocalPlayer:SetAttribute("AutopilotStyle", "Crawl") -- how it paces a run:
--     Sprint (default) | Crawl (~45 st/s, no dash) | LateBurst (crawl, then sprint the slam
--     runway) | Coast (sprint, then ease off on the slam runway to aim)
--
-- Route waypoints: Position, Radius (arrival), Jump / Dash on arrival, Slide while heading
-- there, MaxSpeed while heading there, WaitForBlinkWave (hold until the blink wave starts).
-- Timed dangers ahead (live lasers, sweeping blocks) make the bot wait for a gap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Geometry = require(Shared.Geometry)
local HazardMath = require(Shared.HazardMath)

local CourseController = require(script.Parent.CourseController)
local DashController = require(script.Parent.DashController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local SlamController = require(script.Parent.SlamController)
local ChallengeMenu = require(script.Parent.ChallengeMenu)
local UIController = require(script.Parent.UIController)

local DevAutopilot = {}

local course: any = nil
local courses: { any } = {}
local lobby: any = nil
local index = 1
local previousPoint = Vector3.zero
local driving = false
local pendingDashAt: number? = nil
local pendingJump: { dash: boolean }? = nil
local challengeName: string? = nil
local lastLevelPick = 0
local lastHoldLog = 0

local OBSTACLE_MARGIN = Vector3.new(1.9, 3, 1.9) -- game bonk margin (1.4) plus a little

local function attribute(name: string): any
	return Players.LocalPlayer:GetAttribute(name)
end

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

local function drive(stick: Vector3?)
	driving = stick ~= nil
	InputController.setOverride(stick)
end

function DevAutopilot.init(allCourses: { any }, activeLobby: any)
	courses = allCourses
	course = allCourses[1]
	lobby = activeLobby
end

function DevAutopilot.setCourse(newCourse: any)
	course = newCourse
end

function DevAutopilot.isEnabled(): boolean
	return RunService:IsStudio() and attribute("Autopilot") == true and course.BotRoute ~= nil
end

function DevAutopilot.shouldLoop(): boolean
	return DevAutopilot.isEnabled() and attribute("AutopilotLoop") == true
end

function DevAutopilot.shouldAdvance(): boolean
	return DevAutopilot.shouldLoop() and attribute("AutopilotAdvance") == true
end

-- After a respawn in a course run the player is back at a checkpoint: carry on from the first
-- waypoint still ahead of them (so the gap they respawned before gets jumped again).
function DevAutopilot.resync()
	local root = MovementController.getRoot()
	if not root then
		return
	end
	previousPoint = root.Position
	index = #course.BotRoute + 1
	for i, waypoint in course.BotRoute do
		if waypoint.Position.Z < root.Position.Z - 2 then
			index = i
			break
		end
	end
	pendingJump = nil
	pendingDashAt = nil
end

-- After a fall in a hub challenge the player is back at its start: rerun the route.
function DevAutopilot.restartRoute()
	local root = MovementController.getRoot()
	if not root or not challengeName then
		return
	end
	previousPoint = root.Position
	for _, challenge in lobby.Challenges do
		if challenge.Name == challengeName then
			-- Resume from the waypoint nearest the respawn point.
			local best = math.huge
			for i, waypoint in challenge.BotRoute do
				local distance = (waypoint.Position - root.Position).Magnitude
				if distance < best then
					best = distance
					index = i
				end
			end
		end
	end
end

function DevAutopilot.reset()
	index = 1
	previousPoint = course.Spawn.Position
	pendingDashAt = nil
	pendingJump = nil
	challengeName = nil
	if driving then
		drive(nil)
	end
end

local function verbose(): boolean
	return RunService:IsStudio() and attribute("AutopilotVerbose") == true
end

function DevAutopilot.log(...: any)
	if DevAutopilot.isEnabled() or verbose() then
		print("[Autopilot]", ...)
	end
end

-- True if pushing on toward `direction` could run into a live laser or a sweeping block.
-- For each point ahead we take the whole window of times we might arrive there: as late as
-- walking on at the current pace, as early as full acceleration (30 st/s^2). If a hazard is
-- dangerous at that point at ANY time in the window, the bot holds.
local function dangerAhead(position: Vector3, direction: Vector3, speed: number, obstacles: { any }, hazards: { any }?, centerX: number?): string?
	local t0 = workspace:GetServerTimeNow()
	local v0 = math.max(speed, 20)
	for distance = 3, 24, 1.5 do
		local point = position + direction * distance
		if centerX and math.abs(point.X - centerX) > 15 then
			return "edge" -- that heading would leave the floor
		end
		local late = distance / v0
		local early = (-v0 + math.sqrt(v0 * v0 + 2 * 30 * distance)) / 30
		local at = early - 0.12
		while at <= late + 0.12 do
			local time = t0 + math.max(at, 0)
			for _, def in hazards or {} do
				if def.Type == "Laser" and HazardMath.isOn(def, time) then
					if Geometry.pointInBox(point, def.CFrame, def.Size, Vector3.new(1.6, 2.5, 1.6)) then
						return "laser"
					end
				end
			end
			for _, def in obstacles do
				local phase = (time / def.Period + def.Phase) * math.pi * 2
				local cf = def.CFrame + def.Axis * (math.sin(phase) * def.Amplitude)
				if Geometry.pointInBox(point, cf, def.Size, OBSTACLE_MARGIN) then
					return "block"
				end
			end
			at += 0.05
		end
	end
	return nil
end

-- A heading that is safe to take: straight on if possible, else a gentle sidestep (sweeping
-- blocks leave free floor on one side; full-width lasers don't, so those are waited out).
local function safeHeading(position: Vector3, direction: Vector3, speed: number, obstacles: { any }, hazards: { any }?, centerX: number?): Vector3?
	-- The straight heading heads for a waypoint on the floor, so only sidesteps are edge-checked.
	local danger = dangerAhead(position, direction, speed, obstacles, hazards, nil)
	if not danger then
		return direction
	end
	-- Full-width lasers can only be waited out; a sweeping block can be sidestepped.
	if centerX and danger == "block" then
		for _, degrees in { 12, -12, 24, -24, 36, -36 } do
			local candidate = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
			if dangerAhead(position, candidate, speed, obstacles, hazards, centerX) == nil then
				return candidate
			end
		end
	end
	return nil
end

-- Follow `route` one step. Returns true once the last waypoint is reached.
local function followRoute(route: { any }, obstacles: { any }, hazards: { any }?, paced: boolean): boolean
	local root = MovementController.getRoot()
	local humanoid = MovementController.getHumanoid()
	if not root or not humanoid then
		return false
	end
	if pendingDashAt and os.clock() >= pendingDashAt then
		pendingDashAt = nil
		DashController.tryDash()
	end
	-- Jumps only happen from the ground, like a player's; one queued in the air fires on landing.
	if pendingJump and MovementController.isGrounded() then
		local dash = pendingJump.dash
		pendingJump = nil
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		if dash then
			pendingDashAt = os.clock() + 0.1
		end
	end
	local waypoint = route[index]
	if not waypoint then
		drive(nil)
		return true
	end
	local position = root.Position
	local toWaypoint = Vector3.new(waypoint.Position.X - position.X, 0, waypoint.Position.Z - position.Z)
	local segment = flat(waypoint.Position - previousPoint)
	local passed = segment ~= Vector3.zero and -toWaypoint:Dot(segment) > 0
	if toWaypoint.Magnitude < (waypoint.Radius or 8) or passed then
		if waypoint.WaitForBlinkWave then
			-- Leave the corner just as the first blink segment lights up.
			local first = nil
			for _, def in hazards or {} do
				if def.Type == "Blink" then
					first = def
					break
				end
			end
			if first and HazardMath.cycle(first, workspace:GetServerTimeNow()) > 0.06 then
				drive(Vector3.zero)
				return false
			end
		end
		if waypoint.Jump then
			if MovementController.isGrounded() then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				if waypoint.Dash then
					pendingDashAt = os.clock() + 0.1
				end
			else
				pendingJump = { dash = waypoint.Dash == true }
			end
		end
		if verbose() then
			print(string.format("[Autopilot] waypoint %d reached at %s, speed %.0f", index, tostring(position), MovementController.getActualSpeed()))
		end
		previousPoint = waypoint.Position
		index += 1
		return false
	end

	local direction = toWaypoint.Unit
	local speed = MovementController.getActualSpeed()
	local grounded = MovementController.isGrounded()
	if grounded then
		-- Courses (paced runs) are 36 wide around their origin; hub challenges stay on line.
		local centerX = if paced then course.Origin.X else nil
		local heading = safeHeading(position, direction, speed, obstacles, hazards, centerX)
		if not heading then
			if verbose() and os.clock() - lastHoldLog > 1 then
				lastHoldLog = os.clock()
				print(string.format("[Autopilot] holding for a hazard at %s (waypoint %d)", tostring(position), index))
			end
			drive(Vector3.zero)
			return false
		end
		direction = heading
	end

	-- Pacing styles let QA compare how momentum rewards (or doesn't) different runs.
	if paced then
		local style = attribute("AutopilotStyle") or "Sprint"
		local inSlamZone = CourseController.getProgress() >= course.SlamModeDistance
		local holdBack = style == "Crawl" or (style == "LateBurst" and not inSlamZone) or (style == "Coast" and inSlamZone)
		if holdBack then
			local limit = if style == "Coast" then 28 else 45
			drive(if speed > limit and grounded then Vector3.zero else toStick(direction))
			return false
		end
	end

	if waypoint.MaxSpeed and grounded and speed > waypoint.MaxSpeed then
		drive(Vector3.zero)
		return false
	end
	if verbose() then
		Players.LocalPlayer:SetAttribute(
			"AutopilotDebug",
			string.format(
				"wp %d/%d target=(%.1f, %.1f, %.1f) pos=(%.1f, %.1f) dir=(%.2f, %.2f) speed=%.0f slide=%s grounded=%s",
				index, #route, waypoint.Position.X, waypoint.Position.Y, waypoint.Position.Z,
				position.X, position.Z, direction.X, direction.Z, speed, tostring(MovementController.isSliding()), tostring(grounded)
			)
		)
	end
	drive(toStick(direction))
	if waypoint.Slide then
		if not MovementController.isSliding() then
			MovementController.trySlide()
		end
	elseif paced and not waypoint.MaxSpeed and DashController.getReadiness() >= 1 and speed > 40 and grounded then
		-- A dash cuts steering to 30% for 0.3 s, so only dash when no precise waypoint (a
		-- pillar lane, a gap edge, a death-block lane) is near.
		local precise = (waypoint.Radius or 8) <= 4
		-- ...and never into timed hazards: a dash would beat the arrival-time estimate.
		for _, def in hazards or {} do
			if def.Type == "Laser" then
				local ahead = position.Z - def.CFrame.Position.Z
				if ahead > -6 and ahead < 90 then
					precise = true
				end
			end
		end
		for _, def in obstacles do
			local ahead = position.Z - def.CFrame.Position.Z
			if ahead > -6 and ahead < 90 then
				precise = true
			end
		end
		local nextWaypoint = route[index + 1]
		if nextWaypoint and (nextWaypoint.Radius or 8) <= 4 and toWaypoint.Magnitude < 60 then
			precise = true
		end
		if not precise then
			DashController.tryDash()
		end
	end
	return false
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

-- In the hub: run the requested challenge, or walk into the portal and pick a level.
local function lobbyStep()
	local wanted = attribute("AutopilotChallenge")
	if typeof(wanted) == "string" and wanted ~= "" then
		if challengeName ~= wanted then
			challengeName = wanted
			index = 1
			previousPoint = lobby.Spawn.Position
		end
		for _, challenge in lobby.Challenges do
			if challenge.Name == wanted then
				if followRoute(challenge.BotRoute, lobby.MovingObstacles, nil, false) then
					-- Done: stop here rather than wandering off to the portal.
					Players.LocalPlayer:SetAttribute("AutopilotChallenge", "")
					Players.LocalPlayer:SetAttribute("Autopilot", false)
				end
				return
			end
		end
		return
	end
	challengeName = nil

	if ChallengeMenu.isOpen() then
		drive(Vector3.zero)
		if os.clock() - lastLevelPick > 1 then
			lastLevelPick = os.clock()
			ChallengeMenu.ChallengeChosen:Fire(attribute("AutopilotLevel") or 1)
		end
		return
	end
	local root = MovementController.getRoot()
	if not root then
		return
	end
	for _, portal in lobby.Portals do
		if portal.Mode == "SprintSlam" then
			local target = portal.Trigger.CFrame.Position
			local toPortal = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
			drive(if toPortal.Magnitude > 0.5 then toStick(toPortal.Unit) else nil)
			return
		end
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
	if state == "Lobby" then
		lobbyStep()
	elseif state == "Running" then
		followRoute(course.BotRoute, course.MovingObstacles, course.Hazards, true)
	elseif state == "Flight" then
		flightStep()
	elseif driving then
		drive(nil)
	end
end

return DevAutopilot
