--[[
	Placement  (ModuleScript)
	Location: ReplicatedStorage > BaseShared > Placement

	Shared smart-connect / snapping maths. The CLIENT uses it to draw the ghost
	outline, the SERVER runs the exact same code to validate the placement, so
	the two can never disagree (and exploiters can't place things anywhere).

	Every placed piece stores these attributes:
	  BuildType, BuildId, Owner, State ("Blueprint" / "Built"),
	  Center (CFrame), Size (Vector3)
	  Tiles:      FloorY
	  Walls:      HostTile (BuildId), Side ("PX","NX","PZ","NZ")
	  Components: HostTile (BuildId), Slot ("A","B","C" or "ALL")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent:WaitForChild("Config"))

local Placement = {}

local UP = Vector3.yAxis
local SIDES = {
	PX = Vector3.new(1, 0, 0),
	NX = Vector3.new(-1, 0, 0),
	PZ = Vector3.new(0, 0, 1),
	NZ = Vector3.new(0, 0, -1),
}
Placement.SIDES = SIDES
Placement.SIDE_ORDER = { "PX", "NX", "PZ", "NZ" }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
local function xzDist(a, b)
	return (flat(a) - flat(b)).Magnitude
end
Placement.XZDist = xzDist

------------------------------------------------------------------ lookups
function Placement.GetRoot()
	return workspace:FindFirstChild(Config.Build.RootFolder)
end

-- Template can be one name or a list of names (first one that exists wins)
function Placement.TemplateNames(typeName)
	local def = Config.Buildables[typeName]
	local t = def and def.Template or typeName
	return type(t) == "table" and t or { t }
end

function Placement.TemplateName(typeName)
	local folder = ReplicatedStorage:FindFirstChild(Config.Build.TemplatesFolder)
	local names = Placement.TemplateNames(typeName)
	if folder then
		for _, n in ipairs(names) do
			if folder:FindFirstChild(n) then
				return n
			end
		end
	end
	return names[1]
end

function Placement.GetTemplate(typeName)
	local folder = ReplicatedStorage:FindFirstChild(Config.Build.TemplatesFolder)
	return folder and folder:FindFirstChild(Placement.TemplateName(typeName))
end

function Placement.Def(model)
	return model and Config.Buildables[model:GetAttribute("BuildType") or ""]
end

-- The "main" part of a model: a part called Base, otherwise the biggest part
function Placement.MainPart(model)
	if model:IsA("BasePart") then
		return model
	end
	local base = model:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base
	end
	local best, bestVol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVol then
				best, bestVol = d, v
			end
		end
	end
	return best
end

-- Size + pivot offset of a template (cached)
local infoCache = {}
function Placement.GetInfo(typeName)
	local model = Placement.GetTemplate(typeName)
	if not model then
		return nil
	end
	local cached = infoCache[typeName]
	if cached and cached.Model == model then
		return cached
	end
	local bbCF, size = model:GetBoundingBox()
	cached = { Model = model, Size = size, Offset = bbCF:ToObjectSpace(model:GetPivot()) }
	infoCache[typeName] = cached
	return cached
end

-- Walk up from any part to the placed piece model it belongs to
function Placement.GetPiece(inst)
	local root = Placement.GetRoot()
	while inst and inst ~= root and inst ~= workspace and inst ~= game do
		if inst:IsA("Model") and inst:GetAttribute("BuildType") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

function Placement.GetPieces()
	local out = {}
	local root = Placement.GetRoot()
	if not root then
		return out
	end
	for _, folder in ipairs(root:GetChildren()) do
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and Placement.Def(m) then
				table.insert(out, m)
			end
		end
	end
	return out
end

------------------------------------------------------------------ sockets
-- A socket = the centre of an edge at floor level + the outward direction
function Placement.TileSockets(model)
	local cf, size = model:GetAttribute("Center"), model:GetAttribute("Size")
	local res = {}
	for side, n in pairs(SIDES) do
		local half = math.abs(n.X) * size.X / 2 + math.abs(n.Z) * size.Z / 2
		local worldN = cf:VectorToWorldSpace(n)
		res[side] = {
			Pos = cf.Position + worldN * half - Vector3.new(0, size.Y / 2, 0),
			Normal = worldN,
			Length = (math.abs(n.X) > 0) and size.Z or size.X, -- edge length
		}
	end
	return res
end

local function longAxis(size)
	return (size.X >= size.Z) and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
end

function Placement.LinearSockets(model)
	local cf, size = model:GetAttribute("Center"), model:GetAttribute("Size")
	local axis = longAxis(size)
	local half = (axis.X == 1) and size.X / 2 or size.Z / 2
	local w = cf:VectorToWorldSpace(axis)
	local down = Vector3.new(0, size.Y / 2, 0)
	return {
		{ Pos = cf.Position + w * half - down, Normal = w },
		{ Pos = cf.Position - w * half - down, Normal = -w },
	}
end

function Placement.SocketsMatch(a, b)
	return xzDist(a.Pos, b.Pos) <= Config.Build.SocketTolerance
		and math.abs(a.Pos.Y - b.Pos.Y) <= Config.Build.HeightTolerance
		and a.Normal:Dot(b.Normal) < -0.7
end

------------------------------------------------------------------ context
-- One scan of everything placed: who is connected to what.
-- ownerId (optional) = only include that player's pieces.
function Placement.BuildContext(ownerId)
	local ctx = {
		Tiles = {}, Linears = {}, Walls = {}, Components = {}, ById = {},
		TileSockets = {}, LinearSockets = {},
		TileSide = {},          -- [tile][side] = {Kind="Linear"/"Wall", Model=...}
		LinearSocketUsed = {},  -- [linear][socketIndex] = tile
		TileSlots = {},         -- [tile][slotName] = component
		TileComponents = {},    -- [tile] = {components}
		TileAdj = {},           -- [tile] = { neighbour tiles that touch it edge-to-edge }
		TileShared = {},        -- [tile][side] = length of that edge touching other tiles
		TileSideNeighbors = {}, -- [tile][side] = { tiles touching that edge }
	}
	for _, m in ipairs(Placement.GetPieces()) do
		local def = Placement.Def(m)
		local ownerOk = ownerId == nil or m:GetAttribute("Owner") == ownerId
		if ownerOk and m:GetAttribute("Center") and m:GetAttribute("Size") then
			local id = m:GetAttribute("BuildId")
			if id then
				ctx.ById[id] = m
			end
			if def.Kind == "Tile" then
				table.insert(ctx.Tiles, m)
				ctx.TileSockets[m] = Placement.TileSockets(m)
				ctx.TileSide[m], ctx.TileSlots[m], ctx.TileComponents[m] = {}, {}, {}
				ctx.TileAdj[m], ctx.TileShared[m], ctx.TileSideNeighbors[m] = {}, {}, {}
			elseif def.Kind == "Linear" then
				table.insert(ctx.Linears, m)
				ctx.LinearSockets[m] = Placement.LinearSockets(m)
				ctx.LinearSocketUsed[m] = {}
			elseif def.Kind == "Wall" then
				table.insert(ctx.Walls, m)
			elseif def.Kind == "Component" then
				table.insert(ctx.Components, m)
			end
		end
	end

	-- Tiles placed directly against each other (merged rooms)
	local tol = Config.Build.SocketTolerance
	for i = 1, #ctx.Tiles do
		local a = ctx.Tiles[i]
		for j = i + 1, #ctx.Tiles do
			local b = ctx.Tiles[j]
			for sideA, sa in pairs(ctx.TileSockets[a]) do
				for sideB, sb in pairs(ctx.TileSockets[b]) do
					if sa.Normal:Dot(sb.Normal) < -0.9
						and math.abs((sb.Pos - sa.Pos):Dot(sa.Normal)) <= tol
						and math.abs(sa.Pos.Y - sb.Pos.Y) <= Config.Build.HeightTolerance then
						local t = UP:Cross(sa.Normal)
						local o = (sb.Pos - sa.Pos):Dot(t)
						local overlap = math.min(sa.Length / 2, o + sb.Length / 2) - math.max(-sa.Length / 2, o - sb.Length / 2)
						if overlap > tol then
							ctx.TileShared[a][sideA] = (ctx.TileShared[a][sideA] or 0) + overlap
							ctx.TileShared[b][sideB] = (ctx.TileShared[b][sideB] or 0) + overlap
							ctx.TileSideNeighbors[a][sideA] = ctx.TileSideNeighbors[a][sideA] or {}
							ctx.TileSideNeighbors[b][sideB] = ctx.TileSideNeighbors[b][sideB] or {}
							table.insert(ctx.TileSideNeighbors[a][sideA], b)
							table.insert(ctx.TileSideNeighbors[b][sideB], a)
							if not table.find(ctx.TileAdj[a], b) then
								table.insert(ctx.TileAdj[a], b)
								table.insert(ctx.TileAdj[b], a)
							end
							ctx.TileSide[a][sideA] = ctx.TileSide[a][sideA] or { Kind = "PartialTile", Model = b }
							ctx.TileSide[b][sideB] = ctx.TileSide[b][sideB] or { Kind = "PartialTile", Model = a }
						end
					end
				end
			end
		end
	end
	-- an edge completely covered by neighbours is a shared (open) edge
	for _, tile in ipairs(ctx.Tiles) do
		for side, len in pairs(ctx.TileShared[tile]) do
			if len >= ctx.TileSockets[tile][side].Length - tol then
				ctx.TileSide[tile][side].Kind = "Tile"
			end
		end
	end

	for _, lin in ipairs(ctx.Linears) do
		for i, ls in ipairs(ctx.LinearSockets[lin]) do
			for _, tile in ipairs(ctx.Tiles) do
				for side, ts in pairs(ctx.TileSockets[tile]) do
					if Placement.SocketsMatch(ls, ts) then
						ctx.TileSide[tile][side] = { Kind = "Linear", Model = lin }
						ctx.LinearSocketUsed[lin][i] = tile
					end
				end
			end
		end
	end

	for _, w in ipairs(ctx.Walls) do
		local host = ctx.ById[w:GetAttribute("HostTile") or ""]
		local side = w:GetAttribute("Side")
		if host and ctx.TileSide[host] and side then
			ctx.TileSide[host][side] = { Kind = "Wall", Model = w }
		end
	end

	for _, c in ipairs(ctx.Components) do
		local host = ctx.ById[c:GetAttribute("HostTile") or ""]
		if host and ctx.TileSlots[host] then
			ctx.TileSlots[host][c:GetAttribute("Slot") or "?"] = c
			table.insert(ctx.TileComponents[host], c)
		end
	end
	return ctx
end

------------------------------------------------------------------ overlap
-- Only tiles/connectors can block each other (walls & components use slots)
function Placement.Overlaps(cf, size, ignore)
	local root = Placement.GetRoot()
	if not root then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { root }
	local box = Vector3.new(math.max(size.X - 2, 0.2), math.max(size.Y - 0.5, 0.2), math.max(size.Z - 2, 0.2))
	for _, p in ipairs(workspace:GetPartBoundsInBox(cf, box, params)) do
		local piece = Placement.GetPiece(p)
		if piece and piece ~= ignore then
			local kind = Placement.Def(piece).Kind
			if kind == "Tile" or kind == "Linear" then
				return true
			end
		end
	end
	return false
end

local function resolveTile(hitInst, ctx)
	local piece = hitInst and Placement.GetPiece(hitInst)
	if not piece then
		return nil
	end
	local def = Placement.Def(piece)
	if def.Kind == "Tile" then
		return ctx.TileSide[piece] and piece -- nil if it's not in this context (someone else's)
	end
	local host = piece:GetAttribute("HostTile")
	return host and ctx.ById[host]
end
Placement.ResolveTile = resolveTile

-- Does this tile have a component that forbids walls (e.g. Solar Panel)?
local function tileBlocksWalls(tile, ctx)
	for _, c in ipairs(ctx.TileComponents[tile] or {}) do
		local d = Placement.Def(c)
		if d and d.BlocksWalls then
			return d
		end
	end
	return nil
end
Placement.TileBlocksWalls = tileBlocksWalls

local function tileHasWalls(tile, ctx)
	for _, occ in pairs(ctx.TileSide[tile] or {}) do
		if occ.Kind == "Wall" then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ solvers
local function yawCF(rot)
	return CFrame.Angles(0, rot * math.pi / 2, 0)
end

local function solveTile(def, info, hitPos, hitInst, rot, ctx)
	local yaw = yawCF(rot)
	local size = info.Size
	local best, bestD

	-- Smart connect: snap onto the open end of a Connector
	for _, lin in ipairs(ctx.Linears) do
		if Placement.Def(lin).ConnectsTiles then
			for i, s in ipairs(ctx.LinearSockets[lin]) do
				if not ctx.LinearSocketUsed[lin][i] then
					local n = s.Normal
					local ext = math.abs(n:Dot(yaw.RightVector)) * size.X / 2 + math.abs(n:Dot(yaw.LookVector)) * size.Z / 2
					local center = s.Pos + n * ext + Vector3.new(0, size.Y / 2, 0)
					local d = xzDist(center, hitPos)
					if d <= Config.Build.SnapRadius and (not bestD or d < bestD) then
						best, bestD = center, d
					end
				end
			end
		end
	end

	-- Smart connect: snap directly against another tile's free edge (merged rooms).
	-- Different sizes can line up centred or flush with either end.
	if Config.Build.AllowTileToTile and not def.SelfEnclosed then
		for _, tile in ipairs(ctx.Tiles) do
			local targetSealed = Placement.Def(tile).SelfEnclosed
			for side, s in pairs(ctx.TileSockets[tile]) do
				local occ = ctx.TileSide[tile][side]
				if not targetSealed and (not occ or occ.Kind == "PartialTile") then
					local n = s.Normal
					local t = UP:Cross(n)
					local extN = math.abs(n:Dot(yaw.RightVector)) * size.X / 2 + math.abs(n:Dot(yaw.LookVector)) * size.Z / 2
					local newLen = 2 * (math.abs(t:Dot(yaw.RightVector)) * size.X / 2 + math.abs(t:Dot(yaw.LookVector)) * size.Z / 2)
					local offsets = { 0 }
					local diff = (s.Length - newLen) / 2
					if math.abs(diff) > Config.Build.SocketTolerance then
						table.insert(offsets, diff)
						table.insert(offsets, -diff)
					end
					for _, off in ipairs(offsets) do
						local center = s.Pos + n * extN + t * off + Vector3.new(0, size.Y / 2, 0)
						local d = xzDist(center, hitPos)
						if d <= Config.Build.SnapRadius and (not bestD or d < bestD) then
							best, bestD = center, d
						end
					end
				end
			end
		end
	end

	local cf
	if best then
		cf = CFrame.new(best) * yaw
	else
		local g = Config.Build.GridSize
		local p = Vector3.new(math.round(hitPos.X / g) * g, hitPos.Y + size.Y / 2, math.round(hitPos.Z / g) * g)
		cf = CFrame.new(p) * yaw
		if Config.Build.RequireTerrainForFreeTiles and not (hitInst and hitInst:IsA("Terrain")) then
			return { Valid = false, CFrame = cf, Size = size, Reason = "Tiles must be placed on terrain" }
		end
	end
	if Placement.Overlaps(cf, size) then
		return { Valid = false, CFrame = cf, Size = size, Reason = "Something is in the way" }
	end
	return { Valid = true, CFrame = cf, Size = size, Snapped = best ~= nil }
end

local function solveLinear(def, info, hitPos, hitInst, rot, ctx)
	local size = info.Size
	local alongX = size.X >= size.Z
	local halfLong = (alongX and size.X or size.Z) / 2
	local best, bestN, bestD

	for _, tile in ipairs(ctx.Tiles) do
		for side, s in pairs(ctx.TileSockets[tile]) do
			if not ctx.TileSide[tile][side] then
				local center = s.Pos + s.Normal * halfLong + Vector3.new(0, size.Y / 2, 0)
				local d = xzDist(center, hitPos)
				if d <= Config.Build.SnapRadius and (not bestD or d < bestD) then
					best, bestN, bestD = center, s.Normal, d
				end
			end
		end
	end
	if not best then
		return { Valid = false, Reason = "Hover near a free tile edge" }
	end

	local cf
	if alongX then
		cf = CFrame.fromMatrix(best, bestN, UP)
	else
		cf = CFrame.fromMatrix(best, UP:Cross(bestN), UP)
	end
	if Placement.Overlaps(cf, size) then
		return { Valid = false, CFrame = cf, Size = size, Reason = "Something is in the way" }
	end
	return { Valid = true, CFrame = cf, Size = size }
end

local function solveWall(def, info, hitPos, hitInst, rot, ctx)
	local tile = resolveTile(hitInst, ctx)
	if not tile then
		return nil
	end
	if Placement.Def(tile).SelfEnclosed then
		return { Valid = false, Reason = Placement.Def(tile).DisplayName .. " is already sealed - no walls needed" }
	end
	local cf, size = tile:GetAttribute("Center"), tile:GetAttribute("Size")
	local lp = cf:PointToObjectSpace(hitPos)
	local fx, fz = math.abs(lp.X) / (size.X / 2), math.abs(lp.Z) / (size.Z / 2)
	local side, edgeDist
	if fx >= fz then
		side = lp.X >= 0 and "PX" or "NX"
		edgeDist = size.X / 2 - math.abs(lp.X)
	else
		side = lp.Z >= 0 and "PZ" or "NZ"
		edgeDist = size.Z / 2 - math.abs(lp.Z)
	end
	if edgeDist > Config.Walls.EdgeHoverDistance then
		return nil
	end

	local nLocal = SIDES[side]
	local n = cf:VectorToWorldSpace(nLocal)
	local tangent = UP:Cross(n)
	local onX = math.abs(nLocal.X) > 0
	local length = onX and size.Z or size.X
	local half = onX and size.X / 2 or size.Z / 2
	local h = Config.Walls.Height or info.Size.Y
	local th = Config.Walls.Thickness or math.min(info.Size.X, info.Size.Z)
	local floorY = tile:GetAttribute("FloorY") or (cf.Position.Y - size.Y / 2)
	local pos = flat(cf.Position) + n * (half - th / 2) + Vector3.new(0, floorY + h / 2, 0)

	local res = {
		Valid = true,
		CFrame = CFrame.fromMatrix(pos, tangent, UP),
		Size = Vector3.new(length, h, th),
		HostTile = tile, Side = side,
	}
	local blocker = tileBlocksWalls(tile, ctx)
	if tile:GetAttribute("State") ~= "Built" then
		res.Valid, res.Reason = false, "Finish building the tile first"
	elseif blocker then
		res.Valid, res.Reason = false, blocker.DisplayName .. " needs open sky - no walls on this tile"
	elseif ctx.TileSide[tile][side] then
		local kind = ctx.TileSide[tile][side].Kind
		res.Valid = false
		res.Reason = (kind == "Wall" and "There's already a wall here")
			or (kind == "Tile" and "This edge joins another tile (it's open inside the room)")
			or (kind == "PartialTile" and "Edge is partly joined - add another tile to fill the gap")
			or "A connector is on this side (walls close around it automatically)"
	end
	return res
end

local function solveComponent(def, info, hitPos, hitInst, rot, ctx)
	local tile = resolveTile(hitInst, ctx)
	if not tile then
		return nil
	end
	local tdef = Placement.Def(tile)
	local slots = tdef.Slots or {}
	local cf, size = tile:GetAttribute("Center"), tile:GetAttribute("Size")
	local occupied = ctx.TileSlots[tile]
	local slotCount = 0
	for _ in pairs(slots) do
		slotCount += 1
	end

	local slotName, offset, valid, reason = nil, Vector2.zero, true, nil
	if def.Size == "Large" then
		slotName = "ALL"
		if slotCount < 2 then
			valid, reason = false, "Large components need a large tile"
		elseif next(occupied) ~= nil then
			valid, reason = false, "Tile needs to be empty"
		end
	else
		local lp = cf:PointToObjectSpace(hitPos)
		local bestD
		for name, off in pairs(slots) do
			local p = Vector3.new(off.X * size.X, 0, off.Y * size.Z)
			local d = (Vector3.new(lp.X, 0, lp.Z) - p).Magnitude
			local free = not occupied[name] and not occupied.ALL
			-- prefer free slots
			local score = d + (free and 0 or 10000)
			if not bestD or score < bestD then
				bestD, slotName, offset = score, name, off
			end
		end
		if not slotName then
			return { Valid = false, Reason = "This tile has no slots" }
		end
		if occupied[slotName] or occupied.ALL then
			valid, reason = false, "Tile is full"
		end
	end

	local floorY = tile:GetAttribute("FloorY") or (cf.Position.Y - size.Y / 2)
	local wp = cf:PointToWorldSpace(Vector3.new(offset.X * size.X, 0, offset.Y * size.Z))
	local ccf = CFrame.new(wp.X, floorY + info.Size.Y / 2, wp.Z) * (cf - cf.Position) * yawCF(rot)

	if valid and tile:GetAttribute("State") ~= "Built" then
		valid, reason = false, "Finish building the tile first"
	elseif valid and def.BlocksWalls and (tileHasWalls(tile, ctx) or tile:FindFirstChild("AutoRoof")) then
		valid, reason = false, def.DisplayName .. " needs open sky - remove this tile's walls first"
	end
	return { Valid = valid, Reason = reason, CFrame = ccf, Size = info.Size, HostTile = tile, Slot = slotName }
end

local SOLVERS = {
	Tile = solveTile,
	Linear = solveLinear,
	Wall = solveWall,
	Component = solveComponent,
}

--[[
	Placement.Solve(typeName, hitPos, rot, hitInstance, ownerId?, ctx?)
	ownerId = the player's UserId: they can only snap to / build on their own pieces
	-> nil (nothing to show) or
	   { Valid, Reason, CFrame, Size, HostTile, Side, Slot }
]]
function Placement.Solve(typeName, hitPos, rot, hitInst, ownerId, ctx)
	local def = Config.Buildables[typeName]
	local info = Placement.GetInfo(typeName)
	if not def or not info or typeof(hitPos) ~= "Vector3" then
		return nil
	end
	local solver = SOLVERS[def.Kind]
	if not solver then
		return nil
	end
	ctx = ctx or Placement.BuildContext(Config.Build.OwnerOnlySnap and ownerId or nil)
	rot = math.floor(tonumber(rot) or 0) % 4
	return solver(def, info, hitPos, hitInst, rot, ctx)
end

return Placement
