--[[
	WaterService  (ModuleScript)
	Location: ServerScriptService > BaseServer > WaterService

	Water is shared across a base (the same groups as power: tiles joined by
	connectors / edges) and is STORED over time:

	  Producers  WaterOutput  (Water Pump, needs power)
	  Storage    WaterCapacity (Water Tank). Attribute "Water" = amount inside
	  Consumers  WaterUse      (Oxygen Generator, per second, while powered)
	             Greenhouse    Config.Farming.WaterPerPlot x growing plots

	Every tick: production + stored water is handed out to consumers in order
	(oxygen first, then greenhouses). A consumer that gets its water has
	attribute Watered = true. Leftover goes into the tanks.
	When an oxygen generator gains/loses water, the network is recalculated.

	Published for the build menu (on tiles + connectors of the group):
	  WaterIn, WaterOut (per second), WaterStored, WaterCapacity
]]

local Water = {}
local S, Config, Placement, Network

local function built(m)
	return m and m.Parent and m:GetAttribute("State") == "Built"
end

local function useOf(m, def)
	if def.Plots then
		return (m:GetAttribute("GrowingPlots") or 0) * Config.Farming.WaterPerPlot
	end
	return def.WaterUse or 0
end

local function tick(dt)
	local changed = false
	for _, g in ipairs(Network.Groups) do
		local produce, capacity, stored = 0, 0, 0
		local tanks, consumers = {}, {}
		for _, c in ipairs(g.Components) do
			if built(c) then
				local d = Placement.Def(c)
				if d.WaterOutput and c:GetAttribute("Powered") then
					produce += d.WaterOutput
				end
				if d.WaterCapacity then
					capacity += d.WaterCapacity
					stored += c:GetAttribute("Water") or 0
					table.insert(tanks, c)
				end
				if d.WaterUse then
					table.insert(consumers, { Model = c, Use = c:GetAttribute("Powered") and useOf(c, d) or 0, Priority = 1 })
				end
			end
		end
		for _, n in ipairs(g.Nodes) do
			local d = Placement.Def(n)
			if d.Plots and built(n) then
				table.insert(consumers, { Model = n, Use = useOf(n, d), Priority = 2 })
			end
		end
		table.sort(consumers, function(a, b)
			return a.Priority < b.Priority
		end)

		-- hand out water
		local available = stored + produce * dt
		local used = 0
		for _, con in ipairs(consumers) do
			local need = con.Use * dt
			local ok = need <= available + 1e-6
			if ok then
				available -= need
				used += con.Use
			end
			if con.Model:GetAttribute("Watered") ~= ok then
				con.Model:SetAttribute("Watered", ok)
				if Placement.Def(con.Model).OxygenSource then
					changed = true
				end
			end
		end

		-- store what's left, split evenly across tanks
		local newStored = math.clamp(available, 0, capacity)
		for _, t in ipairs(tanks) do
			local share = capacity > 0 and newStored * (Placement.Def(t).WaterCapacity / capacity) or 0
			t:SetAttribute("Water", math.floor(share * 10) / 10)
		end
		for _, n in ipairs(g.Nodes) do
			n:SetAttribute("WaterIn", produce)
			n:SetAttribute("WaterOut", used)
			n:SetAttribute("WaterStored", math.floor(newStored))
			n:SetAttribute("WaterCapacity", capacity)
		end
	end
	if changed then
		Network.Request()
	end
end

function Water.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Network = S.NetworkService

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Water.TickRate)
			local now = os.clock()
			local ok, err = pcall(tick, now - last)
			last = now
			if not ok then
				warn("[Water] " .. tostring(err))
			end
		end
	end)
end

-- Dev helper: fill every tank owned by a player
function Water.FillTanks(userId, empty)
	local n = 0
	for _, m in ipairs(Placement.GetPieces()) do
		local d = Placement.Def(m)
		if d.WaterCapacity and m:GetAttribute("Owner") == userId then
			m:SetAttribute("Water", empty and 0 or d.WaterCapacity)
			n += 1
		end
	end
	return n
end

return Water
