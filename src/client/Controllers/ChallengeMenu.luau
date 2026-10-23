--!strict
-- The Sprint Slam portal menu: the week's ten challenges (first clears in order, then any),
-- the two leaderboards of the highlighted challenge (BEST SCORE and FASTEST TIME), and the
-- Hall of Fame. Opens when the player stands in the portal and closes when they step out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Weeks = require(Shared.Weeks)

local Palette = Config.Palette

local ChallengeMenu = {}

ChallengeMenu.ChallengeChosen = Signal.new() -- (index: number)
ChallengeMenu.BoardRequested = Signal.new() -- (index: number)
ChallengeMenu.HallOfFameRequested = Signal.new()

local HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local MEDIUM = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local BOARD_ROWS = 5

type BoardRow = { frame: Frame, rank: TextLabel, name: TextLabel, value: TextLabel }

local week: any = nil
local courses: { any } = {}
local gui: ScreenGui
local holder: Frame
local panel: CanvasGroup
local panelScale: UIScale
local countdownLabel: TextLabel
local rows: { { button: TextButton, name: TextLabel, best: TextLabel, status: TextLabel, number: TextLabel } } = {}
local boardTitle: TextLabel
local scoreRows: { BoardRow } = {}
local timeRows: { BoardRow } = {}
local boardPage: Frame
local hallPage: Frame
local hallText: TextLabel
local tabBoard: TextButton
local tabHall: TextButton
local mineLabel: TextLabel
local opened = false
local viewing = 1
local state = { Cleared = 0, Unlocked = 1, AllCleared = false, Bests = {} :: { [string]: any } }
local lastBoardRequest = 0
local hallRequested = false

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
	return new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0 })
end

local function formatMs(ms: number?): string
	if not ms then
		return "-"
	end
	return string.format("%.2fs", ms / 1000)
end

local function formatScore(score: number?): string
	if not score then
		return "-"
	end
	local text = tostring(math.floor(score))
	return (string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2"))
end

local function shortName(name: string): string
	if #name > 15 then
		return string.sub(name, 1, 14) .. "."
	end
	return name
end

local function formatCountdown(seconds: number): string
	seconds = math.max(math.floor(seconds), 0)
	local days = seconds // 86400
	local hours = (seconds % 86400) // 3600
	local minutes = (seconds % 3600) // 60
	local secs = seconds % 60
	if days > 0 then
		return string.format("%dd %02d:%02d:%02d", days, hours, minutes, secs)
	end
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function buildBoard(parent: Instance, y: number, title: string, color: Color3): { BoardRow }
	label({
		Name = title .. "Title",
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = HEAVY,
		TextSize = 17,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		Parent = parent,
	})
	local built: { BoardRow } = {}
	for index = 1, BOARD_ROWS do
		local frame = new("Frame", {
			Name = title .. index,
			Position = UDim2.fromOffset(0, y + 24 + (index - 1) * 26),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Palette.Panel,
			BackgroundTransparency = 0.45,
			Children = { corner(6) },
			Parent = parent,
		})
		local rank = label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(24, 24), FontFace = HEAVY, TextSize = 15, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(index), Parent = frame })
		local name = label({ Position = UDim2.fromOffset(36, 0), Size = UDim2.new(0.55, 0, 1, 0), FontFace = BOLD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = "-", Parent = frame })
		local value = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), FontFace = MONO, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = frame })
		built[index] = { frame = frame, rank = rank, name = name, value = value }
	end
	return built
end

local function fillBoard(target: { BoardRow }, entries: { any }?, format: (number) -> string)
	for index, row in target do
		local entry = entries and entries[index]
		row.name.Text = if entry then shortName(entry.Name) else "-"
		row.value.Text = if entry then format(entry.Value) else ""
		local isMe = entry ~= nil and entry.UserId == Players.LocalPlayer.UserId
		row.frame.BackgroundColor3 = if isMe then Palette.Cyan else Palette.Panel
		row.frame.BackgroundTransparency = if isMe then 0.7 else 0.45
	end
end

local function statusFor(index: number): (string, Color3, boolean)
	if state.AllCleared or index <= state.Cleared then
		return "REPLAY", Palette.Cyan, true
	elseif index == state.Cleared + 1 then
		return "NEXT", Palette.Orange, true
	end
	return "LOCKED", Palette.Muted, false
end

local function refreshRows()
	for index, row in rows do
		local status, color, available = statusFor(index)
		row.status.Text = status
		row.status.TextColor3 = color
		row.button.BackgroundTransparency = if available then 0.1 else 0.6
		row.number.TextTransparency = if available then 0 else 0.55
		row.name.TextTransparency = if available then 0 else 0.55
		local bests = state.Bests[tostring(index)]
		if bests and (bests.Score or bests.TimeMs) then
			row.best.Text = string.format("BEST %s  |  %s", formatScore(bests.Score), formatMs(bests.TimeMs))
		elseif available then
			row.best.Text = if index == state.Cleared + 1 and not state.AllCleared then "CLEAR THIS TO UNLOCK THE NEXT" else "NOT PLAYED YET"
		else
			row.best.Text = "CLEAR CHALLENGE " .. tostring(index - 1) .. " FIRST"
		end
		row.best.TextTransparency = if available then 0 else 0.55
		row.button.UIStroke.Color = if index == viewing then Palette.Orange else Palette.Cyan
		row.button.UIStroke.Transparency = if index == viewing then 0 else 0.6
	end
end

local function view(index: number)
	viewing = index
	boardTitle.Text = string.format("CHALLENGE %d  -  %s", index, courses[index].DisplayName)
	local bests = state.Bests[tostring(index)]
	mineLabel.Text = if bests and (bests.Score or bests.TimeMs)
		then string.format("YOUR BEST   %s   |   %s", formatScore(bests.Score), formatMs(bests.TimeMs))
		else "YOU HAVEN'T SET A SCORE HERE YET"
	fillBoard(scoreRows, nil, formatScore)
	fillBoard(timeRows, nil, formatMs)
	refreshRows()
	if os.clock() - lastBoardRequest > 0.4 then
		lastBoardRequest = os.clock()
		ChallengeMenu.BoardRequested:Fire(index)
	end
end

local function showTab(name: string)
	boardPage.Visible = name == "Board"
	hallPage.Visible = name == "Hall"
	tabBoard.BackgroundTransparency = if name == "Board" then 0 else 0.6
	tabHall.BackgroundTransparency = if name == "Hall" then 0 else 0.6
	if name == "Hall" and not hallRequested then
		hallRequested = true
		ChallengeMenu.HallOfFameRequested:Fire()
	end
end

function ChallengeMenu.init(activeWeek: any, allCourses: { any })
	week = activeWeek
	courses = allCourses
	gui = new("ScreenGui", {
		Name = "SprintSlamMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	holder = new("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	panel = new("CanvasGroup", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(960, 600),
		BackgroundColor3 = Palette.Charcoal,
		BackgroundTransparency = 0.04,
		Children = { corner(16), stroke(Palette.Orange, 2, 0.2) },
		Parent = holder,
	})
	panelScale = new("UIScale", { Parent = panel })
	local function resize()
		local viewport = workspace.CurrentCamera.ViewportSize
		panelScale.Scale = math.clamp(math.min(viewport.X / 1060, viewport.Y / 680), 0.5, 1.2)
	end
	resize()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

	label({
		Name = "Title",
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.fromOffset(520, 34),
		FontFace = HEAVY,
		TextSize = 30,
		TextColor3 = Palette.Orange,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = week.Title .. "  -  SPRINT SLAM",
		Parent = panel,
	})
	countdownLabel = label({
		Name = "Countdown",
		Position = UDim2.fromOffset(24, 48),
		Size = UDim2.fromOffset(520, 20),
		FontFace = MONO,
		TextSize = 15,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = panel,
	})

	-- Challenge list (left)
	local list = new("Frame", { Name = "List", Position = UDim2.fromOffset(24, 80), Size = UDim2.fromOffset(500, 488), BackgroundTransparency = 1, Parent = panel })
	for index, course in courses do
		local button = new("TextButton", {
			Name = "Challenge" .. index,
			Position = UDim2.fromOffset(0, (index - 1) * 49),
			Size = UDim2.new(1, 0, 0, 45),
			BackgroundColor3 = Palette.Panel,
			AutoButtonColor = false,
			Text = "",
			Children = { corner(10), stroke(Palette.Cyan, 1.5, 0.6) },
			Parent = list,
		})
		local number = label({ Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(34, 45), FontFace = HEAVY, TextSize = 24, TextColor3 = Palette.Cyan, Text = tostring(index), Parent = button })
		local name = label({ Position = UDim2.fromOffset(54, 4), Size = UDim2.new(0.55, 0, 0, 22), FontFace = HEAVY, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = course.DisplayName, Parent = button })
		local best = label({ Position = UDim2.fromOffset(54, 26), Size = UDim2.new(0.7, 0, 0, 16), FontFace = MEDIUM, TextSize = 13, TextColor3 = Palette.Muted, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = button })
		local status = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.25, 0, 1, 0), FontFace = HEAVY, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = button })
		rows[index] = { button = button, name = name, best = best, status = status, number = number }
		button.MouseEnter:Connect(function()
			view(index)
		end)
		button.Activated:Connect(function()
			local _, _, available = statusFor(index)
			if available then
				ChallengeMenu.ChallengeChosen:Fire(index)
			else
				view(index)
			end
		end)
	end

	-- Right side: tabs + pages
	tabBoard = new("TextButton", { Position = UDim2.fromOffset(548, 80), Size = UDim2.fromOffset(190, 32), BackgroundColor3 = Palette.Cyan, AutoButtonColor = true, FontFace = HEAVY, TextSize = 15, TextColor3 = Palette.Charcoal, Text = "LEADERBOARDS", Children = { corner(8) }, Parent = panel })
	tabHall = new("TextButton", { Position = UDim2.fromOffset(746, 80), Size = UDim2.fromOffset(190, 32), BackgroundColor3 = Palette.Orange, AutoButtonColor = true, FontFace = HEAVY, TextSize = 15, TextColor3 = Palette.Charcoal, Text = "HALL OF FAME", BackgroundTransparency = 0.6, Children = { corner(8) }, Parent = panel })
	tabBoard.Activated:Connect(function()
		showTab("Board")
	end)
	tabHall.Activated:Connect(function()
		showTab("Hall")
	end)

	boardPage = new("Frame", { Name = "BoardPage", Position = UDim2.fromOffset(548, 124), Size = UDim2.fromOffset(388, 444), BackgroundTransparency = 1, Parent = panel })
	boardTitle = label({ Size = UDim2.new(1, 0, 0, 26), FontFace = HEAVY, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = boardPage })
	mineLabel = label({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20), FontFace = MEDIUM, TextSize = 14, TextColor3 = Palette.Muted, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = boardPage })
	scoreRows = buildBoard(boardPage, 56, "BEST SCORE", Palette.Orange)
	timeRows = buildBoard(boardPage, 232, "FASTEST TIME", Palette.Cyan)
	label({
		Position = UDim2.fromOffset(0, 408),
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = MEDIUM,
		TextSize = 13,
		TextColor3 = Palette.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Score = impact power x ring + time bonus (faster = more points) + combo. Time = GO to launch. Only server-verified runs count.",
		Parent = boardPage,
	})

	hallPage = new("Frame", { Name = "HallPage", Position = UDim2.fromOffset(548, 124), Size = UDim2.fromOffset(388, 444), BackgroundTransparency = 1, Visible = false, Parent = panel })
	hallText = label({
		Size = UDim2.fromScale(1, 1),
		FontFace = MEDIUM,
		TextSize = 15,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Loading...",
		Parent = hallPage,
	})
	label({
		Position = UDim2.new(0, 24, 1, -26),
		Size = UDim2.fromOffset(500, 20),
		FontFace = MEDIUM,
		TextSize = 14,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = if UserInputService.TouchEnabled then "Tap a challenge to start  |  step out of the portal to close" else "Click a challenge or press 1-9, 0 for #10  |  step out of the portal to close",
		Parent = panel,
	})
end

function ChallengeMenu.isOpen(): boolean
	return opened
end

-- Opens (or refreshes) the menu with the player's progress. `data` is a RunState/RunResult
-- payload: Cleared, Unlocked, AllCleared, Bests.
function ChallengeMenu.open(data: any)
	state.Cleared = data.Cleared or state.Cleared
	state.Unlocked = data.Unlocked or state.Unlocked
	state.AllCleared = data.AllCleared == true
	state.Bests = data.Bests or state.Bests
	if not opened then
		opened = true
		holder.Visible = true
		-- Start on the next challenge to clear (or the first when all are done).
		viewing = if state.AllCleared then 1 else math.clamp(state.Cleared + 1, 1, #courses)
		showTab("Board")
	end
	view(viewing)
end

function ChallengeMenu.close()
	if opened then
		opened = false
		holder.Visible = false
	end
end

function ChallengeMenu.update()
	if opened then
		countdownLabel.Text = string.format("NEW WEEK IN  %s", formatCountdown(Weeks.endsAt(week) - workspace:GetServerTimeNow()))
	end
end

function ChallengeMenu.showBoard(data: any)
	if data.Challenge ~= viewing then
		return
	end
	fillBoard(scoreRows, data.Score, formatScore)
	fillBoard(timeRows, data.Time, formatMs)
end

local function hallLines(list: { any }): string
	if #list == 0 then
		return string.format(
			"<b>No champions yet.</b>\n\nWhen a week ends, the top player on every challenge's score and time boards is inducted here, along with that week's champion (most board wins).\n\nThe first inductions happen when %s ends.",
			week.Title
		)
	end
	local entry = list[1]
	local lines = { string.format("<b>%s CHAMPION</b>", entry.Title) }
	if entry.Champion then
		table.insert(lines, string.format('<font color="#FF7A1A"><b>%s</b></font>  (%d board wins)\n', shortName(entry.Champion.Name), entry.Champion.Wins))
	end
	for index in entry.Winners do
		local row = entry.Winners[index]
		local def = courses[index]
		local name = if def then def.DisplayName else "CHALLENGE " .. index
		local score = if row.Score then string.format("%s %s", shortName(row.Score.Name), formatScore(row.Score.Value)) else "-"
		local time = if row.Time then string.format("%s %s", shortName(row.Time.Name), formatMs(row.Time.Value)) else "-"
		table.insert(lines, string.format('%d. %s\n    <font color="#FF7A1A">%s</font>   <font color="#00E5FF">%s</font>', index, name, score, time))
	end
	return table.concat(lines, "\n")
end

function ChallengeMenu.showHallOfFame(list: { any })
	hallText.Text = hallLines(list)
end

ChallengeMenu.hallLines = hallLines
ChallengeMenu.formatScore = formatScore
ChallengeMenu.formatMs = formatMs

return ChallengeMenu
