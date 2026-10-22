--!strict
-- Client run state machine. Predicts everything locally for instant feel (countdown,
-- timer, combos, impact) and defers to the server's RunState / RunResult for the truth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ComboTracker = require(Shared.ComboTracker)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CameraController = require(script.Parent.CameraController)
local CourseController = require(script.Parent.CourseController)
local DashController = require(script.Parent.DashController)
local DevAutopilot = require(script.Parent.DevAutopilot)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local ProceduralPose = require(script.Parent.ProceduralPose)
local SlamController = require(script.Parent.SlamController)
local Sfx = require(script.Parent.Sfx)
local UIController = require(script.Parent.UIController)

local RunController = {}

-- "Waiting" | "Countdown" | "Running" | "Flight" | "Impact" | "AwaitResult" | "Results"
local state = "Waiting"
local runId = 0
local goTime = math.huge
local roundTime = Config.Round.RoundTime
local checkpoint = 1
local launchTime: number? = nil
local frozenTimeLeft: number? = nil
local combo = ComboTracker.new()
local lastRestart = -math.huge
local impactAt = 0
local resultDeadline: number? = nil
local resultsShownAt = 0
local pendingResult: any = nil
local course: any = nil
local remotes: { [string]: RemoteEvent } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setState(newState: string)
	state = newState
end

local function enterCountdown()
	SlamController.cleanup()
	MovementController.setEnabled(false)
	MovementController.reset()
	DashController.reset()
	InputController.setMovementEnabled(false)
	CourseController.resetRun()
	combo = ComboTracker.new()
	checkpoint = 1
	launchTime = nil
	frozenTimeLeft = nil
	pendingResult = nil
	resultDeadline = nil
	UIController.resetRun()
	DevAutopilot.reset()
	UIController.showCountdown(goTime)
	setState("Countdown")
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
	if payload.State == "Countdown" and isNewRun then
		enterCountdown()
	end
end

local function onCheckpoint(payload: any)
	if payload.RunId ~= runId then
		return
	end
	checkpoint = payload.Index
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
		"result: %s reason=%s speed=%s zone=%s time=+%s combo=+%s final=%s best=%s",
		tostring(b.Outcome), tostring(payload.Reason), tostring(b.ImpactSpeed), tostring(b.Zone),
		tostring(b.TimeBonus), tostring(b.ComboBonus), tostring(b.Final), tostring(payload.BestScore)
	))
	UIController.setFlight(false)
	UIController.showResults(payload)
	UIController.setBest(payload.BestScore)
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
	UIController.combo(def.Label, points, multiplier, combo.total)
end

function RunController.restart()
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

local function respawn()
	local respawnAt = course.Checkpoints[checkpoint].Respawn
	MovementController.teleport(respawnAt)
	CourseController.forgetPosition()
	remotes.RequestRespawn:FireServer(runId)
	CameraController.shake(0.3)
	UIController.toast("RESPAWN", Config.Palette.Orange, 0.7)
end

local function beginFlight(approachSpeed: number)
	if state ~= "Running" then
		return
	end
	launchTime = now()
	frozenTimeLeft = math.max(goTime + roundTime - launchTime, 0)
	setState("Flight")
	DevAutopilot.log(string.format("launch: approach %.1f st/s, %.2fs left", approachSpeed, frozenTimeLeft :: number))
	UIController.setSlamMode(true)
	UIController.setFlight(true)
	SlamController.begin(approachSpeed)
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

	if state == "Countdown" and t >= goTime then
		setState("Running")
		MovementController.setEnabled(true)
		InputController.setMovementEnabled(true)
		UIController.go()
		Sfx.play("Go")
	end

	local root = MovementController.getRoot()
	DevAutopilot.update(state)
	if state == "Running" and root then
		MovementController.update(dt)
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
		RunController.restart()
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
		local r = root
		speed = if r then r.AssemblyLinearVelocity.Magnitude else 0
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
		Progress = if inFlight or state == "Impact" or state == "Results" then 1 else distance / length,
		Prediction = if inFlight then SlamController.getPrediction() else nil,
	})
end

local function bindCharacter(character: Model)
	MovementController.bindCharacter(character)
	ProceduralPose.bindCharacter(character)
	EffectsController.bindCharacter(character)
	SlamController.cleanup()
end

function RunController.init(activeCourse: any)
	course = activeCourse
	DevAutopilot.init(activeCourse)
	for _, name in Net.Names do
		remotes[name] = Net.get(name)
	end
	remotes.RunState.OnClientEvent:Connect(onRunState)
	remotes.Checkpoint.OnClientEvent:Connect(onCheckpoint)
	remotes.RunResult.OnClientEvent:Connect(onRunResult)

	MovementController.Combo:Connect(onCombo)
	DashController.Combo:Connect(onCombo)
	CourseController.Combo:Connect(onCombo)
	SlamController.SlamDashed:Connect(function()
		onCombo("SlamDash")
	end)
	CourseController.Launched:Connect(beginFlight)
	CourseController.FellOut:Connect(respawn)
	SlamController.Impact:Connect(onImpact)

	InputController.Dash:Connect(function()
		if state == "Running" then
			DashController.tryDash()
		elseif state == "Flight" then
			SlamController.trySlamDash()
		end
	end)
	InputController.Slide:Connect(function()
		if state == "Running" then
			MovementController.trySlide()
		end
	end)
	InputController.Restart:Connect(RunController.restart)
	UIController.RestartClicked:Connect(RunController.restart)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

return RunController
