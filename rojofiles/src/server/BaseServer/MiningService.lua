--[[
	MiningService  (ModuleScript)
	Location: ServerScriptService > BaseServer > MiningService

	ORES
	  Any Model inside the folders in Config.Mining.OreFolders (Workspace >
	  Resources, ScatterBrush_Placed) whose name is in Config.Ores, or in
	  Config.OreAliases, or that has an "OreType" attribute, is an ore.
	  A "Mine" ProximityPrompt is added automatically if it has none.
	  Ore attributes: OreType, OreHealth, OreMaxHealth, OreTier, Depleted

	DRILLING (several hits)
	  PC: equip the drill and click the ore (DrillClient -> "DrillHit" remote)
	  Mobile/console: every press of the Mine prompt is one hit
	  Damage per hit and cooldown come from Config.Drill.Tiers[tier].
	  An ore needs drill tier >= Config.Ores[id].Tier.
	  The player who lands the final hit gets the ore. A damaged ore heals
	  after Config.Drill.HealAfter seconds without hits.

	DRILL TIERS
	  Player attribute "DrillTier" (saved). Tools with a BoolValue "Miner"
	  are renamed "Drill [T1]" etc. and get attribute DrillTier.
	  Mining.UpgradeDrill(player) is used by the Fabricator.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mining = {}
local S, Config, Inventory
local ores = {}        -- [model] = oreId
local depleted = {}    -- [model] = token
local lastHit = {}     -- [player] = os.clock()
local lastWarn = {}    -- [player] = os.clock()
local remotes = {}

------------------------------------------------------------------ helpers
function Mining.ResolveOreId(model)
	local id = model:GetAttribute("OreType") or model.Name
	id = Config.OreAliases[id] or id
	return Config.Ores[id] and id or nil
end

-- Walk up from any part to the ore model it belongs to
function Mining.GetOre(inst)
	while inst and inst ~= workspace do
		if ores[inst] then
			return inst, ores[inst]
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
		for _, t in ipairs(bp and bp:GetChildren() or {}) do
			if t:IsA("Tool") and isMiner(t) then
				return t
			end
		end
	end
	return nil
end

local function notify(player, msg)
	local now = os.clock()
	if lastWarn[player] and now - lastWarn[player] < 1.5 then
		return
	end
	lastWarn[player] = now
	S.Notify(player, msg)
end

local function setDepleted(model, isDepleted)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if isDepleted then
				d:SetAttribute("_oreT", d.Transparency)
				d:SetAttribute("_oreCC", d.CanCollide)
				d.Transparency = math.max(d.Transparency, Config.Mining.DepletedTransparency)
				d.CanCollide = false
			elseif d:GetAttribute("_oreT") ~= nil then
				d.Transparency = d:GetAttribute("_oreT")
				d.CanCollide = d:GetAttribute("_oreCC")
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if isDepleted then
				d:SetAttribute("_oreT", d.Transparency)
				d.Transparency = 1
			elseif d:GetAttribute("_oreT") ~= nil then
				d.Transparency = d:GetAttribute("_oreT")
			end
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = not isDepleted
		end
	end
	model:SetAttribute("Depleted", isDepleted)
	if not isDepleted then
		model:SetAttribute("OreHealth", model:GetAttribute("OreMaxHealth"))
	end
end

------------------------------------------------------------------ drill tiers
local function tierOf(player)
	return math.clamp(player:GetAttribute("DrillTier") or 0, 0, Config.Drill.MaxTier)
end
Mining.GetTier = tierOf

local function nameTool(player, tool)
	if tool:IsA("Tool") and isMiner(tool) then
		local t = tierOf(player)
		tool.Name = string.format(Config.Drill.ToolNameFormat, t)
		tool:SetAttribute("DrillTier", t)
	end
end

local function renameAll(player)
	for _, bag in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		for _, t in ipairs(bag and bag:GetChildren() or {}) do
			nameTool(player, t)
		end
	end
end

function Mining.SetTier(player, tier)
	tier = math.clamp(math.floor(tier), 0, Config.Drill.MaxTier)
	player:SetAttribute("DrillTier", tier)
	Inventory.SetMeta(player, "DrillTier", tier)
	renameAll(player)
end

-- Fabricator: buy the next tier. Returns ok, message
function Mining.UpgradeDrill(player)
	local cur = tierOf(player)
	if cur >= Config.Drill.MaxTier then
		return false, "Your drill is already max tier"
	end
	local cost = Config.Drill.Tiers[cur + 1].Cost or {}
	if not Inventory.Has(player, cost) then
		return false, "Missing materials: " .. Config.CostText(cost)
	end
	for item, n in pairs(cost) do
		Inventory.Remove(player, item, n)
	end
	Mining.SetTier(player, cur + 1)
	return true, string.format("Drill upgraded to T%d!", cur + 1)
end

------------------------------------------------------------------ hits
function Mining.Hit(player, model, viaPrompt)
	local oreId = ores[model]
	if not oreId or model:GetAttribute("Depleted") then
		return false
	end
	local tool = getMinerTool(player)
	if not tool then
		notify(player, "Equip your drill to mine.")
		return false
	end
	local ore = Config.Ores[oreId]
	local tier = tierOf(player)
	if (ore.Tier or 0) > tier then
		notify(player, string.format("%s needs a Drill T%d (yours is T%d). Upgrade it at the Fabricator.",
			Config.ItemName(ore.Item), ore.Tier, tier))
		return false
	end
	local tierDef = Config.Drill.Tiers[tier]
	local now = os.clock()
	if lastHit[player] and now - lastHit[player] < tierDef.Cooldown * 0.85 then
		return false
	end
	-- range check (generous for the prompt, which has its own distance)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local _, size = model:GetBoundingBox()
	if not hrp or (hrp.Position - model:GetPivot().Position).Magnitude > Config.Drill.Range + size.Magnitude / 2 + (viaPrompt and 6 or 2) then
		return false
	end
	lastHit[player] = now

	local health = (model:GetAttribute("OreHealth") or ore.Health) - tierDef.Damage
	model:SetAttribute("LastHit", workspace:GetServerTimeNow())
	if S.BreathingService and S.BreathingService.Exert then
		S.BreathingService.Exert(player) -- drilling is hard work: uses more air
	end

	if health > 0 then
		model:SetAttribute("OreHealth", health)
		-- heal back if abandoned
		local stamp = model:GetAttribute("LastHit")
		task.delay(Config.Drill.HealAfter, function()
			if model.Parent and model:GetAttribute("LastHit") == stamp and not model:GetAttribute("Depleted") then
				model:SetAttribute("OreHealth", model:GetAttribute("OreMaxHealth"))
			end
		end)
		return true, health
	end

	-- broken!
	model:SetAttribute("OreHealth", 0)
	local amount = Config.Mining.GetYield(player, tool, oreId) or 1
	setDepleted(model, true)
	Inventory.Add(player, ore.Item, amount)
	S.Notify(player, string.format("+%d %s", amount, Config.ItemName(ore.Item)))

	local token = (depleted[model] or 0) + 1
	depleted[model] = token
	task.delay(ore.RespawnTime or Config.Mining.RespawnTime, function()
		if depleted[model] == token and model.Parent then
			depleted[model] = nil
			setDepleted(model, false)
		end
	end)
	return true, 0
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

------------------------------------------------------------------ registration
local function inOreFolder(inst)
	for _, name in ipairs(Config.Mining.OreFolders) do
		local f = workspace:FindFirstChild(name)
		if f and inst:IsDescendantOf(f) then
			return true
		end
	end
	return false
end

local function biggestPart(model)
	local best, vol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > vol then
				best, vol = d, v
			end
		end
	end
	return best
end

local function registerOre(model, oreId)
	if ores[model] then
		return
	end
	-- don't register an ore that sits inside another ore
	local p = model.Parent
	while p and p ~= workspace do
		if ores[p] then
			return
		end
		p = p.Parent
	end
	ores[model] = oreId
	local ore = Config.Ores[oreId]
	model:SetAttribute("OreType", oreId)
	model:SetAttribute("OreMaxHealth", ore.Health)
	model:SetAttribute("OreHealth", model:GetAttribute("OreHealth") or ore.Health)
	model:SetAttribute("OreTier", ore.Tier or 0)

	local prompt
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == Config.Mining.PromptName then
			prompt = d
			break
		end
	end
	if not prompt then
		local part = biggestPart(model)
		if not part then
			return
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = Config.Mining.PromptName
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = part
	end
	prompt.HoldDuration = 0
	if Config.Mining.SetPromptText then
		prompt.ActionText = "Drill"
		prompt.ObjectText = string.format("%s  (T%d)", Config.ItemName(ore.Item), ore.Tier or 0)
	end
	prompt.Triggered:Connect(function(player)
		Mining.Hit(player, model, true)
	end)
	model.Destroying:Connect(function()
		ores[model] = nil
		depleted[model] = nil
	end)
end

local function tryRegister(inst)
	if inst:IsA("Model") and inOreFolder(inst) then
		local id = Mining.ResolveOreId(inst)
		if id then
			registerOre(inst, id)
		end
	elseif inst:IsA("ProximityPrompt") and inst.Name == Config.Mining.PromptName then
		-- a Mine prompt outside the ore folders: use the nearest ore-named ancestor
		local p = inst.Parent
		while p and p ~= workspace do
			if p:IsA("Model") then
				local id = Mining.ResolveOreId(p)
				if id then
					registerOre(p, id)
					return
				end
			end
			p = p.Parent
		end
	end
end

------------------------------------------------------------------ init
function Mining.Init(services)
	S = services
	Config = S.Config
	Inventory = S.InventoryService

	local folder = ReplicatedStorage:WaitForChild("BaseRemotes")
	local hit = folder:FindFirstChild("DrillHit") or Instance.new("RemoteEvent")
	hit.Name = "DrillHit"
	hit.Parent = folder
	remotes.Hit = hit
	hit.OnServerEvent:Connect(function(player, target)
		if typeof(target) ~= "Instance" then
			return
		end
		local model = Mining.GetOre(target)
		if model then
			Mining.Hit(player, model, false)
		end
	end)

	-- Register ores (folders first so whole models are found before stray prompts)
	for _, name in ipairs(Config.Mining.OreFolders) do
		local f = workspace:FindFirstChild(name)
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			tryRegister(d)
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			tryRegister(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		task.defer(tryRegister, d)
	end)

	-- Drill tier: load, and keep tool names in sync
	Inventory.PlayerLoaded.Event:Connect(function(player)
		local t = Inventory.GetMeta(player, "DrillTier")
		player:SetAttribute("DrillTier", type(t) == "number" and t or 0)
		renameAll(player)
	end)
	local function hook(player)
		local function watch(container)
			container.ChildAdded:Connect(function(c)
				nameTool(player, c)
			end)
		end
		player.ChildAdded:Connect(function(c)
			if c:IsA("Backpack") then
				watch(c)
				task.defer(renameAll, player)
			end
		end)
		player.CharacterAdded:Connect(function(char)
			watch(char)
			task.delay(0.5, renameAll, player)
		end)
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			watch(bp)
		end
		if player.Character then
			watch(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastHit[p], lastWarn[p] = nil, nil
	end)
end

return Mining
