--!strict
-- Part-building primitives shared by every world builder (course, lobby). Each builder
-- turns data definitions into parts; gameplay reads the data, never these parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Palette = Config.Palette
local SPEED_LINE_SPACING = 16

local BuildKit = {}

function BuildKit.accentColor(accent: string?): Color3
	if accent == "Orange" then
		return Palette.Orange
	elseif accent == "White" then
		return Palette.White
	elseif accent == "Muted" then
		return Palette.Muted
	end
	return Palette.Cyan
end

function BuildKit.part(props: { [string]: any }): BasePart
	local shape = props.Shape
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.SmoothPlastic
	instance.CanTouch = false
	if shape then
		instance.Shape = shape
	end
	for key, value in props do
		if key ~= "Shape" and key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

function BuildKit.decor(props: { [string]: any }): BasePart
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = false
	return BuildKit.part(props)
end

function BuildKit.neon(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, transparency: number?): BasePart
	return BuildKit.decor({
		Name = "Glow",
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0,
		Parent = parent,
	})
end

function BuildKit.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Ring of neon segments around `frame`'s Z axis (the ring faces frame.LookVector).
function BuildKit.ring(parent: Instance, frame: CFrame, radius: number, thickness: number, color: Color3, segments: number?, transparency: number?)
	local count = segments or 24
	local segmentLength = 2 * math.pi * radius / count * 1.08
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		BuildKit.neon(parent, frame * CFrame.Angles(0, 0, angle) * CFrame.new(radius, 0, 0), Vector3.new(thickness, segmentLength, thickness), color, transparency)
	end
end

-- Flat round platform; `top` is the center of its top surface.
function BuildKit.disc(props: { Name: string, Top: Vector3, Radius: number, Thickness: number, Color: Color3?, Parent: Instance }): BasePart
	return BuildKit.part({
		Name = props.Name,
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(props.Top - Vector3.yAxis * props.Thickness / 2) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(props.Thickness, props.Radius * 2, props.Radius * 2),
		Color = props.Color or Palette.Floor,
		Parent = props.Parent,
	})
end

function BuildKit.platforms(defs: { any }?, parent: Instance)
	for _, def in defs or {} do
		local color = if def.Style == "FloorAlt" then Palette.FloorAlt elseif def.Style == "Beam" then Palette.Panel else Palette.Floor
		local slab = BuildKit.part({ Name = def.Name, CFrame = def.CFrame, Size = def.Size, Color = color, Parent = parent })
		if def.UntilLevel then
			slab:SetAttribute("UntilLevel", def.UntilLevel) -- clients hide it on later levels
		end
		local top = def.Size.Y / 2 + 0.05
		local edgeColor = if def.Style == "Beam" then Palette.Orange else Palette.Cyan
		local alongX = def.EdgeAxis == "X"
		local length = if alongX then def.Size.X else def.Size.Z
		local width = if alongX then def.Size.Z else def.Size.X
		local function local3(along: number, across: number): CFrame
			return def.CFrame * (if alongX then CFrame.new(along, top, across) else CFrame.new(across, top, along))
		end
		local function size3(along: number, across: number): Vector3
			return if alongX then Vector3.new(along, 0.1, across) else Vector3.new(across, 0.1, along)
		end
		for _, side in { -1, 1 } do
			BuildKit.neon(slab, local3(0, side * (width / 2 - 0.25)), size3(length, 0.5), edgeColor)
		end
		-- Cross lines streaming past are the strongest cheap speed cue.
		if def.Style ~= "Beam" then
			for along = -length / 2 + SPEED_LINE_SPACING / 2, length / 2, SPEED_LINE_SPACING do
				BuildKit.neon(slab, local3(along, 0), size3(0.35, width - 2), Palette.Cyan, 0.8)
			end
		end
	end
end

function BuildKit.wall(name: string, cframe: CFrame, size: Vector3, parent: Instance)
	BuildKit.part({
		Name = name,
		CFrame = cframe,
		Size = size,
		Color = Color3.fromRGB(70, 110, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		Parent = parent,
	})
	BuildKit.neon(parent, cframe * CFrame.new(0, size.Y / 2 + 0.1, 0), Vector3.new(size.X + 0.1, 0.2, size.Z), Palette.Cyan)
end

function BuildKit.walls(defs: { any }?, parent: Instance)
	for _, def in defs or {} do
		BuildKit.wall(def.Name, def.CFrame, def.Size, parent)
	end
end

function BuildKit.ramps(defs: { any }?, parent: Instance)
	for _, def in defs or {} do
		local delta = def.To - def.From
		local length = delta.Magnitude
		local mid = (def.From + def.To) / 2
		local surface = CFrame.lookAt(mid, mid + delta.Unit)
		local accent = if def.Name == "LaunchRamp" then Palette.Orange else Palette.Cyan
		BuildKit.part({
			Name = def.Name,
			CFrame = surface * CFrame.new(0, -def.Thickness / 2, 0),
			Size = Vector3.new(def.Width, def.Thickness, length),
			Color = Palette.Floor,
			Parent = parent,
		})
		for along = -length / 2 + SPEED_LINE_SPACING / 2, length / 2, SPEED_LINE_SPACING do
			BuildKit.neon(parent, surface * CFrame.new(0, 0.05, along), Vector3.new(def.Width - 2, 0.1, 0.35), accent, 0.8)
		end
		for _, side in { -1, 1 } do
			BuildKit.neon(parent, surface * CFrame.new(side * (def.Width / 2 - 0.25), 0.05, 0), Vector3.new(0.5, 0.1, length), accent)
			if def.Walls then
				BuildKit.wall(def.Name .. "Wall", surface * CFrame.new(side * (def.Width / 2 + 0.5), 1.5, 0), Vector3.new(1, 3, length), parent)
			end
		end
		if def.Name == "LaunchRamp" then
			-- Chevrons pointing up the ramp sell the launch.
			for i = 1, 4 do
				local z = length / 2 - i * (length / 5)
				for _, side in { -1, 1 } do
					local cf = surface * CFrame.new(side * 2.2, 0.08, z) * CFrame.Angles(0, side * math.rad(35), 0)
					BuildKit.neon(parent, cf, Vector3.new(0.6, 0.1, 6), Palette.Orange)
				end
			end
		end
	end
end

-- Boost pads, jump pads and boost rings, named so client interactables can find them.
function BuildKit.pads(data: any, parent: Instance)
	local pads = BuildKit.folder("BoostPads", parent)
	for index, def in data.BoostPads or {} do
		local cf = CFrame.lookAt(def.Position, def.Position + def.Forward)
		local pad = BuildKit.decor({
			Name = "BoostPad" .. index,
			CFrame = cf * CFrame.new(0, 0.06, 0),
			Size = Vector3.new(def.Size.X, 0.12, def.Size.Z),
			Color = Palette.Orange,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			Parent = pads,
		})
		for i = 0, 2 do
			local z = def.Size.Z / 2 - 2.5 - i * (def.Size.Z - 3) / 3
			for _, side in { -1, 1 } do
				local chevron = cf * CFrame.new(side * def.Size.X * 0.16, 0.16, -z) * CFrame.Angles(0, side * math.rad(40), 0)
				BuildKit.neon(pad, chevron, Vector3.new(0.5, 0.1, def.Size.X * 0.42), Palette.White)
			end
		end
		local light = Instance.new("PointLight")
		light.Color = Palette.Orange
		light.Range = 14
		light.Brightness = 2
		light.Parent = pad
	end

	local jumpPads = BuildKit.folder("JumpPads", parent)
	for index, def in data.JumpPads or {} do
		local pad = BuildKit.decor({
			Name = "JumpPad" .. index,
			CFrame = CFrame.new(def.Position + Vector3.new(0, 0.06, 0)),
			Size = Vector3.new(def.Size.X, 0.12, def.Size.Z),
			Color = Palette.Cyan,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Parent = jumpPads,
		})
		BuildKit.decor({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.new(def.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Size = Vector3.new(0.1, def.Size.X * 0.7, def.Size.X * 0.7),
			Color = Palette.White,
			Material = Enum.Material.Neon,
			Parent = pad,
		})
		local light = Instance.new("PointLight")
		light.Color = Palette.Cyan
		light.Range = 16
		light.Brightness = 3
		light.Parent = pad
	end

	local rings = BuildKit.folder("BoostRings", parent)
	for index, def in data.BoostRings or {} do
		local ring = Instance.new("Model")
		ring.Name = "BoostRing" .. index
		BuildKit.ring(ring, CFrame.lookAt(def.Position, def.Position + def.Normal), def.Radius, 0.7, Palette.Orange, 18)
		ring.Parent = rings
	end
end

-- Moving obstacles are anchored; every client animates them from server time.
function BuildKit.obstacles(defs: { any }?, parent: Instance)
	local obstacles = BuildKit.folder("Obstacles", parent)
	for index, def in defs or {} do
		local block = BuildKit.part({
			Name = "Obstacle" .. index,
			CFrame = def.CFrame,
			Size = def.Size,
			Color = Palette.Hazard,
			CanQuery = false,
			Parent = obstacles,
		})
		if def.UntilLevel then
			block:SetAttribute("UntilLevel", def.UntilLevel)
		end
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = Palette.Orange
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = block
		local stripe = Instance.new("Part")
		stripe.Name = "Stripe"
		stripe.Anchored = false
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.CanTouch = false
		stripe.Massless = true
		stripe.Material = Enum.Material.Neon
		stripe.Color = Palette.Orange
		stripe.Size = Vector3.new(def.Size.X + 0.1, 0.6, def.Size.Z + 0.1)
		stripe.CFrame = def.CFrame * CFrame.new(0, def.Size.Y * 0.2, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = block
		weld.Part1 = stripe
		weld.Parent = stripe
		stripe.Parent = block
	end
end

function BuildKit.pillars(defs: { any }?, parent: Instance)
	local pillars = BuildKit.folder("Pillars", parent)
	for index, def in defs or {} do
		local column = BuildKit.part({
			Name = "Pillar" .. index,
			CFrame = def.CFrame,
			Size = def.Size,
			Color = Palette.Hazard,
			Parent = pillars,
		})
		BuildKit.neon(column, def.CFrame * CFrame.new(0, def.Size.Y / 2 + 0.1, 0), Vector3.new(def.Size.X + 0.2, 0.2, def.Size.Z + 0.2), Palette.Cyan)
		BuildKit.neon(column, def.CFrame * CFrame.new(0, -def.Size.Y / 2 + 1.2, 0), Vector3.new(def.Size.X + 0.1, 0.5, def.Size.Z + 0.1), Palette.Orange)
	end
end

function BuildKit.arches(defs: { any }?, parent: Instance)
	for _, def in defs or {} do
		local color = BuildKit.accentColor(def.Accent)
		local base = if def.CFrame then def.CFrame else CFrame.new(def.Position)
		for _, side in { -1, 1 } do
			BuildKit.neon(parent, base * CFrame.new(side * def.Width / 2, def.Height / 2, 0), Vector3.new(0.8, def.Height, 0.8), color, 0.1)
		end
		BuildKit.neon(parent, base * CFrame.new(0, def.Height, 0), Vector3.new(def.Width + 0.8, 0.8, 0.8), color, 0.1)
	end
end

-- Text signs; the front face (-Z of the CFrame) is the readable side.
function BuildKit.signs(defs: { any }?, parent: Instance)
	for _, def in defs or {} do
		local board = BuildKit.decor({
			Name = "Sign",
			CFrame = def.CFrame,
			Size = Vector3.new(def.Size.X, def.Size.Y, 0.2),
			Transparency = if def.Backing then 0.2 else 1,
			Color = Palette.Charcoal,
			Parent = parent,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = if def.Body then Enum.Font.GothamBold else Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextWrapped = true
		label.Text = def.Text
		label.TextColor3 = Palette.White
		label.Parent = gui
		if def.Body then
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0.06, 0)
			padding.PaddingRight = UDim.new(0.06, 0)
			padding.PaddingTop = UDim.new(0.06, 0)
			padding.PaddingBottom = UDim.new(0.06, 0)
			padding.Parent = label
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = BuildKit.accentColor(def.Accent)
		stroke.Thickness = if def.Body then 2 else 4
		stroke.Parent = label
	end
end

return BuildKit
