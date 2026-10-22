--!strict
-- Builds a course from its data definition into workspace.Course. Gameplay logic never
-- reads these parts back: it uses the definition, so visuals can change freely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)

local Palette = Config.Palette
local SPEED_LINE_SPACING = 16

local CourseManager = {}

CourseManager.Active = nil :: any

local function accentColor(accent: string?): Color3
	if accent == "Orange" then
		return Palette.Orange
	elseif accent == "White" then
		return Palette.White
	end
	return Palette.Cyan
end

local function part(props: { [string]: any }): BasePart
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

local function decor(props: { [string]: any }): BasePart
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = false
	return part(props)
end

local function neon(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, transparency: number?): BasePart
	return decor({
		Name = "Glow",
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0,
		Parent = parent,
	})
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildPlatforms(course: any, parent: Instance)
	for _, def in course.Platforms do
		local color = if def.Style == "FloorAlt" then Palette.FloorAlt elseif def.Style == "Beam" then Palette.Panel else Palette.Floor
		local slab = part({ Name = def.Name, CFrame = def.CFrame, Size = def.Size, Color = color, Parent = parent })
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
			neon(slab, local3(0, side * (width / 2 - 0.25)), size3(length, 0.5), edgeColor)
		end
		-- Cross lines streaming past are the strongest cheap speed cue.
		if def.Style ~= "Beam" then
			for along = -length / 2 + SPEED_LINE_SPACING / 2, length / 2, SPEED_LINE_SPACING do
				neon(slab, local3(along, 0), size3(0.35, width - 2), Palette.Cyan, 0.8)
			end
		end
	end
end

local function buildWall(name: string, cframe: CFrame, size: Vector3, parent: Instance)
	part({
		Name = name,
		CFrame = cframe,
		Size = size,
		Color = Color3.fromRGB(70, 110, 150),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		Parent = parent,
	})
	neon(parent, cframe * CFrame.new(0, size.Y / 2 + 0.1, 0), Vector3.new(size.X + 0.1, 0.2, size.Z), Palette.Cyan)
end

local function buildRamps(course: any, parent: Instance)
	for _, def in course.Ramps do
		local delta = def.To - def.From
		local length = delta.Magnitude
		local mid = (def.From + def.To) / 2
		local surface = CFrame.lookAt(mid, mid + delta.Unit)
		local accent = if def.Name == "LaunchRamp" then Palette.Orange else Palette.Cyan
		part({
			Name = def.Name,
			CFrame = surface * CFrame.new(0, -def.Thickness / 2, 0),
			Size = Vector3.new(def.Width, def.Thickness, length),
			Color = Palette.Floor,
			Parent = parent,
		})
		for along = -length / 2 + SPEED_LINE_SPACING / 2, length / 2, SPEED_LINE_SPACING do
			neon(parent, surface * CFrame.new(0, 0.05, along), Vector3.new(def.Width - 2, 0.1, 0.35), accent, 0.8)
		end
		for _, side in { -1, 1 } do
			neon(parent, surface * CFrame.new(side * (def.Width / 2 - 0.25), 0.05, 0), Vector3.new(0.5, 0.1, length), accent)
			if def.Walls then
				buildWall(def.Name .. "Wall", surface * CFrame.new(side * (def.Width / 2 + 0.5), 1.5, 0), Vector3.new(1, 3, length), parent)
			end
		end
		if def.Name == "LaunchRamp" then
			-- Chevrons pointing up the ramp sell the launch.
			for i = 1, 4 do
				local z = length / 2 - i * (length / 5)
				for _, side in { -1, 1 } do
					local cf = surface * CFrame.new(side * 2.2, 0.08, z) * CFrame.Angles(0, side * math.rad(35), 0)
					neon(parent, cf, Vector3.new(0.6, 0.1, 6), Palette.Orange)
				end
			end
		end
	end
end

local function buildPads(course: any, parent: Instance)
	local pads = folder("BoostPads", parent)
	for index, def in course.BoostPads do
		local cf = CFrame.lookAt(def.Position, def.Position + def.Forward)
		local pad = decor({
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
				neon(pad, chevron, Vector3.new(0.5, 0.1, def.Size.X * 0.42), Palette.White)
			end
		end
		local light = Instance.new("PointLight")
		light.Color = Palette.Orange
		light.Range = 14
		light.Brightness = 2
		light.Parent = pad
	end

	local jumpPads = folder("JumpPads", parent)
	for index, def in course.JumpPads do
		local pad = decor({
			Name = "JumpPad" .. index,
			CFrame = CFrame.new(def.Position + Vector3.new(0, 0.06, 0)),
			Size = Vector3.new(def.Size.X, 0.12, def.Size.Z),
			Color = Palette.Cyan,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Parent = jumpPads,
		})
		decor({
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

	local rings = folder("BoostRings", parent)
	for index, def in course.BoostRings do
		local ring = Instance.new("Model")
		ring.Name = "BoostRing" .. index
		local frame = CFrame.lookAt(def.Position, def.Position + def.Normal)
		local segments = 18
		local segmentLength = 2 * math.pi * def.Radius / segments * 1.08
		for i = 1, segments do
			local angle = (i / segments) * math.pi * 2
			neon(ring, frame * CFrame.Angles(0, 0, angle) * CFrame.new(def.Radius, 0, 0), Vector3.new(0.7, segmentLength, 0.7), Palette.Orange)
		end
		ring.Parent = rings
	end
end

local function buildObstacles(course: any, parent: Instance)
	local obstacles = folder("Obstacles", parent)
	for index, def in course.MovingObstacles do
		local block = part({
			Name = "Obstacle" .. index,
			CFrame = def.CFrame,
			Size = def.Size,
			Color = Palette.Hazard,
			CanQuery = false,
			Parent = obstacles,
		})
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

local function buildPillars(course: any, parent: Instance)
	local pillars = folder("Pillars", parent)
	for index, def in course.Pillars do
		local column = part({
			Name = "Pillar" .. index,
			CFrame = def.CFrame,
			Size = def.Size,
			Color = Palette.Hazard,
			Parent = pillars,
		})
		neon(column, def.CFrame * CFrame.new(0, def.Size.Y / 2 + 0.1, 0), Vector3.new(def.Size.X + 0.2, 0.2, def.Size.Z + 0.2), Palette.Cyan)
		neon(column, def.CFrame * CFrame.new(0, -def.Size.Y / 2 + 1.2, 0), Vector3.new(def.Size.X + 0.1, 0.5, def.Size.Z + 0.1), Palette.Orange)
	end
end

local function buildDecor(course: any, parent: Instance)
	local decorFolder = folder("Decor", parent)
	for _, def in course.Arches do
		local color = accentColor(def.Accent)
		local base = CFrame.new(def.Position)
		for _, side in { -1, 1 } do
			neon(decorFolder, base * CFrame.new(side * def.Width / 2, def.Height / 2, 0), Vector3.new(0.8, def.Height, 0.8), color, 0.1)
		end
		neon(decorFolder, base * CFrame.new(0, def.Height, 0), Vector3.new(def.Width + 0.8, 0.8, 0.8), color, 0.1)
	end

	for _, def in course.Signs do
		local board = decor({
			Name = "Sign",
			CFrame = def.CFrame,
			Size = Vector3.new(def.Size.X, def.Size.Y, 0.2),
			Transparency = 1,
			Parent = decorFolder,
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
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = def.Text
		label.TextColor3 = Palette.White
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = accentColor(def.Accent)
		stroke.Thickness = 4
		stroke.Parent = label
	end

	-- Start line.
	neon(decorFolder, CFrame.new(0, 0.06, -20), Vector3.new(44, 0.12, 1.2), Palette.White)

	-- Checkpoint shimmer planes.
	local gates = folder("Gates", parent)
	for index, def in course.Checkpoints do
		if index > 1 then
			neon(gates, def.CFrame, Vector3.new(def.Size.X, def.Size.Y, 0.2), Palette.Cyan, 0.93)
		end
	end
end

local function buildTarget(course: any, parent: Instance)
	local target = course.Target
	local model = Instance.new("Model")
	model.Name = "Target"
	local normal: Vector3 = target.Normal
	local center: Vector3 = target.Center
	local facing = CFrame.lookAt(center, center + normal)

	local wallCenter = Vector3.new(center.X, target.WallCenterY, center.Z) - normal * 3
	part({
		Name = "SlamWall",
		CFrame = CFrame.lookAt(wallCenter, wallCenter + normal),
		Size = Vector3.new(target.WallSize.X, target.WallSize.Y, 4),
		Color = Palette.Charcoal,
		Parent = model,
	})
	local wallFace = wallCenter + normal * 2.03
	for offset = -target.WallSize.X / 2 + 20, target.WallSize.X / 2 - 20, 20 do
		neon(model, CFrame.lookAt(wallFace, wallFace + normal) * CFrame.new(offset, 0, 0), Vector3.new(0.3, target.WallSize.Y, 0.1), Palette.Cyan, 0.75)
	end
	for offset = -target.WallSize.Y / 2 + 20, target.WallSize.Y / 2 - 20, 20 do
		neon(model, CFrame.lookAt(wallFace, wallFace + normal) * CFrame.new(0, offset, 0), Vector3.new(target.WallSize.X, 0.3, 0.1), Palette.Cyan, 0.75)
	end

	local zoneStyles = {
		OUTER = { Fill = Color3.fromRGB(44, 48, 62), Rim = Palette.Cyan, Material = Enum.Material.SmoothPlastic },
		MIDDLE = { Fill = Color3.fromRGB(78, 86, 104), Rim = Palette.White, Material = Enum.Material.SmoothPlastic },
		INNER = { Fill = Palette.Cyan, Rim = Palette.White, Material = Enum.Material.Neon },
		BULLSEYE = { Fill = Palette.Orange, Rim = Palette.White, Material = Enum.Material.Neon },
	}
	local zones = Config.Target.Zones
	local layer = 0
	for i = #zones, 1, -1 do
		local zone = zones[i]
		local style = zoneStyles[zone.Name]
		for _, piece in { { Radius = zone.Radius + 0.7, Color = style.Rim, Material = Enum.Material.Neon, Suffix = "Rim" }, { Radius = zone.Radius, Color = style.Fill, Material = style.Material, Suffix = "" } } do
			local depth = -0.9 + layer * 0.15
			layer += 1
			decor({
				Name = "Zone_" .. zone.Name .. piece.Suffix,
				Shape = Enum.PartType.Cylinder,
				CFrame = facing * CFrame.new(0, 0, -depth) * CFrame.Angles(0, math.pi / 2, 0),
				Size = Vector3.new(0.5, piece.Radius * 2, piece.Radius * 2),
				Color = piece.Color,
				Material = piece.Material,
				Parent = model,
			})
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Palette.Orange
	glow.Range = 40
	glow.Brightness = 3
	glow.Parent = model:FindFirstChild("Zone_BULLSEYE")

	-- Pit floor catches every post-impact fall.
	local launch = course.Launch.Position
	local pitLength = math.abs(center.Z - launch.Z) + 20
	local pitCenter = Vector3.new(center.X, course.PitFloorY - 1, (center.Z + launch.Z) / 2)
	part({
		Name = "PitFloor",
		CFrame = CFrame.new(pitCenter),
		Size = Vector3.new(target.WallSize.X, 2, pitLength),
		Color = Palette.Charcoal,
		Parent = model,
	})
	for offset = -target.WallSize.X / 2 + 24, target.WallSize.X / 2 - 24, 24 do
		neon(model, CFrame.new(pitCenter + Vector3.new(offset, 1.05, 0)), Vector3.new(0.4, 0.1, pitLength), Palette.Orange, 0.5)
	end

	model.Parent = parent
end

function CourseManager.build(courseId: string?)
	local course = Courses.get(courseId)
	local existing = workspace:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Course"
	local geometry = folder("Geometry", root)
	buildPlatforms(course, geometry)
	for _, def in course.Walls do
		buildWall(def.Name, def.CFrame, def.Size, geometry)
	end
	buildRamps(course, geometry)
	buildPads(course, root)
	buildObstacles(course, root)
	buildPillars(course, root)
	buildDecor(course, root)
	buildTarget(course, root)
	root:SetAttribute("CourseId", course.Id)
	root.Parent = workspace

	ReplicatedStorage:SetAttribute("ActiveCourse", course.Id)
	CourseManager.Active = course
	return course
end

return CourseManager
