--!strict
-- Client bootstrap. One ordered update loop drives gameplay; it runs right after the
-- default ControlModule so our Humanoid:Move call wins each frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Courses = require(Shared:WaitForChild("Courses"))
local Lobby = require(Shared:WaitForChild("Lobby"))
local Weeks = require(Shared:WaitForChild("Weeks"))

local Controllers = script.Parent:WaitForChild("Controllers")
local InputController = require(Controllers.InputController)
local CameraController = require(Controllers.CameraController)
local EffectsController = require(Controllers.EffectsController)
local ProceduralPose = require(Controllers.ProceduralPose)
local LobbyController = require(Controllers.LobbyController)
local SlamController = require(Controllers.SlamController)
local UIController = require(Controllers.UIController)
local ChallengeMenu = require(Controllers.ChallengeMenu)
local RunController = require(Controllers.RunController)

-- The server publishes which week is live before players load in; the ten courses are then
-- rebuilt here from the same shared recipes the server used.
while ReplicatedStorage:GetAttribute("ActiveWeek") == nil do
	ReplicatedStorage:GetAttributeChangedSignal("ActiveWeek"):Wait()
end
local week = Weeks.get(ReplicatedStorage:GetAttribute("ActiveWeek"))
local courses = Courses.forWeek(week)

InputController.init()
CameraController.init()
EffectsController.init()
ProceduralPose.init()
LobbyController.init(Lobby)
SlamController.init()
UIController.init(courses)
ChallengeMenu.init(week, courses)
RunController.init(week, courses, Lobby)

-- Gameplay normally updates every rendered frame. If rendering stalls (an occluded or
-- backgrounded window), the physics tick keeps the game running so timers, hazards and
-- runs never freeze.
local lastRender = os.clock()
local lastTick = os.clock()

RunService:BindToRenderStep("SprintSlamUpdate", Enum.RenderPriority.Input.Value + 1, function(dt)
	lastRender = os.clock()
	lastTick = lastRender
	RunController.update(math.min(dt, 0.1))
end)

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	if t - lastRender > 0.25 then
		local dt = math.min(t - lastTick, 0.1)
		lastTick = t
		RunController.update(dt)
	end
end)
