--!strict
-- Level hazards on the client: shows only the current level's set (locally, so players on
-- different levels share one world), animates them from server time, and reports contacts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local HazardMath = require(Shared.HazardMath)

local Hazards = {}
Hazards.__index = Hazards

-- Body extent around the root: ~1 stud to each side, feet 3 below, head 2.5 above.
local BODY_MARGIN = Vector3.new(1, 2.5, 1)
local WARNING_TIME = 0.35
local SPINNER_COOLDOWN = 0.6

type Saved = { Transparency: number, CanCollide: boolean }

export type Hazards = typeof(setmetatable(
	{} :: {
		defs: { any },
		models: { [number]: Model },
		levelParts: { BasePart }, -- base parts tagged UntilLevel
		saved: { [BasePart]: Saved },
		level: number,
		lastSpin: number,
	},
	Hazards
))

function Hazards.new(course: any, worldRoot: Instance): Hazards
	local models = {}
	local folder = worldRoot:WaitForChild("Hazards")
	for index = 1, #(course.Hazards or {}) do
		models[index] = folder:WaitForChild("Hazard" .. index) :: Model
	end
	local levelParts = {}
	for _, descendant in worldRoot:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("UntilLevel") then
			table.insert(levelParts, descendant)
		end
	end
	local self = setmetatable({
		defs = course.Hazards or {},
		models = models,
		levelParts = levelParts,
		saved = {},
		level = 0,
		lastSpin = -math.huge,
	}, Hazards)
	self:setLevel(1)
	return self
end

function Hazards.setVisible(self: Hazards, root: Instance, visible: boolean)
	local parts: { Instance } = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, item in parts do
		if item:IsA("BasePart") then
			local saved = self.saved[item]
			if not saved then
				saved = { Transparency = item.Transparency, CanCollide = item.CanCollide }
				self.saved[item] = saved
			end
			if visible then
				item.Transparency = saved.Transparency
				item.CanCollide = saved.CanCollide
			else
				item.Transparency = 1
				item.CanCollide = false
			end
		end
	end
end

function Hazards.setLevel(self: Hazards, level: number)
	if level == self.level then
		return
	end
	self.level = level
	for index, def in self.defs do
		local model = self.models[index]
		if model then
			self:setVisible(model, HazardMath.activeForLevel(def, level))
		end
	end
	for _, part in self.levelParts do
		self:setVisible(part, level <= (part:GetAttribute("UntilLevel") :: number))
	end
end

-- Flicker during the last moments before a state change so players can read the timing.
local function flicker(t: number): boolean
	return math.floor(t * 16) % 2 == 0
end

function Hazards.animate(self: Hazards, t: number)
	for index, def in self.defs do
		local model = self.models[index]
		if not model or not HazardMath.activeForLevel(def, self.level) then
			continue
		end
		local main = model.PrimaryPart
		if not main then
			continue
		end
		if def.Type == "Spinner" then
			main.CFrame = HazardMath.spinnerCFrame(def, t)
		elseif def.Type == "Laser" then
			local on = HazardMath.isOn(def, t)
			local warning = not on and HazardMath.timeToFlip(def, t) < WARNING_TIME
			main.Transparency = if on then 0.15 elseif warning and flicker(t) then 0.55 else 0.93
		elseif def.Type == "Blink" then
			local on = HazardMath.isOn(def, t)
			local warning = on and HazardMath.timeToFlip(def, t) < WARNING_TIME
			main.CanCollide = on
			main.Transparency = if not on then 0.88 elseif warning and flicker(t) then 0.7 else 0.3
		end
	end
end

-- Returns "Kill" when the runner touches something lethal, "Bonk" (+ push direction) for a
-- spinner, or nil.
function Hazards.check(self: Hazards, position: Vector3, t: number): (string?, Vector3?)
	for _, def in self.defs do
		if not HazardMath.activeForLevel(def, self.level) then
			continue
		end
		if def.Type == "Kill" or (def.Type == "Laser" and HazardMath.isOn(def, t)) then
			if Geometry.pointInBox(position, def.CFrame, def.Size, BODY_MARGIN) then
				return "Kill", nil
			end
		elseif def.Type == "Spinner" and t - self.lastSpin > SPINNER_COOLDOWN then
			if Geometry.pointInBox(position, HazardMath.spinnerCFrame(def, t), HazardMath.spinnerSize(def), BODY_MARGIN) then
				self.lastSpin = t
				-- Knocked along the bar's sweep, plus outward.
				local offset = Vector3.new(position.X - def.Center.X, 0, position.Z - def.Center.Z)
				local outward = if offset.Magnitude > 0.1 then offset.Unit else Vector3.xAxis
				local sweep = Vector3.yAxis:Cross(outward) * math.sign(def.Speed)
				return "Bonk", sweep + outward * 0.5
			end
		end
	end
	return nil, nil
end

-- Upcoming danger for the QA bot: true if a lethal hazard covers `point` at time `t`.
function Hazards.lethalAt(self: Hazards, point: Vector3, t: number): boolean
	for _, def in self.defs do
		if HazardMath.activeForLevel(def, self.level) then
			if def.Type == "Kill" or (def.Type == "Laser" and HazardMath.isOn(def, t)) then
				if Geometry.pointInBox(point, def.CFrame, def.Size, BODY_MARGIN + Vector3.new(1, 0, 1)) then
					return true
				end
			end
		end
	end
	return false
end

function Hazards.getLevel(self: Hazards): number
	return self.level
end

return Hazards
