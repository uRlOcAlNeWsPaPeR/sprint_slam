--!strict
-- Minimal synchronous signal for wiring client controllers together.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} :: { [number]: (...any) -> () }, _nextId = 0 }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local handlers = self._handlers
	return {
		Disconnect = function()
			handlers[id] = nil
		end,
	}
end

function Signal:Fire(...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

return Signal
