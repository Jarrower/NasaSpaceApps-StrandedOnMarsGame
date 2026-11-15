--[[
	InventoryService  (ModuleScript)
	Location: ServerScriptService > BaseServer > InventoryService

	The real inventory is a table on the server: { [itemId] = count }.
	Each item type is shown to the player as ONE stacked Tool in the hotbar
	(e.g. "Gold x10"). The Tool has no handle, can't be dropped, and has the
	attributes ItemId + Count. Tools are rebuilt automatically on respawn.

	API:
	  Inventory.Get(player, itemId) -> number
	  Inventory.Add(player, itemId, amount)
	  Inventory.Remove(player, itemId, amount) -> amountRemoved
	  Inventory.Has(player, costTable) -> bool
	  Inventory.GetHeld(player) -> itemId, count, tool   (tool in hand)
	  Inventory.Changed  (BindableEvent: player, itemId, newCount)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Inventory = {}
Inventory.Changed = Instance.new("BindableEvent")
Inventory.ItemUsed = Instance.new("BindableEvent")     -- (player, itemId, tool) for Usable items
Inventory.PlayerLoaded = Instance.new("BindableEvent") -- (player) after saved data is loaded

local S, Config
local data = {}
local meta = {} -- [player] = { any extra saved values, e.g. Suit, OwnedSuits, O2 }
local store

local function findTool(player, itemId)
	local bags = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, bag in pairs(bags) do
		for _, t in ipairs(bag:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("ItemId") == itemId then
				return t
			end
		end
	end
	return nil
end

function Inventory.Sync(player, itemId)
	local inv = data[player]
	local count = inv and inv[itemId] or 0
	local tool = findTool(player, itemId)
	if count <= 0 then
		if tool then
			tool:Destroy()
		end
		return
	end
	if not tool then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then
			return
		end
		tool = Instance.new("Tool")
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		tool.ToolTip = Config.ItemName(itemId)
		tool:SetAttribute("ItemId", itemId)
		local icon = Config.Items[itemId] and Config.Items[itemId].Icon
		if icon then
			tool.TextureId = icon
		end
		if Config.Items[itemId] and Config.Items[itemId].Usable then
			tool.ToolTip ..= " (click to use)"
			tool.Activated:Connect(function()
				Inventory.ItemUsed:Fire(player, itemId, tool)
			end)
		end
		tool.Parent = backpack
	end
	tool.Name = string.format(Config.Inventory.NameFormat, Config.ItemName(itemId), count)
	tool:SetAttribute("Count", count)
end

function Inventory.SyncAll(player)
	local inv = data[player]
	if not inv then
		return
	end
	for itemId in pairs(inv) do
		Inventory.Sync(player, itemId)
	end
end

function Inventory.Get(player, itemId)
	local inv = data[player]
	return inv and inv[itemId] or 0
end

function Inventory.Add(player, itemId, amount)
	local inv = data[player]
	if not inv or not amount or amount <= 0 then
		return
	end
	inv[itemId] = (inv[itemId] or 0) + amount
	Inventory.Sync(player, itemId)
	Inventory.Changed:Fire(player, itemId, inv[itemId])
end

function Inventory.Remove(player, itemId, amount)
	local inv = data[player]
	if not inv then
		return 0
	end
	local take = math.min(inv[itemId] or 0, amount or 0)
	if take <= 0 then
		return 0
	end
	inv[itemId] -= take
	if inv[itemId] <= 0 then
		inv[itemId] = nil
	end
	Inventory.Sync(player, itemId)
	Inventory.Changed:Fire(player, itemId, inv[itemId] or 0)
	return take
end

-- Everything the player has: { [itemId] = count } (a copy)
function Inventory.GetAll(player)
	return table.clone(data[player] or {})
end

function Inventory.Clear(player)
	for itemId, count in pairs(Inventory.GetAll(player)) do
		Inventory.Remove(player, itemId, count)
	end
end

-- Extra saved values (other systems store their own data here)
function Inventory.GetMeta(player, key)
	return meta[player] and meta[player][key]
end

function Inventory.SetMeta(player, key, value)
	if meta[player] then
		meta[player][key] = value
	end
end

function Inventory.IsLoaded(player)
	return meta[player] ~= nil
end

function Inventory.Has(player, cost)
	for item, n in pairs(cost) do
		if Inventory.Get(player, item) < n then
			return false
		end
	end
	return true
end

function Inventory.GetHeld(player)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("ItemId")
	if id then
		return id, Inventory.Get(player, id), tool
	end
	return nil
end

------------------------------------------------------------------ saving
local loaded = {} -- only save players whose data loaded OK (prevents wiping saves)

local function withRetry(fn)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[Inventory] DataStore attempt %d failed: %s"):format(attempt, tostring(result)))
		task.wait(attempt * 2)
	end
	return false
end

local function save(player)
	if not (Config.Inventory.SaveEnabled and store and data[player] and loaded[player]) then
		return
	end
	local snapshot = table.clone(data[player])
	snapshot._meta = meta[player] and table.clone(meta[player]) or nil
	withRetry(function()
		store:UpdateAsync("u" .. player.UserId, function()
			return snapshot
		end)
	end)
end
Inventory.Save = save

local function onPlayerAdded(player)
	data[player] = {}
	local loadedMeta = {}
	if Config.Inventory.SaveEnabled and store then
		local ok, saved = withRetry(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok then
			loaded[player] = true
			if type(saved) == "table" then
				for k, v in pairs(saved) do
					if Config.Items[k] and type(v) == "number" and v > 0 then
						data[player][k] = v
					end
				end
				if type(saved._meta) == "table" then
					loadedMeta = saved._meta
				end
			end
		else
			warn("[Inventory] Could not load " .. player.Name .. "'s inventory - it will NOT be saved this session")
		end
	end
	if not player.Parent then
		return
	end
	meta[player] = loadedMeta
	Inventory.PlayerLoaded:Fire(player)
	-- Rebuild tools whenever a fresh Backpack / character appears (respawn)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.defer(Inventory.SyncAll, player)
		end
	end)
	player.CharacterAdded:Connect(function()
		task.delay(0.5, Inventory.SyncAll, player)
	end)
	Inventory.SyncAll(player)
end

function Inventory.Init(services)
	S = services
	Config = S.Config
	if Config.Inventory.SaveEnabled then
		store = DataStoreService:GetDataStore(Config.Inventory.DataStoreName)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		data[p] = nil
		meta[p] = nil
		loaded[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Inventory.AutoSaveInterval or 120)
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(save, p)
			end
		end
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			save(p)
		end
	end)
end

return Inventory
