--!strict
-- Dash: cooldown-gated burst. Dashing within the chain window of a boost pad or ring (in
-- either order) is a BOOST CHAIN: extra speed and combo points. Pads and rings refresh it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local MovementController = require(script.Parent.MovementController)
local Sfx = require(script.Parent.Sfx)

local D = Config.Dash

local DashController = {}

DashController.Combo = Signal.new()

local cooldownUntil = 0
local lastDashTime = -math.huge
local lastBoostTime = -math.huge
local chainedPair = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function chain()
	chainedPair = true
	MovementController.applyBoost(D.BoostChainBonus)
	CameraController.kick(D.BoostChainBonus * 0.6)
	CameraController.shake(0.25)
	EffectsController.boost()
	DashController.Combo:Fire("BoostChain")
end

function DashController.reset()
	cooldownUntil = 0
	lastDashTime = -math.huge
	lastBoostTime = -math.huge
	chainedPair = false
end

-- Ground/air dash while running. Returns false if on cooldown.
function DashController.tryDash(): boolean
	local t = now()
	if t < cooldownUntil then
		return false
	end
	cooldownUntil = t + D.Cooldown
	lastDashTime = t
	chainedPair = false
	local airborne = MovementController.applyDash()
	CameraController.kick()
	CameraController.shake(0.18)
	EffectsController.dash()
	Sfx.play("Dash")
	if t - lastBoostTime <= D.BoostChainWindow then
		chain()
	end
	if airborne then
		DashController.Combo:Fire("AirDash")
	end
	return true
end

-- Called by the course when a pad or ring fires.
function DashController.notifyBoost()
	local t = now()
	lastBoostTime = t
	cooldownUntil = 0
	if not chainedPair and t - lastDashTime <= D.BoostChainWindow then
		chain()
	end
end

-- 0 = just used, 1 = ready.
function DashController.getReadiness(): number
	local remaining = cooldownUntil - now()
	if remaining <= 0 then
		return 1
	end
	return 1 - remaining / D.Cooldown
end

return DashController
