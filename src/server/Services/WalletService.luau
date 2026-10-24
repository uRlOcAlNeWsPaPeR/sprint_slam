--!strict
-- Coin balances. Coins are only ever awarded by the server from a verified impact.
-- Balances persist in a DataStore. Where DataStores are unavailable (an unpublished place
-- in Studio), they last for the session, with one warning.

local SaveGuard = require(script.Parent.SaveGuard)
local Storage = require(script.Parent.Storage)

local WalletService = {}

local STORE_NAME = "SprintSlamWallet_v1"

local balances: { [Player]: number } = {}
local store: DataStore? = nil
local warned = false

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function disablePersistence(reason: any)
	store = nil
	if not warned then
		warned = true
		warn("[SprintSlam] Coins are session-only (DataStore unavailable): " .. tostring(reason))
	end
end

function WalletService.init()
	store = Storage.dataStore(STORE_NAME)
	if not store then
		disablePersistence("no data store")
	end
end

-- Yields while the saved balance loads.
function WalletService.load(player: Player)
	balances[player] = balances[player] or 0
	local dataStore = store
	if not dataStore then
		return
	end
	local ok, result = Storage.retry(3, function()
		return dataStore:GetAsync(key(player))
	end)
	if ok then
		balances[player] = (balances[player] or 0) + (tonumber(result) or 0)
	else
		warn("[SprintSlam] Could not load coins for " .. player.Name .. ": " .. tostring(result))
	end
end

-- Tests: stop talking to any store.
function WalletService.disableSaving()
	store = nil
end

function WalletService.get(player: Player): number
	return balances[player] or 0
end

function WalletService.award(player: Player, amount: number): number
	if amount <= 0 then
		return WalletService.get(player)
	end
	balances[player] = WalletService.get(player) + amount
	local dataStore = store
	if dataStore then
		local saveKey = key(player)
		SaveGuard.run(function()
			local ok, err = Storage.retry(3, function()
				return dataStore:IncrementAsync(saveKey, amount)
			end)
			if not ok then
				warn("[SprintSlam] Could not save coins: " .. tostring(err))
			end
		end)
	end
	return balances[player]
end

function WalletService.clear(player: Player)
	balances[player] = nil
end

return WalletService
