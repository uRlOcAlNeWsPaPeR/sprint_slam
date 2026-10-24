--!strict
-- Client state machine for the hub and Sprint Slam runs. Predicts everything locally for
-- instant feel (countdown, timer, combos, impact) and defers to the server's RunState /
-- RunResult for the truth. The server decides when you are in the hub or in a run, and which
-- of the week's ten challenges (each its own course) a run is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ComboTracker = require(Shared.ComboTracker)
local Momentum = require(Shared.Momentum)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CameraController = require(script.Parent.CameraController)
local ChallengeMenu = require(script.Parent.ChallengeMenu)
local MusicController = require(script.Parent.MusicController)
local TitleScreen = require(script.Parent.TitleScreen)
local CourseController = require(script.Parent.CourseController)
local DashController = require(script.Parent.DashController)
local DevAutopilot = require(script.Parent.DevAutopilot)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local LobbyController = require(script.Parent.LobbyController)
local MovementController = require(script.Parent.MovementController)
local ProceduralPose = require(script.Parent.ProceduralPose)
local SlamController = require(script.Parent.SlamController)
local Sfx = require(script.Parent.Sfx)
local UIController = require(script.Parent.UIController)

local RunController = {}

-- "Waiting" | "Lobby" | "Countdown" | "Running" | "Flight" | "Impact" | "AwaitResult" | "Results"
local state = "Waiting"
local runId = 0
local goTime = math.huge
local roundTime = Config.Round.RoundTime
local checkpoint = 1
local launchTime: number? = nil
local frozenTimeLeft: number? = nil
local combo = ComboTracker.new()
local momentum = Momentum.new()
local lastRestart = -math.huge
local impactAt = 0
local resultDeadline: number? = nil
local resultsShownAt = 0
local pendingResult: any = nil
local course: any = nil
local week: any = nil
local courses: { any } = {}
local challenge = 1
-- Weekly progress as last reported by the server.
local lobbyLocked = false
local progress = { Cleared = 0, Unlocked = 1, AllCleared = false, Bests = {} :: { [string]: any } }
local remotes: { [string]: RemoteEvent } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setState(newState: string)
	state = newState
end

local function useCourse(newCourse: any)
	course = newCourse
	CourseController.setCourse(newCourse)
	SlamController.setCourse(newCourse)
	UIController.setCourse(newCourse)
	DevAutopilot.setCourse(newCourse)
end

local function enterCountdown()
	SlamController.cleanup()
	useCourse(courses[challenge])
	MovementController.setEnabled(false)
	-- Always start on the line at rest: entering from the pit (next level) or the hub would
	-- otherwise carry leftover velocity into the countdown and read as a false start.
	MovementController.teleport(course.Spawn)
	MovementController.reset()
	DashController.reset()
	InputController.setMovementEnabled(false)
	CourseController.resetRun()
	combo = ComboTracker.new()
	momentum = Momentum.new()
	checkpoint = 1
	launchTime = nil
	frozenTimeLeft = nil
	pendingResult = nil
	resultDeadline = nil
	UIController.resetRun()
	UIController.setRunLabel(challenge, course)
	UIController.setMode("Run")
	MusicController.setScene("Run")
	UIController.showLevelIntro(challenge, course)
	DevAutopilot.reset()
	UIController.showCountdown(goTime)
	setState("Countdown")
end

-- In the hub you move freely with the full movement kit; no timer, no scoring.
local function enterLobby()
	DevAutopilot.log("entering the hub (state was " .. state .. ")")
	SlamController.cleanup()
	MovementController.reset()
	MovementController.setEnabled(true)
	InputController.setMovementEnabled(true)
	DashController.reset()
	LobbyController.reset()
	pendingResult = nil
	resultDeadline = nil
	frozenTimeLeft = nil
	UIController.resetRun()
	UIController.setMode("Lobby")
	MusicController.setScene("Hub")
	DevAutopilot.reset()
	setState("Lobby")
end

local function onRunState(payload: any)
	if typeof(payload) ~= "table" or payload.RunId < runId then
		return
	end
	local isNewRun = payload.RunId ~= runId
	runId = payload.RunId
	goTime = payload.GoTime
	roundTime = payload.RoundTime
	UIController.setBest(payload.BestScore)
	UIController.setCoins(payload.CoinBalance)
	challenge = payload.Challenge or challenge
	progress.Cleared = payload.Cleared or progress.Cleared
	progress.Unlocked = payload.Unlocked or progress.Unlocked
	progress.AllCleared = payload.AllCleared == true
	progress.Bests = payload.Bests or progress.Bests
	if ChallengeMenu.isOpen() then
		ChallengeMenu.open(progress)
	end
	if payload.State == "Countdown" and isNewRun then
		enterCountdown()
	elseif payload.State == "Lobby" and state ~= "Lobby" then
		enterLobby()
	end
end

local function onCheckpoint(payload: any)
	if payload.RunId ~= runId then
		return
	end
	checkpoint = payload.Index
	Sfx.play("Checkpoint", 0.35, 1.4)
	UIController.split(payload.Delta)
	DevAutopilot.log(string.format("checkpoint %d at %.2fs", payload.Index, payload.Split))
end

local function showResult(payload: any)
	pendingResult = nil
	resultDeadline = nil
	-- The server can end a run first (time up), so make sure the runner stops here too.
	frozenTimeLeft = frozenTimeLeft or math.max(goTime + roundTime - now(), 0)
	MovementController.setEnabled(false)
	InputController.setMovementEnabled(false)
	setState("Results")
	resultsShownAt = os.clock()
	local b = payload.Breakdown or {}
	DevAutopilot.log(string.format(
		"result C%s: %s reason=%s momentum=%s impact=%s power=%s zone=%s time=+%s combo=+%s final=%s coins=+%s best=%s",
		tostring(payload.Challenge), tostring(b.Outcome), tostring(payload.Reason), tostring(b.Momentum), tostring(b.ImpactSpeed),
		tostring(b.ImpactPower), tostring(b.Zone), tostring(b.TimeBonus), tostring(b.ComboBonus),
		tostring(b.Final), tostring(payload.Coins), tostring(payload.BestScore)
	))
	progress.Cleared = payload.Cleared or progress.Cleared
	progress.Unlocked = payload.Unlocked or progress.Unlocked
	progress.AllCleared = payload.AllCleared == true
	if payload.Challenge and (payload.BestScore or payload.BestTimeMs) then
		progress.Bests[tostring(payload.Challenge)] = { Score = payload.BestScore, TimeMs = payload.BestTimeMs }
	end
	if payload.TimeMs then
		DevAutopilot.log(string.format("run time %.2fs, cleared=%s newlyCleared=%s", payload.TimeMs / 1000, tostring(payload.Cleared), tostring(payload.NewlyCleared)))
	end
	UIController.setFlight(false)
	UIController.showResults(payload)
	UIController.setBest(payload.BestScore)
	if payload.CoinBalance then
		UIController.setCoins(payload.CoinBalance)
	end
	Sfx.play("Results")
end

local function onRunResult(payload: any)
	if payload.RunId ~= runId then
		return
	end
	-- Let the impact moment breathe before the panel covers it.
	local reveal = impactAt + (if SlamController.isActive() then 1.1 else 0)
	if os.clock() < reveal then
		pendingResult = payload
	else
		showResult(payload)
	end
end

local function onCombo(eventType: string)
	if state ~= "Running" and state ~= "Flight" then
		return
	end
	local points, multiplier = combo:add(eventType, now())
	if points <= 0 then
		return
	end
	remotes.ComboEvent:FireServer(runId, eventType)
	local def = Config.Combo.Events[eventType]
	Sfx.play("Combo", 0.3, 1.15 + (multiplier - 1) * 0.2)
	UIController.combo(def.Label, points, multiplier, combo.total)
end

function RunController.restart()
	if state == "Lobby" then
		local respawnAt = LobbyController.restartChallenge()
		if respawnAt then
			MovementController.teleport(respawnAt)
		end
		return
	end
	local t = now()
	if t - lastRestart < Config.Round.RestartCooldown or state == "Waiting" then
		return
	end
	lastRestart = t
	SlamController.cleanup()
	MovementController.setEnabled(false)
	MovementController.teleport(course.Spawn)
	CourseController.resetRun()
	UIController.hideResults()
	remotes.RequestRestart:FireServer()
end

-- Start (or switch to) one of the week's challenges; the server checks it is unlocked.
function RunController.chooseChallenge(chosen: number)
	if chosen < 1 or chosen > #courses then
		return
	end
	local unlocked = progress.AllCleared or chosen <= progress.Unlocked
	if not unlocked then
		UIController.toast("LOCKED - CLEAR CHALLENGE " .. tostring(chosen - 1) .. " FIRST", Config.Palette.Muted, 1.2)
		return
	end
	if state == "Lobby" and not ChallengeMenu.isOpen() then
		return
	end
	ChallengeMenu.close()
	remotes.RequestMode:FireServer("SprintSlam", chosen)
end

function RunController.nextChallenge()
	if state == "Results" and challenge < #courses and (progress.AllCleared or progress.Unlocked > challenge) then
		RunController.chooseChallenge(challenge + 1)
	end
end

function RunController.returnToLobby()
	if state ~= "Lobby" and state ~= "Waiting" then
		remotes.RequestMode:FireServer("Lobby")
	end
end

local function zapped(def: any, position: Vector3?, t: number?)
	if def and position and t then
		local on = if def.Period then require(ReplicatedStorage.Shared.HazardMath).isOn(def, t) else nil
		DevAutopilot.log(string.format(
			"zapped by %s at %s (hazard z=%.1f, on=%s, speed=%.0f, grounded=%s)",
			def.Type, tostring(position), def.CFrame.Position.Z, tostring(on), MovementController.getActualSpeed(), tostring(MovementController.isGrounded())
		) .. string.format(" sliding=%s", tostring(MovementController.isSliding())))
	end
	local respawnAt = course.Checkpoints[checkpoint].Respawn
	MovementController.teleport(respawnAt)
	CourseController.forgetPosition()
	remotes.RequestRespawn:FireServer(runId)
	CameraController.shake(0.6)
	Sfx.play("Zap", 0.8)
	EffectsController.burst(Config.Palette.Danger, 30)
	UIController.toast("ZAPPED!", Config.Palette.Danger, 0.8)
	DevAutopilot.resync()
	DevAutopilot.log(string.format("zapped; respawn at checkpoint %d", checkpoint))
end

local function respawn()
	local respawnAt = course.Checkpoints[checkpoint].Respawn
	MovementController.teleport(respawnAt)
	CourseController.forgetPosition()
	remotes.RequestRespawn:FireServer(runId)
	CameraController.shake(0.3)
	UIController.toast("RESPAWN", Config.Palette.Orange, 0.7)
	DevAutopilot.resync()
end

-- Launch speed comes from momentum (the whole run), not the speed at the lip.
local function beginFlight()
	if state ~= "Running" then
		return
	end
	launchTime = now()
	frozenTimeLeft = math.max(goTime + roundTime - launchTime, 0)
	setState("Flight")
	local runMomentum = momentum:value()
	DevAutopilot.log(string.format(
		"launch: momentum %.1f -> launch %.1f st/s, %.2fs left",
		runMomentum, Momentum.launchSpeed(runMomentum), frozenTimeLeft :: number
	))
	UIController.setSlamMode(true)
	UIController.setFlight(true)
	SlamController.begin(runMomentum)
end

local function onImpact(result: any)
	setState("Impact")
	DevAutopilot.log(string.format("impact: %.1f st/s, radius %.2f (%s)", result.Speed, result.Radius, result.Zone.Name))
	impactAt = os.clock()
	UIController.setFlight(false)
	remotes.ImpactClaim:FireServer(runId, {
		Point = result.Point,
		Speed = result.Speed,
		LaunchTime = launchTime or result.LaunchTime,
	})
	resultDeadline = os.clock() + Config.Round.ResultTimeout + 1.1
end

local function timeLeft(): number
	if frozenTimeLeft then
		return frozenTimeLeft
	end
	if state == "Countdown" or state == "Waiting" then
		return roundTime
	end
	return math.max(goTime + roundTime - now(), 0)
end

function RunController.update(dt: number)
	local t = now()
	CourseController.animate()
	LobbyController.animate()

	if state == "Countdown" and t >= goTime then
		setState("Running")
		MovementController.setEnabled(true)
		InputController.setMovementEnabled(true)
		UIController.go()
		Sfx.play("Go")
	end

	local root = MovementController.getRoot()
	DevAutopilot.update(state)
	if state == "Lobby" and root then
		-- The cover screen holds the player in place until they press PLAY.
		local locked = TitleScreen.isOpen()
		if locked ~= lobbyLocked then
			lobbyLocked = locked
			MovementController.setEnabled(not locked)
			InputController.setMovementEnabled(not locked)
		end
		MovementController.update(dt)
		LobbyController.update(root)
		if ChallengeMenu.isOpen() then
			ChallengeMenu.update()
			if not LobbyController.isInPortal() then
				ChallengeMenu.close()
			end
		end
	elseif state == "Running" and root then
		MovementController.update(dt)
		momentum:add(MovementController.getActualSpeed() * dt, dt)
		CourseController.update(root)
		local distance = CourseController.getProgress()
		UIController.setSlamMode(distance >= course.SlamModeDistance)
		if state == "Running" and t >= goTime + roundTime then
			frozenTimeLeft = 0
			setState("AwaitResult")
			MovementController.setEnabled(false)
			InputController.setMovementEnabled(false)
			UIController.toast("TIME UP", Config.Palette.Orange, 1.5)
			resultDeadline = os.clock() + Config.Round.ResultTimeout
		end
	elseif state == "Flight" then
		SlamController.update(dt)
	end

	if state == "Results" and DevAutopilot.shouldLoop() and os.clock() - resultsShownAt > 3 then
		if DevAutopilot.shouldAdvance() and challenge < #courses and (progress.AllCleared or progress.Unlocked > challenge) then
			resultsShownAt = math.huge -- one request per result
			RunController.nextChallenge()
		else
			RunController.restart()
		end
	end
	if pendingResult and os.clock() >= impactAt + 1.1 then
		showResult(pendingResult)
	end
	if resultDeadline and os.clock() > resultDeadline and (state == "Impact" or state == "AwaitResult") then
		resultDeadline = nil
		showResult({ RunId = runId, Breakdown = {}, Reason = "no response from server" })
	end

	-- HUD
	local speed = 0
	if state == "Flight" or state == "Impact" then
		speed = SlamController.getImpactSpeed()
	else
		speed = MovementController.getActualSpeed()
	end
	CameraController.setSpeed(speed)
	EffectsController.update(speed, MovementController.isDashing())
	local distance, length = CourseController.getProgress()
	local inFlight = state == "Flight"
	UIController.update({
		State = state,
		TimeLeft = timeLeft(),
		Speed = speed,
		DashReadiness = DashController.getReadiness(),
		SlamDashAvailable = SlamController.canSlamDash(),
		ComboMultiplier = combo:multiplier(t),
		ComboWindow = combo:windowRemaining(t),
		ComboTotal = combo.total,
		Momentum = momentum:value(),
		Progress = if inFlight or state == "Impact" or state == "Results" then 1 else distance / length,
		Prediction = if inFlight then SlamController.getPrediction() else nil,
		Challenge = if state == "Lobby" then LobbyController.getStatus() else nil,
	})
end

local function bindCharacter(character: Model)
	MovementController.bindCharacter(character)
	ProceduralPose.bindCharacter(character)
	EffectsController.bindCharacter(character)
	SlamController.cleanup()
end

function RunController.init(activeWeek: any, allCourses: { any }, activeLobby: any)
	week = activeWeek
	courses = allCourses
	course = allCourses[1]
	DevAutopilot.init(allCourses, activeLobby)
	for _, name in Net.Names do
		remotes[name] = Net.get(name)
	end
	remotes.RunState.OnClientEvent:Connect(onRunState)
	remotes.Checkpoint.OnClientEvent:Connect(onCheckpoint)
	remotes.RunResult.OnClientEvent:Connect(onRunResult)
	remotes.BoardData.OnClientEvent:Connect(function(data: any)
		ChallengeMenu.showBoard(data)
	end)
	remotes.HallOfFameData.OnClientEvent:Connect(function(list: any)
		ChallengeMenu.showHallOfFame(list)
		LobbyController.setHallOfFame(list, courses, ChallengeMenu.hallLines)
	end)
	ChallengeMenu.BoardRequested:Connect(function(index: number)
		remotes.RequestBoard:FireServer(index)
	end)
	ChallengeMenu.HallOfFameRequested:Connect(function()
		remotes.RequestHallOfFame:FireServer()
	end)
	ChallengeMenu.ChallengeChosen:Connect(RunController.chooseChallenge)
	-- The in-world Hall of Fame board loads once the hub is ready.
	task.delay(2, function()
		remotes.RequestHallOfFame:FireServer()
	end)

	MovementController.Combo:Connect(onCombo)
	DashController.Combo:Connect(onCombo)
	CourseController.Combo:Connect(onCombo)
	SlamController.SlamDashed:Connect(function()
		onCombo("SlamDash")
	end)
	CourseController.Launched:Connect(beginFlight)
	CourseController.FellOut:Connect(respawn)
	SlamController.Impact:Connect(onImpact)

	LobbyController.EnterRequested:Connect(function(mode: string)
		if state == "Lobby" and mode == "SprintSlam" then
			ChallengeMenu.open(progress)
		end
	end)
	InputController.LevelKey:Connect(function(chosen: number)
		if ChallengeMenu.isOpen() then
			RunController.chooseChallenge(chosen)
		end
	end)
	UIController.NextLevelClicked:Connect(RunController.nextChallenge)
	InputController.NextLevel:Connect(RunController.nextChallenge)
	CourseController.Zapped:Connect(zapped)
	LobbyController.FellOut:Connect(function(respawnAt: CFrame, challengeName: string?)
		MovementController.teleport(respawnAt)
		CameraController.shake(0.25)
		if challengeName then
			UIController.toast(challengeName .. "  -  TRY AGAIN", Config.Palette.Orange, 1)
			DevAutopilot.log("challenge " .. challengeName .. ": fell, retrying")
			DevAutopilot.restartRoute()
		end
	end)
	LobbyController.ChallengeFinished:Connect(function(name: string, time: number, best: number, isBest: boolean)
		local text = string.format("%s  %.2fs", name, time)
		if isBest then
			text ..= "  NEW BEST!"
		else
			text ..= string.format("  (BEST %.2fs)", best)
		end
		UIController.toast(text, if isBest then Config.Palette.Orange else Config.Palette.Cyan, 2.5)
		DevAutopilot.log(string.format("challenge %s finished in %.2fs", name, time))
		CameraController.shake(0.2)
		EffectsController.burst(Config.Palette.Orange, 30)
	end)

	InputController.Dash:Connect(function()
		if state == "Running" or state == "Lobby" then
			DashController.tryDash()
		elseif state == "Flight" then
			SlamController.trySlamDash()
		end
	end)
	InputController.Slide:Connect(function()
		if state == "Running" or state == "Lobby" then
			MovementController.trySlide()
		end
	end)
	InputController.Restart:Connect(RunController.restart)
	UIController.RestartClicked:Connect(RunController.restart)
	InputController.Lobby:Connect(RunController.returnToLobby)
	UIController.LobbyClicked:Connect(RunController.returnToLobby)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

return RunController
