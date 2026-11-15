--[[
	HungerService  (ModuleScript)
	Location: ServerScriptService > BaseServer > HungerService

	Player attribute "Hunger" (0 - Config.Hunger.Max), saved.
	Drains over time; at 0 the player takes StarveDamage per second.
	Eat: click a food item (Config.Items[x].Food = amount restored).
	Respawn with Config.Hunger.RespawnHunger.

	API: Hunger.Set(player, value)  Hunger.SetInfinite(player, bool)  (dev panel)
]]

local Players = game:GetService("Players")

local Hunger = {}
local S, Config, Inventory
local infinite = {}

function Hunger.Set(player, value)
	player:SetAttribute("Hunger", math.clamp(value, 0, Config.Hunger.Max))
end

function Hunger.SetInfinite(player, on)
	infinite[player] = on or nil
	player:SetAttribute("InfiniteHunger", on == true)
end

local function onItemUsed(player, itemId)
	local item = Config.Items[itemId]
	if not item or not item.Food then
		return
	end
	local h = player:GetAttribute("Hunger") or Config.Hunger.Max
	if h >= Config.Hunger.Max - 1 then
		S.Notify(player, "You're full.")
		return
	end
	if Inventory.Remove(player, itemId, 1) == 1 then
		Hunger.Set(player, h + item.Food)
		S.Notify(player, string.format("Ate %s (+%d food)", Config.ItemName(itemId), item.Food))
	end
end

function Hunger.Init(services)
	S = services
	Config = S.Config
	Inventory = S.InventoryService
	if not Config.Hunger.Enabled then
		return
	end

	Inventory.ItemUsed.Event:Connect(onItemUsed)

	Inventory.PlayerLoaded.Event:Connect(function(player)
		local saved = Inventory.GetMeta(player, "Hunger")
		Hunger.Set(player, type(saved) == "number" and saved or Config.Hunger.Max)
		-- starter seeds, once per player
		if not Inventory.GetMeta(player, "StarterSeedsGiven") then
			for item, n in pairs(Config.Farming.StarterSeeds or {}) do
				Inventory.Add(player, item, n)
			end
			Inventory.SetMeta(player, "StarterSeedsGiven", true)
		end
	end)

	local function hook(player)
		local first = true
		player.CharacterAdded:Connect(function()
			if first then
				first = false -- keep the saved value on the very first spawn
				return
			end
			Hunger.Set(player, Config.Hunger.RespawnHunger)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		infinite[p] = nil
	end)

	task.spawn(function()
		local tickRate = 1
		while true do
			task.wait(tickRate)
			for _, p in ipairs(Players:GetPlayers()) do
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				local h = p:GetAttribute("Hunger")
				if hum and hum.Health > 0 and h and not infinite[p] then
					h = math.max(0, h - Config.Hunger.DrainPerSecond * tickRate)
					Hunger.Set(p, h)
					Inventory.SetMeta(p, "Hunger", math.floor(h))
					if h <= 0 then
						hum:TakeDamage(Config.Hunger.StarveDamage * tickRate)
					end
				end
			end
		end
	end)
end

return Hunger
