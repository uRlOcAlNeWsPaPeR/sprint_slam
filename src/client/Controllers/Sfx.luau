--!strict
-- Fire-and-forget sounds keyed by Config.Sounds. Empty ids are skipped so the game runs
-- silently until audio is chosen (Phase 2).

local SoundService = game:GetService("SoundService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Sfx = {}

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
