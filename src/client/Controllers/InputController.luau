--!strict
-- Keyboard / gamepad / touch bindings. Exposes action signals plus the raw move vector
-- from the default ControlModule (so slam steering works with any input device).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)

local InputController = {}

InputController.Dash = Signal.new()
InputController.Slide = Signal.new()
InputController.Restart = Signal.new()
InputController.Lobby = Signal.new()
InputController.Music = Signal.new()
InputController.LevelKey = Signal.new() -- (level: number) number keys 1-5
InputController.NextLevel = Signal.new()

local controls: any = nil

local function bind(name: string, signal: any, title: string?, position: UDim2?, ...: Enum.KeyCode)
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			signal:Fire()
		end
		return Enum.ContextActionResult.Sink
	end, title ~= nil, ...)
	if title then
		ContextActionService:SetTitle(name, title)
		if position then
			ContextActionService:SetPosition(name, position)
		end
	end
end

function InputController.init()
	local playerModule = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any)
	controls = playerModule:GetControls()

	bind("SprintSlamDash", InputController.Dash, "DASH", UDim2.new(1, -170, 1, -150), Enum.KeyCode.LeftShift, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	bind("SprintSlamSlide", InputController.Slide, "SLIDE", UDim2.new(1, -250, 1, -90), Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	bind("SprintSlamRestart", InputController.Restart, nil, nil, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	bind("SprintSlamLobby", InputController.Lobby, nil, nil, Enum.KeyCode.L, Enum.KeyCode.ButtonSelect)
	bind("SprintSlamMusic", InputController.Music, nil, nil, Enum.KeyCode.M)
	bind("SprintSlamNextLevel", InputController.NextLevel, nil, nil, Enum.KeyCode.N)
	local levelKeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
		Enum.KeyCode.Eight,
		Enum.KeyCode.Nine,
		Enum.KeyCode.Zero, -- challenge 10
	}
	for level, keyCode in levelKeys do
		ContextActionService:BindAction("SprintSlamLevel" .. level, function(_, state)
			if state == Enum.UserInputState.Begin then
				InputController.LevelKey:Fire(level)
			end
			return Enum.ContextActionResult.Pass
		end, false, keyCode)
	end
end

local override: Vector3? = nil

-- Studio autopilot feeds its own stick input through here.
function InputController.setOverride(vector: Vector3?)
	override = vector
end

-- Raw input: X = right, Z = -1 when pushing forward. Zero when controls are disabled.
function InputController.getMoveVector(): Vector3
	if override then
		return override
	end
	if not controls then
		return Vector3.zero
	end
	return controls:GetMoveVector()
end

function InputController.setMovementEnabled(enabled: boolean)
	if not controls then
		return
	end
	if enabled then
		controls:Enable()
	else
		controls:Disable()
	end
end

return InputController
