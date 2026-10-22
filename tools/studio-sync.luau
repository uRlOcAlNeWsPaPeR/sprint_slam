-- Live sync without Rojo: run `node tools/build-place.js --serve`, then paste this into
-- Studio's command bar (or run it through an MCP execute call) in Edit mode.
-- HTTP is enabled only for the fetch and restored afterwards.

local HttpService = game:GetService("HttpService")
local was = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local ok, body = pcall(function()
	return HttpService:GetAsync("http://127.0.0.1:34873/manifest.json", true)
end)
HttpService.HttpEnabled = was
if not ok then
	error("Sprint Slam sync failed: " .. tostring(body))
end

local manifest = HttpService:JSONDecode(body)
local changed, created = 0, 0
for _, entry in manifest do
	local node: Instance = game:GetService(entry.path[1])
	for i = 2, #entry.path do
		local name = entry.path[i]
		local isLeaf = i == #entry.path
		local child = node:FindFirstChild(name)
		if child and isLeaf and child.ClassName ~= entry.className then
			child:Destroy()
			child = nil
		end
		if not child then
			child = Instance.new(if isLeaf then entry.className else "Folder")
			child.Name = name
			child.Parent = node
			created += 1
		end
		node = child
	end
	if entry.source and (node :: any).Source ~= entry.source then
		(node :: any).Source = entry.source
		changed += 1
	end
end
print(string.format("Sprint Slam sync: %d entries, %d sources changed, %d created", #manifest, changed, created))
