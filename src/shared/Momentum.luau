--!strict
-- Momentum: average horizontal speed over the whole run (distance ÷ time since GO).
-- Shared by the client (HUD, launch) and server (from its own position samples), so both
-- turn a run into the same launch and impact speed.

local Config = require(script.Parent.Config)

local Momentum = {}
Momentum.__index = Momentum

export type Momentum = typeof(setmetatable({} :: { distance: number, elapsed: number }, Momentum))

function Momentum.new(): Momentum
	return setmetatable({ distance = 0, elapsed = 0 }, Momentum)
end

function Momentum.add(self: Momentum, distance: number, dt: number)
	self.distance += distance
	self.elapsed += dt
end

function Momentum.value(self: Momentum): number
	if self.elapsed <= 0 then
		return 0
	end
	return self.distance / self.elapsed
end

-- Launch speed off the lip for a given momentum.
function Momentum.launchSpeed(momentum: number): number
	return math.clamp(momentum * Config.Momentum.LaunchScale, Config.Slam.MinLaunchSpeed, Config.Slam.MaxLaunchSpeed)
end

-- Speed driving into the wall: the launch's horizontal part, plus any Slam Dash bonus.
-- Gravity and steering act along the wall, so they never change it.
function Momentum.impactSpeed(launchSpeed: number, slamDashBonus: number?): number
	return launchSpeed * math.cos(math.rad(Config.Slam.LaunchPitchDeg)) * (1 + (slamDashBonus or 0))
end

return Momentum
