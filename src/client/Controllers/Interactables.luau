--!strict
-- Boost pads, jump pads, boost rings and moving obstacles for one world (course or hub).
-- Obstacles are animated from server time, identically on every client; contacts come from
-- the world's data, not Touched events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)

local CameraController = require(script.Parent.CameraController)
local DashController = require(script.Parent.DashController)
local EffectsController = require(script.Parent.EffectsController)
local MovementController = require(script.Parent.MovementController)
local Sfx = require(script.Parent.Sfx)

local PAD_MARGIN = Vector3.new(0.5, 3.5, 0.5)

local Interactables = {}
Interactables.__index = Interactables

export type Interactables = typeof(setmetatable(
	{} :: {
		data: any,
		obstacleParts: { [number]: BasePart },
		padCooldowns: { [number]: number },
		jumpPadCooldowns: { [number]: number },
		lastBonk: number,
		level: number,
		onEvent: (eventType: string) -> (),
	},
	Interactables
))

-- `worldRoot` is the built folder (workspace.Course / workspace.Lobby); `onEvent` receives
-- combo event names ("BoostPad", "BoostRing").
function Interactables.new(data: any, worldRoot: Instance, onEvent: ((string) -> ())?): Interactables
	local obstacleParts = {}
	local folder = worldRoot:WaitForChild("Obstacles")
	for index = 1, #(data.MovingObstacles or {}) do
		obstacleParts[index] = folder:WaitForChild("Obstacle" .. index) :: BasePart
	end
	return setmetatable({
		data = data,
		obstacleParts = obstacleParts,
		padCooldowns = {},
		jumpPadCooldowns = {},
		lastBonk = -math.huge,
		level = 1,
		onEvent = onEvent or function() end,
	}, Interactables)
end

-- Obstacles retired on later levels (UntilLevel) stop colliding there.
function Interactables.setLevel(self: Interactables, level: number)
	self.level = level
end

function Interactables.reset(self: Interactables)
	table.clear(self.padCooldowns)
	table.clear(self.jumpPadCooldowns)
end

function Interactables.animate(self: Interactables, t: number)
	for index, def in self.data.MovingObstacles or {} do
		local part = self.obstacleParts[index]
		if part then
			local phase = (t / def.Period + def.Phase) * math.pi * 2
			part.CFrame = def.CFrame + def.Axis * (math.sin(phase) * def.Amplitude)
		end
	end
end

local function padBox(position: Vector3, forward: Vector3): CFrame
	return CFrame.lookAt(position + Vector3.yAxis * 2, position + Vector3.yAxis * 2 + forward)
end

function Interactables.checkPads(self: Interactables, position: Vector3, t: number)
	for index, pad in self.data.BoostPads or {} do
		if (self.padCooldowns[index] or 0) <= t then
			if Geometry.pointInBox(position, padBox(pad.Position, pad.Forward), Vector3.new(pad.Size.X, 4, pad.Size.Z), PAD_MARGIN) then
				self.padCooldowns[index] = t + Config.Course.BoostPadRetrigger
				MovementController.applyBoost(Config.Course.BoostPadSpeed)
				DashController.notifyBoost()
				EffectsController.boost()
				CameraController.kick(6)
				CameraController.shake(0.15)
				Sfx.play("Boost")
				self.onEvent("BoostPad")
			end
		end
	end

	for index, pad in self.data.JumpPads or {} do
		if (self.jumpPadCooldowns[index] or 0) <= t then
			if Geometry.pointInBox(position, padBox(pad.Position, pad.Forward), Vector3.new(pad.Size.X, 4, pad.Size.Z), PAD_MARGIN) then
				self.jumpPadCooldowns[index] = t + Config.Course.JumpPadRetrigger
				MovementController.launchUp(pad.UpVelocity, pad.MinForwardSpeed, pad.Forward)
				EffectsController.burst(Config.Palette.Cyan, 24)
				CameraController.shake(0.2)
				Sfx.play("Boost", 0.6, 1.2)
			end
		end
	end
end

function Interactables.checkRings(self: Interactables, previous: Vector3, position: Vector3)
	for _, ring in self.data.BoostRings or {} do
		local point = Geometry.planeCrossing(previous, position, ring.Position, ring.Normal)
		if point and (point - ring.Position).Magnitude <= ring.Radius + 1 then
			MovementController.applyBoost(Config.Course.BoostRingSpeed)
			DashController.notifyBoost()
			EffectsController.boost()
			CameraController.kick(10)
			CameraController.shake(0.25)
			Sfx.play("Boost", 0.7, 1.35)
			self.onEvent("BoostRing")
		end
	end
end

function Interactables.checkObstacles(self: Interactables, root: BasePart, position: Vector3, t: number)
	if t - self.lastBonk < Config.Movement.BonkCooldown then
		return
	end
	for index, def in self.data.MovingObstacles or {} do
		local part = self.obstacleParts[index]
		local retired = def.UntilLevel ~= nil and self.level > def.UntilLevel
		if part and not retired and Geometry.pointInBox(position, part.CFrame, def.Size, Vector3.new(1.4, 2.5, 1.4)) then
			self.lastBonk = t
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

-- All contact checks for one frame of movement from `previous` to the root's position.
function Interactables.update(self: Interactables, root: BasePart, previous: Vector3, t: number)
	local position = root.Position
	self:checkPads(position, t)
	self:checkRings(previous, position)
	self:checkObstacles(root, position, t)
end

return Interactables
