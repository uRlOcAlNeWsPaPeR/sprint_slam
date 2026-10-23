--!strict
-- Client side of THE HUB: portal triggers, timed parkour challenges, pads and obstacles,
-- falling out, and ambient animation (halo, portal cores).
--
-- Challenge flow per challenge: Ready (inside the start box) → Active (timer runs from the
-- moment you leave it) → Done (finish box reached). Falling below FailY while Active sends
-- you back to the challenge start; walking back onto the plaza cancels it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Geometry = require(Shared.Geometry)
local Signal = require(Shared.Signal)

local Interactables = require(script.Parent.Interactables)

local LobbyController = {}

LobbyController.EnterRequested = Signal.new() -- (mode: string)
LobbyController.FellOut = Signal.new() -- (respawn: CFrame, challengeName: string?)
LobbyController.ChallengeFinished = Signal.new() -- (name: string, time: number, best: number, isBest: boolean)

local lobby: any = nil
local interactables: Interactables.Interactables? = nil
local previousPosition: Vector3? = nil
local lastEnterRequest = -math.huge
local inPortal = false
local current: { index: number, phase: string, startedAt: number, finishedTime: number? }? = nil
local bests: { [string]: number } = {}
local hallBody: TextLabel? = nil
local halo: Model? = nil
local haloPivot: CFrame? = nil
local portalCores: { { part: BasePart } } = {}

local ENTER_RETRY = 1.5

local function now(): number
	return workspace:GetServerTimeNow()
end

function LobbyController.init(activeLobby: any)
	lobby = activeLobby
	local root = workspace:WaitForChild("Lobby")
	interactables = Interactables.new(lobby, root)
	local decor = root:WaitForChild("Decor")
	halo = decor:WaitForChild("Halo") :: Model
	haloPivot = (halo :: Model):GetPivot()
	local board = decor:FindFirstChild("HallOfFameBoard")
	local body = board and board:FindFirstChild("Gui") and board.Gui:FindFirstChild("Body")
	if body and body:IsA("TextLabel") then
		hallBody = body
	end
	for _, portal in root:WaitForChild("Portals"):GetChildren() do
		local core = portal:FindFirstChild("Core")
		if core and core:IsA("BasePart") and portal:GetAttribute("Mode") ~= "" then
			table.insert(portalCores, { part = core })
		end
	end
end

-- Fills the in-world Hall of Fame wall. `format` turns the server's list into rich text.
function LobbyController.setHallOfFame(list: { any }, _courses: { any }, format: ({ any }) -> string)
	if hallBody then
		hallBody.Text = format(list)
	end
end

function LobbyController.reset()
	if interactables then
		interactables:reset()
	end
	previousPosition = nil
	current = nil
	inPortal = false
end

function LobbyController.getLobby(): any
	return lobby
end

function LobbyController.forgetPosition()
	previousPosition = nil
end

-- Ambient motion, run every frame regardless of mode (cheap: a few CFrame writes).
function LobbyController.animate()
	local t = now()
	if interactables then
		interactables:animate(t)
	end
	if halo and haloPivot then
		halo:PivotTo(haloPivot * CFrame.Angles(0, t * 0.15, 0))
	end
	-- Active portal cores breathe so they read as live.
	local glow = 0.45 + math.sin(t * 2.4) * 0.12
	for _, entry in portalCores do
		entry.part.Transparency = glow
	end
end

local function insideBox(position: Vector3, box: any): boolean
	return Geometry.pointInBox(position, box.CFrame, box.Size)
end

local function updateChallenges(position: Vector3)
	local plaza = lobby.Plaza
	local flat = Vector3.new(position.X - plaza.Center.X, 0, position.Z - plaza.Center.Z)
	if flat.Magnitude < plaza.Radius - 6 then
		current = nil
		return
	end

	if current and current.phase == "Active" then
		local challenge = lobby.Challenges[current.index]
		if insideBox(position, challenge.Finish) then
			local elapsed = os.clock() - current.startedAt
			local best = bests[challenge.Name]
			local isBest = best == nil or elapsed < best
			if isBest then
				bests[challenge.Name] = elapsed
			end
			current.phase = "Done"
			current.finishedTime = elapsed
			LobbyController.ChallengeFinished:Fire(challenge.Name, elapsed, bests[challenge.Name], isBest)
			return
		elseif position.Y < challenge.FailY then
			current.phase = "Ready"
			previousPosition = nil
			LobbyController.FellOut:Fire(challenge.Respawn, challenge.Name)
			return
		end
	end

	for index, challenge in lobby.Challenges do
		local inStart = insideBox(position, challenge.Start)
		if inStart then
			if not current or current.index ~= index or current.phase ~= "Ready" then
				current = { index = index, phase = "Ready", startedAt = 0 }
			end
		elseif current and current.index == index and current.phase == "Ready" then
			current.phase = "Active"
			current.startedAt = os.clock()
		end
	end
end

local function updatePortals(position: Vector3)
	local wasInPortal = inPortal
	inPortal = false
	for _, portal in lobby.Portals do
		if portal.Active and Geometry.pointInBox(position, portal.Trigger.CFrame, portal.Trigger.Size) then
			inPortal = true
			local t = os.clock()
			if not wasInPortal and t - lastEnterRequest >= ENTER_RETRY then
				lastEnterRequest = t
				LobbyController.EnterRequested:Fire(portal.Mode)
			end
		end
	end
end

-- True while standing in an active portal (the level select stays open only then).
function LobbyController.isInPortal(): boolean
	return inPortal
end

-- Per-frame checks while the player is in the hub.
function LobbyController.update(root: BasePart)
	local position = root.Position
	local previous = previousPosition or position
	previousPosition = position

	updateChallenges(position)
	if position.Y < lobby.KillY then
		previousPosition = nil
		current = nil
		LobbyController.FellOut:Fire(lobby.Spawn, nil)
		return
	end
	if interactables then
		interactables:update(root, previous, now())
	end
	updatePortals(position)
end

-- R in the hub: back to the start of the challenge you're on.
function LobbyController.restartChallenge(): CFrame?
	if not current then
		return nil
	end
	local challenge = lobby.Challenges[current.index]
	current = nil
	previousPosition = nil
	return challenge.Respawn
end

export type ChallengeStatus = { Name: string, Phase: string, Elapsed: number, Best: number? }

function LobbyController.getStatus(): ChallengeStatus?
	if not current then
		return nil
	end
	local challenge = lobby.Challenges[current.index]
	local elapsed = 0
	if current.phase == "Active" then
		elapsed = os.clock() - current.startedAt
	elseif current.phase == "Done" then
		elapsed = current.finishedTime or 0
	end
	return { Name = challenge.Name, Phase = current.phase, Elapsed = elapsed, Best = bests[challenge.Name] }
end

return LobbyController
