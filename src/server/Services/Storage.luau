--!strict
-- One doorway to Roblox data stores. In the live game it returns the real stores; tests switch
-- on an in-memory stand-in that behaves the same, so "save, leave, come back" can be tested
-- without publishing.

local DataStoreService = game:GetService("DataStoreService")

local Storage = {}

local useMemory = false
local memory: { [string]: { [string]: any } } = {}

local function fake(name: string): any
	memory[name] = memory[name] or {}
	local data = memory[name]
	local store = {}
	function store.GetAsync(_self: any, key: string)
		return data[key]
	end
	function store.SetAsync(_self: any, key: string, value: any)
		data[key] = value
	end
	function store.UpdateAsync(_self: any, key: string, transform: (any) -> any)
		local value = transform(data[key])
		if value ~= nil then
			data[key] = value
		end
		return data[key]
	end
	function store.IncrementAsync(_self: any, key: string, delta: number)
		data[key] = (data[key] or 0) + delta
		return data[key]
	end
	function store.GetSortedAsync(_self: any, ascending: boolean, pageSize: number)
		local rows = {}
		for key, value in data do
			table.insert(rows, { key = key, value = value })
		end
		table.sort(rows, function(a, b)
			return if ascending then a.value < b.value else a.value > b.value
		end)
		local page = {}
		for index = 1, math.min(pageSize, #rows) do
			page[index] = rows[index]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
		}
	end
	return store
end

-- Tests: true switches to a fresh in-memory store set; false goes back to the real ones.
function Storage.useMemory(enabled: boolean)
	useMemory = enabled
	memory = {}
end

function Storage.dataStore(name: string): any?
	if useMemory then
		return fake(name)
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	return if ok then result else nil
end

function Storage.orderedStore(name: string): any?
	if useMemory then
		return fake(name)
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then result else nil
end

-- Calls `work` up to `attempts` times, waiting between failures. Returns (ok, result).
function Storage.retry(attempts: number, work: () -> any): (boolean, any)
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(work)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(1 + attempt)
		end
	end
	return false, lastError
end

return Storage
