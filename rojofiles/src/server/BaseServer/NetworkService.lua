--[[
	NetworkService  (ModuleScript)
	Location: ServerScriptService > BaseServer > NetworkService

	Recalculates the whole base whenever something is built or removed:

	  ENCLOSURE  A built tile is "Enclosed" when all 4 sides have a built wall
	             (or a connector/airlock if Config.Walls.LinearCountsAsWall).
	  ROOF       Enclosed tiles get an auto-generated roof ("AutoRoof").
	  POWER      Tiles + connectors form networks. A network is powered when
	             total generator output >= total component draw (and > 0).
	             Sets tile BoolValue "Powered?" and attribute Powered on
	             tiles / connectors / components.
	  OXYGEN     Enclosed tiles joined by sealed connectors form rooms. A room
	             with a (powered) OxygenGenerator is oxygenated.
	             Sets tile BoolValue "Oxygenated?" + attribute Oxygenated.

	Other systems (farms, water...) can listen to NetworkService.Updated (ctx)
	or read the attributes above.
]]

local Network = {}
Network.Updated = Instance.new("BindableEvent")
Network.Groups = {} -- { {Nodes, Components, Powered}, ... } from the last recompute

local S, Config, Placement, Build
local pending = false

local function built(m)
	return m ~= nil and m.Parent ~= nil and m:GetAttribute("State") == "Built"
end

local function wallTemplateHeight()
	local info = Placement.GetInfo("Wall")
	return Config.Walls.Height or (info and info.Size.Y) or 12
end

local UP = Vector3.yAxis

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function wallTemplatePart()
	local t = Placement.GetTemplate("Wall")
	return t and Placement.MainPart(t)
end

local function wallThickness()
	local info = Placement.GetInfo("Wall")
	return Config.Walls.Thickness or (info and math.min(info.Size.X, info.Size.Z)) or 1
end

local function styleLike(part, ref)
	ref = ref or wallTemplatePart()
	if ref then
		part.Material = ref.Material
		part.MaterialVariant = ref.MaterialVariant
		part.Color = ref.Color
	end
end

local function updateRoof(tile, enclosed, h, ref)
	local roof = tile:FindFirstChild("AutoRoof")
	local sig = enclosed and tostring(h) or nil
	if roof and roof:GetAttribute("Sig") == sig then
		return
	end
	if roof then
		roof:Destroy()
	end
	if not enclosed then
		return
	end
	local cf, size = tile:GetAttribute("Center"), tile:GetAttribute("Size")
	local floorY = tile:GetAttribute("FloorY") or (cf.Position.Y - size.Y / 2)
	local th = Config.Walls.RoofThickness

	roof = Instance.new("Part")
	roof.Name = "AutoRoof"
	roof.Anchored = true
	roof:SetAttribute("Sig", sig)
	roof.Size = Vector3.new(size.X, th, size.Z)
	roof.CFrame = CFrame.new(cf.Position.X, floorY + h + th / 2, cf.Position.Z) * (cf - cf.Position)
	styleLike(roof, ref)
	roof.Parent = tile
end

-- Wall pieces around a connector/airlock opening so the room has no holes.
-- Left + right of the opening (full height) and a lintel above it.
local function updateFill(tile, ctx, enabled, h, ref)
	local specs, sigParts = {}, {}
	if enabled then
		for _, side in ipairs(Placement.SIDE_ORDER) do
			local occ = ctx.TileSide[tile][side]
			if occ and occ.Kind == "Linear" and built(occ.Model) then
				table.insert(specs, { Side = side, Linear = occ.Model })
				table.insert(sigParts, side .. (occ.Model:GetAttribute("BuildId") or ""))
			end
		end
	end
	local sig = table.concat(sigParts, ";") .. "|" .. tostring(h)
	if tile:GetAttribute("_fillSig") == sig then
		return
	end
	tile:SetAttribute("_fillSig", sig)
	for _, c in ipairs(tile:GetChildren()) do
		if c.Name == "AutoFill" then
			c:Destroy()
		end
	end

	local cf, size = tile:GetAttribute("Center"), tile:GetAttribute("Size")
	local floorY = tile:GetAttribute("FloorY") or (cf.Position.Y - size.Y / 2)
	local th = wallThickness()

	local function panel(base, t, from, to, y0, y1)
		local len, height = to - from, y1 - y0
		if len < 0.05 or height < 0.05 then
			return
		end
		local mid = (from + to) / 2
		local pos = base + t * mid + Vector3.new(0, (y0 + y1) / 2, 0)
		local p = Instance.new("Part")
		p.Name = "AutoFill"
		p.Anchored = true
		p.Size = Vector3.new(len, height, th)
		p.CFrame = CFrame.fromMatrix(pos, t, UP)
		styleLike(p, ref)
		p.Parent = tile
	end

	for _, spec in ipairs(specs) do
		local nLocal = Placement.SIDES[spec.Side]
		local n = cf:VectorToWorldSpace(nLocal)
		local t = UP:Cross(n)
		local onX = math.abs(nLocal.X) > 0
		local L = onX and size.Z or size.X
		local half = onX and size.X / 2 or size.Z / 2
		local base = flat(cf.Position) + n * (half - th / 2)

		local lcf, lsize = spec.Linear:GetAttribute("Center"), spec.Linear:GetAttribute("Size")
		local width = math.min(lsize.X, lsize.Z)
		local off = (flat(lcf.Position) - base):Dot(t)
		local openTop = math.clamp(lcf.Position.Y + lsize.Y / 2 - floorY, 0, h)

		panel(base, t, -L / 2, off - width / 2, floorY, floorY + h)          -- left
		panel(base, t, off + width / 2, L / 2, floorY, floorY + h)           -- right
		panel(base, t, off - width / 2, off + width / 2, floorY + openTop, floorY + h) -- above
	end
end

function Network.Recompute()
	local ctx = Placement.BuildContext()

	-- 1) Rooms = built tiles joined edge-to-edge. A room is enclosed when every
	--    outside edge of every tile has a built wall / connector, and every
	--    inside edge is fully joined to another built tile.
	local function sideClosed(tile, side)
		if Placement.Def(tile).SelfEnclosed then
			return true -- e.g. the greenhouse dome is airtight by itself
		end
		local occ = ctx.TileSide[tile][side]
		if not occ or not built(occ.Model) then
			return false
		end
		if occ.Kind == "Wall" then
			return true
		end
		if occ.Kind == "Tile" then
			-- every tile along this edge must be finished, or there's a hole
			for _, nb in ipairs(ctx.TileSideNeighbors[tile][side] or {}) do
				if not built(nb) then
					return false
				end
			end
			return true
		end
		if occ.Kind == "Linear" then
			return Config.Walls.LinearCountsAsWall
		end
		return false -- PartialTile: there's still a gap
	end

	local roomOf, rooms = {}, {}
	for _, tile in ipairs(ctx.Tiles) do
		if built(tile) and not roomOf[tile] then
			local room, queue = { Tiles = {} }, { tile }
			roomOf[tile] = room
			while #queue > 0 do
				local t = table.remove(queue)
				table.insert(room.Tiles, t)
				for _, nb in ipairs(ctx.TileAdj[t]) do
					if built(nb) and not roomOf[nb] then
						roomOf[nb] = room
						table.insert(queue, nb)
					end
				end
			end
			table.insert(rooms, room)
		end
	end

	for _, room in ipairs(rooms) do
		local enclosed, h, ref = true, nil, nil
		for _, tile in ipairs(room.Tiles) do
			if Placement.TileBlocksWalls(tile, ctx) then
				enclosed = false
			end
			for _, side in ipairs(Placement.SIDE_ORDER) do
				if not sideClosed(tile, side) then
					enclosed = false
				end
				local occ = ctx.TileSide[tile][side]
				if not h and occ and occ.Kind == "Wall" and built(occ.Model) then
					h = occ.Model:GetAttribute("Size").Y
					ref = Placement.MainPart(occ.Model)
				end
			end
		end
		local hasWalls = h ~= nil
		h = h or wallTemplateHeight()
		for _, tile in ipairs(room.Tiles) do
			local sealedShape = Placement.Def(tile).SelfEnclosed
			tile:SetAttribute("Enclosed", enclosed)
			updateRoof(tile, enclosed and not sealedShape, h, ref)
			updateFill(tile, ctx, Config.Walls.AutoFillAroundLinears and hasWalls and not sealedShape, h, ref)
		end
	end
	for _, tile in ipairs(ctx.Tiles) do
		if not roomOf[tile] then
			tile:SetAttribute("Enclosed", false)
			updateRoof(tile, false, 0)
			updateFill(tile, ctx, false, 0)
		end
	end

	-- 2) Graph: built connectors <-> built tiles, and tile <-> tile
	local adj, nodes = {}, {}
	for _, t in ipairs(ctx.Tiles) do
		if built(t) then
			adj[t] = {}
			table.insert(nodes, t)
		end
	end
	for _, l in ipairs(ctx.Linears) do
		if built(l) then
			adj[l] = {}
			table.insert(nodes, l)
		end
	end
	for _, lin in ipairs(ctx.Linears) do
		if adj[lin] then
			for _, tile in pairs(ctx.LinearSocketUsed[lin]) do
				if adj[tile] then
					table.insert(adj[lin], tile)
					table.insert(adj[tile], lin)
				end
			end
		end
	end
	for _, tile in ipairs(ctx.Tiles) do
		if adj[tile] then
			for _, nb in ipairs(ctx.TileAdj[tile]) do
				if adj[nb] then
					table.insert(adj[tile], nb) -- each pair is added from both sides
				end
			end
		end
	end

	local function flood(start, visited, canEnter)
		local group, queue = {}, { start }
		visited[start] = true
		while #queue > 0 do
			local n = table.remove(queue)
			table.insert(group, n)
			for _, nb in ipairs(adj[n]) do
				if not visited[nb] and canEnter(nb) then
					visited[nb] = true
					table.insert(queue, nb)
				end
			end
		end
		return group
	end

	local function componentsOf(group)
		local list = {}
		for _, n in ipairs(group) do
			for _, c in ipairs(ctx.TileComponents[n] or {}) do
				if built(c) then
					table.insert(list, c)
				end
			end
		end
		return list
	end

	-- 3) Power
	local powered, supplyOf, demandOf = {}, {}, {}
	local visited = {}
	local groups = {}
	for _, start in ipairs(nodes) do
		if not visited[start] then
			local group = flood(start, visited, function()
				return true
			end)
			local comps = componentsOf(group)
			local supply, demand = 0, 0
			for _, c in ipairs(comps) do
				local cdef = Placement.Def(c)
				supply += Config.Power.GetOutput(c, cdef)
				demand += cdef.PowerDraw or 0
			end
			for _, n in ipairs(group) do
				demand += Placement.Def(n).PowerDraw or 0 -- tiles that use power (greenhouse)
			end
			local on = supply > 0 and supply >= demand
			table.insert(groups, { Nodes = group, Components = comps, Powered = on })
			for _, n in ipairs(group) do
				powered[n], supplyOf[n], demandOf[n] = on, supply, demand
			end
			for _, c in ipairs(comps) do
				powered[c], supplyOf[c], demandOf[c] = on, supply, demand
			end
		end
	end

	-- 4) Oxygen (only through enclosed tiles + sealed connectors)
	--    Each working Oxygen Generator has an OxygenCapacity (in tile units).
	--    Air spreads outward from the generator rooms until capacity runs out.
	local function sealed(n)
		local d = Placement.Def(n)
		if d.Kind == "Tile" then
			return n:GetAttribute("Enclosed") == true
		end
		return d.Sealed == true
	end
	local oxygen, oxReason = {}, {}
	local oxVisited = {}
	for _, start in ipairs(nodes) do
		if not oxVisited[start] and sealed(start) then
			local group = flood(start, oxVisited, sealed)
			local inGroup = {}
			for _, n in ipairs(group) do
				inGroup[n] = true
			end
			local capacity, sources, sourceList = 0, {}, {}
			local function works(m, d)
				return built(m) and d.OxygenSource
					and (not Config.Oxygen.RequiresPower or powered[m])
					and (not (d.WaterUse or d.Plots) or m:GetAttribute("Watered") == true)
			end
			for _, n in ipairs(group) do
				local nd = Placement.Def(n)
				if nd.Kind == "Tile" and works(n, nd) then
					capacity += nd.OxygenCapacity or 0
					if not sources[n] then
						sources[n] = true
						table.insert(sourceList, n)
					end
				end
				for _, c in ipairs(ctx.TileComponents[n] or {}) do
					local cd = Placement.Def(c)
					if works(c, cd) then
						capacity += cd.OxygenCapacity or math.huge
						if not sources[n] then
							sources[n] = true
							table.insert(sourceList, n)
						end
					end
				end
			end
			if #sourceList == 0 then
				for _, n in ipairs(group) do
					oxReason[n] = "No working oxygen generator (needs power + water)"
				end
			else
				-- breadth-first from the generator rooms
				local queue, seen, head, used = {}, {}, 1, 0
				for _, n in ipairs(sourceList) do
					table.insert(queue, n)
					seen[n] = true
				end
				while head <= #queue do
					local n = queue[head]
					head += 1
					local d = Placement.Def(n)
					local units = d.Kind == "Tile" and (d.OxygenUnits or 1) or 0
					if used + units <= capacity then
						used += units
						oxygen[n] = true
					else
						oxReason[n] = "Not enough oxygen generators for this many rooms"
					end
					for _, nb in ipairs(adj[n]) do
						if inGroup[nb] and not seen[nb] then
							seen[nb] = true
							table.insert(queue, nb)
						end
					end
				end
				-- connectors only have air if a tile next to them does
				for _, n in ipairs(group) do
					if oxygen[n] and Placement.Def(n).Kind ~= "Tile" then
						local ok = false
						for _, nb in ipairs(adj[n]) do
							if oxygen[nb] and Placement.Def(nb).Kind == "Tile" then
								ok = true
								break
							end
						end
						if not ok then
							oxygen[n] = nil
							oxReason[n] = "Not enough oxygen generators for this many rooms"
						end
					end
				end
			end
		end
	end
	for _, t in ipairs(ctx.Tiles) do
		if not oxygen[t] and not oxReason[t] then
			oxReason[t] = built(t) and "Room isn't sealed (needs 4 walls + roof)" or "Not built yet"
		end
	end

	-- 5) Apply
	local function apply(list, isTile)
		for _, m in ipairs(list) do
			m:SetAttribute("Powered", powered[m] == true)
			-- Losing air isn't instant: the room keeps breathable air for LeakTime seconds
			local had, has = m:GetAttribute("Oxygenated") == true, oxygen[m] == true
			if had and not has and (Config.Oxygen.LeakTime or 0) > 0 then
				m:SetAttribute("AirLeftUntil", workspace:GetServerTimeNow() + Config.Oxygen.LeakTime)
			elseif has then
				m:SetAttribute("AirLeftUntil", nil)
			end
			m:SetAttribute("Oxygenated", has)
			m:SetAttribute("OxygenReason", oxReason[m])
			m:SetAttribute("PowerSupply", supplyOf[m] or 0)
			m:SetAttribute("PowerDemand", demandOf[m] or 0)
			if isTile then
				Build.EnsureBool(m, Config.Power.PoweredValueName, powered[m] == true)
				Build.EnsureBool(m, Config.Oxygen.ValueName, oxygen[m] == true)
			end
		end
	end
	apply(ctx.Tiles, true)
	apply(ctx.Linears, false)
	for _, c in ipairs(ctx.Components) do
		c:SetAttribute("Powered", powered[c] == true)
		c:SetAttribute("PowerSupply", supplyOf[c] or 0)
		c:SetAttribute("PowerDemand", demandOf[c] or 0)
	end

	Network.Groups = groups -- read by WaterService
	Network.Updated:Fire(ctx)
end

-- Batches many changes in the same frame into one recompute
function Network.Request()
	if pending then
		return
	end
	pending = true
	task.delay(0.1, function()
		pending = false
		Network.Recompute()
	end)
end

function Network.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Build = S.BuildService
	Build.Changed.Event:Connect(Network.Request)
	Network.Request()
end

return Network
