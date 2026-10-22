--!strict
-- Client bootstrap. One ordered update loop drives gameplay; it runs right after the
-- default ControlModule so our Humanoid:Move call wins each frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Courses = require(Shared:WaitForChild("Courses"))
local Lobby = require(Shared:WaitForChild("Lobby"))

local Controllers = script.Parent:WaitForChild("Controllers")
local InputController = require(Controllers.InputController)
local CameraController = require(Controllers.CameraController)
local EffectsController = require(Controllers.EffectsController)
local ProceduralPose = require(Controllers.ProceduralPose)
local CourseController = require(Controllers.CourseController)
local LobbyController = require(Controllers.LobbyController)
local SlamController = require(Controllers.SlamController)
local UIController = require(Controllers.UIController)
local RunController = require(Controllers.RunController)

-- The server publishes which course is live before players load in.
while ReplicatedStorage:GetAttribute("ActiveCourse") == nil do
	ReplicatedStorage:GetAttributeChangedSignal("ActiveCourse"):Wait()
end
local course = Courses.get(ReplicatedStorage:GetAttribute("ActiveCourse"))

InputController.init()
CameraController.init()
EffectsController.init()
ProceduralPose.init()
CourseController.init(course)
LobbyController.init(Lobby)
SlamController.init(course)
UIController.init(course)
RunController.init(course, Lobby)

RunService:BindToRenderStep("SprintSlamUpdate", Enum.RenderPriority.Input.Value + 1, function(dt)
	RunController.update(math.min(dt, 0.1))
end)
