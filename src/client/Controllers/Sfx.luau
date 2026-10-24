--!strict
-- Fire-and-forget sounds keyed by Config.Sounds. Empty ids are skipped so the game runs
-- silently until audio is chosen (Phase 2).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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

-- Bright chimes are softened so they feel like a gentle tap rather than a ping: much quieter,
-- a lower pitch, the harsh highs filtered away, and a slow fade-out. Throttled so a string of
-- pads never stacks into a buzz.
type Soft = { Volume: number, Pitch: number, HighCut: number, Fade: number, Gap: number }

local SOFT: { [string]: Soft } = {
	Boost = { Volume = 0.16, Pitch = 0.8, HighCut = -22, Fade = 0.5, Gap = 0.3 },
	Combo = { Volume = 0.1, Pitch = 0.85, HighCut = -22, Fade = 0.4, Gap = 0.25 },
	Checkpoint = { Volume = 0.14, Pitch = 0.9, HighCut = -20, Fade = 0.5, Gap = 0.4 },
	Countdown = { Volume = 0.25, Pitch = 0.95, HighCut = -14, Fade = 0.3, Gap = 0.2 },
	Go = { Volume = 0.3, Pitch = 0.95, HighCut = -14, Fade = 0.4, Gap = 0.2 },
}

local lastPlayed: { [string]: number } = {}

function Sfx.play(name: string, volume: number?, pitch: number?)
	local id = (Config.Sounds :: any)[name]
	if not id or id == "" then
		return
	end
	local soft = SOFT[name]
	if soft then
		local now = os.clock()
		if now - (lastPlayed[name] or -math.huge) < soft.Gap then
			return
		end
		lastPlayed[name] = now
	end
	local sound = Instance.new("Sound")
	sound.SoundId = if string.find(id, "rbxasset") then id else "rbxassetid://" .. id
	if soft then
		-- Callers pass loudness/pitch meant for the raw sound; keep only a small part of it.
		local callerPitch = pitch or 1
		sound.Volume = soft.Volume * math.clamp((volume or 0.6) / 0.6, 0.5, 1)
		sound.PlaybackSpeed = soft.Pitch * (1 + (callerPitch - 1) * 0.15)
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = soft.HighCut
		eq.MidGain = -4
		eq.LowGain = 2
		eq.Parent = sound
	else
		sound.Volume = volume or 0.6
		sound.PlaybackSpeed = pitch or 1
	end
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	if soft then
		local fadeAfter = math.min(soft.Fade * 2, 0.8)
		task.delay(fadeAfter, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(soft.Fade), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

return Sfx
