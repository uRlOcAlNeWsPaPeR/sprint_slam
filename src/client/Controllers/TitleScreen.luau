--!strict
-- The cover screen shown when a player joins: game title, tagline, this week's name and a PLAY
-- button (click, tap, Space or Enter). The hub is blurred behind it, and the player can't move
-- until they press play.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Weeks = require(ReplicatedStorage.Shared.Weeks)

local Palette = Config.Palette

local TitleScreen = {}

TitleScreen.Dismissed = Signal.new()

local HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local MEDIUM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)

local gui: ScreenGui
local root: CanvasGroup
local blur: BlurEffect
local open = false
local playButton: TextButton

local function label(props: { [string]: any }): TextLabel
	local instance = Instance.new("TextLabel")
	instance.BackgroundTransparency = 1
	instance.TextColor3 = Palette.White
	instance.FontFace = BOLD
	for key, value in props do
		(instance :: any)[key] = value
	end
	return instance
end

function TitleScreen.isOpen(): boolean
	return open
end

function TitleScreen.dismiss()
	if not open then
		return
	end
	open = false
	TweenService:Create(root, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { GroupTransparency = 1 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.6), { Size = 0 }):Play()
	task.delay(0.7, function()
		gui.Enabled = false
		blur.Enabled = false
	end)
	TitleScreen.Dismissed:Fire()
end

function TitleScreen.init(week: any)
	blur = Instance.new("BlurEffect")
	blur.Name = "TitleBlur"
	blur.Size = 16
	blur.Parent = Lighting

	gui = Instance.new("ScreenGui")
	gui.Name = "SprintSlamTitle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	root = Instance.new("CanvasGroup")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Palette.Charcoal
	root.BackgroundTransparency = 0.08
	root.Parent = gui

	-- Neon speed lines streaking across the cover.
	for i = 1, 14 do
		local streak = Instance.new("Frame")
		local accent = if i % 3 == 0 then Palette.Orange else Palette.Cyan
		streak.BackgroundColor3 = accent
		streak.BackgroundTransparency = 0.55
		streak.BorderSizePixel = 0
		streak.Size = UDim2.new(0, math.random(160, 420), 0, 3)
		streak.Position = UDim2.fromScale(math.random() * 1.2 - 0.2, 0.08 + (i / 14) * 0.84)
		streak.Parent = root
		local row = streak.Position.Y.Scale
		streak.Position = UDim2.new(-0.3, 0, row, 0)
		TweenService:Create(streak, TweenInfo.new(6 + math.random() * 8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {
			Position = UDim2.new(1.3, 0, row, 0),
		}):Play()
	end

	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function resize()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.5, 1.3)
	end
	resize()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(900, 520)
	content.BackgroundTransparency = 1
	content.Parent = root

	local title = label({
		Size = UDim2.new(1, 0, 0, 130),
		FontFace = HEAVY,
		TextSize = 120,
		Text = "SPRINT SLAM",
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Cyan
	stroke.Thickness = 5
	stroke.Parent = title
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Palette.White, Palette.Orange)
	gradient.Rotation = 90
	gradient.Parent = title
	title.Parent = content
	TweenService:Create(title, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 10) }):Play()

	label({
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = HEAVY,
		TextSize = 34,
		TextColor3 = Palette.Orange,
		Text = "RUN.   BOOST.   SLAM.   REPEAT.",
	}).Parent = content

	label({
		Position = UDim2.fromOffset(0, 205),
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = MEDIUM,
		TextSize = 22,
		TextColor3 = Palette.Muted,
		Text = week.Title .. "  -  10 NEW CHALLENGES  -  NEW WEEK EVERY SUNDAY",
	}).Parent = content

	playButton = Instance.new("TextButton")
	playButton.AnchorPoint = Vector2.new(0.5, 0)
	playButton.Position = UDim2.new(0.5, 0, 0, 300)
	playButton.Size = UDim2.fromOffset(300, 70)
	playButton.BackgroundColor3 = Palette.Orange
	playButton.AutoButtonColor = true
	playButton.FontFace = HEAVY
	playButton.TextSize = 34
	playButton.TextColor3 = Palette.Charcoal
	playButton.Text = "PLAY"
	playButton.Parent = content
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 18)
	buttonCorner.Parent = playButton
	TweenService:Create(playButton, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromOffset(318, 74) }):Play()

	label({
		Position = UDim2.fromOffset(0, 395),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = MEDIUM,
		TextSize = 18,
		TextColor3 = Palette.Muted,
		Text = if UserInputService.TouchEnabled then "TAP PLAY" else "CLICK PLAY  |  OR PRESS SPACE",
	}).Parent = content
	label({
		Position = UDim2.fromOffset(0, 440),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = MEDIUM,
		TextSize = 15,
		TextColor3 = Palette.Muted,
		Text = "WASD run   SPACE jump   SHIFT dash   CTRL slide   R restart   L hub   M music",
	}).Parent = content

	open = true
	playButton.Activated:Connect(TitleScreen.dismiss)
	UserInputService.InputBegan:Connect(function(input, processed)
		if open and not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			TitleScreen.dismiss()
		end
	end)
end

return TitleScreen
