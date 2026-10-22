--!strict
-- Server bootstrap: world → remotes → hub + course → sessions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Services = script.Parent.Services
local WorldSetup = require(Services.WorldSetup)
local CourseManager = require(Services.CourseManager)
local LobbyManager = require(Services.LobbyManager)
local RunSessionService = require(Services.RunSessionService)
local WalletService = require(Services.WalletService)
local ProgressService = require(Services.ProgressService)

WorldSetup.init()
Net.init()
WalletService.init()
ProgressService.init()
local lobby = LobbyManager.build()
local course = CourseManager.build()
RunSessionService.init(course, lobby)

print(`[SprintSlam] Server ready — course {course.Id}`)
