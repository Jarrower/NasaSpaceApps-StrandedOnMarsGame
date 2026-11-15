--[[
	ProcessingService  (ModuleScript)
	Location: ServerScriptService > BaseServer > ProcessingService

	Every BUILT buildable with Machine = true (SmallRefinery, LargeRefinery)
	gets two prompts:
	  [E] Insert  - hold an ore tool; the whole stack goes into the machine
	  [F] Collect - take the processed items into your inventory
	Which machine processes which ore is set in Config.Processing.Recipes.
	Machines only run while Powered (Config.Processing.RequiresPower).

	State lives in attributes so a GUI can read it later:
	  QueueItem, QueueCount, OutputItem, OutputCount, Progress (0-1)
]]

local Processing = {}
Processing.SpeedMultiplier = 1 -- dev panel can speed this up
local S, Config, Placement, Inventory, Build
local active = {}

local function statusText(model)
	local q, qi = model:GetAttribute("QueueCount") or 0, model:GetAttribute("QueueItem")
	local o, oi = model:GetAttribute("OutputCount") or 0, model:GetAttribute("OutputItem")
	local parts = {}
	if q > 0 and qi then
		table.insert(parts, string.format("In: %s x%d (%d%%)", Config.ItemName(qi), q,
			math.floor((model:GetAttribute("Progress") or 0) * 100)))
	end
	if o > 0 and oi then
		table.insert(parts, string.format("Out: %s x%d", Config.ItemName(oi), o))
	end
	if Config.Processing.RequiresPower and not model:GetAttribute("Powered") then
		table.insert(parts, "NO POWER")
	end
	return #parts > 0 and table.concat(parts, " | ") or "Idle"
end

local function machinesFor(recipe)
	local names = {}
	for m in pairs(recipe.Machines) do
		table.insert(names, Config.Buildables[m] and Config.Buildables[m].DisplayName or m)
	end
	return table.concat(names, " / ")
end

local function setup(model)
	if active[model] then
		return
	end
	active[model] = true
	local typeName = model:GetAttribute("BuildType")
	local def = Config.Buildables[typeName]

	local insertP = Build.AttachPrompt(model, "Insert", "Insert Ore", Enum.KeyCode.E, 0)
	local collectP = Build.AttachPrompt(model, "Collect", "Collect", Enum.KeyCode.F, 0)

	local function refresh()
		local txt = def.DisplayName .. " - " .. statusText(model)
		insertP.ObjectText = txt
		collectP.ObjectText = txt
		collectP.Enabled = (model:GetAttribute("OutputCount") or 0) > 0
	end
	model.AttributeChanged:Connect(refresh)
	refresh()

	insertP.Triggered:Connect(function(player)
		if not Build.CanUse(player, model) then
			S.Notify(player, "That's not your base.")
			return
		end
		local itemId, count = Inventory.GetHeld(player)
		if not itemId then
			S.Notify(player, "Hold an ore to insert it.")
			return
		end
		local recipe = Config.Processing.Recipes[itemId]
		if not recipe then
			S.Notify(player, Config.ItemName(itemId) .. " can't be processed.")
			return
		end
		if not recipe.Machines[typeName] then
			S.Notify(player, Config.ItemName(itemId) .. " needs a " .. machinesFor(recipe) .. ".")
			return
		end
		local qi, q = model:GetAttribute("QueueItem"), model:GetAttribute("QueueCount") or 0
		if q > 0 and qi ~= itemId then
			S.Notify(player, "Busy processing " .. Config.ItemName(qi) .. ".")
			return
		end
		local space = Config.Processing.MaxQueue - q
		local took = Inventory.Remove(player, itemId, math.min(count, space))
		if took <= 0 then
			S.Notify(player, "Machine is full.")
			return
		end
		model:SetAttribute("QueueItem", itemId)
		model:SetAttribute("QueueCount", q + took)
		S.Notify(player, string.format("Inserted %d %s", took, Config.ItemName(itemId)))
	end)

	collectP.Triggered:Connect(function(player)
		if not Build.CanUse(player, model) then
			return
		end
		local oi, o = model:GetAttribute("OutputItem"), model:GetAttribute("OutputCount") or 0
		if not oi or o <= 0 then
			return
		end
		model:SetAttribute("OutputCount", 0)
		model:SetAttribute("OutputItem", nil)
		Inventory.Add(player, oi, o)
		S.Notify(player, string.format("+%d %s", o, Config.ItemName(oi)))
	end)

	task.spawn(function()
		local progress = 0
		while model.Parent do
			local dt = task.wait(0.25)
			local qi, q = model:GetAttribute("QueueItem"), model:GetAttribute("QueueCount") or 0
			local recipe = qi and Config.Processing.Recipes[qi]
			local oi, o = model:GetAttribute("OutputItem"), model:GetAttribute("OutputCount") or 0
			local powered = not Config.Processing.RequiresPower or model:GetAttribute("Powered")
			local canOutput = recipe and (o == 0 or oi == recipe.Output) and o < Config.Processing.MaxOutput

			if q > 0 and recipe and powered and canOutput then
				local time = recipe.Time or Config.Processing.DefaultTime
				progress += dt * Processing.SpeedMultiplier
				if progress >= time then
					progress = 0
					q -= 1
					model:SetAttribute("QueueCount", q)
					if q <= 0 then
						model:SetAttribute("QueueItem", nil)
					end
					model:SetAttribute("OutputItem", recipe.Output)
					model:SetAttribute("OutputCount", o + (recipe.Amount or 1))
				end
				model:SetAttribute("Progress", progress / time)
			elseif q <= 0 then
				progress = 0
				if model:GetAttribute("Progress") ~= 0 then
					model:SetAttribute("Progress", 0)
				end
			end
		end
		active[model] = nil
	end)
end

function Processing.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Build = S.BuildService

	Build.PieceBuilt.Event:Connect(function(model)
		local def = Placement.Def(model)
		if def and def.Machine then
			setup(model)
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		local def = Placement.Def(m)
		if def.Machine and m:GetAttribute("State") == "Built" then
			setup(m)
		end
	end
end

return Processing
