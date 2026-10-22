--!strict
-- Server-side view of one run, built only from replicated root positions sampled at a
-- fixed rate. Detects gate crossings, the launch, the impact plane, and implausible motion.
-- Nothing in here trusts a number sent by the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)

local V = Config.Validation

type Sample = { t: number, p: Vector3 }

export type Event = {
	Type: string, -- "Checkpoint" | "Shortcut" | "Launch" | "Impact"
	Time: number,
	Index: number?,
	Name: string?,
	Point: Vector3?,
	Speed: number?,
}

local RunValidator = {}
RunValidator.__index = RunValidator

export type RunValidator = typeof(setmetatable(
	{} :: {
		course: any,
		samples: { Sample },
		strikes: number,
		invalidReason: string?,
		nextCheckpoint: number,
		shortcutsHit: { [string]: boolean },
		expectNear: { Vector3 }?,
		expectDeadline: number,
	},
	RunValidator
))

function RunValidator.new(course: any): RunValidator
	local self = setmetatable({
		course = course,
		samples = {},
		strikes = 0,
		invalidReason = nil,
		nextCheckpoint = 2,
		shortcutsHit = {},
		expectNear = nil,
		expectDeadline = 0,
	}, RunValidator)
	return self
end

function RunValidator.reset(self: RunValidator)
	table.clear(self.samples)
	self.strikes = 0
	self.invalidReason = nil
	self.nextCheckpoint = 2
	table.clear(self.shortcutsHit)
	self.expectNear = nil
end

function RunValidator.invalidate(self: RunValidator, reason: string)
	if not self.invalidReason then
		self.invalidReason = reason
	end
end

-- The client teleports itself (restart/respawn). Until a sample lands near one of these
-- points we skip motion checks; if none does before the deadline the run is invalid.
function RunValidator.expectTeleport(self: RunValidator, positions: { Vector3 }, now: number)
	self.expectNear = positions
	self.expectDeadline = now + 2.5
	table.clear(self.samples)
end

function RunValidator.isTeleportPending(self: RunValidator): boolean
	return self.expectNear ~= nil
end

function RunValidator.latest(self: RunValidator): Sample?
	return self.samples[#self.samples]
end

-- Average velocity over roughly the last `window` seconds ending at the newest sample.
function RunValidator.windowVelocity(self: RunValidator, window: number): Vector3?
	local samples = self.samples
	local newest = samples[#samples]
	if not newest then
		return nil
	end
	for i = #samples - 1, 1, -1 do
		local sample = samples[i]
		if newest.t - sample.t >= window or i == 1 then
			local dt = newest.t - sample.t
			if dt < window * 0.5 then
				return nil
			end
			return (newest.p - sample.p) / dt
		end
	end
	return nil
end

function RunValidator.wasNear(self: RunValidator, points: { Vector3 }, now: number, distance: number, lookback: number): boolean
	local samples = self.samples
	for i = #samples, 1, -1 do
		local sample = samples[i]
		if now - sample.t > lookback then
			break
		end
		for _, point in points do
			if (sample.p - point).Magnitude <= distance then
				return true
			end
		end
	end
	return false
end

function RunValidator.allCheckpointsReached(self: RunValidator): boolean
	return self.nextCheckpoint > #self.course.Checkpoints
end

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function RunValidator.sample(self: RunValidator, now: number, position: Vector3, phase: string): { Event }
	local events: { Event } = {}

	if self.expectNear then
		local arrived = false
		for _, point in self.expectNear do
			if (position - point).Magnitude <= V.RespawnTolerance then
				arrived = true
				break
			end
		end
		if arrived then
			self.expectNear = nil
			table.clear(self.samples)
		else
			if now > self.expectDeadline then
				self.expectNear = nil
				self:invalidate("teleport mismatch")
			end
			return events
		end
	end

	local samples = self.samples
	local previous = samples[#samples]
	table.insert(samples, { t = now, p = position })
	if #samples > V.SampleBuffer then
		table.remove(samples, 1)
	end
	if not previous then
		return events
	end

	if (position - previous.p).Magnitude > V.MaxSampleJump then
		self:invalidate("teleport")
	end

	local velocity = self:windowVelocity(V.SpeedWindow)
	if velocity then
		local implausible
		if phase == "Flight" then
			implausible = velocity.Magnitude > V.MaxFlightSpeed
		else
			implausible = horizontal(velocity).Magnitude > V.MaxRunSpeed or velocity.Y > V.MaxRiseSpeed
		end
		if implausible then
			self.strikes += 1
			if self.strikes >= V.SpeedStrikesToInvalidate then
				self:invalidate("speed")
			end
		end
	end

	local course = self.course
	if phase == "Running" then
		local gate = course.Checkpoints[self.nextCheckpoint]
		if gate and Geometry.segmentIntersectsBox(previous.p, position, gate.CFrame, gate.Size) then
			table.insert(events, { Type = "Checkpoint", Time = now, Index = self.nextCheckpoint })
			self.nextCheckpoint += 1
		end

		for _, shortcut in course.ShortcutGates do
			if not self.shortcutsHit[shortcut.Name] and Geometry.segmentIntersectsBox(previous.p, position, shortcut.CFrame, shortcut.Size) then
				self.shortcutsHit[shortcut.Name] = true
				table.insert(events, { Type = "Shortcut", Time = now, Name = shortcut.Name })
			end
		end

		local launch = course.Launch
		local point, fraction = Geometry.planeCrossing(previous.p, position, launch.Position, -launch.Forward)
		if point and fraction then
			local offset = point - launch.Position
			local lateral = offset - launch.Forward * offset:Dot(launch.Forward)
			lateral = Vector3.new(lateral.X, 0, lateral.Z)
			if lateral.Magnitude <= launch.HalfWidth and math.abs(offset.Y) <= launch.HeightRange then
				local approach = self:windowVelocity(V.LaunchApproachWindow)
				table.insert(events, {
					Type = "Launch",
					Time = previous.t + (now - previous.t) * fraction,
					Point = point,
					Speed = if approach then horizontal(approach).Magnitude else 0,
				})
			end
		end
	elseif phase == "Flight" then
		local target = course.Target
		local planePoint = target.Center + target.Normal * Config.Slam.TriggerOffset
		local point, fraction = Geometry.planeCrossing(previous.p, position, planePoint, target.Normal)
		if point and fraction then
			local impactVelocity = self:windowVelocity(0.3)
			table.insert(events, {
				Type = "Impact",
				Time = previous.t + (now - previous.t) * fraction,
				Point = point,
				Speed = if impactVelocity then impactVelocity.Magnitude else 0,
			})
		end
	end

	return events
end

-- Used when the client reports an impact the samples have not shown yet: project the
-- newest motion onto the impact plane if it is close enough to be believable.
function RunValidator.extrapolateImpact(self: RunValidator): (Vector3?, number?)
	local newest = self:latest()
	local velocity = self:windowVelocity(0.3)
	if not newest or not velocity then
		return nil, nil
	end
	local target = self.course.Target
	local planePoint = target.Center + target.Normal * Config.Slam.TriggerOffset
	local distance = Geometry.signedDistance(newest.p, planePoint, target.Normal)
	local closing = -velocity:Dot(target.Normal)
	if distance < 0 or distance > V.ImpactExtrapolate or closing <= 1 then
		return nil, nil
	end
	return newest.p + velocity * (distance / closing), velocity.Magnitude
end

return RunValidator
