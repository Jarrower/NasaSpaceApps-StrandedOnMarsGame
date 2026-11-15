--[[
	SuitService  (ModuleScript)
	Location: ServerScriptService > BaseServer > SuitService

	Suits are WORN, not held. Each player has:
	  player attribute "Suit"     current suit id (Config.Suits)
	  saved meta "Suit", "OwnedSuits"
	Everyone owns the starting suit (Config.Breathing.StartingSuit).

	Look (Config.SuitVisuals):
	  "Tint"  - recolours the character in the suit colour + glass helmet
	  "Model" - clones ReplicatedStorage > SuitModels > [Suit.Model] onto the
	            character (Accessories are added with Humanoid:AddAccessory,
	            other parts are welded to the matching body part by name)
	  "None"  - no visual change

	FABRICATOR: any built buildable with IsFabricator = true gets an [E] prompt
	that opens the crafting window (FabricatorClient). Crafting suits and
	items (Config.Fabricator.Items) happens here on the server.

	API: Suit.Get(player) -> suitId, def     Suit.Equip(player, id)
	     Suit.Give(player, id)               Suit.Changed (player, id)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Suit = {}
Suit.Changed = Instance.new("BindableEvent")

local S, Config, Placement, Inventory, Build
local remotes = {}

------------------------------------------------------------------ data
local function owned(player)
	local list = Inventory.GetMeta(player, "OwnedSuits")
	if type(list) ~= "table" then
		list = {}
	end
	return list
end

function Suit.Owns(player, id)
	return id == Config.Breathing.StartingSuit or table.find(owned(player), id) ~= nil
end

function Suit.Get(player)
	local id = player:GetAttribute("Suit")
	if not id or not Config.Suits[id] then
		id = Config.Breathing.StartingSuit
	end
	return id, Config.Suits[id]
end

function Suit.Give(player, id)
	if not Config.Suits[id] or Suit.Owns(player, id) then
		return
	end
	local list = owned(player)
	table.insert(list, id)
	Inventory.SetMeta(player, "OwnedSuits", list)
	player:SetAttribute("OwnedSuits", table.concat(list, ","))
end

------------------------------------------------------------------ visuals
local function clearVisual(char)
	for _, d in ipairs(char:GetChildren()) do
		if d:GetAttribute("SuitVisual") then
			d:Destroy()
		end
	end
end

local function applyTint(char, def)
	local vis = Config.SuitVisuals
	if vis.HideClothing then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then
				c:Destroy() -- the avatar's clothing comes back on respawn
			end
		end
	end
	local bc = char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bc.TorsoColor3 = def.Color
	bc.LeftArmColor3, bc.RightArmColor3 = def.Color, def.Color
	bc.LeftLegColor3, bc.RightLegColor3 = def.Color, def.Color
	bc.Parent = char

	local head = char:FindFirstChild("Head")
	if vis.Helmet and head then
		local helmet = Instance.new("Part")
		helmet.Name = "SuitHelmet"
		helmet:SetAttribute("SuitVisual", true)
		helmet.Shape = Enum.PartType.Ball
		helmet.Size = Vector3.new(2.4, 2.4, 2.4)
		helmet.Material = Enum.Material.Glass
		helmet.Transparency = 0.6
		helmet.Color = def.VisorColor
		helmet.CanCollide, helmet.CanQuery, helmet.CanTouch, helmet.Massless = false, false, false, true
		helmet.CastShadow = false
		helmet.CFrame = head.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, helmet
		weld.Parent = helmet
		helmet.Parent = char
	end
end

local function applyModel(char, def)
	local folder = ReplicatedStorage:FindFirstChild("SuitModels")
	local src = folder and def.Model and folder:FindFirstChild(def.Model)
	if not src then
		applyTint(char, def)
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local items = src:IsA("Folder") and src:GetChildren() or { src }
	for _, item in ipairs(items) do
		local c = item:Clone()
		c:SetAttribute("SuitVisual", true)
		if c:IsA("Accessory") and hum then
			hum:AddAccessory(c)
		elseif c:IsA("BasePart") or c:IsA("Model") then
			local bodyPart = char:FindFirstChild(c:GetAttribute("AttachTo") or "UpperTorso") or char:FindFirstChild("Torso")
			if bodyPart then
				local part = c:IsA("Model") and (c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart", true)) or c
				c:PivotTo(bodyPart.CFrame)
				for _, p in ipairs(c:IsA("Model") and c:GetDescendants() or { c }) do
					if p:IsA("BasePart") then
						p.Anchored, p.CanCollide, p.Massless = false, false, true
						if p ~= part then
							local w = Instance.new("WeldConstraint")
							w.Part0, w.Part1 = part, p
							w.Parent = p
						end
					end
				end
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = bodyPart, part
				w.Parent = part
				c.Parent = char
			end
		end
	end
end

local function applyVisual(player)
	local char = player.Character
	if not char then
		return
	end
	clearVisual(char)
	local _, def = Suit.Get(player)
	local mode = Config.SuitVisuals.Mode
	if mode == "Tint" then
		applyTint(char, def)
	elseif mode == "Model" then
		applyModel(char, def)
	end
end

function Suit.Equip(player, id)
	if not Config.Suits[id] or not Suit.Owns(player, id) then
		return false
	end
	local _, oldDef = Suit.Get(player)
	player:SetAttribute("Suit", id)
	Inventory.SetMeta(player, "Suit", id)
	-- keep the same fraction of air in the new tank
	local tank = player:GetAttribute("O2") or oldDef.TankSeconds
	local frac = math.clamp(tank / oldDef.TankSeconds, 0, 1)
	player:SetAttribute("O2Max", Config.Suits[id].TankSeconds)
	player:SetAttribute("O2", Config.Suits[id].TankSeconds * frac)
	applyVisual(player)
	Suit.Changed:Fire(player, id)
	return true
end

------------------------------------------------------------------ fabricator
local function fabricatorList(player)
	-- what the client shows: drill upgrade, suits, item recipes
	local list = {}
	local tier = S.MiningService and S.MiningService.GetTier(player) or 0
	local nextTier = Config.Drill.Tiers[tier + 1]
	table.insert(list, {
		Kind = "Drill", Id = "Drill", Order = 0, Tier = tier, MaxTier = Config.Drill.MaxTier,
		Name = nextTier and string.format("Drill Upgrade  T%d -> T%d", tier, tier + 1) or string.format("Drill  T%d (max)", tier),
		Cost = nextTier and nextTier.Cost or nil,
		Damage = (nextTier or Config.Drill.Tiers[tier]).Damage,
	})
	for id, def in pairs(Config.Suits) do
		table.insert(list, {
			Kind = "Suit", Id = id, Name = def.DisplayName, Order = def.Order or 99,
			Cost = def.Recipe, TankSeconds = def.TankSeconds, StormProtection = def.StormProtection,
		})
	end
	for i, r in ipairs(Config.Fabricator.Items) do
		table.insert(list, {
			Kind = "Item", Id = "Item" .. i, Item = r.Item, Amount = r.Amount or 1,
			Name = Config.ItemName(r.Item), Order = 100 + i, Cost = r.Cost,
		})
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

local function nearFabricator(player, model)
	if typeof(model) ~= "Instance" or not model.Parent then
		return false, "Fabricator not found"
	end
	local def = Placement.Def(model)
	if not def or not def.IsFabricator or model:GetAttribute("State") ~= "Built" then
		return false, "Not a fabricator"
	end
	if not Build.CanUse(player, model) then
		return false, "That's not your fabricator"
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local center = model:GetAttribute("Center")
	if not hrp or (center and (hrp.Position - center.Position).Magnitude > 25) then
		return false, "Move closer to the fabricator"
	end
	if Config.Fabricator.RequiresPower and not model:GetAttribute("Powered") then
		return false, "The fabricator has no power"
	end
	return true
end

local function pay(player, cost)
	if not cost then
		return true
	end
	if not Inventory.Has(player, cost) then
		return false
	end
	for item, n in pairs(cost) do
		Inventory.Remove(player, item, n)
	end
	return true
end

local function onAction(player, action, model, id)
	local ok, err = nearFabricator(player, model)
	if not ok then
		return false, err
	end
	if action == "CraftSuit" then
		local def = Config.Suits[id]
		if not def then
			return false, "Unknown suit"
		end
		if Suit.Owns(player, id) then
			return false, "You already own this suit"
		end
		if not pay(player, def.Recipe) then
			return false, "Missing materials: " .. Config.CostText(def.Recipe)
		end
		Suit.Give(player, id)
		Suit.Equip(player, id)
		return true, def.DisplayName .. " crafted and equipped!"
	elseif action == "EquipSuit" then
		if Suit.Equip(player, id) then
			return true, "Equipped " .. Config.Suits[id].DisplayName
		end
		return false, "You don't own that suit"
	elseif action == "UpgradeDrill" then
		local okUp, msg = S.MiningService.UpgradeDrill(player)
		return okUp, msg, fabricatorList(player)
	elseif action == "CraftItem" then
		local index = tonumber(string.match(tostring(id), "^Item(%d+)$"))
		local r = index and Config.Fabricator.Items[index]
		if not r then
			return false, "Unknown recipe"
		end
		if not pay(player, r.Cost) then
			return false, "Missing materials: " .. Config.CostText(r.Cost)
		end
		Inventory.Add(player, r.Item, r.Amount or 1)
		return true, string.format("+%d %s", r.Amount or 1, Config.ItemName(r.Item))
	end
	return false, "Unknown action"
end

local function setupFabricator(model)
	if model:GetAttribute("_fabSetup") then
		return
	end
	model:SetAttribute("_fabSetup", true)
	local prompt = Build.AttachPrompt(model, "OpenFabricator", "Open Fabricator", Enum.KeyCode.E, 0)
	prompt.ObjectText = Placement.Def(model).DisplayName
	prompt.Triggered:Connect(function(player)
		local ok, err = nearFabricator(player, model)
		if not ok then
			S.Notify(player, err)
			return
		end
		remotes.Open:FireClient(player, model, fabricatorList(player))
	end)
end

------------------------------------------------------------------ init
local function onLoaded(player)
	local saved = Inventory.GetMeta(player, "Suit")
	local id = (saved and Config.Suits[saved] and Suit.Owns(player, saved)) and saved or Config.Breathing.StartingSuit
	player:SetAttribute("Suit", id)
	player:SetAttribute("OwnedSuits", table.concat(owned(player), ","))
	player:SetAttribute("O2Max", Config.Suits[id].TankSeconds)
	if player.Character then
		applyVisual(player)
	end
end

function Suit.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Build = S.BuildService

	local folder = ReplicatedStorage:WaitForChild("BaseRemotes")
	local function remote(class, name)
		local r = folder:FindFirstChild(name) or Instance.new(class)
		r.Name = name
		r.Parent = folder
		return r
	end
	remotes.Open = remote("RemoteEvent", "FabricatorOpen")
	remotes.Action = remote("RemoteFunction", "FabricatorAction")
	remotes.Action.OnServerInvoke = function(player, action, model, id)
		local ok, a, b, c = pcall(onAction, player, action, model, id)
		if not ok then
			warn("[Suit] " .. tostring(a))
			return false, "Something went wrong"
		end
		return a, b, c
	end

	Inventory.PlayerLoaded.Event:Connect(onLoaded)
	local function hookPlayer(player)
		player.CharacterAppearanceLoaded:Connect(function()
			applyVisual(player)
		end)
		if Inventory.IsLoaded(player) then
			onLoaded(player)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end

	Build.PieceBuilt.Event:Connect(function(model)
		local def = Placement.Def(model)
		if def and def.IsFabricator then
			setupFabricator(model)
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		if Placement.Def(m).IsFabricator and m:GetAttribute("State") == "Built" then
			setupFabricator(m)
		end
	end
end

return Suit
