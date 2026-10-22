--!strict
-- Combo chain logic shared by client (display) and server (authoritative tally).
-- Each event extends the chain if it lands within the window; points scale with the chain.

local Config = require(script.Parent.Config)

local ComboTracker = {}
ComboTracker.__index = ComboTracker

export type ComboTracker = typeof(setmetatable(
	{} :: {
		chain: number,
		lastTime: number,
		total: number,
		window: number,
		lastByType: { [string]: number },
	},
	ComboTracker
))

function ComboTracker.new(windowSlack: number?): ComboTracker
	return setmetatable({
		chain = 0,
		lastTime = -math.huge,
		total = 0,
		window = Config.Combo.Window + (windowSlack or 0),
		lastByType = {},
	}, ComboTracker)
end

function ComboTracker.multiplierFor(chain: number): number
	if chain <= 0 then
		return 1
	end
	return math.min(1 + (chain - 1) * Config.Combo.ChainStep, Config.Combo.MaxMultiplier)
end

function ComboTracker.multiplier(self: ComboTracker, now: number): number
	if now - self.lastTime > self.window then
		return 1
	end
	return ComboTracker.multiplierFor(self.chain)
end

-- Seconds left before the chain drops, as 0..1 of the window.
function ComboTracker.windowRemaining(self: ComboTracker, now: number): number
	if self.chain <= 0 then
		return 0
	end
	return math.clamp(1 - (now - self.lastTime) / self.window, 0, 1)
end

function ComboTracker.canAdd(self: ComboTracker, eventType: string, now: number): boolean
	local def = Config.Combo.Events[eventType]
	if not def then
		return false
	end
	local last = self.lastByType[eventType]
	return last == nil or now - last >= def.MinInterval
end

-- Returns points actually awarded (0 if rejected or capped) and the chain multiplier used.
function ComboTracker.add(self: ComboTracker, eventType: string, now: number): (number, number)
	if not self:canAdd(eventType, now) then
		return 0, self:multiplier(now)
	end
	local def = Config.Combo.Events[eventType]
	self.lastByType[eventType] = now
	if now - self.lastTime <= self.window then
		self.chain += 1
	else
		self.chain = 1
	end
	self.lastTime = now
	local multiplier = ComboTracker.multiplierFor(self.chain)
	local before = self.total
	self.total = math.min(before + math.floor(def.Points * multiplier + 0.5), Config.Score.MaxComboBonus)
	return self.total - before, multiplier
end

return ComboTracker
