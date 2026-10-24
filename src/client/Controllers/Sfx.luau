--!strict
-- Fire-and-forget sounds keyed by Config.Sounds. Empty ids are skipped so the game runs
-- silently until audio is chosen (Phase 2).

local SoundService = game:GetService("SoundService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Sfx = {}

-- Loads every effect up front so the first dash or boost doesn't lag.
function Sfx.preload()
	local ContentProvider = game:GetService("ContentProvider")
	local assets = {}
	for _, id in Config.Sounds :: any do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = "rbxassetid://" .. id
			table.insert(assets, sound)
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
		for _, sound in assets do
			sound:Destroy()
		end
	end)
end

function Sfx.play(name: string, volume: number?, pitch: number?)
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = if string.find(id, "rbxasset") then id else "rbxassetid://" .. id
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return Sfx
