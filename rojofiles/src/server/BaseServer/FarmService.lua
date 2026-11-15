--[[
	FarmService  (ModuleScript)
	Location: ServerScriptService > BaseServer > FarmService

	Every BUILT buildable with Plots = N (the Greenhouse Dome) gets N soil
	plots on its floor. Each plot has an [E] prompt:
	  empty  -> hold a seed (Config.Crops) and press E to plant
	  growing-> shows progress; pauses without power / water
	  ready  -> press E to harvest: food + 1-2 seeds back

	Plot attributes: Seed, Progress (0-1), Ready
	Greenhouse attribute GrowingPlots (WaterService uses it for water demand)

	API: Farm.GrowAll(userId) (dev)
]]

local Farm = {}
local S, Config, Placement, Inventory, Build
local greenhouses = {} -- [model] = { plots }

local SOIL = Color3.fromRGB(105, 70, 45)
local LEAF = Color3.fromRGB(90, 170, 70)

------------------------------------------------------------------ visuals
local function setVisual(plot)
	local old = plot:FindFirstChild("Crop")
	local seed = plot:GetAttribute("Seed")
	local progress = plot:GetAttribute("Progress") or 0
	local stage = not seed and -1 or (plot:GetAttribute("Ready") and 2 or (progress < 0.34 and 0 or 1))
	if old and old:GetAttribute("Stage") == stage then
		return
	end
	if old then
		old:Destroy()
	end
	if stage < 0 then
		return
	end
	local crop = Config.Crops[seed]
	local model = Instance.new("Model")
	model.Name = "Crop"
	model:SetAttribute("Stage", stage)
	local top = plot.Position + Vector3.new(0, plot.Size.Y / 2, 0)
	local function part(size, cf, color, shape)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Size, p.CFrame, p.Color = size, cf, color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	-- 4 plants per plot
	local h = ({ [0] = 0.8, [1] = 2.2, [2] = 3 })[stage]
	for _, off in ipairs({ Vector3.new(-1.6, 0, -1.6), Vector3.new(1.6, 0, -1.6), Vector3.new(-1.6, 0, 1.6), Vector3.new(1.6, 0, 1.6) }) do
		local base = top + off
		part(Vector3.new(h, 0.4, 0.4), CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), LEAF, Enum.PartType.Cylinder)
		part(Vector3.new(h * 0.9, h * 0.5, h * 0.9), CFrame.new(base + Vector3.new(0, h * 0.85, 0)), LEAF, Enum.PartType.Ball)
		if stage == 2 then
			part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(base + Vector3.new(0.5, h * 0.7, 0.3)), crop.Color, Enum.PartType.Ball)
			part(Vector3.new(0.8, 0.8, 0.8), CFrame.new(base + Vector3.new(-0.4, h * 0.9, -0.4)), crop.Color, Enum.PartType.Ball)
		end
	end
	model.Parent = plot
end

local function blockers(gh)
	local why = {}
	if Config.Farming.RequiresPower and not gh:GetAttribute("Powered") then
		table.insert(why, "no power")
	end
	if Config.Farming.RequiresWater and gh:GetAttribute("Watered") == false then
		table.insert(why, "no water")
	end
	return why
end

local function refreshPrompt(gh, plot)
	local prompt = plot:FindFirstChild("PlotPrompt", true)
	if not prompt then
		return
	end
	local seed = plot:GetAttribute("Seed")
	if not seed then
		prompt.ActionText = "Plant seed"
		prompt.ObjectText = "Empty plot (hold a seed)"
	elseif plot:GetAttribute("Ready") then
		prompt.ActionText = "Harvest"
		prompt.ObjectText = Config.Crops[seed].Crop .. " - ready!"
	else
		local why = blockers(gh)
		prompt.ActionText = "Check"
		prompt.ObjectText = string.format("%s %d%%%s", Config.Crops[seed].Crop,
			math.floor((plot:GetAttribute("Progress") or 0) * 100),
			#why > 0 and ("  (paused: " .. table.concat(why, ", ") .. ")") or "")
	end
end

------------------------------------------------------------------ interaction
local function onPlot(player, gh, plot)
	if not Build.CanUse(player, gh) then
		S.Notify(player, "That's not your greenhouse.")
		return
	end
	local seed = plot:GetAttribute("Seed")
	if not seed then
		local held = Inventory.GetHeld(player)
		if not held or not Config.Crops[held] then
			S.Notify(player, "Hold a seed to plant it. You can make seeds at the Fabricator.")
			return
		end
		if Inventory.Remove(player, held, 1) == 1 then
			plot:SetAttribute("Seed", held)
			plot:SetAttribute("Progress", 0)
			plot:SetAttribute("Ready", false)
			S.Notify(player, "Planted " .. Config.Crops[held].Crop)
		end
	elseif plot:GetAttribute("Ready") then
		local crop = Config.Crops[seed]
		local seeds = math.random(crop.Seeds[1], crop.Seeds[2])
		Inventory.Add(player, crop.Crop, crop.Yield)
		if seeds > 0 then
			Inventory.Add(player, seed, seeds)
		end
		plot:SetAttribute("Seed", nil)
		plot:SetAttribute("Progress", 0)
		plot:SetAttribute("Ready", false)
		S.Notify(player, string.format("+%d %s, +%d %s", crop.Yield, Config.ItemName(crop.Crop), seeds, Config.ItemName(seed)))
	else
		local why = blockers(gh)
		S.Notify(player, #why > 0 and ("Growth paused: " .. table.concat(why, ", ")) or "Still growing...")
	end
	setVisual(plot)
	refreshPrompt(gh, plot)
end

------------------------------------------------------------------ setup
local function setup(gh)
	if greenhouses[gh] then
		return
	end
	local def = Placement.Def(gh)
	local cf, size = gh:GetAttribute("Center"), gh:GetAttribute("Size")
	local floorY = gh:GetAttribute("FloorY") or (cf.Position.Y - size.Y / 2)
	local ps = Config.Farming.PlotSize
	local count = def.Plots or 8
	local cols = math.ceil(count / 2)
	local spacing = ps.X + 2
	local plots = {}

	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = gh
	for i = 1, count do
		local row = (i - 1) % 2
		local col = (i - 1) // 2
		local x = (col - (cols - 1) / 2) * spacing
		local z = (row - 0.5) * (ps.Z + 4)
		local plot = Instance.new("Part")
		plot.Name = "Plot"
		plot.Anchored = true
		plot.Size = ps
		plot.Color = SOIL
		plot.Material = Enum.Material.Ground
		plot.CFrame = CFrame.new(cf:PointToWorldSpace(Vector3.new(x, 0, z)) * Vector3.new(1, 0, 1) + Vector3.new(0, floorY + ps.Y / 2, 0))
			* (cf - cf.Position)
		plot:SetAttribute("Progress", 0)
		plot:SetAttribute("Ready", false)
		plot.Parent = folder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PlotPrompt"
		prompt.HoldDuration = 0.2
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = plot
		prompt.Triggered:Connect(function(player)
			onPlot(player, gh, plot)
		end)
		table.insert(plots, plot)
		refreshPrompt(gh, plot)
	end
	greenhouses[gh] = plots
	gh.Destroying:Connect(function()
		greenhouses[gh] = nil
	end)
end

function Farm.GrowAll(userId)
	local n = 0
	for gh, plots in pairs(greenhouses) do
		if gh:GetAttribute("Owner") == userId then
			for _, plot in ipairs(plots) do
				if plot:GetAttribute("Seed") and not plot:GetAttribute("Ready") then
					plot:SetAttribute("Progress", 1)
					plot:SetAttribute("Ready", true)
					setVisual(plot)
					refreshPrompt(gh, plot)
					n += 1
				end
			end
		end
	end
	return n
end

local function tick(dt)
	for gh, plots in pairs(greenhouses) do
		if gh.Parent then
			local canGrow = #blockers(gh) == 0
			local growing = 0
			for _, plot in ipairs(plots) do
				local seed = plot:GetAttribute("Seed")
				if seed and not plot:GetAttribute("Ready") then
					growing += 1
					if canGrow then
						local p = (plot:GetAttribute("Progress") or 0) + dt / Config.Crops[seed].GrowTime
						if p >= 1 then
							plot:SetAttribute("Progress", 1)
							plot:SetAttribute("Ready", true)
						else
							plot:SetAttribute("Progress", p)
						end
						setVisual(plot)
					end
				end
				refreshPrompt(gh, plot)
			end
			gh:SetAttribute("GrowingPlots", growing)
		end
	end
end

function Farm.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Build = S.BuildService

	Build.PieceBuilt.Event:Connect(function(model)
		local def = Placement.Def(model)
		if def and def.Plots then
			setup(model)
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		if Placement.Def(m).Plots and m:GetAttribute("State") == "Built" then
			setup(m)
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Farming.TickRate)
			local now = os.clock()
			local ok, err = pcall(tick, now - last)
			last = now
			if not ok then
				warn("[Farm] " .. tostring(err))
			end
		end
	end)
end

return Farm
