--!strict
-- Course registry. Phase 5 adds daily rotation on top of this; every entry must be a
-- hand-validated template.

local Courses = {}

Courses.Default = "NeonRush"

local registry = {
	NeonRush = require(script.NeonRush),
}

function Courses.get(id: string?): any
	return registry[id or Courses.Default] or registry[Courses.Default]
end

return Courses
