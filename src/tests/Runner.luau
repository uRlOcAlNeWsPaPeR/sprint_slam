--!strict
-- Minimal spec runner for pure modules. From the Studio command bar or MCP:
--   require(game.ServerStorage.Tests.Runner).run()

local Runner = {}

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	eq: (actual: any, expected: any, message: string?) -> (),
	near: (actual: number, expected: number, epsilon: number?, message: string?) -> (),
	truthy: (value: any, message: string?) -> (),
}

function Runner.run(): (number, number, { string })
	local passed, failed = 0, 0
	local failures = {}
	for _, spec in script.Parent:GetChildren() do
		if spec:IsA("ModuleScript") and string.sub(spec.Name, -5) == ".spec" then
			local suite = require(spec) :: any
			local ctx: Context = {
				test = function(name, fn)
					local ok, err = pcall(fn)
					if ok then
						passed += 1
					else
						failed += 1
						table.insert(failures, `{spec.Name} > {name}: {err}`)
					end
				end,
				eq = function(actual, expected, message)
					if actual ~= expected then
						error(`{message or "expected equal"}: got {tostring(actual)}, want {tostring(expected)}`, 2)
					end
				end,
				near = function(actual, expected, epsilon, message)
					if math.abs(actual - expected) > (epsilon or 1e-6) then
						error(`{message or "expected near"}: got {actual}, want {expected}`, 2)
					end
				end,
				truthy = function(value, message)
					if not value then
						error(message or "expected truthy", 2)
					end
				end,
			}
			suite(ctx)
		end
	end
	print(`[Tests] {passed} passed, {failed} failed`)
	for _, failure in failures do
		warn("[Tests] " .. failure)
	end
	return passed, failed, failures
end

return Runner
