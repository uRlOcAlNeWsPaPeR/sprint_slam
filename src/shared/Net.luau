--!strict
-- RemoteEvent registry. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Names = {
	-- server → client
	RunState = "RunState",
	Checkpoint = "Checkpoint",
	RunResult = "RunResult",
	-- client → server
	RequestRestart = "RequestRestart",
	RequestMode = "RequestMode", -- "SprintSlam" (from a portal) or "Lobby"
	RequestRespawn = "RequestRespawn",
	ComboEvent = "ComboEvent",
	ImpactClaim = "ImpactClaim",
}

local FOLDER_NAME = "Remotes"

local function folder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.init()
	local remotes = folder()
	for _, name in Net.Names do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end
end

function Net.get(name: string): RemoteEvent
	local remote = folder():WaitForChild(name)
	return remote :: RemoteEvent
end

return Net
