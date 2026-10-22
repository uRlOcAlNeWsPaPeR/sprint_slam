--!strict
-- HUD, countdown, SLAM MODE, and the animated results reveal. Built in code so the whole
-- interface lives in source control and follows Config.Palette.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local Palette = Config.Palette

local UIController = {}

UIController.RestartClicked = Signal.new()

local HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local MEDIUM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local function new(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	local children = props.Children
	for key, value in props do
		if key ~= "Children" and key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or Palette.White
	props.FontFace = props.FontFace or BOLD
	return new("TextLabel", props)
end

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	local instance = new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0 })
	instance:SetAttribute("BaseTransparency", transparency or 0)
	return instance
end

local function tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- UIStroke ignores TextTransparency, so text fades must fade the outline too.
local function fadeText(target: TextLabel, visible: boolean, duration: number?)
	local outline = target:FindFirstChildOfClass("UIStroke")
	local textGoal = if visible then 0 else 1
	local strokeGoal = if visible then (outline and outline:GetAttribute("BaseTransparency") or 0) else 1
	if duration and duration > 0 then
		tween(target, duration, { TextTransparency = textGoal })
		if outline then
			tween(outline, duration, { Transparency = strokeGoal })
		end
	else
		target.TextTransparency = textGoal
		if outline then
			outline.Transparency = strokeGoal :: number
		end
	end
end

local function formatTime(seconds: number): string
	seconds = math.max(seconds, 0)
	return string.format("%05.2f", seconds)
end

-- Instances -----------------------------------------------------------------------------
local gui: ScreenGui
local rootScale: UIScale
local timerLabel: TextLabel
local progressFill: Frame
local progressMarker: Frame
local splitLabel: TextLabel
local bestLabel: TextLabel
local courseLabel: TextLabel
local speedFrame: Frame
local speedScale: UIScale
local speedValue: TextLabel
local speedCaption: TextLabel
local speedFill: Frame
local momentumValue: TextLabel
local momentumFill: Frame
local coinsLabel: TextLabel
local dashPill: Frame
local dashFill: Frame
local dashLabel: TextLabel
local dashStroke: UIStroke
local comboFrame: Frame
local comboMultiplier: TextLabel
local comboTotal: TextLabel
local comboEvent: TextLabel
local comboBar: Frame
local countdownLabel: TextLabel
local countdownScale: UIScale
local toastLabel: TextLabel
local slamOverlay: Frame
local slamBanner: TextLabel
local flightHint: TextLabel
local predictionLabel: TextLabel
local results: Frame
local resultsScale: UIScale

local course: any = nil
local countdownGoTime: number? = nil
local lastCountdownDigit: string? = nil
local slamMode = false
local inFlight = false
local comboVisible = false
local comboEventToken = 0
local splitToken = 0
local toastToken = 0
local resultsToken = 0

local function buildTop(parent: Instance)
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(460, 100),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	timerLabel = label({
		Name = "Timer",
		Size = UDim2.new(1, 0, 0, 54),
		FontFace = MONO,
		TextSize = 50,
		Text = formatTime(Config.Round.RoundTime),
		Children = { stroke(Palette.Charcoal, 2.5, 0.2) },
		Parent = top,
	})
	local bar = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Palette.Panel,
		BackgroundTransparency = 0.15,
		Children = { corner(4), stroke(Palette.Charcoal, 1.5, 0.3) },
		Parent = top,
	})
	progressFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Palette.Cyan,
		Children = { corner(4) },
		Parent = bar,
	})
	local pathLength = 0
	do
		local points = course.Path
		for i = 2, #points do
			pathLength += (points[i] - points[i - 1]).Magnitude
		end
	end
	local slamStart = math.clamp(course.SlamModeDistance / pathLength, 0, 1)
	new("Frame", {
		Name = "SlamSegment",
		Position = UDim2.fromScale(slamStart, 0),
		Size = UDim2.fromScale(1 - slamStart, 1),
		BackgroundColor3 = Palette.Orange,
		BackgroundTransparency = 0.45,
		Children = { corner(4) },
		Parent = bar,
	})
	progressMarker = new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundColor3 = Palette.White,
		Children = { stroke(Palette.Cyan, 2) },
		Parent = bar,
	})
	splitLabel = label({
		Name = "Split",
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = MONO,
		TextSize = 22,
		Text = "",
		TextTransparency = 1,
		Children = { stroke(Palette.Charcoal, 2, 0.2) },
		Parent = top,
	})
	fadeText(splitLabel, false)
end

local function buildCorners(parent: Instance)
	courseLabel = label({
		Name = "Course",
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.fromOffset(300, 26),
		FontFace = HEAVY,
		TextSize = 24,
		TextColor3 = Palette.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = course.DisplayName,
		Children = { stroke(Palette.Charcoal, 2, 0.3) },
		Parent = parent,
	})
	bestLabel = label({
		Name = "Best",
		Position = UDim2.fromOffset(24, 46),
		Size = UDim2.fromOffset(300, 20),
		FontFace = MEDIUM,
		TextSize = 16,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SESSION BEST  -",
		Parent = parent,
	})
	coinsLabel = label({
		Name = "Coins",
		Position = UDim2.fromOffset(24, 68),
		Size = UDim2.fromOffset(300, 20),
		FontFace = HEAVY,
		TextSize = 17,
		TextColor3 = Palette.Orange,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "COINS  0",
		Parent = parent,
	})
	local restart = new("TextButton", {
		Name = "Restart",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 16),
		Size = UDim2.fromOffset(150, 40),
		BackgroundColor3 = Palette.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		FontFace = BOLD,
		TextSize = 16,
		TextColor3 = Palette.White,
		Text = if UserInputService.TouchEnabled then "RESTART" else "RESTART  [R]",
		Children = { corner(10), stroke(Palette.Cyan, 1.5, 0.4) },
		Parent = parent,
	})
	restart.Activated:Connect(function()
		UIController.RestartClicked:Fire()
	end)
end

local function buildSpeed(parent: Instance)
	speedFrame = new("Frame", {
		Name = "Speed",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.fromOffset(340, 186),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	speedScale = new("UIScale", { Parent = speedFrame })
	speedValue = label({
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 78),
		FontFace = HEAVY,
		TextSize = 80,
		Text = "0",
		Children = { stroke(Palette.Charcoal, 3, 0.15) },
		Parent = speedFrame,
	})
	speedCaption = label({
		Name = "Caption",
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = BOLD,
		TextSize = 15,
		TextColor3 = Palette.Muted,
		Text = "SPEED",
		Parent = speedFrame,
	})
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(300, 8),
		BackgroundColor3 = Palette.Panel,
		Children = { corner(4) },
		Parent = speedFrame,
	})
	speedFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Palette.White,
		Children = {
			corner(4),
			new("UIGradient", { Color = ColorSequence.new(Palette.Cyan, Palette.Orange) }),
		},
		Parent = bar,
	})
	local capFraction = Config.Movement.RunSpeedCap / Config.Movement.OverspeedCap
	new("Frame", {
		Name = "CapMark",
		Position = UDim2.fromScale(capFraction, -0.5),
		Size = UDim2.new(0, 2, 2, 0),
		BackgroundColor3 = Palette.White,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = bar,
	})
	-- Momentum = average speed over the whole run; it sets launch speed and impact power.
	local momentumRow = new("Frame", {
		Name = "Momentum",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 116),
		Size = UDim2.fromOffset(300, 34),
		BackgroundTransparency = 1,
		Parent = speedFrame,
	})
	label({
		Name = "Caption",
		Size = UDim2.new(0.6, 0, 0, 18),
		FontFace = HEAVY,
		TextSize = 15,
		TextColor3 = Palette.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "MOMENTUM",
		Parent = momentumRow,
	})
	momentumValue = label({
		Name = "Value",
		Position = UDim2.fromScale(0.6, 0),
		Size = UDim2.new(0.4, 0, 0, 18),
		FontFace = MONO,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
		Parent = momentumRow,
	})
	local momentumBar = new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Palette.Panel,
		Children = { corner(5), stroke(Palette.Cyan, 1, 0.6) },
		Parent = momentumRow,
	})
	momentumFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Palette.White,
		Children = {
			corner(5),
			new("UIGradient", { Color = ColorSequence.new(Palette.Cyan, Palette.Orange) }),
		},
		Parent = momentumBar,
	})
	dashPill = new("Frame", {
		Name = "Dash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 158),
		Size = UDim2.fromOffset(150, 26),
		BackgroundColor3 = Palette.Panel,
		ClipsDescendants = true,
		Children = { corner(13) },
		Parent = speedFrame,
	})
	dashStroke = stroke(Palette.Cyan, 1.5)
	dashStroke.Parent = dashPill
	dashFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Cyan,
		BackgroundTransparency = 0.55,
		Children = { corner(13) },
		Parent = dashPill,
	})
	dashLabel = label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		FontFace = HEAVY,
		TextSize = 14,
		Text = "DASH READY",
		ZIndex = 2,
		Parent = dashPill,
	})
end

local function buildCombo(parent: Instance)
	comboFrame = new("CanvasGroup", {
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.45, 0),
		Size = UDim2.fromOffset(230, 132),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = parent,
	})
	label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 18),
		FontFace = BOLD,
		TextSize = 15,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "COMBO",
		Parent = comboFrame,
	})
	comboMultiplier = label({
		Name = "Multiplier",
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 52),
		FontFace = HEAVY,
		TextSize = 50,
		TextColor3 = Palette.Orange,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "x1",
		Children = { stroke(Palette.Charcoal, 2.5, 0.2) },
		Parent = comboFrame,
	})
	comboTotal = label({
		Name = "Total",
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = MONO,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "+0",
		Parent = comboFrame,
	})
	comboEvent = label({
		Name = "Event",
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = HEAVY,
		TextSize = 17,
		TextColor3 = Palette.Cyan,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = comboFrame,
	})
	local bar = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 118),
		Size = UDim2.fromOffset(150, 5),
		BackgroundColor3 = Palette.Panel,
		Children = { corner(3) },
		Parent = comboFrame,
	})
	comboBar = new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Orange,
		Children = { corner(3) },
		Parent = bar,
	})
end

local function buildCenter(parent: Instance)
	countdownLabel = label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 200),
		FontFace = HEAVY,
		TextSize = 170,
		Text = "",
		Children = { stroke(Palette.Charcoal, 5, 0.1) },
		Parent = parent,
	})
	countdownScale = new("UIScale", { Parent = countdownLabel })
	fadeText(countdownLabel, false)
	toastLabel = label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(700, 60),
		FontFace = HEAVY,
		TextSize = 44,
		Text = "",
		TextTransparency = 1,
		Children = { stroke(Palette.Charcoal, 3, 0.1) },
		Parent = parent,
	})
	fadeText(toastLabel, false)
end

local function buildSlamOverlay(parent: Instance)
	slamOverlay = new("CanvasGroup", {
		Name = "SlamMode",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	})
	for _, spec in { { 0, 90 }, { 1, -90 } } do
		new("Frame", {
			AnchorPoint = Vector2.new(0, spec[1]),
			Position = UDim2.fromScale(0, spec[1]),
			Size = UDim2.new(1, 0, 0.22, 0),
			BackgroundColor3 = Palette.Orange,
			BorderSizePixel = 0,
			Children = {
				new("UIGradient", {
					Rotation = spec[2],
					Transparency = NumberSequence.new(0.55, 1),
				}),
			},
			Parent = slamOverlay,
		})
	end
	slamBanner = label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Size = UDim2.fromOffset(500, 44),
		FontFace = HEAVY,
		TextSize = 40,
		TextColor3 = Palette.Orange,
		Text = "SLAM MODE",
		Children = { stroke(Palette.Charcoal, 3, 0.1) },
		Parent = slamOverlay,
	})
	predictionLabel = label({
		Name = "Prediction",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 162),
		Size = UDim2.fromOffset(500, 28),
		FontFace = HEAVY,
		TextSize = 24,
		Text = "",
		Children = { stroke(Palette.Charcoal, 2, 0.2) },
		Parent = slamOverlay,
	})
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	flightHint = label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -186),
		Size = UDim2.fromOffset(640, 24),
		FontFace = BOLD,
		TextSize = 18,
		Text = if touch then "STEER WITH THE STICK   |   TAP DASH TO SLAM DASH" else "STEER  W A S D   |   SLAM DASH  [SHIFT]   |   EARLIER = BIGGER BONUS",
		TextTransparency = 1,
		Children = { stroke(Palette.Charcoal, 2, 0.2) },
		Parent = slamOverlay,
	})
	fadeText(flightHint, false)
end

local function resultRow(parent: Instance, order: number, name: string): TextLabel
	local row = new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	label({
		Name = "Key",
		Size = UDim2.fromScale(0.5, 1),
		FontFace = MEDIUM,
		TextSize = 22,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		Parent = row,
	})
	return label({
		Name = "Value",
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.5, 1),
		FontFace = MONO,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = row,
	})
end

local function buildResults(parent: Instance)
	results = new("CanvasGroup", {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(540, 640),
		BackgroundColor3 = Palette.Charcoal,
		BackgroundTransparency = 0.04,
		GroupTransparency = 1,
		Visible = false,
		Children = { corner(16), stroke(Palette.Cyan, 2, 0.2) },
		Parent = parent,
	})
	resultsScale = new("UIScale", { Parent = results })
	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = {
			new("UIPadding", {
				PaddingLeft = UDim.new(0, 36),
				PaddingRight = UDim.new(0, 36),
				PaddingTop = UDim.new(0, 26),
				PaddingBottom = UDim.new(0, 24),
			}),
			new("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		},
		Parent = results,
	})
	label({
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 46),
		FontFace = HEAVY,
		TextSize = 40,
		Text = "SPRINT COMPLETE",
		Parent = body,
	})
	new("Frame", { Name = "Gap", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, Parent = body })
	resultRow(body, 3, "Momentum")
	resultRow(body, 4, "Impact Speed")
	resultRow(body, 5, "Impact Power")
	resultRow(body, 6, "Accuracy")
	resultRow(body, 7, "Time Bonus")
	resultRow(body, 8, "Combo Bonus")
	new("Frame", {
		Name = "Divider",
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Palette.Cyan,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = body,
	})
	label({
		Name = "FinalCaption",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = BOLD,
		TextSize = 18,
		TextColor3 = Palette.Muted,
		Text = "FINAL SCORE",
		Parent = body,
	})
	label({
		Name = "Final",
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, 72),
		FontFace = HEAVY,
		TextSize = 72,
		TextColor3 = Palette.Cyan,
		Text = "0",
		Parent = body,
	})
	label({
		Name = "CoinsEarned",
		LayoutOrder = 12,
		Size = UDim2.new(1, 0, 0, 28),
		FontFace = HEAVY,
		TextSize = 24,
		TextColor3 = Palette.Orange,
		Text = "",
		Parent = body,
	})
	label({
		Name = "Banner",
		LayoutOrder = 13,
		Size = UDim2.new(1, 0, 0, 30),
		FontFace = HEAVY,
		TextSize = 26,
		TextColor3 = Palette.Orange,
		Text = "",
		Parent = body,
	})
	local button = new("TextButton", {
		Name = "Again",
		LayoutOrder = 14,
		Size = UDim2.fromOffset(260, 50),
		BackgroundColor3 = Palette.Orange,
		AutoButtonColor = true,
		FontFace = HEAVY,
		TextSize = 22,
		TextColor3 = Palette.Charcoal,
		Text = if UserInputService.TouchEnabled then "RUN AGAIN" else "RUN AGAIN  [R]",
		Children = { corner(12) },
		Parent = body,
	})
	button.Activated:Connect(function()
		UIController.RestartClicked:Fire()
	end)
end

local function updateScale()
	local viewport = workspace.CurrentCamera.ViewportSize
	rootScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.55, 1.25)
end

function UIController.init(activeCourse: any)
	course = activeCourse
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = new("ScreenGui", {
		Name = "SprintSlamHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	local canvas = new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	rootScale = new("UIScale", { Parent = canvas })
	-- UIScale shrinks the canvas too; grow it back so anchored corners stay on screen.
	local function resize()
		updateScale()
		canvas.Size = UDim2.fromScale(1 / rootScale.Scale, 1 / rootScale.Scale)
	end
	resize()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

	buildSlamOverlay(canvas)
	buildTop(canvas)
	buildCorners(canvas)
	buildSpeed(canvas)
	buildCombo(canvas)
	buildCenter(canvas)
	buildResults(canvas)
end

-- Public API ----------------------------------------------------------------------------

function UIController.setCoins(balance: number?)
	if balance then
		coinsLabel.Text = "COINS  " .. tostring(balance)
	end
end

function UIController.setBest(score: number?)
	bestLabel.Text = if score then "SESSION BEST  " .. tostring(score) else "SESSION BEST  -"
end

function UIController.toast(text: string, color: Color3?, duration: number?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or Palette.White
	fadeText(toastLabel, true)
	toastLabel.Position = UDim2.fromScale(0.5, 0.3)
	tween(toastLabel, 0.25, { Position = UDim2.fromScale(0.5, 0.28) }, Enum.EasingStyle.Back)
	task.delay(duration or 1.1, function()
		if token == toastToken then
			fadeText(toastLabel, false, 0.3)
		end
	end)
end

function UIController.showCountdown(goTime: number)
	countdownGoTime = goTime
	lastCountdownDigit = nil
end

local function popCountdown(text: string, color: Color3)
	countdownLabel.Text = text
	countdownLabel.TextColor3 = color
	fadeText(countdownLabel, true)
	countdownScale.Scale = 1.6
	tween(countdownScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UIController.go()
	countdownGoTime = nil
	popCountdown("GO!", Palette.Cyan)
	task.delay(0.45, function()
		if countdownGoTime == nil then
			fadeText(countdownLabel, false, 0.25)
		end
	end)
end

function UIController.combo(eventLabel: string, points: number, multiplier: number, total: number)
	comboEventToken += 1
	local token = comboEventToken
	comboEvent.Text = string.format("%s  +%d", eventLabel, points)
	fadeText(comboEvent, true)
	comboMultiplier.Text = string.format("x%s", if multiplier % 1 == 0 then tostring(multiplier) else string.format("%.2f", multiplier))
	comboTotal.Text = "+" .. tostring(total)
	local scale = comboMultiplier:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = comboMultiplier })
	scale.Scale = 1.35
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.4, function()
		if token == comboEventToken then
			fadeText(comboEvent, false, 0.3)
		end
	end)
end

function UIController.split(delta: number?)
	splitToken += 1
	local token = splitToken
	if delta == nil then
		splitLabel.Text = "CHECKPOINT"
		splitLabel.TextColor3 = Palette.White
	else
		local ahead = delta <= 0
		splitLabel.Text = string.format("%s%.2f", if ahead then "-" else "+", math.abs(delta))
		splitLabel.TextColor3 = if ahead then Palette.Cyan else Palette.Orange
	end
	fadeText(splitLabel, true)
	task.delay(2, function()
		if token == splitToken then
			fadeText(splitLabel, false, 0.4)
		end
	end)
end

function UIController.setSlamMode(enabled: boolean)
	if enabled == slamMode then
		return
	end
	slamMode = enabled
	tween(slamOverlay, 0.35, { GroupTransparency = if enabled then 0 else 1 })
	tween(speedScale, 0.35, { Scale = if enabled then 1.3 else 1 }, Enum.EasingStyle.Back)
	if enabled then
		slamBanner.TextTransparency = 0
		local scale = slamBanner:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = slamBanner })
		scale.Scale = 1.6
		tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

function UIController.setFlight(enabled: boolean)
	inFlight = enabled
	fadeText(flightHint, enabled, 0.25)
	if not enabled then
		predictionLabel.Text = ""
	end
end

export type HudInfo = {
	State: string,
	TimeLeft: number,
	Speed: number,
	DashReadiness: number,
	SlamDashAvailable: boolean,
	ComboMultiplier: number,
	ComboWindow: number,
	ComboTotal: number,
	Momentum: number,
	Progress: number,
	Prediction: { TimeToImpact: number, Zone: string }?,
}

function UIController.update(info: HudInfo)
	timerLabel.Text = formatTime(info.TimeLeft)
	timerLabel.TextColor3 = if info.TimeLeft <= 10 and info.State == "Running" then Palette.Orange else Palette.White

	local progress = math.clamp(info.Progress, 0, 1)
	progressFill.Size = UDim2.fromScale(progress, 1)
	progressMarker.Position = UDim2.fromScale(progress, 0.5)

	local speed = math.floor(info.Speed + 0.5)
	speedValue.Text = tostring(speed)
	local overspeed = info.Speed > Config.Movement.RunSpeedCap + 1
	speedValue.TextColor3 = if slamMode or overspeed then Palette.Orange else Palette.White
	speedCaption.Text = if inFlight then "IMPACT SPEED" else "SPEED"
	speedFill.Size = UDim2.fromScale(math.clamp(info.Speed / Config.Movement.OverspeedCap, 0, 1), 1)
	momentumValue.Text = tostring(math.floor(info.Momentum + 0.5))
	momentumFill.Size = UDim2.fromScale(math.clamp(info.Momentum / Config.Momentum.MeterMax, 0, 1), 1)

	if inFlight then
		dashFill.Size = UDim2.fromScale(if info.SlamDashAvailable then 1 else 0, 1)
		dashFill.BackgroundColor3 = Palette.Orange
		dashStroke.Color = Palette.Orange
		dashLabel.Text = if info.SlamDashAvailable then "SLAM DASH READY" else "SLAM DASH USED"
		local prediction = info.Prediction
		if prediction and prediction.TimeToImpact > 0 then
			predictionLabel.Text = string.format("%s LINE   %.2fs", prediction.Zone, prediction.TimeToImpact)
			predictionLabel.TextColor3 = if prediction.Zone == "BULLSEYE"
				then Palette.Orange
				elseif prediction.Zone == "WALL" then Palette.Muted
				else Palette.White
		end
	else
		local ready = info.DashReadiness >= 1
		dashFill.Size = UDim2.fromScale(info.DashReadiness, 1)
		dashFill.BackgroundColor3 = Palette.Cyan
		dashFill.BackgroundTransparency = if ready then 0.35 else 0.65
		dashStroke.Color = Palette.Cyan
		dashStroke.Transparency = if ready then 0 else 0.6
		dashLabel.Text = if ready then "DASH READY" else "DASH"
	end

	local showCombo = info.ComboWindow > 0
	if showCombo ~= comboVisible then
		comboVisible = showCombo
		tween(comboFrame, 0.25, { GroupTransparency = if showCombo then 0 else 1 })
	end
	comboBar.Size = UDim2.fromScale(info.ComboWindow, 1)

	if countdownGoTime then
		local remaining = countdownGoTime - workspace:GetServerTimeNow()
		if remaining > 0 then
			local digit = tostring(math.ceil(remaining))
			if digit ~= lastCountdownDigit then
				lastCountdownDigit = digit
				popCountdown(digit, Palette.White)
			end
		end
	end
end

local RESULT_ROWS = { "Momentum", "Impact Speed", "Impact Power", "Accuracy", "Time Bonus", "Combo Bonus" }

local function setRow(name: string, value: string, color: Color3?)
	local body = results:FindFirstChild("Body") :: Frame
	local row = body:FindFirstChild(name) :: Frame
	local valueLabel = row:FindFirstChild("Value") :: TextLabel
	valueLabel.Text = value
	valueLabel.TextColor3 = color or Palette.White
end

local function countUp(target: TextLabel, to: number, duration: number, prefix: string, token: number)
	local start = os.clock()
	while os.clock() - start < duration do
		if token ~= resultsToken then
			return
		end
		local alpha = (os.clock() - start) / duration
		local eased = 1 - (1 - alpha) ^ 3
		target.Text = prefix .. tostring(math.floor(to * eased))
		task.wait()
	end
	target.Text = prefix .. tostring(to)
end

-- Each row is { rowName, valueText, valueColor? }.
local function revealRows(rows: { { any } }, token: number)
	local body = results:FindFirstChild("Body") :: Frame
	for _, entry in rows do
		local row = body:FindFirstChild(entry[1]) :: Frame
		row.Visible = true
		local value = row:FindFirstChild("Value") :: TextLabel
		value.Text = entry[2]
		value.TextColor3 = entry[3] or Palette.White
		value.TextTransparency = 1
		tween(value, 0.2, { TextTransparency = 0 })
		task.wait(0.16)
		if token ~= resultsToken then
			return
		end
	end
end

function UIController.showVerifying()
	resultsToken += 1
	results.Visible = true
	local body = results:FindFirstChild("Body") :: Frame
	(body:FindFirstChild("Title") :: TextLabel).Text = "VERIFYING..."
	for _, name in RESULT_ROWS do
		setRow(name, "...", Palette.Muted)
	end
	(body:FindFirstChild("Final") :: TextLabel).Text = "-"
	(body:FindFirstChild("Banner") :: TextLabel).Text = ""
	(body:FindFirstChild("CoinsEarned") :: TextLabel).Text = ""
	results.GroupTransparency = 0.2
end

function UIController.showResults(payload: any)
	resultsToken += 1
	local token = resultsToken
	local breakdown = payload.Breakdown
	local body = results:FindFirstChild("Body") :: Frame
	local title = body:FindFirstChild("Title") :: TextLabel
	local final = body:FindFirstChild("Final") :: TextLabel
	local banner = body:FindFirstChild("Banner") :: TextLabel
	local coinsEarned = body:FindFirstChild("CoinsEarned") :: TextLabel

	results.Visible = true
	UIController.setSlamMode(false)
	speedFrame.Visible = false
	results.GroupTransparency = 1
	resultsScale.Scale = 0.85
	tween(results, 0.3, { GroupTransparency = 0 })
	tween(resultsScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	banner.Text = ""
	coinsEarned.Text = ""
	final.Text = "0"
	for _, name in RESULT_ROWS do
		setRow(name, "", nil)
	end

	if payload.Reason then
		title.Text = "RUN NOT VERIFIED"
		title.TextColor3 = Palette.Orange
		banner.Text = string.upper(tostring(payload.Reason))
		banner.TextColor3 = Palette.Muted
		final.Text = "-"
		return
	elseif breakdown.Outcome == "TimeUp" then
		title.Text = "TIME UP"
		title.TextColor3 = Palette.Orange
		banner.Text = "REACH THE LAUNCH RAMP BEFORE 0.00"
		banner.TextColor3 = Palette.Muted
		return
	end

	title.Text = "SPRINT COMPLETE"
	title.TextColor3 = Palette.White
	local zoneLabel = string.format("%s  x%s", breakdown.Zone, tostring(breakdown.Multiplier))
	local zoneColor = if breakdown.Zone == "BULLSEYE" then Palette.Orange elseif breakdown.Zone == "WALL" then Palette.Muted else Palette.Cyan

	task.spawn(function()
		task.wait(0.25)
		revealRows({
			{ "Momentum", string.format("%d st/s avg", breakdown.Momentum) },
			{ "Impact Speed", string.format("%d st/s", breakdown.ImpactSpeed) },
			{ "Impact Power", tostring(breakdown.ImpactPower), Palette.Cyan },
			{ "Accuracy", zoneLabel, zoneColor },
			{ "Time Bonus", "+" .. tostring(breakdown.TimeBonus) },
			{ "Combo Bonus", "+" .. tostring(breakdown.ComboBonus) },
		}, token)
		if token ~= resultsToken then
			return
		end
		countUp(final, breakdown.Final, 0.7, "", token)
		if token ~= resultsToken then
			return
		end
		local scale = final:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = final })
		scale.Scale = 1.25
		tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		if (payload.Coins or 0) > 0 then
			coinsEarned.Text = string.format("+%d COINS", payload.Coins)
		end
		if payload.IsNewBest then
			banner.Text = "NEW PERSONAL BEST!"
			banner.TextColor3 = Palette.Orange
			local bannerScale = banner:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = banner })
			bannerScale.Scale = 0.4
			tween(bannerScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		elseif payload.BestScore then
			banner.Text = "BEST  " .. tostring(payload.BestScore)
			banner.TextColor3 = Palette.Muted
		end
	end)
end

function UIController.hideResults()
	resultsToken += 1
	if results.Visible then
		local t = tween(results, 0.15, { GroupTransparency = 1 })
		local token = resultsToken
		t.Completed:Once(function()
			if token == resultsToken then
				results.Visible = false
			end
		end)
	end
end

function UIController.resetRun()
	UIController.hideResults()
	speedFrame.Visible = true
	UIController.setSlamMode(false)
	UIController.setFlight(false)
	fadeText(splitLabel, false)
	comboMultiplier.Text = "x1"
	comboTotal.Text = "+0"
	comboEvent.Text = ""
end

return UIController
