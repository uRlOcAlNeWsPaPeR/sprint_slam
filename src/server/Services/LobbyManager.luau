--!strict
-- Builds THE HUB (lobby) from Shared.Lobby into workspace.Lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Lobby = require(Shared.Lobby)

local BuildKit = require(script.Parent.BuildKit)

local Palette = Config.Palette
local decor, neon, part, folder = BuildKit.decor, BuildKit.neon, BuildKit.part, BuildKit.folder

local LobbyManager = {}

local FLAT_UP = CFrame.Angles(-math.pi / 2, 0, 0) -- turns a ring's facing axis to point up

local function buildIslands(parent: Instance)
	for _, island in Lobby.Islands do
		BuildKit.disc({ Name = island.Name, Top = island.Top, Radius = island.Radius, Thickness = island.Thickness, Parent = parent })
		local flat = CFrame.new(island.Top + Vector3.new(0, 0.1, 0)) * FLAT_UP
		BuildKit.ring(parent, flat, island.Radius - 0.4, 0.5, Palette.Cyan, math.max(24, math.floor(island.Radius * 0.9)))
		for _, radius in island.Rings or {} do
			BuildKit.ring(parent, flat, radius, 0.35, Palette.Cyan, math.floor(radius * 0.9), 0.55)
		end
	end
end

local function buildColumns(parent: Instance)
	for _, column in Lobby.Columns do
		local center = column.Base + Vector3.new(0, column.Height / 2, 0)
		local upright = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
		local props = {
			Name = "Column",
			Shape = Enum.PartType.Cylinder,
			CFrame = upright,
			Size = Vector3.new(column.Height, column.Radius * 2, column.Radius * 2),
			Color = Palette.Panel,
			Parent = parent,
		}
		if column.Solid then
			part(props)
		else
			decor(props)
		end
		local color = BuildKit.accentColor(column.Accent)
		for y = 6, column.Height, 10 do
			decor({
				Name = "Band",
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(column.Base + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Size = Vector3.new(0.5, column.Radius * 2 + 0.3, column.Radius * 2 + 0.3),
				Color = color,
				Material = Enum.Material.Neon,
				Parent = parent,
			})
		end
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 24
		light.Brightness = 1.5
		light.Parent = neon(parent, CFrame.new(column.Base + Vector3.new(0, column.Height + 0.5, 0)), Vector3.new(1.4, 1, 1.4) * column.Radius, color)
	end
end

local function buildPortals(parent: Instance)
	for index, portal in Lobby.Portals do
		local model = Instance.new("Model")
		model.Name = "Portal" .. index
		local color = BuildKit.accentColor(portal.Accent)
		local frame: CFrame = portal.Frame
		BuildKit.ring(model, frame, portal.Radius, 1.3, color, 32)
		BuildKit.ring(model, frame, portal.Radius + 1.4, 0.4, Palette.White, 32, 0.4)
		local core = decor({
			Name = "Core",
			Shape = Enum.PartType.Cylinder,
			CFrame = frame * CFrame.Angles(0, math.pi / 2, 0),
			Size = Vector3.new(0.3, (portal.Radius - 0.6) * 2, (portal.Radius - 0.6) * 2),
			Color = if portal.Active then color else Palette.Charcoal,
			Material = if portal.Active then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Transparency = if portal.Active then 0.45 else 0.15,
			Parent = model,
		})
		-- Floor plate in front of the portal marks the way in.
		local plate = CFrame.lookAt(portal.Base, portal.Base + frame.LookVector) * CFrame.new(0, 0.07, -3)
		neon(model, plate, Vector3.new(portal.Radius * 2, 0.12, 10), color, if portal.Active then 0.35 else 0.75)
		for _, side in { -1, 1 } do
			neon(model, CFrame.lookAt(portal.Base, portal.Base + frame.LookVector) * CFrame.new(side * (portal.Radius + 3), portal.Radius + 1.5, 0), Vector3.new(1, portal.Radius * 2 + 3, 1), color, 0.15)
		end
		local signFrame = frame * CFrame.new(0, portal.Radius + 5, 0)
		BuildKit.signs({
			{ Text = portal.Title, CFrame = signFrame, Size = Vector2.new(26, 4.5), Accent = portal.Accent },
			{ Text = portal.Subtitle, CFrame = signFrame * CFrame.new(0, -3.6, 0), Size = Vector2.new(20, 2), Accent = "White" },
		}, model)
		if portal.Active then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 40
			light.Brightness = 4
			light.Parent = core
		end
		model:SetAttribute("Mode", portal.Mode or "")
		model.Parent = parent
	end
end

local function buildMarkers(parent: Instance)
	-- Spawn pad.
	local spawnFloor = Vector3.new(Lobby.Spawn.Position.X, Lobby.Origin.Y, Lobby.Spawn.Position.Z)
	decor({
		Name = "SpawnPad",
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(spawnFloor + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(0.12, 10, 10),
		Color = Palette.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		Parent = parent,
	})
	-- Finish zones glow so every challenge has a visible goal.
	for _, challenge in Lobby.Challenges do
		neon(parent, challenge.Finish.CFrame, challenge.Finish.Size, Palette.Orange, 0.9)
	end
	-- Slowly spinning halo over the plaza (animated on clients).
	local halo = Instance.new("Model")
	halo.Name = "Halo"
	BuildKit.ring(halo, CFrame.new(Lobby.Halo.Center) * FLAT_UP, Lobby.Halo.Radius, 0.9, Palette.Cyan, 36, 0.2)
	BuildKit.ring(halo, CFrame.new(Lobby.Halo.Center + Vector3.new(0, -3, 0)) * FLAT_UP, Lobby.Halo.Radius * 0.7, 0.5, Palette.Orange, 28, 0.3)
	halo.Parent = parent
end

-- options.Preview: edit-time preview (Studio plugin); never saved with the place.
function LobbyManager.build(options: { Preview: boolean? }?)
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Lobby"
	local geometry = folder("Geometry", root)
	buildIslands(geometry)
	BuildKit.platforms(Lobby.Platforms, geometry)
	BuildKit.walls(Lobby.Walls, geometry)
	buildColumns(geometry)
	BuildKit.pads(Lobby, root)
	BuildKit.obstacles(Lobby.MovingObstacles, root)
	local decorFolder = folder("Decor", root)
	BuildKit.arches(Lobby.Arches, decorFolder)
	BuildKit.signs(Lobby.Signs, decorFolder)
	buildMarkers(decorFolder)
	buildPortals(folder("Portals", root))
	if options and options.Preview then
		root.Archivable = false
	end
	root.Parent = workspace
	return Lobby
end

return LobbyManager
