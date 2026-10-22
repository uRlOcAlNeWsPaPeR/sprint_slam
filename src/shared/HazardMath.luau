--!strict
-- Pure timing/geometry for level hazards. Everything is a function of server time, so all
-- clients (and the server's anti-cheat) agree on where spinners are and which lasers and
-- blink floors are live.
--
-- Hazard types:
--   Kill    static death block: touch = respawn at the last checkpoint
--   Laser   kill bar that blinks on/off (Period, OnFraction, Phase)
--   Spinner floor-level bar rotating about Center (Speed rad/s); contact knocks you away
--   Blink   floor segment that blinks solid/void (Period, OnFraction, Phase)

local HazardMath = {}

-- A def applies to a level if it was introduced at or before it and not retired yet.
function HazardMath.activeForLevel(def: any, level: number): boolean
	local from = def.Level or 1
	local untilLevel = def.UntilLevel or math.huge
	return level >= from and level <= untilLevel
end

-- 0..1 position within the current cycle.
function HazardMath.cycle(def: any, t: number): number
	return (t / def.Period + (def.Phase or 0)) % 1
end

-- Lasers and blink floors share timing: "on" for the first OnFraction of each cycle.
function HazardMath.isOn(def: any, t: number): boolean
	return HazardMath.cycle(def, t) < def.OnFraction
end

-- Seconds until the current state flips.
function HazardMath.timeToFlip(def: any, t: number): number
	local c = HazardMath.cycle(def, t)
	if c < def.OnFraction then
		return (def.OnFraction - c) * def.Period
	end
	return (1 - c) * def.Period
end

function HazardMath.spinnerAngle(def: any, t: number): number
	return t * def.Speed + (def.Phase or 0)
end

-- CFrame of a spinner's bar (its long axis is local X).
function HazardMath.spinnerCFrame(def: any, t: number): CFrame
	return CFrame.new(def.Center + Vector3.new(0, def.Height, 0)) * CFrame.Angles(0, HazardMath.spinnerAngle(def, t), 0)
end

function HazardMath.spinnerSize(def: any): Vector3
	return Vector3.new(def.Length, def.Thickness, def.Thickness)
end

return HazardMath
