--[[
	MiningService  (ModuleScript)
	Location: ServerScriptService > BaseServer > MiningService

	Finds every ProximityPrompt called "Mine" in Workspace (including ores
	added later, e.g. by ScatterBrush). The ore type is the first ancestor
	whose NAME is in Config.Ores (e.g. "GoldOre") or that has an "OreType"
	attribute. Mining requires a Tool with a BoolValue "Miner" = true.
]]

local Mining = {}
local S, Config, Inventory
local registered = {}
local depleted = {} -- [model] = token

local function resolveOre(prompt)
	local inst = prompt.Parent
	while inst and inst ~= workspace do
		local id = inst:GetAttribute("OreType") or inst.Name
		if Config.Ores[id] then
			return inst, id
		end
		inst = inst.Parent
	end
	return nil
end

local function isMiner(tool)
	local v = tool:FindFirstChild(Config.Mining.MinerValueName)
	return v ~= nil and v:IsA("BoolValue") and v.Value == true
end

local function getMinerTool(player)
	local char = player.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") and isMiner(t) then
				return t
			end
		end
	end
	if not Config.Mining.RequireEquipped then
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			for _, t in ipairs(bp:GetChildren()) do
				if t:IsA("Tool") and isMiner(t) then
					return t
				end
			end
		end
	end
	return nil
end

local function setDepleted(model, depleted)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if depleted then
				d:SetAttribute("_oreT", d.Transparency)
				d:SetAttribute("_oreCC", d.CanCollide)
				d.Transparency = math.max(d.Transparency, Config.Mining.DepletedTransparency)
				d.CanCollide = false
			elseif d:GetAttribute("_oreT") ~= nil then
				d.Transparency = d:GetAttribute("_oreT")
				d.CanCollide = d:GetAttribute("_oreCC")
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if depleted then
				d:SetAttribute("_oreT", d.Transparency)
				d.Transparency = 1
			elseif d:GetAttribute("_oreT") ~= nil then
				d.Transparency = d:GetAttribute("_oreT")
			end
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = not depleted
		end
	end
	model:SetAttribute("Depleted", depleted)
end

local function onMine(player, model, oreId)
	if model:GetAttribute("Depleted") then
		return
	end
	local tool = getMinerTool(player)
	if not tool then
		S.Notify(player, Config.Mining.RequireEquipped and "Equip a mining tool to mine this." or "You need a mining tool to mine this.")
		return
	end
	local ore = Config.Ores[oreId]
	local amount = Config.Mining.GetYield(player, tool, oreId) or 1
	setDepleted(model, true)
	Inventory.Add(player, ore.Item, amount)
	if S.BreathingService and S.BreathingService.Exert then
		S.BreathingService.Exert(player) -- mining is hard work: uses more air
	end
	S.Notify(player, string.format("+%d %s", amount, Config.ItemName(ore.Item)))

	local token = (depleted[model] or 0) + 1
	depleted[model] = token
	task.delay(ore.RespawnTime or Config.Mining.RespawnTime, function()
		if depleted[model] == token and model.Parent then
			depleted[model] = nil
			setDepleted(model, false)
		end
	end)
end

-- Instantly respawn every depleted ore (dev panel). Returns how many.
function Mining.RespawnAll()
	local n = 0
	for model in pairs(depleted) do
		depleted[model] = nil
		if model.Parent and model:GetAttribute("Depleted") then
			setDepleted(model, false)
			n += 1
		end
	end
	return n
end

local function tryRegister(inst)
	if not inst:IsA("ProximityPrompt") or inst.Name ~= Config.Mining.PromptName or registered[inst] then
		return
	end
	local model, oreId = resolveOre(inst)
	if not model then
		warn("[Mining] 'Mine' prompt with no known ore type: " .. inst:GetFullName()
			.. " (rename the ore model or give it an OreType attribute)")
		return
	end
	registered[inst] = true
	if Config.Mining.SetPromptText then
		inst.ActionText = "Mine"
		inst.ObjectText = Config.ItemName(Config.Ores[oreId].Item)
	end
	inst.Triggered:Connect(function(player)
		onMine(player, model, oreId)
	end)
	inst.Destroying:Connect(function()
		registered[inst] = nil
	end)
end

function Mining.Init(services)
	S = services
	Config = S.Config
	Inventory = S.InventoryService
	for _, d in ipairs(workspace:GetDescendants()) do
		tryRegister(d)
	end
	workspace.DescendantAdded:Connect(tryRegister)
end

return Mining
