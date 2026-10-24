--!strict
-- Runs saves in the background and keeps the server alive until they finish. Without this,
-- when the last player leaves the server can shut down mid-write and lose that last save
-- (the run they just finished). Roblox allows up to 30 s in BindToClose.

local SaveGuard = {}

local pending = 0
local MAX_WAIT = 25

-- Runs `work` in a new thread (errors are caught); the server will not close until it ends.
function SaveGuard.run(work: () -> ())
	pending += 1
	task.spawn(function()
		local ok, err = pcall(work)
		if not ok then
			warn("[SprintSlam] Save failed: " .. tostring(err))
		end
		pending -= 1
	end)
end

function SaveGuard.pending(): number
	return pending
end

-- Yields until every save has finished (or `timeout` seconds pass). Returns true if idle.
function SaveGuard.waitIdle(timeout: number?): boolean
	local deadline = os.clock() + (timeout or MAX_WAIT)
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	return pending == 0
end

function SaveGuard.init()
	game:BindToClose(function()
		SaveGuard.waitIdle(MAX_WAIT)
	end)
end

return SaveGuard
