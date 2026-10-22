--!strict
-- Momentum model layered on the Humanoid. We keep our own `speed`, feed it to WalkSpeed,
-- and steer by calling Humanoid:Move after the default ControlModule each frame, so the
-- turn rate can tighten as speed rises (carving) and reversals brake.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local InputController = require(script.Parent.InputController)
local ProceduralPose = require(script.Parent.ProceduralPose)

local M = Config.Movement
local D = Config.Dash

local MovementController = {}

-- Fired with a Config.Combo.Events key.
MovementController.Combo = Signal.new()
MovementController.Landed = Signal.new()

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local defaultHipHeight = 2
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local enabled = false
local speed = M.BaseSpeed
local direction = Vector3.new(0, 0, -1)
local dashTimer = 0
local dashBoost = 0
local sliding = false
local slideTimer = 0
local slideCooldownUntil = 0
local landedAt: number? = nil
local blockedTime = 0
local grounded = true
local hasInput = false

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.zero
	end
	return f.Unit
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Rotate unit vector `from` toward `to` (both horizontal) by at most `maxAngle` radians.
local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): (Vector3, number)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return to, angle
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	local rotated = CFrame.Angles(0, sign * maxAngle, 0):VectorToWorldSpace(from)
	return flat(rotated), maxAngle
end

local function endSlide()
	if not sliding then
		return
	end
	sliding = false
	slideCooldownUntil = now() + M.SlideCooldown
	if humanoid then
		humanoid.HipHeight = defaultHipHeight
	end
	ProceduralPose.set(nil)
end

local function consumePerfectLanding(): boolean
	if landedAt and now() - landedAt <= M.PerfectLandingWindow then
		landedAt = nil
		if speed < M.RunSpeedCap then
			speed = math.min(speed + M.PerfectLandingBonus, M.RunSpeedCap)
		end
		MovementController.Combo:Fire("PerfectLanding")
		return true
	end
	return false
end

local function onStateChanged(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
	if new == Enum.HumanoidStateType.Landed then
		if speed >= M.LandingMinSpeed then
			landedAt = now()
		end
		MovementController.Landed:Fire()
	elseif new == Enum.HumanoidStateType.Jumping then
		if sliding then
			speed = math.min(speed + M.SlideJumpBoost, M.OverspeedCap)
			endSlide()
			MovementController.Combo:Fire("SlideJump")
		end
		consumePerfectLanding()
	end
end

function MovementController.bindCharacter(character: Model)
	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = newHumanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	newHumanoid.UseJumpPower = false
	newHumanoid.JumpHeight = M.JumpHeight
	defaultHipHeight = newHumanoid.HipHeight
	rayParams.FilterDescendantsInstances = { character }
	newHumanoid.StateChanged:Connect(onStateChanged)
	MovementController.reset()
end

function MovementController.reset()
	endSlide()
	speed = M.BaseSpeed
	dashTimer = 0
	dashBoost = 0
	landedAt = nil
	blockedTime = 0
	if root then
		direction = flat(root.CFrame.LookVector)
	end
	if humanoid then
		humanoid.WalkSpeed = M.BaseSpeed
	end
end

function MovementController.setEnabled(value: boolean)
	enabled = value
	if not value then
		endSlide()
		if humanoid then
			humanoid:Move(Vector3.zero, false)
		end
	end
end

function MovementController.teleport(cframe: CFrame)
	local character = humanoid and humanoid.Parent :: Model?
	if not character or not root then
		return
	end
	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	MovementController.reset()
	direction = flat(cframe.LookVector)
end

local function desiredDirection(): Vector3
	local raw = InputController.getMoveVector()
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	local desired = right * raw.X + look * -raw.Z
	if desired.Magnitude < 0.15 then
		return Vector3.zero
	end
	return desired.Unit
end

local function slopeAlong(dir: Vector3): number
	if not root or not humanoid then
		return 0
	end
	local result = workspace:Raycast(root.Position, Vector3.new(0, -(humanoid.HipHeight + 3), 0), rayParams)
	if not result then
		return 0
	end
	-- Positive when moving downhill: the surface normal leans the way we travel.
	return result.Normal:Dot(dir)
end

function MovementController.update(dt: number)
	local h = humanoid
	local r = root
	if not enabled or not h or not r then
		return
	end
	local t = now()
	grounded = h.FloorMaterial ~= Enum.Material.Air

	local desired = desiredDirection()
	hasInput = desired ~= Vector3.zero
	local speedFraction = math.clamp((speed - M.BaseSpeed) / (M.RunSpeedCap - M.BaseSpeed), 0, 1)

	if dashTimer > 0 then
		dashTimer = math.max(dashTimer - dt, 0)
		dashBoost = D.Boost * (dashTimer / D.Duration)
	else
		dashBoost = 0
	end
	local dashing = dashTimer > 0

	-- Steering
	if hasInput then
		local turnRate = M.TurnRateLow + (M.TurnRateHigh - M.TurnRateLow) * speedFraction
		if not grounded then
			turnRate *= M.AirTurnRateScale
		end
		if sliding then
			turnRate *= M.SlideTurnRateScale
		end
		if dashing then
			turnRate *= D.SteerScale
		end
		local angle = math.acos(math.clamp(direction:Dot(desired), -1, 1))
		if angle > M.ReverseAngle and grounded and not dashing then
			speed = math.max(M.BaseSpeed, speed - M.BrakeDecel * dt)
			turnRate = M.TurnRateLow * 1.5
		end
		local turned
		direction, turned = rotateToward(direction, desired, turnRate * dt)
		local drag = if sliding then M.SlideTurnDrag else M.TurnDrag
		speed -= math.max(speed - M.BaseSpeed, 0) * drag * turned
	end

	-- Acceleration, slopes, decay
	local slope = if grounded then slopeAlong(direction) else 0
	if sliding then
		slideTimer -= dt
		speed -= M.SlideFriction * dt
		if slope > 0 then
			speed += M.SlideDownhillGain * slope * dt
		end
		if slideTimer <= 0 then
			endSlide()
		end
	elseif hasInput then
		if speed < M.RunSpeedCap then
			local accel = M.Acceleration * (1 - speedFraction) ^ M.AccelerationCurve
			if not grounded then
				accel *= M.AirAccelerationScale
			end
			speed = math.min(speed + accel * dt, M.RunSpeedCap)
		end
		if slope > 0 then
			speed += M.DownhillGain * slope * dt
		elseif slope < 0 then
			speed += M.UphillLoss * slope * dt
		end
	elseif grounded then
		speed = math.max(M.BaseSpeed, speed - M.IdleDecay * dt)
	end
	if speed > M.RunSpeedCap then
		local decay = if grounded then M.OverspeedDecayGround else M.OverspeedDecayAir
		speed = math.max(M.RunSpeedCap, speed - decay * dt)
	end
	speed = math.clamp(speed, M.BaseSpeed, M.OverspeedCap)

	-- Blocked by geometry: momentum collapses toward what we're actually doing.
	local velocity = r.AssemblyLinearVelocity
	local actual = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local commanded = speed + dashBoost
	-- Airborne runners keep their line even with no input held.
	local moving = hasInput or dashing or sliding or (not grounded and speed > M.BaseSpeed + 2)
	if moving and commanded > M.BaseSpeed + 4 and actual < commanded * M.BlockedRatio then
		blockedTime += dt
		if blockedTime >= M.BlockedTime then
			speed = math.max(M.BaseSpeed, math.min(speed, actual + M.BlockedRecover))
			dashTimer = 0
			dashBoost = 0
			blockedTime = 0
		end
	else
		blockedTime = 0
	end

	-- A landing that wasn't chained into a jump or slide costs a little momentum.
	if landedAt and t - landedAt > M.PerfectLandingWindow then
		landedAt = nil
		if grounded then
			speed -= math.max(speed - M.BaseSpeed, 0) * M.LandingLoss
		end
	end

	h.WalkSpeed = speed + dashBoost
	h:Move(if moving then direction else Vector3.zero, false)
end

function MovementController.trySlide(): boolean
	if not enabled or not humanoid or sliding or not grounded then
		return false
	end
	if speed < M.SlideMinSpeed or now() < slideCooldownUntil then
		return false
	end
	consumePerfectLanding()
	sliding = true
	slideTimer = M.SlideDuration
	speed = math.min(speed + M.SlideBoost, M.OverspeedCap)
	humanoid.HipHeight = defaultHipHeight * M.SlideHipHeightScale
	ProceduralPose.set("Slide")
	return true
end

-- Dash: temporary burst plus a permanent slice of momentum. Returns true if airborne.
function MovementController.applyDash(): boolean
	local desired = desiredDirection()
	if desired ~= Vector3.zero then
		direction = desired
	end
	endSlide()
	dashTimer = D.Duration
	dashBoost = D.Boost
	speed = math.min(speed + D.Retain, M.OverspeedCap)
	local airborne = not grounded
	if airborne and root then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, D.AirLift), v.Z)
	end
	return airborne
end

function MovementController.applyBoost(amount: number)
	speed = math.min(math.max(speed, M.RunSpeedCap * 0.75) + amount, M.OverspeedCap)
end

function MovementController.launchUp(upVelocity: number, minForwardSpeed: number, forward: Vector3)
	if not humanoid or not root then
		return
	end
	endSlide()
	local v = root.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(v.X, 0, v.Z)
	if horizontalVelocity.Magnitude < minForwardSpeed then
		horizontalVelocity = forward * minForwardSpeed
		direction = forward
	end
	speed = math.max(speed, minForwardSpeed)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = horizontalVelocity + Vector3.yAxis * upVelocity
end

function MovementController.bonk(push: Vector3)
	if not humanoid or not root then
		return
	end
	endSlide()
	speed = M.BaseSpeed + math.max(speed - M.BaseSpeed, 0) * M.BonkSpeedScale
	dashTimer = 0
	dashBoost = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = flat(push) * M.BonkKnockback + Vector3.yAxis * M.BonkLift
end

function MovementController.getSpeed(): number
	return speed
end

function MovementController.getActualSpeed(): number
	if not root then
		return 0
	end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function MovementController.isDashing(): boolean
	return dashTimer > 0
end

function MovementController.isSliding(): boolean
	return sliding
end

function MovementController.isGrounded(): boolean
	return grounded
end

function MovementController.getRoot(): BasePart?
	return root
end

function MovementController.getHumanoid(): Humanoid?
	return humanoid
end

return MovementController
