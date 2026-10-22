--!strict
-- FOV that breathes with speed, trauma-based shake, and the scripted slam cameras.
-- Shake is applied after the default camera each frame so it never accumulates.

local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local CameraController = {}

local C = Config.Camera
local M = Config.Movement

local camera = workspace.CurrentCamera
local trauma = 0
local fovKick = 0
local currentFov = C.BaseFov
local speedForFov = 0
local mode = "Default" -- "Default" | "Flight" | "Impact"
local flight: { root: BasePart, target: Vector3, forward: Vector3 }? = nil
local impactShot: { point: Vector3, normal: Vector3, start: number, duration: number }? = nil
local flightCFrame: CFrame? = nil
local clock = 0

function CameraController.setSpeed(speed: number)
	speedForFov = speed
end

function CameraController.shake(amount: number)
	trauma = math.min(trauma + amount, 1)
end

function CameraController.kick(amount: number?)
	fovKick = math.max(fovKick, amount or C.DashFovKick)
end

function CameraController.beginFlight(root: BasePart, targetCenter: Vector3, forward: Vector3)
	mode = "Flight"
	flight = { root = root, target = targetCenter, forward = forward }
	flightCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
end

-- Slow push-in on the impact point; longer for exceptional hits.
function CameraController.impactShot(point: Vector3, normal: Vector3, duration: number)
	mode = "Impact"
	impactShot = { point = point, normal = normal, start = os.clock(), duration = duration }
	camera.CameraType = Enum.CameraType.Scriptable
end

function CameraController.reset()
	mode = "Default"
	flight = nil
	impactShot = nil
	fovKick = 0
	camera.CameraType = Enum.CameraType.Custom
end

local function targetFov(): number
	local t = math.clamp((speedForFov - 30) / (M.OverspeedCap - 30), 0, 1)
	return C.BaseFov + (C.MaxFov - C.BaseFov) * t
end

local function shakeOffset(): CFrame
	local amount = trauma * trauma
	if amount < 0.001 then
		return CFrame.identity
	end
	local t = clock * 28
	local pitch = math.noise(t, 1.3) * math.rad(2.4) * amount
	local yaw = math.noise(t, 7.1) * math.rad(2.4) * amount
	local roll = math.noise(t, 13.7) * math.rad(3.2) * amount
	local offset = Vector3.new(math.noise(t, 21.1), math.noise(t, 29.9), 0) * 0.7 * amount
	return CFrame.new(offset) * CFrame.Angles(pitch, yaw, roll)
end

local function updateFlightCamera(dt: number)
	local f = flight :: { root: BasePart, target: Vector3, forward: Vector3 }
	local rootPosition = f.root.Position
	local desiredPosition = rootPosition - f.forward * C.FlightDistance + Vector3.yAxis * C.FlightHeight
	local lookAt = rootPosition:Lerp(f.target, 0.55)
	local desired = CFrame.lookAt(desiredPosition, lookAt)
	local alpha = 1 - math.exp(-dt * 10)
	flightCFrame = (flightCFrame or desired):Lerp(desired, alpha)
	camera.CFrame = flightCFrame :: CFrame
end

local function updateImpactCamera()
	local shot = impactShot :: { point: Vector3, normal: Vector3, start: number, duration: number }
	local t = math.clamp((os.clock() - shot.start) / shot.duration, 0, 1)
	local eased = 1 - (1 - t) ^ 3
	local side = shot.normal:Cross(Vector3.yAxis).Unit
	local distance = 92 - 22 * eased
	local position = shot.point + shot.normal * distance + Vector3.yAxis * (16 - 6 * eased) + side * (22 - 10 * eased)
	camera.CFrame = CFrame.lookAt(position, shot.point)
end

function CameraController.init()
	RunService:BindToRenderStep("SprintSlamCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		clock += dt
		camera = workspace.CurrentCamera
		trauma = math.max(trauma - dt * 1.7, 0)
		fovKick = math.max(fovKick - dt * 24, 0)

		local fovTarget = targetFov()
		if mode == "Flight" then
			fovTarget = C.MaxFov
		elseif mode == "Impact" then
			fovTarget = C.BaseFov - 6
		end
		currentFov += (fovTarget - currentFov) * (1 - math.exp(-dt * 7))
		camera.FieldOfView = currentFov + fovKick

		if mode == "Flight" and flight then
			updateFlightCamera(dt)
		elseif mode == "Impact" and impactShot then
			updateImpactCamera()
		end
		camera.CFrame *= shakeOffset()
	end)
end

return CameraController
