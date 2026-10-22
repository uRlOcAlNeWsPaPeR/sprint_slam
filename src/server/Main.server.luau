--!strict
-- Server bootstrap: world → remotes → course → run sessions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Services = script.Parent.Services
local WorldSetup = require(Services.WorldSetup)
local CourseManager = require(Services.CourseManager)
local RunSessionService = require(Services.RunSessionService)
local WalletService = require(Services.WalletService)

WorldSetup.init()
Net.init()
WalletService.init()
local course = CourseManager.build()
RunSessionService.init(course)

print(`[SprintSlam] Server ready — course {course.Id}`)
