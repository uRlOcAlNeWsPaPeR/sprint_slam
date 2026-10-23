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
local BoardService = require(Services.BoardService)
local Weeks = require(ReplicatedStorage.Shared.Weeks)

WorldSetup.init()
Net.init()
local lobby = LobbyManager.build()
local week, courses = CourseManager.build()
WalletService.init()
ProgressService.init(week.Id, #courses)
BoardService.init()
RunSessionService.init(week, courses, lobby)

-- Weeks that ended since the last server started go into the Hall of Fame.
task.spawn(function()
	BoardService.finalizePastWeeks(Weeks.finishedBefore(os.time()))
end)

print(`[SprintSlam] Server ready: {week.Title}, {#courses} challenges`)
