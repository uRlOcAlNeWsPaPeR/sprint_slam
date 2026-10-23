--!strict
-- One session per player. Players spawn in the hub (Lobby); at the Sprint Slam portal they
-- pick one of the week's ten challenges (first clears must go in order; after that any).
-- A run goes Countdown → Running → Flight → Finished, restartable at any time, and they can
-- return to the hub whenever they like. The server owns every transition that affects score.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local ComboTracker = require(Shared.ComboTracker)
local Net = require(Shared.Net)
local ScoreFormula = require(Shared.ScoreFormula)
local Weeks = require(Shared.Weeks)

local BoardService = require(script.Parent.BoardService)
local ProgressService = require(script.Parent.ProgressService)
local RunValidator = require(script.Parent.RunValidator)
local ScoreService = require(script.Parent.ScoreService)
local WalletService = require(script.Parent.WalletService)

local V = Config.Validation

local RunSessionService = {}

type Session = {
	player: Player,
	course: any,
	runId: number,
	challenge: number, -- 1-10, the challenge of the current/last run
	state: string, -- "Idle" | "Lobby" | "Countdown" | "Running" | "Flight" | "Finished"
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
local week: any
local courses: { any } = {}
local lobby: any
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
	local mine = BoardService.personal(session.player)
	local bests = {}
	for index, entry in mine do
		bests[tostring(index)] = { Score = entry.Score, TimeMs = entry.TimeMs }
	end
	local splitsBest = ScoreService.getBest(session.player, session.challenge)
	remotes.RunState:FireClient(session.player, {
		RunId = session.runId,
		State = session.state,
		WeekId = week.Id,
		Challenge = session.challenge,
		Cleared = ProgressService.clearedCount(session.player),
		Unlocked = ProgressService.unlockedCount(session.player),
		AllCleared = ProgressService.allCleared(session.player),
		Bests = bests,
		GoTime = session.goTime,
		RoundTime = session.course.RoundTime,
		Checkpoint = session.checkpoint,
		BestScore = mine[session.challenge] and mine[session.challenge].Score or nil,
		BestSplits = if splitsBest then splitsBest.Splits else nil,
		CoinBalance = WalletService.get(session.player),
	})
end

local function startCountdown(session: Session, seconds: number, serverTeleport: boolean)
	local t = now()
	session.runId += 1
	session.state = "Countdown"
	session.goTime = t + seconds
	session.course = courses[session.challenge]
	session.validator:setCourse(session.course)
	session.validator:reset()
	session.combo = ComboTracker.new(Config.Combo.ServerWindowSlack)
	session.checkpoint = 1
	session.splits = {}
	session.launch = nil
	session.serverImpact = nil
	session.claim = nil
	session.resolveDeadline = nil

	local spawn: CFrame = session.course.Spawn
	if serverTeleport and session.player.Character then
		session.player.Character:PivotTo(spawn)
	end
	session.validator:expectTeleport({ spawn.Position }, t)
	sendState(session)
end

-- Back to the hub: any run in progress is abandoned, and the run id moves on so late
-- messages from it are ignored.
local function enterLobby(session: Session)
	session.runId += 1
	session.state = "Lobby"
	session.validator:reset()
	session.launch = nil
	session.serverImpact = nil
	session.claim = nil
	session.resolveDeadline = nil
	if session.player.Character then
		session.player.Character:PivotTo(lobby.Spawn)
	end
	sendState(session)
end

-- The player must actually be at an active portal for that mode, by the server's view.
local function nearPortal(player: Player, mode: string): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	for _, portal in lobby.Portals do
		if portal.Active and portal.Mode == mode and (root.Position - portal.Trigger.CFrame.Position).Magnitude <= 30 then
			return true
		end
	end
	return false
end

local function finish(session: Session, breakdown: ScoreFormula.Breakdown, reason: string?)
	session.state = "Finished"
	session.resolveDeadline = nil
	local isNewBest, isNewTime = false, false
	local coins = 0
	local newlyCleared = nil
	local timeMs = nil
	if not reason and breakdown.Outcome == "Impact" then
		local launch = session.launch :: { Time: number, Momentum: number }
		timeMs = math.floor((launch.Time - session.goTime) * 1000 + 0.5)
		ScoreService.recordRun(session.player, session.challenge, breakdown, session.splits)
		isNewBest, isNewTime = BoardService.submit(session.player, week.Id, session.challenge, breakdown.Final, timeMs)
		coins = breakdown.Coins
		WalletService.award(session.player, coins)
		-- The first verified slam on the next challenge in order clears it.
		if ProgressService.recordClear(session.player, session.challenge) then
			newlyCleared = session.challenge
		end
	end
	local mine = BoardService.personal(session.player)[session.challenge]
	remotes.RunResult:FireClient(session.player, {
		RunId = session.runId,
		Breakdown = breakdown,
		Reason = reason,
		IsNewBest = isNewBest,
		IsNewTime = isNewTime,
		TimeMs = timeMs,
		BestScore = mine and mine.Score or nil,
		BestTimeMs = mine and mine.TimeMs or nil,
		Coins = coins,
		CoinBalance = WalletService.get(session.player),
		Challenge = session.challenge,
		Cleared = ProgressService.clearedCount(session.player),
		Unlocked = ProgressService.unlockedCount(session.player),
		AllCleared = ProgressService.allCleared(session.player),
		NewlyCleared = newlyCleared,
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
		course = session.course,
		roundTime = session.course.RoundTime,
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
		local best = ScoreService.getBest(session.player, session.challenge)
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
	if session.state == "Idle" or session.state == "Lobby" or session.state == "Finished" then
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
			local offset = root.Position - session.course.Spawn.Position
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

	if session.state == "Running" and t > session.goTime + session.course.RoundTime + V.TimeGrace then
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
		course = courses[1],
		runId = 0,
		challenge = 1,
		state = "Idle",
		goTime = 0,
		validator = RunValidator.new(courses[1]),
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
		ProgressService.load(player)
		BoardService.loadPlayer(player, week.Id, #courses)
		if sessions[player] == session and session.state ~= "Idle" then
			sendState(session)
		end
	end)

	local function onCharacter(character: Model)
		character:WaitForChild("HumanoidRootPart")
		task.defer(enterLobby, session)
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
		if not session or not rootOf(player) or session.state == "Lobby" or session.state == "Idle" then
			return
		end
		local t = now()
		if t - session.lastRestart < Config.Round.RestartCooldown then
			return
		end
		session.lastRestart = t
		startCountdown(session, Config.Round.RestartCountdownSeconds, false)
	end)

	remotes.RequestMode.OnServerEvent:Connect(function(player: Player, mode: any, challenge: any)
		local session = sessions[player]
		if not session or typeof(mode) ~= "string" or not rootOf(player) then
			return
		end
		if mode == "Lobby" then
			if session.state ~= "Lobby" and session.state ~= "Idle" then
				enterLobby(session)
			end
		elseif mode == "SprintSlam" then
			-- Only challenges the player has unlocked (the next one in order, or any once
			-- all ten are cleared). From the hub they must be standing at the portal; once
			-- in Sprint Slam (e.g. NEXT on the results screen) they may switch directly.
			if typeof(challenge) ~= "number" or challenge % 1 ~= 0 or challenge < 1 or challenge > #courses then
				return
			end
			if not ProgressService.isUnlocked(player, challenge) then
				return
			end
			local inMode = session.state ~= "Lobby" and session.state ~= "Idle"
			if inMode or (session.state == "Lobby" and nearPortal(player, mode)) then
				session.challenge = challenge
				startCountdown(session, Config.Round.CountdownSeconds, true)
			end
		end
	end)

	local lastBoardRequest: { [Player]: number } = {}
	remotes.RequestBoard.OnServerEvent:Connect(function(player: Player, challenge: any)
		if typeof(challenge) ~= "number" or challenge % 1 ~= 0 or challenge < 1 or challenge > #courses then
			return
		end
		local t = os.clock()
		if t - (lastBoardRequest[player] or -math.huge) < 0.5 then
			return
		end
		lastBoardRequest[player] = t
		task.spawn(function()
			remotes.BoardData:FireClient(player, {
				WeekId = week.Id,
				Challenge = challenge,
				Score = BoardService.top(week.Id, challenge, "Score", 10),
				Time = BoardService.top(week.Id, challenge, "Time", 10),
			})
		end)
	end)

	remotes.RequestHallOfFame.OnServerEvent:Connect(function(player: Player)
		local t = os.clock()
		if t - (lastBoardRequest[player] or -math.huge) < 0.5 then
			return
		end
		lastBoardRequest[player] = t
		task.spawn(function()
			remotes.HallOfFameData:FireClient(player, BoardService.hallOfFame(Weeks.finishedBefore(os.time()), 5))
		end)
	end)

	remotes.RequestRespawn.OnServerEvent:Connect(function(player: Player, runId: any)
		local session = sessionFor(player, runId)
		if not session or session.state ~= "Running" then
			return
		end
		local positions = {}
		for index = 1, session.checkpoint do
			table.insert(positions, session.course.Checkpoints[index].Respawn.Position)
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

-- Re-sends a player's state (used by Studio test tooling after changing their progress).
function RunSessionService.refresh(player: Player)
	local session = sessions[player]
	if session then
		sendState(session)
	end
end

function RunSessionService.init(activeWeek: any, activeCourses: { any }, activeLobby: any)
	week = activeWeek
	courses = activeCourses
	lobby = activeLobby
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
		ProgressService.clear(player)
		BoardService.clear(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, session in sessions do
			step(session, dt)
		end
		-- Studio QA only: workspace attribute DevClearTo = N marks challenges 1..N cleared for
		-- everyone in the session (so a test can jump straight to challenge N+1).
		local clearTo = workspace:GetAttribute("DevClearTo")
		if clearTo ~= nil and RunService:IsStudio() then
			workspace:SetAttribute("DevClearTo", nil)
			for _, session in sessions do
				for index = 1, math.min(tonumber(clearTo) or 0, #courses) do
					ProgressService.recordClear(session.player, index)
				end
				sendState(session)
			end
		end
	end)
end

return RunSessionService
