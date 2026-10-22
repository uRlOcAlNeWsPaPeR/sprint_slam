--!strict
-- Level unlocks. Clearing level N with a verified slam unlocks N + 1. Persists in a
-- DataStore; where DataStores are unavailable (unpublished place), it lasts for the session.

local DataStoreService = game:GetService("DataStoreService")

local ProgressService = {}

local STORE_NAME = "SprintSlamProgress_v1"

local unlocked: { [Player]: number } = {}
local store: DataStore? = nil

local function key(player: Player): string
	return "u_" .. player.UserId
end

function ProgressService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

-- Yields while the saved progress loads.
function ProgressService.load(player: Player)
	unlocked[player] = unlocked[player] or 1
	local dataStore = store
	if not dataStore then
		return
	end
	local ok, result = pcall(function()
		return dataStore:GetAsync(key(player))
	end)
	if ok then
		unlocked[player] = math.max(unlocked[player] or 1, tonumber(result) or 1)
	else
		store = nil -- the wallet already warned; stay session-only quietly
	end
end

function ProgressService.get(player: Player): number
	return unlocked[player] or 1
end

-- Returns true if this actually raised the player's unlocked level.
function ProgressService.unlock(player: Player, level: number): boolean
	if level <= ProgressService.get(player) then
		return false
	end
	unlocked[player] = level
	local dataStore = store
	if dataStore then
		task.spawn(function()
			pcall(function()
				dataStore:UpdateAsync(key(player), function(saved)
					return math.max(tonumber(saved) or 1, level)
				end)
			end)
		end)
	end
	return true
end

function ProgressService.clear(player: Player)
	unlocked[player] = nil
end

return ProgressService
