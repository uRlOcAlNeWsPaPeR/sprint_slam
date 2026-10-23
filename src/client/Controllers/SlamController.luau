--!strict
-- The Final Slam. Launch speed comes from run momentum; flight uses its own gravity,
-- limited steering, a predicted-impact reticle and a one-shot Slam Dash. The impact
-- freezes the runner (hit-stop) and fires the effects; the server decides the score.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Momentum = require(Shared.Momentum)
local ScoreFormula = require(Shared.ScoreFormula)
local Signal = require(Shared.Signal)

local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local ProceduralPose = require(script.Parent.ProceduralPose)
local Sfx = require(script.Parent.Sfx)

local S = Config.Slam
local Palette = Config.Palette

local SlamController = {}

-- Impact:Fire({ Point, Speed, Radius, Zone, LaunchTime })
SlamController.Impact = Signal.new()
SlamController.SlamDashed = Signal.new()

type Flight = {
	root: BasePart,
	humanoid: Humanoid,
	velocity: Vector3,
	forward: Vector3,
	right: Vector3,
	launchTime: number,
	elapsed: number,
	slamDashUsed: boolean,
	steerScale: number,
	previous: Vector3,
	attachment: Attachment,
	linear: LinearVelocity,
	align: AlignOrientation,
}

local course: any = nil
local flight: Flight? = nil
local impacted = false
local reticleRing: BasePart? = nil
local reticleDot: BasePart? = nil
local zoneParts: { { part: BasePart, base: CFrame } } = {}
local prediction = { TimeToImpact = 0, Zone = "WALL", Radius = math.huge, Point = Vector3.zero }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function triggerPlane(): (Vector3, Vector3)
	local target = course.Target
	return target.Center + target.Normal * S.TriggerOffset, target.Normal
end

local function zoneColor(zoneName: string): Color3
	if zoneName == "BULLSEYE" then
		return Palette.Orange
	elseif zoneName == "INNER" then
		return Palette.Cyan
	elseif zoneName == "WALL" then
		return Palette.Muted
	end
	return Palette.White
end

local function makeDisc(name: string, radius: number, color: Color3, parent: Instance): BasePart
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Size = Vector3.new(0.15, radius * 2, radius * 2)
	disc.Parent = parent
	return disc
end

local function buildReticle()
	local folder = Instance.new("Folder")
	folder.Name = "SlamReticle"
	folder.Parent = workspace.CurrentCamera
	reticleRing = makeDisc("Ring", 2.8, Palette.White, folder)
	reticleRing.Transparency = 0.3
	reticleDot = makeDisc("Dot", 1.6, Palette.Orange, folder)
	SlamController.hideReticle()
end

local function placeReticle(cframe: CFrame)
	if reticleRing and reticleDot then
		-- Cylinders extrude along X; the dot sits a hair in front of the ring.
		reticleRing.CFrame = cframe * CFrame.Angles(0, math.pi / 2, 0)
		reticleDot.CFrame = cframe * CFrame.new(0, 0, -0.1) * CFrame.Angles(0, math.pi / 2, 0)
	end
end

function SlamController.hideReticle()
	placeReticle(CFrame.new(0, -1000, 0))
end

function SlamController.init()
	buildReticle()
end

-- Points the slam at one challenge's course and gathers its target rings for the hit pulse.
function SlamController.setCourse(newCourse: any)
	course = newCourse
	table.clear(zoneParts)
	local target = workspace:WaitForChild("Courses"):WaitForChild(newCourse.Id):WaitForChild("Target")
	for _, child in target:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 5) == "Zone_" then
			table.insert(zoneParts, { part = child, base = child.CFrame })
		end
	end
end

function SlamController.isActive(): boolean
	return flight ~= nil
end

function SlamController.getPrediction()
	return prediction
end

function SlamController.canSlamDash(): boolean
	return flight ~= nil and not flight.slamDashUsed
end

-- Speed driving into the wall right now; this is what impact power is scored on.
function SlamController.getImpactSpeed(): number
	if not flight then
		return 0
	end
	return math.max(-flight.velocity:Dot(course.Target.Normal), 0)
end

function SlamController.begin(momentum: number)
	local root = MovementController.getRoot()
	local humanoid = MovementController.getHumanoid()
	if not root or not humanoid or flight then
		return
	end
	impacted = false
	local launch = course.Launch
	local forward: Vector3 = launch.Forward
	local right = forward:Cross(Vector3.yAxis).Unit
	local pitch = math.rad(S.LaunchPitchDeg)
	local launchSpeed = Momentum.launchSpeed(momentum)
	local velocity = (forward * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)) * launchSpeed

	MovementController.setEnabled(false)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "SlamAttachment"
	attachment.Parent = root
	local linear = Instance.new("LinearVelocity")
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = math.huge
	linear.VectorVelocity = velocity
	linear.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = false
	align.MaxTorque = math.huge
	align.Responsiveness = 35
	align.CFrame = CFrame.lookAt(Vector3.zero, velocity.Unit) * CFrame.Angles(-math.rad(80), 0, 0)
	align.Parent = root

	flight = {
		root = root,
		humanoid = humanoid,
		velocity = velocity,
		forward = forward,
		right = right,
		launchTime = serverNow(),
		elapsed = 0,
		slamDashUsed = false,
		steerScale = 1,
		previous = root.Position,
		attachment = attachment,
		linear = linear,
		align = align,
	}

	ProceduralPose.set("Flight")
	CameraController.beginFlight(root, course.Target.Center, forward)
	CameraController.kick(10)
	CameraController.shake(0.3)
	EffectsController.burst(Palette.Orange, 30)
	Sfx.play("Launch")
end

local function timeToPlane(position: Vector3, velocity: Vector3): number?
	local planePoint, normal = triggerPlane()
	local distance = Geometry.signedDistance(position, planePoint, normal)
	local closing = -velocity:Dot(normal)
	if closing <= 1 then
		return nil
	end
	return math.max(distance, 0) / closing
end

local function updatePrediction(f: Flight)
	local target = course.Target
	local t = timeToPlane(f.root.Position, f.velocity)
	if not t then
		prediction.TimeToImpact = 0
		prediction.Zone = "WALL"
		SlamController.hideReticle()
		return
	end
	local gravity = Vector3.new(0, -S.FlightGravity, 0)
	local predicted = f.root.Position + f.velocity * t + gravity * (0.5 * t * t)
	local _, radius = Geometry.targetOffset(predicted, target.Center, target.Normal)
	local zone = ScoreFormula.zoneForRadius(radius)
	prediction.TimeToImpact = t
	prediction.Zone = zone.Name
	prediction.Radius = radius
	prediction.Point = predicted

	local onFace = predicted - target.Normal * Geometry.signedDistance(predicted, target.Center, target.Normal)
	local position = onFace + target.Normal * 0.8
	placeReticle(CFrame.lookAt(position, position + target.Normal))
	if reticleDot then
		reticleDot.Color = zoneColor(zone.Name)
	end
end

function SlamController.trySlamDash(): boolean
	local f = flight
	if not f or f.slamDashUsed or impacted then
		return false
	end
	local t = timeToPlane(f.root.Position, f.velocity) or 0
	local early = math.clamp(t / S.SlamDashFullBonusTime, 0, 1)
	local bonus = S.SlamDashMinBonus + (S.SlamDashMaxBonus - S.SlamDashMinBonus) * early
	f.slamDashUsed = true
	f.velocity *= 1 + bonus
	f.steerScale = S.SlamDashSteerScale
	CameraController.kick(14)
	CameraController.shake(0.35)
	EffectsController.dash()
	Sfx.play("Dash", 0.8, 0.8)
	SlamController.SlamDashed:Fire(bonus)
	return true
end

-- Target rings punch in and spring back; bigger hits push deeper.
local function pulseTarget(strength: number)
	local normal: Vector3 = course.Target.Normal
	for _, entry in zoneParts do
		local depth = strength * (if string.find(entry.part.Name, "BULLSEYE") then 2.4 else 1.2)
		entry.part.CFrame = entry.base
		local push = TweenService:Create(entry.part, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = entry.base - normal * depth })
		push.Completed:Once(function()
			TweenService:Create(entry.part, TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = entry.base }):Play()
		end)
		push:Play()
	end
end

local function spawnFxPart(cframe: CFrame, size: Vector3, color: Color3, shape: Enum.PartType): BasePart
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.CanTouch = false
	fx.CastShadow = false
	fx.Material = Enum.Material.Neon
	fx.Shape = shape
	fx.Color = color
	fx.CFrame = cframe
	fx.Size = size
	fx.Parent = workspace.CurrentCamera
	return fx
end

local function shockwave(point: Vector3, normal: Vector3, color: Color3, maxRadius: number, duration: number)
	local facing = CFrame.lookAt(point, point + normal) * CFrame.Angles(0, math.pi / 2, 0)
	local ring = spawnFxPart(facing, Vector3.new(0.2, 4, 4), color, Enum.PartType.Cylinder)
	ring.Transparency = 0.1
	local tween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, maxRadius * 2, maxRadius * 2),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function flash(point: Vector3, size: number)
	local ball = spawnFxPart(CFrame.new(point), Vector3.one * 3, Palette.White, Enum.PartType.Ball)
	ball.Transparency = 0.15
	local tween = TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	})
	tween.Completed:Once(function()
		ball:Destroy()
	end)
	tween:Play()
end

local function sparkBurst(point: Vector3, normal: Vector3, color: Color3, count: number, timeScale: number)
	local holder = spawnFxPart(CFrame.lookAt(point, point + normal), Vector3.one * 0.2, color, Enum.PartType.Block)
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.SpreadAngle = Vector2.new(75, 75)
	emitter.Speed = NumberRange.new(40, 110)
	emitter.Lifetime = NumberRange.new(0.6, 1.3)
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -60, 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(color, Palette.White)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.TimeScale = timeScale
	emitter.Parent = holder
	emitter:Emit(if EffectsController.isLowQuality() then math.ceil(count / 3) else count)
	task.delay(4, function()
		holder:Destroy()
	end)
	return emitter
end

local function popup(point: Vector3, zoneName: string, color: Color3, score: number)
	local anchor = spawnFxPart(CFrame.new(point), Vector3.one * 0.1, color, Enum.PartType.Block)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 160)
	gui.StudsOffsetWorldSpace = course.Target.Normal * 3 + Vector3.yAxis * 10
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = gui
	local zoneLabel = Instance.new("TextLabel")
	zoneLabel.BackgroundTransparency = 1
	zoneLabel.Size = UDim2.new(1, 0, 0.55, 0)
	zoneLabel.Font = Enum.Font.GothamBlack
	zoneLabel.TextScaled = true
	zoneLabel.Text = if zoneName == "WALL" then "WALL HIT" else zoneName .. "!"
	zoneLabel.TextColor3 = color
	zoneLabel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Palette.Charcoal
	stroke.Parent = zoneLabel
	local scoreLabel = zoneLabel:Clone()
	scoreLabel.Position = UDim2.fromScale(0, 0.55)
	scoreLabel.Size = UDim2.new(1, 0, 0.45, 0)
	scoreLabel.Text = "+" .. tostring(score)
	scoreLabel.TextColor3 = Palette.White
	scoreLabel.Parent = gui
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.8, function()
		for _, label in { zoneLabel, scoreLabel } do
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		task.wait(0.5)
		anchor:Destroy()
	end)
end

local function release(f: Flight)
	f.linear:Destroy()
	f.align:Destroy()
	f.attachment:Destroy()
end

local function onImpact(f: Flight, point: Vector3)
	impacted = true
	local target = course.Target
	local normal: Vector3 = target.Normal
	local speed = math.max(-f.velocity:Dot(normal), 0)
	local _, radius = Geometry.targetOffset(point, target.Center, target.Normal)
	local zone = ScoreFormula.zoneForRadius(radius)
	local provisional = math.floor(ScoreFormula.impactPower(speed) * zone.Multiplier + 0.5)

	SlamController.hideReticle()
	-- Hit-stop: hold the runner just past the plane with the flight constraints at zero
	-- velocity. Anchoring would stop physics replication, and the server needs to see
	-- this position to confirm the crossing.
	local frozen = point - normal * 0.4
	f.linear.VectorVelocity = Vector3.zero
	f.root.CFrame = CFrame.lookAt(frozen, frozen - normal) * CFrame.Angles(-math.rad(80), 0, 0)
	f.align.CFrame = f.root.CFrame.Rotation

	local exceptional = zone.Name == "BULLSEYE" or provisional >= S.ExceptionalScore
	local hitStop = if exceptional then S.HitStopExceptional else S.HitStop
	local strength = math.clamp(speed / S.MaxLaunchSpeed, 0.3, 1.4) * (0.6 + zone.Multiplier * 0.25)
	local color = zoneColor(zone.Name)
	local wallPoint = point - normal * (S.TriggerOffset - 0.6)

	CameraController.shake(math.clamp(0.45 + strength * 0.35, 0, 1))
	CameraController.kick(-8)
	CameraController.impactShot(wallPoint, normal, if exceptional then 2.4 else 1.4)
	flash(wallPoint, 14 + strength * 22)
	shockwave(wallPoint, normal, Palette.White, 26 + strength * 34, 0.55)
	shockwave(wallPoint, normal, color, 18 + strength * 26, 0.8)
	local sparks = sparkBurst(wallPoint, normal, color, math.floor(50 + strength * 70), if exceptional then 0.18 else 1)
	pulseTarget(strength)
	popup(wallPoint, zone.Name, color, provisional)
	Sfx.play(if exceptional then "ImpactBig" else "Impact", 0.9, 1.1 - strength * 0.15)

	SlamController.Impact:Fire({
		Point = point,
		Speed = speed,
		Radius = radius,
		Zone = zone,
		LaunchTime = f.launchTime,
		Exceptional = exceptional,
	})

	task.delay(hitStop, function()
		if flight ~= f then
			return
		end
		if exceptional then
			-- Let the slow-motion sparks catch up to real time.
			TweenService:Create(sparks, TweenInfo.new(0.6), { TimeScale = 1 }):Play()
		end
		release(f)
		f.root.AssemblyLinearVelocity = normal * math.min(speed * 0.18, 30) + Vector3.yAxis * 12
		ProceduralPose.set(nil)
	end)
end

function SlamController.update(dt: number)
	local f = flight
	if not f or impacted then
		return
	end
	f.elapsed += dt

	local move = InputController.getMoveVector()
	local vertical = -move.Z * (if S.InvertVertical then -1 else 1)
	local steer = (f.right * move.X + Vector3.yAxis * vertical) * S.SteerAcceleration * f.steerScale
	local velocity = f.velocity + (steer + Vector3.new(0, -S.FlightGravity, 0)) * dt
	local lateral = velocity:Dot(f.right)
	if math.abs(lateral) > S.MaxSteerSpeed then
		velocity -= f.right * (lateral - math.sign(lateral) * S.MaxSteerSpeed)
	end
	f.velocity = velocity
	f.linear.VectorVelocity = velocity
	f.align.CFrame = CFrame.lookAt(Vector3.zero, velocity.Unit) * CFrame.Angles(-math.rad(80), 0, 0)

	local position = f.root.Position
	local planePoint, normal = triggerPlane()
	local hit = Geometry.planeCrossing(f.previous, position, planePoint, normal)
	f.previous = position
	if hit then
		onImpact(f, hit)
		return
	end
	if f.elapsed > S.MaxFlightTime or position.Y < course.PitFloorY + 4 then
		onImpact(f, position)
		return
	end
	updatePrediction(f)
end

-- Restore the character after a slam (or when a run restarts mid-flight).
function SlamController.cleanup()
	local f = flight
	flight = nil
	impacted = false
	SlamController.hideReticle()
	for _, entry in zoneParts do
		entry.part.CFrame = entry.base
	end
	if f then
		if f.linear.Parent then
			release(f)
		end
		f.humanoid.PlatformStand = false
		f.humanoid.AutoRotate = true
		f.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	ProceduralPose.set(nil)
	CameraController.reset()
end

return SlamController
