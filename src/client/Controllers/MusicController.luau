--!strict
-- Background music: one calm track for the title screen and hub, another during runs, with a
-- crossfade between them. Mute with M or the button in the bottom-left corner (the choice
-- lasts for the session).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)

local Palette = Config.Palette
local M = Config.Music

local MusicController = {}

MusicController.MuteToggled = Signal.new()

local tracks: { [string]: { sound: Sound, volume: number } } = {}
local scene = "Hub"
local muted = false
local button: TextButton? = nil

local function makeTrack(name: string, id: string, volume: number)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music" .. name
	sound.SoundId = "rbxassetid://" .. id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	tracks[name] = { sound = sound, volume = volume }
end

local function apply(duration: number)
	for name, track in tracks do
		local target = if muted or name ~= scene then 0 else track.volume
		if target > 0 and not track.sound.IsPlaying then
			track.sound:Play()
		end
		TweenService:Create(track.sound, TweenInfo.new(duration), { Volume = target }):Play()
	end
end

function MusicController.setScene(name: string)
	if name == scene then
		return
	end
	scene = name
	apply(M.FadeSeconds)
end

function MusicController.toggleMute()
	muted = not muted
	if button then
		button.Text = if muted then "MUSIC OFF  [M]" else "MUSIC ON  [M]"
		button.TextTransparency = if muted then 0.4 else 0
	end
	apply(0.3)
end

function MusicController.isMuted(): boolean
	return muted
end

function MusicController.init()
	makeTrack("Hub", M.Hub, M.HubVolume)
	makeTrack("Run", M.Run, M.RunVolume)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SprintSlamMusic"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local pill = Instance.new("TextButton")
	pill.Name = "MuteButton"
	pill.AnchorPoint = Vector2.new(0, 1)
	pill.Position = UDim2.new(0, 20, 1, -20)
	pill.Size = UDim2.fromOffset(150, 32)
	pill.BackgroundColor3 = Palette.Panel
	pill.BackgroundTransparency = 0.15
	pill.AutoButtonColor = true
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 14
	pill.TextColor3 = Palette.White
	pill.Text = "MUSIC ON  [M]"
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Cyan
	stroke.Transparency = 0.5
	stroke.Thickness = 1.5
	stroke.Parent = pill
	pill.Activated:Connect(MusicController.toggleMute)
	button = pill

	apply(0.5)
end

return MusicController
