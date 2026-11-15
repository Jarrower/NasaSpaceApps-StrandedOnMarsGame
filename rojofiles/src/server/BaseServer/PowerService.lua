--[[
	PowerService  (ModuleScript)
	Location: ServerScriptService > BaseServer > PowerService

	FUEL: any built buildable with a Fuel table (the Fuel Generator) gets an
	[E] "Add Fuel" prompt. Hold Sulfur and press it to load fuel.
	  Attribute FuelTime = seconds of running left.
	  Each Sulfur = Fuel.SecondsPerItem seconds, max Fuel.MaxItems Sulfur loaded.
	  Fuel only burns while the network needs power (Config.Power.FuelBurnsOnlyWithDemand).
	  When fuel runs out or is added, the power network is recalculated.

	SOLAR: if Config.Power.SolarDaytimeOnly is on, the network is recalculated
	when day turns to night and back.
]]

local Lighting = game:GetService("Lighting")

local Power = {}
local S, Config, Placement, Inventory, Build, Network
local active = {}

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function setupFuel(model)
	if active[model] then
		return
	end
	active[model] = true
	local def = Placement.Def(model)
	local fuel = def.Fuel
	local maxTime = fuel.SecondsPerItem * fuel.MaxItems
	if model:GetAttribute("FuelTime") == nil then
		model:SetAttribute("FuelTime", 0)
	end

	local prompt = Build.AttachPrompt(model, "AddFuel", "Add " .. Config.ItemName(fuel.Item), Enum.KeyCode.E, 0.2)
	local function refresh()
		local t = model:GetAttribute("FuelTime") or 0
		local status
		if t <= 0 then
			status = "NO FUEL"
		elseif (model:GetAttribute("PowerDemand") or 0) <= 0 and Config.Power.FuelBurnsOnlyWithDemand then
			status = "Idle (nothing to power)"
		else
			status = "Running"
		end
		prompt.ObjectText = string.format("%s - Fuel %s / %s - %s", def.DisplayName, fmtTime(t), fmtTime(maxTime), status)
	end
	model.AttributeChanged:Connect(refresh)
	refresh()

	prompt.Triggered:Connect(function(player)
		if not Build.CanUse(player, model) then
			S.Notify(player, "That's not your base.")
			return
		end
		local itemId, count = Inventory.GetHeld(player)
		if itemId ~= fuel.Item then
			S.Notify(player, "Hold " .. Config.ItemName(fuel.Item) .. " to refuel. (Refine Sulfate Ore in a Small Refinery)")
			return
		end
		local t = model:GetAttribute("FuelTime") or 0
		local space = math.floor((maxTime - t) / fuel.SecondsPerItem)
		if space <= 0 then
			S.Notify(player, "Fuel tank is full.")
			return
		end
		local took = Inventory.Remove(player, itemId, math.min(count, space))
		if took > 0 then
			model:SetAttribute("FuelTime", t + took * fuel.SecondsPerItem)
			S.Notify(player, string.format("Added %d %s", took, Config.ItemName(itemId)))
			if t <= 0 then
				Network.Request() -- generator just came back online
			end
		end
	end)

	task.spawn(function()
		while model.Parent do
			task.wait(1)
			local t = model:GetAttribute("FuelTime") or 0
			local needed = not Config.Power.FuelBurnsOnlyWithDemand or (model:GetAttribute("PowerDemand") or 0) > 0
			if t > 0 and needed then
				t = math.max(0, t - 1)
				model:SetAttribute("FuelTime", t)
				if t <= 0 then
					Network.Request() -- ran dry
				end
			end
		end
		active[model] = nil
	end)
end

function Power.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Build = S.BuildService
	Network = S.NetworkService

	Build.PieceBuilt.Event:Connect(function(model)
		local def = Placement.Def(model)
		if def and def.Fuel then
			setupFuel(model)
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		if Placement.Def(m).Fuel and m:GetAttribute("State") == "Built" then
			setupFuel(m)
		end
	end

	-- Day / night switch for solar
	task.spawn(function()
		local wasDay
		while true do
			task.wait(5)
			if Config.Power.SolarDaytimeOnly then
				local t = Lighting.ClockTime
				local isDay = t >= 6 and t <= 18
				if isDay ~= wasDay then
					wasDay = isDay
					Network.Request()
				end
			end
		end
	end)
end

return Power
