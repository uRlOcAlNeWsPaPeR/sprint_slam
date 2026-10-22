--!strict
-- One run session per player: Countdown → Running → Flight → Finished, restartable at any
-- time. The server owns every state transition that affects score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local ComboTracker = require(Shared.ComboTracker)
local Net = require(Shared.Net)
local ScoreFormula = require(Shared.ScoreFormula)

local RunValidator = require(script.Parent.RunValidator)
local ScoreService = require(script.Parent.ScoreService)
local WalletService = require(script.Parent.WalletService)

local V = Config.Validation

local RunSessionService = {}

type Session = {
	player: Player,
	course: any,
	runId: number,
	state: string, -- "Idle" | "Countdown" | "Running" | "Flight" | "Finished"
	goTime: number,
	validator: RunValidator.RunValidator,
	combo: ComboTracker.ComboTracker,
	checkpoint: number,
	splits: { number },
	launch: { Time: number, Momentum: number }?,
	serverImpact: { Point: Vector3, Speed: number, Time: number }?,
	claim: { Point: Vector3, Speed: number, LaunchTime: number }?,
	resolveDeadline: number?,
	lastRestart: number,
	sampleClock: number,
}

local sessions: { [Player]: Session } = {}
local course: any
local remotes: { [string]: RemoteEvent } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function sendState(session: Session)
	local best = ScoreService.getBest(session.player)
	remotes.RunState:FireClient(session.player, {
		RunId = session.runId,
		State = session.state,
		GoTime = session.goTime,
		RoundTime = Config.Round.RoundTime,
		Checkpoint = session.checkpoint,
		BestScore = if best then best.Score else nil,
		BestSplits = if best then best.Splits else nil,
		CoinBalance = WalletService.get(session.player),
	})
end

local function startCountdown(session: Session, seconds: number, serverTeleport: boolean)
	local t = now()
	session.runId += 1
	session.state = "Countdown"
	session.goTime = t + seconds
	session.validator:reset()
	session.combo = ComboTracker.new(Config.Combo.ServerWindowSlack)
	session.checkpoint = 1
	session.splits = {}
	session.launch = nil
	session.serverImpact = nil
	session.claim = nil
	session.resolveDeadline = nil

	local spawn: CFrame = course.Spawn
	if serverTeleport and session.player.Character then
		session.player.Character:PivotTo(spawn)
	end
	session.validator:expectTeleport({ spawn.Position }, t)
	sendState(session)
end

local function finish(session: Session, breakdown: ScoreFormula.Breakdown, reason: string?)
	session.state = "Finished"
	session.resolveDeadline = nil
	local isNewBest = false
	local coins = 0
	if not reason and breakdown.Outcome == "Impact" then
		isNewBest = ScoreService.recordRun(session.player, breakdown, session.splits)
		coins = breakdown.Coins
		WalletService.award(session.player, coins)
	end
	local best = ScoreService.getBest(session.player)
	remotes.RunResult:FireClient(session.player, {
		RunId = session.runId,
		Breakdown = breakdown,
		Reason = reason,
		IsNewBest = isNewBest,
		BestScore = if best then best.Score else nil,
		Coins = coins,
		CoinBalance = WalletService.get(session.player),
	})
	sendState(session)
end

local function finishInvalid(session: Session, reason: string)
	finish(session, ScoreFormula.compute({ Outcome = "Invalid" }), reason)
end

local function resolveImpact(session: Session)
	local invalid = session.validator.invalidReason
	if invalid then
		finishInvalid(session, invalid)
		return
	end
	local launch = session.launch
	if not launch then
		finishInvalid(session, "no launch")
		return
	end
	local extrapolated = nil
	if not session.serverImpact and session.claim then
		local point, speed = session.validator:extrapolateImpact()
		if point and speed then
			extrapolated = { Point = point, Speed = speed }
		end
	end
	local breakdown, reason = ScoreService.scoreImpact({
		course = course,
		goTime = session.goTime,
		launch = launch,
		serverImpact = session.serverImpact,
		claim = session.claim,
		extrapolated = extrapolated,
		ping = session.player:GetNetworkPing(),
		comboBonus = session.combo.total,
	})
	if breakdown then
		finish(session, breakdown, nil)
	else
		finishInvalid(session, reason or "unverified")
	end
end

local function handleEvent(session: Session, event: RunValidator.Event)
	if event.Type == "Checkpoint" and session.state == "Running" then
		local index = event.Index :: number
		session.checkpoint = index
		local split = event.Time - session.goTime
		session.splits[index] = split
		local best = ScoreService.getBest(session.player)
		local bestSplit = best and best.Splits[index]
		remotes.Checkpoint:FireClient(session.player, {
			RunId = session.runId,
			Index = index,
			Split = split,
			Delta = if bestSplit then split - bestSplit else nil,
		})
	elseif event.Type == "Shortcut" and session.state == "Running" then
		ScoreService.tryCombo(session, "Shortcut", event.Time, true)
	elseif event.Type == "Launch" and session.state == "Running" then
		if not session.validator:allCheckpointsReached() then
			session.validator:invalidate("missed checkpoint")
		end
		if event.Time - session.goTime < V.MinRunTime then
			session.validator:invalidate("too fast")
		end
		-- Momentum = horizontal distance ÷ time since GO, from the server's own samples.
		local elapsed = math.max(event.Time - session.goTime, 0.1)
		session.state = "Flight"
		session.launch = { Time = event.Time, Momentum = session.validator.runDistance / elapsed }
		sendState(session)
	elseif event.Type == "Impact" and session.state == "Flight" then
		session.serverImpact = { Point = event.Point :: Vector3, Speed = event.Speed or 0, Time = event.Time }
		if session.claim then
			resolveImpact(session)
		else
			session.resolveDeadline = now() + V.ImpactWait
		end
	end
end

local function step(session: Session, dt: number)
	if session.state == "Idle" or session.state == "Finished" then
		return
	end
	local t = now()

	if session.state == "Countdown" and t >= session.goTime then
		if session.validator:isTeleportPending() then
			session.validator:invalidate("not at start")
		end
		session.state = "Running"
		sendState(session)
	end

	session.sampleClock += dt
	local root = rootOf(session.player)
	if root and session.sampleClock >= V.SampleInterval then
		session.sampleClock = 0
		if session.state == "Countdown" and not session.validator:isTeleportPending() then
			local offset = root.Position - course.Spawn.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > V.FalseStartDistance then
				session.validator:invalidate("false start")
			end
		end
		for _, event in session.validator:sample(t, root.Position, session.state) do
			handleEvent(session, event)
			if session.state == "Finished" then
				return
			end
		end
	end

	if session.state == "Running" and t > session.goTime + Config.Round.RoundTime + V.TimeGrace then
		finish(session, ScoreFormula.compute({ Outcome = "TimeUp" }), nil)
	elseif session.state == "Flight" then
		local launch = session.launch :: { Time: number, Momentum: number }
		if session.resolveDeadline and t >= session.resolveDeadline then
			resolveImpact(session)
		elseif t - launch.Time > Config.Slam.MaxFlightTime then
			resolveImpact(session)
		end
	end
end

local function onPlayerAdded(player: Player)
	local session: Session = {
		player = player,
		course = course,
		runId = 0,
		state = "Idle",
		goTime = 0,
		validator = RunValidator.new(course),
		combo = ComboTracker.new(Config.Combo.ServerWindowSlack),
		checkpoint = 1,
		splits = {},
		launch = nil,
		serverImpact = nil,
		claim = nil,
		resolveDeadline = nil,
		lastRestart = -math.huge,
		sampleClock = 0,
	}
	sessions[player] = session
	task.spawn(function()
		WalletService.load(player)
		if sessions[player] == session and session.state ~= "Idle" then
			sendState(session)
		end
	end)

	local function onCharacter(character: Model)
		character:WaitForChild("HumanoidRootPart")
		task.defer(startCountdown, session, Config.Round.CountdownSeconds, true)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		session.state = "Idle"
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

local function sessionFor(player: Player, runId: any): Session?
	local session = sessions[player]
	if not session or typeof(runId) ~= "number" or runId ~= session.runId then
		return nil
	end
	return session
end

local function connectRemotes()
	remotes.RequestRestart.OnServerEvent:Connect(function(player: Player)
		local session = sessions[player]
		if not session or not rootOf(player) then
			return
		end
		local t = now()
		if t - session.lastRestart < Config.Round.RestartCooldown then
			return
		end
		session.lastRestart = t
		startCountdown(session, Config.Round.RestartCountdownSeconds, false)
	end)

	remotes.RequestRespawn.OnServerEvent:Connect(function(player: Player, runId: any)
		local session = sessionFor(player, runId)
		if not session or session.state ~= "Running" then
			return
		end
		local positions = {}
		for index = 1, session.checkpoint do
			table.insert(positions, course.Checkpoints[index].Respawn.Position)
		end
		session.validator:expectTeleport(positions, now())
	end)

	remotes.ComboEvent.OnServerEvent:Connect(function(player: Player, runId: any, eventType: any)
		local session = sessionFor(player, runId)
		if not session or typeof(eventType) ~= "string" then
			return
		end
		if session.state ~= "Running" and session.state ~= "Flight" then
			return
		end
		ScoreService.tryCombo(session, eventType, now(), false)
	end)

	remotes.ImpactClaim.OnServerEvent:Connect(function(player: Player, runId: any, claim: any)
		local session = sessionFor(player, runId)
		if not session or session.state ~= "Flight" or session.claim then
			return
		end
		if typeof(claim) ~= "table" or typeof(claim.Point) ~= "Vector3" or typeof(claim.Speed) ~= "number" or typeof(claim.LaunchTime) ~= "number" then
			return
		end
		if claim.Speed ~= claim.Speed or claim.LaunchTime ~= claim.LaunchTime then
			return -- NaN
		end
		session.claim = { Point = claim.Point, Speed = claim.Speed, LaunchTime = claim.LaunchTime }
		if session.serverImpact then
			resolveImpact(session)
		else
			session.resolveDeadline = now() + V.ImpactWait
		end
	end)
end

function RunSessionService.init(activeCourse: any)
	course = activeCourse
	for _, name in Net.Names do
		remotes[name] = Net.get(name)
	end
	connectRemotes()

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		ScoreService.clear(player)
		WalletService.clear(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, session in sessions do
			step(session, dt)
		end
	end)
end

return RunSessionService
