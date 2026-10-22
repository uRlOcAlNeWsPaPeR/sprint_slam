--!strict
-- Small geometry helpers used by both the client (feel) and server (validation).

local Geometry = {}

-- Crossing from the side the normal points to (d > 0) onto/behind the plane (d <= 0).
-- Returns the crossing point and the fraction along the segment, or nil.
function Geometry.planeCrossing(p0: Vector3, p1: Vector3, planePoint: Vector3, normal: Vector3): (Vector3?, number?)
	local d0 = (p0 - planePoint):Dot(normal)
	local d1 = (p1 - planePoint):Dot(normal)
	if d0 > 0 and d1 <= 0 then
		local t = d0 / (d0 - d1)
		return p0:Lerp(p1, t), t
	end
	return nil, nil
end

function Geometry.signedDistance(point: Vector3, planePoint: Vector3, normal: Vector3): number
	return (point - planePoint):Dot(normal)
end

function Geometry.pointInBox(point: Vector3, cframe: CFrame, size: Vector3, margin: Vector3?): boolean
	local localPoint = cframe:PointToObjectSpace(point)
	local half = size / 2 + (margin or Vector3.zero)
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- Slab test of segment p0→p1 against an oriented box.
function Geometry.segmentIntersectsBox(p0: Vector3, p1: Vector3, cframe: CFrame, size: Vector3): boolean
	local a = cframe:PointToObjectSpace(p0)
	local b = cframe:PointToObjectSpace(p1)
	local d = b - a
	local half = size / 2
	local tMin, tMax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local origin = (a :: any)[axis] :: number
		local dir = (d :: any)[axis] :: number
		local extent = (half :: any)[axis] :: number
		if math.abs(dir) < 1e-6 then
			if math.abs(origin) > extent then
				return false
			end
		else
			local t1 = (-extent - origin) / dir
			local t2 = (extent - origin) / dir
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return false
			end
		end
	end
	return true
end

export type PathInfo = { points: { Vector3 }, cumulative: { number }, length: number }

function Geometry.buildPath(points: { Vector3 }): PathInfo
	local cumulative = { 0 }
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		cumulative[i] = total
	end
	return { points = points, cumulative = cumulative, length = total }
end

-- Distance travelled along the path at the closest point to `point`.
function Geometry.distanceAlongPath(path: PathInfo, point: Vector3): number
	local best, bestDistance = math.huge, 0
	local points = path.points
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local ab = b - a
		local lengthSq = ab:Dot(ab)
		local t = if lengthSq > 0 then math.clamp((point - a):Dot(ab) / lengthSq, 0, 1) else 0
		local closest = a + ab * t
		local distSq = (point - closest):Dot(point - closest)
		if distSq < best then
			best = distSq
			bestDistance = path.cumulative[i] + math.sqrt(lengthSq) * t
		end
	end
	return bestDistance
end

-- Offset of a point on the target in the target's own frame (right, up) and its radius.
function Geometry.targetOffset(point: Vector3, center: Vector3, normal: Vector3): (Vector2, number)
	local frame = CFrame.lookAt(center, center + normal)
	local localPoint = frame:PointToObjectSpace(point)
	local offset = Vector2.new(localPoint.X, localPoint.Y)
	return offset, offset.Magnitude
end

return Geometry
