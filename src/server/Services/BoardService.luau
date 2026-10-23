--!strict
-- Weekly leaderboards and the Hall of Fame.
--
-- Every challenge has two boards: BEST SCORE (highest final score) and FASTEST TIME (shortest
-- run from GO to launch). Both only ever take server-verified impacts. When a week is over,
-- the top player on each board of each challenge is written to the Hall of Fame, along with
-- the week's champion (most board wins).
--
-- Boards live in OrderedDataStores (one per week × challenge × kind). Where DataStores are
-- unavailable (an unpublished place) everything works from memory for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local BoardService = {}

BoardService.Kinds = { "Score", "Time" }

local HOF_STORE = "SprintSlamHallOfFame_v1"
local CACHE_SECONDS = 20
local FINALIZE_RETRIES = 3

export type Entry = { Rank: number, UserId: number, Name: string, Value: number }
export type Personal = { Score: number?, TimeMs: number? }

local persistent = true
local hofStore: DataStore? = nil
local orderedStores: { [string]: OrderedDataStore } = {}

-- memory[boardKey][userId] = value, names[userId] = display name
local memory: { [string]: { [number]: number } } = {}
local names: { [number]: string } = {}
local personal: { [Player]: { [number]: Personal } } = {}
local cache: { [string]: { at: number, entries: { Entry } } } = {}
local hofMemory: { [string]: any } = {}

local function boardKey(weekId: string, index: number, kind: string): string
	return `SprintSlam_{weekId}_C{index}_{kind}`
end

local function ordered(weekId: string, index: number, kind: string): OrderedDataStore?
	if not persistent then
		return nil
	end
	local name = boardKey(weekId, index, kind)
	local existing = orderedStores[name]
	if existing then
		return existing
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		orderedStores[name] = result
		return result
	end
	persistent = false
	return nil
end

local function disable(reason: any)
	if persistent then
		persistent = false
		warn("[SprintSlam] Leaderboards are session-only (DataStore unavailable): " .. tostring(reason))
	end
end

-- Tests turn persistence off so they never touch real DataStores.
function BoardService.setPersistence(enabled: boolean)
	persistent = enabled
end

function BoardService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(HOF_STORE)
	end)
	hofStore = if ok then result else nil
end

local function nameFor(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and typeof(result) == "string" then result else "Player" .. userId
	return names[userId]
end

local function better(kind: string, a: number, b: number?): boolean
	if b == nil then
		return true
	end
	return if kind == "Time" then a < b else a > b
end

-- Loads the player's saved bests for the week (yields).
function BoardService.loadPlayer(player: Player, weekId: string, count: number)
	names[player.UserId] = player.DisplayName ~= "" and player.DisplayName or player.Name
	personal[player] = personal[player] or {}
	for index = 1, count do
		personal[player][index] = personal[player][index] or {}
		for _, kind in BoardService.Kinds do
			local store = ordered(weekId, index, kind)
			if store then
				local ok, result = pcall(function()
					return store:GetAsync(tostring(player.UserId))
				end)
				if ok then
					if typeof(result) == "number" then
						local entry = personal[player][index]
						if kind == "Score" then
							entry.Score = math.max(entry.Score or 0, result)
						else
							entry.TimeMs = if entry.TimeMs then math.min(entry.TimeMs, result) else result
						end
					end
				else
					disable(result)
					return
				end
			end
		end
	end
end

function BoardService.personal(player: Player): { [number]: Personal }
	return personal[player] or {}
end

-- Records a verified result and returns whether it beat the player's own bests. Runs the
-- store writes in the background.
function BoardService.submit(player: Player, weekId: string, index: number, score: number, timeMs: number): (boolean, boolean)
	personal[player] = personal[player] or {}
	local mine = personal[player][index] or {}
	personal[player][index] = mine
	local newScore = better("Score", score, mine.Score)
	local newTime = better("Time", timeMs, mine.TimeMs)
	if newScore then
		mine.Score = score
	end
	if newTime then
		mine.TimeMs = timeMs
	end
	local userId = player.UserId
	if player.Name ~= "" and not names[userId] then
		names[userId] = player.Name
	end
	for _, pair in { { "Score", newScore, score }, { "Time", newTime, timeMs } } do
		local kind, isNew, value = pair[1] :: string, pair[2] :: boolean, pair[3] :: number
		if isNew then
			local key = boardKey(weekId, index, kind)
			memory[key] = memory[key] or {}
			memory[key][userId] = value
			cache[key] = nil
			local store = ordered(weekId, index, kind)
			if store then
				task.spawn(function()
					local ok, err = pcall(function()
						store:UpdateAsync(tostring(userId), function(saved)
							if typeof(saved) == "number" and not better(kind, value, saved) then
								return nil
							end
							return value
						end)
					end)
					if not ok then
						disable(err)
					end
				end)
			end
		end
	end
	return newScore, newTime
end

local function fetchTop(weekId: string, index: number, kind: string, limit: number): { Entry }
	local key = boardKey(weekId, index, kind)
	local values: { [number]: number } = {}
	local store = ordered(weekId, index, kind)
	if store then
		local ok, result = pcall(function()
			return store:GetSortedAsync(kind == "Time", limit):GetCurrentPage()
		end)
		if ok then
			for _, row in result do
				local userId = tonumber(row.key)
				if userId and typeof(row.value) == "number" then
					values[userId] = row.value
				end
			end
		else
			disable(result)
		end
	end
	-- This server's own submissions always count, even if the store has not caught up.
	for userId, value in memory[key] or {} do
		if better(kind, value, values[userId]) then
			values[userId] = value
		end
	end
	local rows = {}
	for userId, value in values do
		table.insert(rows, { UserId = userId, Value = value })
	end
	table.sort(rows, function(a, b)
		if a.Value == b.Value then
			return a.UserId < b.UserId
		end
		return if kind == "Time" then a.Value < b.Value else a.Value > b.Value
	end)
	local entries: { Entry } = {}
	for rank = 1, math.min(#rows, limit) do
		local row = rows[rank]
		entries[rank] = { Rank = rank, UserId = row.UserId, Name = nameFor(row.UserId), Value = row.Value }
	end
	return entries
end

-- Top `limit` entries of one board (cached briefly).
function BoardService.top(weekId: string, index: number, kind: string, limit: number): { Entry }
	local key = boardKey(weekId, index, kind)
	local cached = cache[key]
	if cached and os.clock() - cached.at < CACHE_SECONDS and #cached.entries >= math.min(limit, #cached.entries) then
		return cached.entries
	end
	local entries = fetchTop(weekId, index, kind, limit)
	cache[key] = { at = os.clock(), entries = entries }
	return entries
end

-- Hall of Fame -------------------------------------------------------------------------

local function winnersOf(week: any): any
	local winners = {}
	local wins: { [number]: number } = {}
	for index in week.Challenges do
		local row = {}
		for _, kind in BoardService.Kinds do
			local top = fetchTop(week.Id, index, kind, 1)[1]
			if top then
				row[kind] = { UserId = top.UserId, Name = top.Name, Value = top.Value }
				wins[top.UserId] = (wins[top.UserId] or 0) + 1
			end
		end
		winners[index] = row
	end
	local champion = nil
	for userId, count in wins do
		if not champion or count > champion.Wins or (count == champion.Wins and userId < champion.UserId) then
			champion = { UserId = userId, Name = nameFor(userId), Wins = count }
		end
	end
	return { WeekId = week.Id, Title = week.Title, Winners = winners, Champion = champion }
end

-- Writes a finished week to the Hall of Fame once (a no-op if it is already there or the
-- week had no verified runs).
function BoardService.finalizeWeek(week: any)
	if hofMemory[week.Id] then
		return
	end
	local entry = winnersOf(week)
	if not entry.Champion then
		return
	end
	local store = hofStore
	if store and persistent then
		for _ = 1, FINALIZE_RETRIES do
			local ok = pcall(function()
				store:UpdateAsync(week.Id, function(saved)
					if saved then
						return nil -- another server already finalized it
					end
					return entry
				end)
			end)
			if ok then
				break
			end
			task.wait(2)
		end
	end
	hofMemory[week.Id] = entry
end

function BoardService.finalizePastWeeks(weeks: { any })
	for _, week in weeks do
		BoardService.finalizeWeek(week)
	end
end

-- Finished weeks, newest first.
function BoardService.hallOfFame(weeks: { any }, limit: number): { any }
	local list = {}
	for index = #weeks, 1, -1 do
		local week = weeks[index]
		local entry = hofMemory[week.Id]
		if not entry and hofStore and persistent then
			local ok, result = pcall(function()
				return (hofStore :: DataStore):GetAsync(week.Id)
			end)
			if ok and typeof(result) == "table" then
				entry = result
				hofMemory[week.Id] = result
			end
		end
		if entry then
			table.insert(list, entry)
			if #list >= limit then
				break
			end
		end
	end
	return list
end

function BoardService.clear(player: Player)
	personal[player] = nil
end

return BoardService
