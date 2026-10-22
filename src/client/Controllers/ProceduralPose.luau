--!strict
-- Code-driven poses layered over the default animations by writing Motor6D.Transform after
-- the Animator runs (PreSimulation). Phase 2 replaces these with authored animations.

local RunService = game:GetService("RunService")

local ProceduralPose = {}

local rad = math.rad

-- R15 joint name → Transform for each pose.
local POSES: { [string]: { [string]: CFrame } } = {
	Slide = {
		Root = CFrame.Angles(rad(52), 0, 0),
		RightHip = CFrame.Angles(rad(34), 0, rad(-6)),
		LeftHip = CFrame.Angles(rad(8), 0, rad(8)),
		LeftKnee = CFrame.Angles(rad(-70), 0, 0),
		RightKnee = CFrame.identity,
		RightShoulder = CFrame.Angles(rad(-25), 0, rad(55)),
		LeftShoulder = CFrame.Angles(rad(-25), 0, rad(-55)),
	},
	Flight = {
		Root = CFrame.identity,
		RightShoulder = CFrame.Angles(rad(172), 0, rad(-8)),
		LeftShoulder = CFrame.Angles(rad(172), 0, rad(8)),
		RightElbow = CFrame.identity,
		LeftElbow = CFrame.identity,
		RightHip = CFrame.Angles(rad(-6), 0, 0),
		LeftHip = CFrame.Angles(rad(-10), 0, 0),
		RightKnee = CFrame.Angles(rad(-8), 0, 0),
		LeftKnee = CFrame.Angles(rad(-18), 0, 0),
	},
}

local BLEND_SPEED = 14

local motors: { [string]: Motor6D } = {}
local activePose: string? = nil
local lastPose: string? = nil
local weight = 0

function ProceduralPose.bindCharacter(character: Model)
	table.clear(motors)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	activePose = nil
	lastPose = nil
	weight = 0
end

function ProceduralPose.set(name: string?)
	if name then
		lastPose = name
	end
	activePose = name
end

function ProceduralPose.init()
	RunService.PreSimulation:Connect(function(dt)
		local targetWeight = if activePose then 1 else 0
		weight += (targetWeight - weight) * math.min(1, dt * BLEND_SPEED)
		if weight < 0.01 or not lastPose then
			return
		end
		local pose = POSES[lastPose]
		for jointName, transform in pose do
			local motor = motors[jointName]
			if motor then
				motor.Transform = motor.Transform:Lerp(transform, weight)
			end
		end
	end)
end

return ProceduralPose
