--!nonstrict
-- Sprint Slam world preview (Studio plugin). The hub and course are generated from data at
-- runtime, so an edit session would otherwise show an empty world. Whenever a Sprint Slam
-- place is open in Edit mode, this builds workspace.Lobby and workspace.Course from the
-- current source and rebuilds them when world or builder code changes. The preview is never saved with the
-- place (Archivable = false), and Play builds the real course as usual.
--
-- Install: node tools/build-place.js --install-plugin

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if not RunService:IsEdit() then
	return
end

local REBUILD_DELAY = 0.4

local function findSources(): (Instance?, Instance?)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local server = ServerScriptService:FindFirstChild("Server")
	local services = server and server:FindFirstChild("Services")
	if shared and shared:FindFirstChild("Courses") and services and services:FindFirstChild("CourseManager") then
		return shared, services
	end
	return nil, nil
end

-- require() caches modules for the whole Studio session, so load them from their current
-- Source instead; every rebuild sees the latest edits.
local function freshLoader()
	local cache = {}
	local loading = {}
	local function load(module: ModuleScript)
		if cache[module] ~= nil then
			return cache[module]
		end
		if loading[module] then
			error("cyclic require: " .. module:GetFullName())
		end
		loading[module] = true
		local chunk, err = loadstring(module.Source, "=" .. module:GetFullName())
		if not chunk then
			error(err, 0)
		end
		setfenv(chunk, setmetatable({ script = module, require = load }, { __index = getfenv(1) }))
		local result = chunk()
		loading[module] = nil
		cache[module] = result
		return result
	end
	return load
end

local building = false

local function rebuild()
	local shared, services = findSources()
	if not shared or not services or building then
		return
	end
	building = true
	local recording = ChangeHistoryService:TryBeginRecording("Sprint Slam course preview")
	local ok, err = pcall(function()
		local load = freshLoader()
		local worldSetup = services:FindFirstChild("WorldSetup")
		if worldSetup then
			load(worldSetup).applyLighting()
		end
		load(services.CourseManager).build({ Preview = true })
		local lobbyManager = services:FindFirstChild("LobbyManager")
		if lobbyManager then
			load(lobbyManager).build({ Preview = true })
		end
	end)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	building = false
	if not ok then
		warn("[Sprint Slam preview] " .. tostring(err))
	end
end

local pending = false
local function scheduleRebuild()
	if pending then
		return
	end
	pending = true
	task.delay(REBUILD_DELAY, function()
		pending = false
		rebuild()
	end)
end

-- Rebuild when any course/builder module changes, or when modules are (re)synced in.
local watched: { [Instance]: boolean } = {}
local function watch(container: Instance)
	if watched[container] then
		return
	end
	watched[container] = true
	local function hook(instance: Instance)
		if instance:IsA("ModuleScript") then
			instance:GetPropertyChangedSignal("Source"):Connect(scheduleRebuild)
		end
	end
	for _, descendant in container:GetDescendants() do
		hook(descendant)
	end
	container.DescendantAdded:Connect(function(descendant)
		hook(descendant)
		scheduleRebuild()
	end)
end

local function attach()
	local shared, services = findSources()
	if not shared or not services then
		return false
	end
	watch(shared)
	watch(services)
	scheduleRebuild()
	return true
end

if not attach() then
	-- Sources may arrive after the plugin loads (place still opening, or a live sync).
	local connections = {}
	local function retry()
		if attach() then
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end
	table.insert(connections, ReplicatedStorage.DescendantAdded:Connect(retry))
	table.insert(connections, ServerScriptService.DescendantAdded:Connect(retry))
end

local toolbar = plugin:CreateToolbar("Sprint Slam")
local button = toolbar:CreateButton("Rebuild Course", "Rebuild the Sprint Slam course preview", "")
button.ClickableWhenViewportHidden = true
button.Click:Connect(rebuild)
