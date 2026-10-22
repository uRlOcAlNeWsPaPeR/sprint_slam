--!strict
-- Lighting, collision groups and player defaults for the neon arcade look.

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local WorldSetup = {}

WorldSetup.RunnerGroup = "Runners"

local function setLighting()
	Lighting.ClockTime = 19.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 78, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 106, 140)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(60, 80, 120)
	atmosphere.Decay = Color3.fromRGB(20, 22, 40)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.9
	bloom.Size = 28
	bloom.Threshold = 0.92
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Contrast = 0.12
	color.Saturation = 0.08
	color.TintColor = Color3.fromRGB(235, 242, 255)
	color.Parent = Lighting
end

local function setCollisionGroups()
	PhysicsService:RegisterCollisionGroup(WorldSetup.RunnerGroup)
	PhysicsService:CollisionGroupSetCollidable(WorldSetup.RunnerGroup, WorldSetup.RunnerGroup, false)
end

local function assignRunnerGroup(character: Model)
	local function apply(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = WorldSetup.RunnerGroup
		end
	end
	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	character.DescendantAdded:Connect(apply)
end

local function setPlayerDefaults()
	Players.RespawnTime = 1
	StarterPlayer.EnableMouseLockOption = false
	StarterPlayer.CharacterUseJumpPower = false
	StarterPlayer.CharacterJumpHeight = Config.Movement.JumpHeight
	StarterPlayer.CharacterWalkSpeed = Config.Movement.BaseSpeed
	StarterPlayer.AutoJumpEnabled = false
end

function WorldSetup.init()
	setLighting()
	setCollisionGroups()
	setPlayerDefaults()

	-- The course is built at runtime; template spawns/baseplates would fill the pits.
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
			child:Destroy()
		end
	end

	local function onPlayer(player: Player)
		player.DevEnableMouseLock = false
		player.CharacterAdded:Connect(assignRunnerGroup)
		if player.Character then
			assignRunnerGroup(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return WorldSetup
