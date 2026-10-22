--!strict
-- Local-only speed feedback: shoulder trails, screen-edge speed streaks, dash/boost bursts.
-- Everything is created once and toggled, so nothing allocates per frame.

local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local EffectsController = {}

local Palette = Config.Palette
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local STREAK_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local trails: { Trail } = {}
local burst: ParticleEmitter? = nil
local streakEmitters: { ParticleEmitter } = {}
local streakParts: { { part: BasePart, offset: CFrame } } = {}
local accentUntil = 0
local lowQuality = false

local function colorSequence(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

local function detectQuality()
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		lowQuality = level.Value <= 3
	end
end

local function makeStreaks()
	local folder = Instance.new("Folder")
	folder.Name = "SpeedStreaks"
	folder.Parent = workspace.CurrentCamera
	-- Four emitters framing the screen edges keep the center (the runner) clear.
	local layout = {
		{ CFrame.new(-15, 0, -16), Vector3.new(8, 20, 4) },
		{ CFrame.new(15, 0, -16), Vector3.new(8, 20, 4) },
		{ CFrame.new(0, 9.5, -16), Vector3.new(30, 5, 4) },
		{ CFrame.new(0, -9.5, -16), Vector3.new(30, 5, 4) },
	}
	for _, entry in layout do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = entry[2]
		part.Parent = folder
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = STREAK_TEXTURE
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.LockedToPart = true
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
		emitter.Speed = NumberRange.new(70, 100)
		emitter.Lifetime = NumberRange.new(0.14, 0.22)
		emitter.Size = NumberSequence.new(0.09)
		emitter.Squash = NumberSequence.new(2.6)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 1
		emitter.Color = ColorSequence.new(Palette.White)
		emitter.Rate = 0
		emitter.Parent = part
		table.insert(streakEmitters, emitter)
		table.insert(streakParts, { part = part, offset = entry[1] })
	end
end

function EffectsController.bindCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- Two thin ribbons off the shoulders read as speed without hiding the course ahead.
	table.clear(trails)
	for _, side in { -1, 1 } do
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(side * 1.05, 0.7, 0.2)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(side * 1.05, 0.35, 0.2)
		bottom.Parent = root

		local newTrail = Instance.new("Trail")
		newTrail.Attachment0 = top
		newTrail.Attachment1 = bottom
		newTrail.Lifetime = 0.12
		newTrail.MinLength = 0.05
		newTrail.FaceCamera = true
		newTrail.LightEmission = 1
		newTrail.Color = colorSequence(Palette.Cyan, Palette.White)
		newTrail.Transparency = NumberSequence.new(0.2, 1)
		newTrail.WidthScale = NumberSequence.new(1, 0)
		newTrail.Enabled = false
		newTrail.Parent = root
		table.insert(trails, newTrail)
	end

	local emitterAttachment = Instance.new("Attachment")
	emitterAttachment.Name = "BurstAttachment"
	emitterAttachment.Parent = root
	local newBurst = Instance.new("ParticleEmitter")
	newBurst.Texture = SPARK_TEXTURE
	newBurst.Rate = 0
	newBurst.Speed = NumberRange.new(14, 30)
	newBurst.SpreadAngle = Vector2.new(180, 180)
	newBurst.Lifetime = NumberRange.new(0.25, 0.45)
	newBurst.Size = NumberSequence.new(0.6, 0)
	newBurst.LightEmission = 1
	newBurst.Drag = 6
	newBurst.Parent = emitterAttachment
	burst = newBurst
end

local function emitBurst(color: Color3, count: number)
	if not burst then
		return
	end
	burst.Color = ColorSequence.new(color)
	burst:Emit(if lowQuality then math.ceil(count / 3) else count)
end

function EffectsController.dash()
	accentUntil = os.clock() + 0.45
	emitBurst(Palette.Cyan, 26)
end

function EffectsController.boost()
	accentUntil = os.clock() + 0.35
	emitBurst(Palette.Orange, 20)
end

function EffectsController.burst(color: Color3, count: number)
	emitBurst(color, count)
end

-- Called every frame with the runner's actual horizontal speed.
function EffectsController.update(speed: number, dashing: boolean)
	local accent = os.clock() < accentUntil
	local trailOn = speed >= Config.Effects.TrailMinSpeed or dashing or accent
	local trailColor = if accent or dashing then colorSequence(Palette.Orange, Palette.White) else colorSequence(Palette.Cyan, Palette.White)
	for _, trail in trails do
		trail.Enabled = trailOn
		trail.Color = trailColor
	end

	local intensity = math.clamp((speed - Config.Effects.StreakMinSpeed) / (Config.Movement.OverspeedCap - Config.Effects.StreakMinSpeed), 0, 1)
	if accent then
		intensity = math.max(intensity, 0.8)
	end
	local rate = intensity * (if lowQuality then 25 else 90)
	for _, emitter in streakEmitters do
		emitter.Rate = rate
	end
end

function EffectsController.init()
	detectQuality()
	makeStreaks()
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		for _, entry in streakParts do
			entry.part.CFrame = camera.CFrame * entry.offset
		end
	end)
end

function EffectsController.isLowQuality(): boolean
	return lowQuality
end

return EffectsController
