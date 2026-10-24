-- "Finish, close the game, come back": progress, bests and coins must survive a rejoin.
-- Uses the in-memory stand-in store, never real DataStores.

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Server.Services
local BoardService = require(Services.BoardService)
local ProgressService = require(Services.ProgressService)
local SaveGuard = require(Services.SaveGuard)
local Storage = require(Services.Storage)
local WalletService = require(Services.WalletService)

local function player(id: number, name: string): any
	return { UserId = id, Name = name, DisplayName = name }
end

return function(t)
	t.test("clearing challenge 1, leaving and rejoining unlocks challenge 2", function()
		Storage.useMemory(true)
		ProgressService.init("WTEST", 10)
		local first = player(-201, "Saver")
		ProgressService.load(first)
		t.eq(ProgressService.unlockedCount(first), 1)
		t.eq(ProgressService.recordClear(first, 1), true)
		-- The server closes right away: the guard must hold it until the write lands.
		t.eq(SaveGuard.waitIdle(5), true, "save finished")
		ProgressService.clear(first)

		local again = player(-201, "Saver")
		ProgressService.load(again)
		t.eq(ProgressService.clearedCount(again), 1)
		t.eq(ProgressService.unlockedCount(again), 2)
		t.eq(ProgressService.isUnlocked(again, 2), true)
		t.eq(ProgressService.isUnlocked(again, 3), false)
		ProgressService.clear(again)
		ProgressService.disableSaving()
		Storage.useMemory(false)
	end)

	t.test("best score and time come back after a rejoin and only ever improve", function()
		Storage.useMemory(true)
		BoardService.setPersistence(true)
		local p = player(-202, "Racer")
		BoardService.loadPlayer(p, "WTEST", 3)
		BoardService.submit(p, "WTEST", 2, 5000, 41000)
		BoardService.submit(p, "WTEST", 2, 3000, 52000) -- worse on both
		t.eq(SaveGuard.waitIdle(5), true, "save finished")
		BoardService.clear(p)

		local back = player(-202, "Racer")
		BoardService.loadPlayer(back, "WTEST", 3)
		local mine = BoardService.personal(back)[2]
		t.eq(mine.Score, 5000)
		t.eq(mine.TimeMs, 41000)
		BoardService.clear(back)
		BoardService.setPersistence(false)
		Storage.useMemory(false)
	end)

	t.test("coins come back after a rejoin", function()
		Storage.useMemory(true)
		WalletService.init()
		local p = player(-203, "Rich")
		WalletService.load(p)
		WalletService.award(p, 120)
		WalletService.award(p, 30)
		t.eq(SaveGuard.waitIdle(5), true, "save finished")
		WalletService.clear(p)

		local back = player(-203, "Rich")
		WalletService.load(back)
		t.eq(WalletService.get(back), 150)
		WalletService.clear(back)
		WalletService.disableSaving()
		Storage.useMemory(false)
	end)
end
