--!strict
-- Builds a course from its data definition into workspace.Course. Gameplay logic never
-- reads these parts back: it uses the definition, so visuals can change freely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)
local Weeks = require(Shared.Weeks)
local HazardMath = require(Shared.HazardMath)

local BuildKit = require(script.Parent.BuildKit)

local Palette = Config.Palette
local decor, neon, part, folder = BuildKit.decor, BuildKit.neon, BuildKit.part, BuildKit.folder

local CourseManager = {}

CourseManager.Week = nil :: any
CourseManager.Courses = {} :: { any }

local function buildCourseMarkings(course: any, parent: Instance)
	-- Start line.
	neon(parent, course.StartLine, Vector3.new(44, 0.12, 1.2), Palette.White)

	-- Checkpoint shimmer planes.
	local gates = folder("Gates", parent)
	for index, def in course.Checkpoints do
		if index > 1 then
			neon(gates, def.CFrame, Vector3.new(def.Size.X, def.Size.Y, 0.2), Palette.Cyan, 0.93)
		end
	end
end

-- Level hazards are built once for every level; each client shows only its own level's
-- (Level / UntilLevel attributes) and animates them from server time.
local function buildHazards(course: any, parent: Instance)
	local hazards = folder("Hazards", parent)
	for index, def in course.Hazards or {} do
		local model = Instance.new("Model")
		model.Name = "Hazard" .. index
		model:SetAttribute("Type", def.Type)
		model:SetAttribute("Level", def.Level or 1)
		if def.UntilLevel then
			model:SetAttribute("UntilLevel", def.UntilLevel)
		end
		local main: BasePart
		if def.Type == "Kill" then
			main = decor({ Name = "Main", CFrame = def.CFrame, Size = def.Size, Color = Palette.Danger, Material = Enum.Material.Neon, Transparency = 0.1, Parent = model })
			-- A dark core with glowing edges reads as "do not touch" from a distance.
			decor({ Name = "Core", CFrame = def.CFrame, Size = def.Size - Vector3.new(0.6, 0.6, 0.6), Color = Palette.Charcoal, Parent = model })
			local light = Instance.new("PointLight")
			light.Color = Palette.Danger
			light.Range = 14
			light.Brightness = 2
			light.Parent = main
		elseif def.Type == "Laser" then
			main = decor({ Name = "Main", CFrame = def.CFrame, Size = def.Size, Color = Palette.Danger, Material = Enum.Material.Neon, Transparency = 0.15, Parent = model })
			for _, side in { -1, 1 } do
				local post = def.CFrame * CFrame.new(side * (def.Size.X / 2 + 0.6), 0, 0)
				part({ Name = "Emitter", CFrame = post, Size = Vector3.new(1.2, def.Size.Y + 2, 1.2), Color = Palette.Panel, Parent = model })
				neon(model, post * CFrame.new(0, (def.Size.Y + 2) / 2 + 0.15, 0), Vector3.new(1.3, 0.3, 1.3), Palette.Danger)
			end
		elseif def.Type == "Spinner" then
			local cf = HazardMath.spinnerCFrame(def, 0)
			main = decor({ Name = "Main", CFrame = cf, Size = HazardMath.spinnerSize(def), Color = Palette.Orange, Material = Enum.Material.Neon, Parent = model })
			decor({
				Name = "Hub",
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(def.Center + Vector3.new(0, def.Height, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Size = Vector3.new(def.Height * 2 + 0.6, 3, 3),
				Color = Palette.Panel,
				Parent = model,
			})
		elseif def.Type == "Blink" then
			main = part({ Name = "Main", CFrame = def.CFrame, Size = def.Size, Color = Palette.Blink, Material = Enum.Material.Neon, Transparency = 0.3, Parent = model })
		else
			continue
		end
		model.PrimaryPart = main
		model.Parent = hazards
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

local function buildCourse(course: any, parent: Instance)
	local root = Instance.new("Folder")
	root.Name = course.Id
	local geometry = folder("Geometry", root)
	BuildKit.platforms(course.Platforms, geometry)
	BuildKit.walls(course.Walls, geometry)
	BuildKit.ramps(course.Ramps, geometry)
	BuildKit.pads(course, root)
	BuildKit.obstacles(course.MovingObstacles, root)
	BuildKit.pillars(course.Pillars, root)
	local decorFolder = folder("Decor", root)
	BuildKit.arches(course.Arches, decorFolder)
	BuildKit.signs(course.Signs, decorFolder)
	buildCourseMarkings(course, root)
	buildHazards(course, root)
	buildTarget(course, root)
	root:SetAttribute("CourseId", course.Id)
	root.Parent = parent
end

-- Builds every challenge of the current week into workspace.Courses (one folder each).
-- options.Preview: edit-time preview (Studio plugin); never saved, nothing published.
function CourseManager.build(options: { Preview: boolean? }?)
	local preview = options ~= nil and options.Preview == true
	local week = Weeks.current(os.time())
	local courses = Courses.forWeek(week)

	local existing = workspace:FindFirstChild("Courses")
	if existing then
		existing:Destroy()
	end
	local container = Instance.new("Folder")
	container.Name = "Courses"
	for _, course in courses do
		buildCourse(course, container)
	end
	if preview then
		container.Archivable = false
	end
	container.Parent = workspace
	if preview then
		return week, courses
	end

	ReplicatedStorage:SetAttribute("ActiveWeek", week.Id)
	CourseManager.Week = week
	CourseManager.Courses = courses
	return week, courses
end

return CourseManager
