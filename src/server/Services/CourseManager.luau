--!strict
-- Builds a course from its data definition into workspace.Course. Gameplay logic never
-- reads these parts back: it uses the definition, so visuals can change freely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Courses = require(Shared.Courses)

local BuildKit = require(script.Parent.BuildKit)

local Palette = Config.Palette
local decor, neon, part, folder = BuildKit.decor, BuildKit.neon, BuildKit.part, BuildKit.folder

local CourseManager = {}

CourseManager.Active = nil :: any

local function buildCourseMarkings(course: any, parent: Instance)
	-- Start line.
	neon(parent, CFrame.new(0, 0.06, -20), Vector3.new(44, 0.12, 1.2), Palette.White)

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

-- options.Preview: edit-time preview (Studio plugin). The folder is not saved with the
-- place and the live course is not published, since the server rebuilds it on Play.
function CourseManager.build(courseId: string?, options: { Preview: boolean? }?)
	local preview = options ~= nil and options.Preview == true
	local course = Courses.get(courseId)
	local existing = workspace:FindFirstChild("Course")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "Course"
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
	buildTarget(course, root)
	root:SetAttribute("CourseId", course.Id)
	if preview then
		root.Archivable = false
		root.Parent = workspace
		return course
	end
	root.Parent = workspace

	ReplicatedStorage:SetAttribute("ActiveCourse", course.Id)
	CourseManager.Active = course
	return course
end

return CourseManager
