--!strict
-- Weekly challenge progression. Each week a player must clear its challenges once, in order
-- (a clear is any server-verified slam). Once all ten are cleared they may replay any of them
-- to improve their score and time. Persists per player per week in a DataStore; where
-- DataStores are unavailable (an unpublished place), it lasts for the session.

local DataStoreService = game:GetService("DataStoreService")

local ProgressService = {}

local STORE_NAME = "SprintSlamProgress_v2"

local cleared: { [Player]: number } = {} -- challenges cleared in order this week
local store: DataStore? = nil
local weekId = ""
local challengeCount = 10

local function key(player: Player): string
	return `u_{player.UserId}_{weekId}`
end

function ProgressService.init(currentWeekId: string, count: number)
	weekId = currentWeekId
	challengeCount = count
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

-- Yields while the saved progress loads.
function ProgressService.load(player: Player)
	cleared[player] = cleared[player] or 0
	local dataStore = store
	if not dataStore then
		return
	end
	local ok, result = pcall(function()
		return dataStore:GetAsync(key(player))
	end)
	if ok then
		cleared[player] = math.max(cleared[player] or 0, math.clamp(tonumber(result) or 0, 0, challengeCount))
	else
		store = nil -- stay session-only; the wallet service already warned
	end
end

function ProgressService.clearedCount(player: Player): number
	return cleared[player] or 0
end

function ProgressService.allCleared(player: Player): boolean
	return ProgressService.clearedCount(player) >= challengeCount
end

-- The highest challenge the player may start: the next uncleared one, or any once all are
-- cleared.
function ProgressService.unlockedCount(player: Player): number
	return math.min(ProgressService.clearedCount(player) + 1, challengeCount)
end

function ProgressService.isUnlocked(player: Player, index: number): boolean
	return ProgressService.allCleared(player) or index <= ProgressService.unlockedCount(player)
end

-- Records a verified slam on challenge `index`. Returns true if it advanced the player's
-- in-order progress (their first clear of that challenge).
function ProgressService.recordClear(player: Player, index: number): boolean
	if index ~= ProgressService.clearedCount(player) + 1 then
		return false
	end
	cleared[player] = index
	local dataStore = store
	if dataStore then
		task.spawn(function()
			pcall(function()
				dataStore:UpdateAsync(key(player), function(saved)
					return math.max(tonumber(saved) or 0, index)
				end)
			end)
		end)
	end
	return true
end

function ProgressService.clear(player: Player)
	cleared[player] = nil
end

return ProgressService
