--[[
	BreathingService  (ModuleScript)
	Location: ServerScriptService > BaseServer > BreathingService

	Every Config.Breathing.TickRate seconds, for every player:
	  INSIDE  = standing in/above a tile or connector that is Oxygenated
	            (or still leaking air, see Config.Oxygen.LeakTime)
	            -> the suit tank refills
	  OUTSIDE -> the tank drains:
	            DrainPerSecond x suit DrainMultiplier x exertion x weather
	            (weather penalty is reduced by the suit's StormProtection)
	  Tank empty -> SuffocationDamage per second
	  Weather can also slow players outside (WalkSpeed) or hurt them (Damage).

	Published on each Player (the HUD reads these):
	  O2, O2Max, Inside (bool), AirStatus ("Pressurized", "Leaking", "Outside",
	  "Suffocating"), Exerted (bool), InfiniteO2 (dev)

	Other systems:
	  Breathing.Exert(player)            -- call when the player does hard work (mining)
	  Breathing.IsInside(player)
	  Breathing.SetTank(player, seconds)
	  Breathing.SetInfinite(player, bool)  (dev panel)
	  Player attribute "BaseWalkSpeed"   -- weather slows from this value
]]

local Players = game:GetService("Players")

local Breathing = {}
local S, Config, Placement, Inventory, Suit, Weather
local lastExert = {}
local infinite = {}

local function serverNow()
	return workspace:GetServerTimeNow()
end

function Breathing.Exert(player)
	lastExert[player] = os.clock()
end

function Breathing.SetInfinite(player, on)
	infinite[player] = on or nil
	player:SetAttribute("InfiniteO2", on == true)
end

function Breathing.SetTank(player, seconds)
	local max = player:GetAttribute("O2Max") or 90
	player:SetAttribute("O2", math.clamp(seconds, 0, max))
end

------------------------------------------------------------------ inside test
-- Returns "Pressurized", "Leaking" or nil (outside)
local function airAt(position)
	local cfg = Config.Breathing
	local t = serverNow()
	local best
	for _, m in ipairs(Placement.GetPieces()) do
		local def = Placement.Def(m)
		if (def.Kind == "Tile" or def.Kind == "Linear") and m:GetAttribute("State") == "Built" then
			local ox = m:GetAttribute("Oxygenated") == true
			local leak = not ox and (m:GetAttribute("AirLeftUntil") or 0) > t
			if ox or leak then
				local cf, size = m:GetAttribute("Center"), m:GetAttribute("Size")
				local p = cf:PointToObjectSpace(position)
				local bottom = -size.Y / 2 - 2
				if math.abs(p.X) <= size.X / 2 and math.abs(p.Z) <= size.Z / 2
					and p.Y >= bottom and p.Y <= bottom + cfg.InsideHeight then
					if ox then
						return "Pressurized"
					end
					best = "Leaking"
				end
			end
		end
	end
	return best
end

function Breathing.IsInside(player)
	return player:GetAttribute("Inside") == true
end

------------------------------------------------------------------ tick
local function tickPlayer(player, dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 or not Inventory.IsLoaded(player) then
		return
	end
	local cfg = Config.Breathing
	local _, suitDef = Suit.Get(player)
	local max = suitDef.TankSeconds
	local tank = player:GetAttribute("O2") or max
	player:SetAttribute("O2Max", max)

	local air = airAt(hrp.Position)
	local inside = air ~= nil
	local exerted = lastExert[player] and (os.clock() - lastExert[player]) < cfg.ExertionWindow
		or hum.MoveDirection.Magnitude > 0.1 and hum.WalkSpeed > 20
	exerted = exerted == true

	-- weather penalties only matter outside, and the suit blocks part of them
	local protection = suitDef.StormProtection or 0
	local function weatherMult(name)
		local raw = Weather and Weather.GetEffect(name) or 1
		return 1 + (raw - 1) * (1 - protection)
	end

	if inside then
		tank = math.min(max, tank + max * cfg.RefillPerSecond * dt)
	elseif not infinite[player] then
		local drain = cfg.DrainPerSecond * (suitDef.DrainMultiplier or 1)
			* (exerted and cfg.ExertionMultiplier or 1)
			* weatherMult("O2Drain")
		tank = math.max(0, tank - drain * dt)
	end

	local status
	if inside then
		status = air -- "Pressurized" / "Leaking"
	elseif tank <= 0 and not infinite[player] then
		status = "Suffocating"
		hum:TakeDamage(cfg.SuffocationDamage * dt)
	else
		status = "Outside"
	end

	-- storm damage + wind outside
	local base = player:GetAttribute("BaseWalkSpeed") or 16
	if not inside and not infinite[player] then
		local dmg = (Weather and Weather.GetEffect("Damage") or 0) * (1 - protection)
		if dmg > 0 then
			hum:TakeDamage(dmg * dt)
		end
		hum.WalkSpeed = base * (Weather and Weather.GetEffect("WalkSpeed") or 1)
	else
		hum.WalkSpeed = base
	end

	player:SetAttribute("O2", tank)
	player:SetAttribute("Inside", inside)
	player:SetAttribute("AirStatus", status)
	player:SetAttribute("Exerted", exerted)
	Inventory.SetMeta(player, "O2", math.floor(tank))
end

------------------------------------------------------------------ canister
local function onItemUsed(player, itemId)
	local can = Config.Breathing.Canister
	if itemId ~= can.Item then
		return
	end
	local max = player:GetAttribute("O2Max") or 90
	local tank = player:GetAttribute("O2") or max
	if tank >= max - 0.5 then
		S.Notify(player, "Your tank is already full.")
		return
	end
	if Inventory.Remove(player, can.Item, 1) == 1 then
		player:SetAttribute("O2", math.min(max, tank + can.Seconds))
		S.Notify(player, string.format("+%ds of air", can.Seconds))
	end
end

------------------------------------------------------------------ respawn
local function findBaseSpawn(player)
	for _, m in ipairs(Placement.GetPieces()) do
		local def = Placement.Def(m)
		if def.Kind == "Tile" and m:GetAttribute("Owner") == player.UserId and m:GetAttribute("Oxygenated") then
			local cf = m:GetAttribute("Center")
			local floorY = m:GetAttribute("FloorY") or cf.Position.Y
			return CFrame.new(cf.Position.X, floorY + 4, cf.Position.Z)
		end
	end
	return nil
end

local function onCharacter(player, char)
	-- Fresh character: full tank
	player:SetAttribute("O2", player:GetAttribute("O2Max") or 90)
	if Config.Breathing.RespawnAtBase then
		task.defer(function()
			local spawnCF = findBaseSpawn(player)
			local hrp = char:WaitForChild("HumanoidRootPart", 5)
			if spawnCF and hrp then
				char:PivotTo(spawnCF)
			end
		end)
	end
end

------------------------------------------------------------------ init
function Breathing.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Suit = S.SuitService
	Weather = S.WeatherService
	if not Config.Breathing.Enabled then
		return
	end

	Inventory.ItemUsed.Event:Connect(onItemUsed)

	local function hook(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	-- restore saved air when data loads
	Inventory.PlayerLoaded.Event:Connect(function(player)
		local saved = Inventory.GetMeta(player, "O2")
		if type(saved) == "number" then
			player:SetAttribute("O2", saved)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastExert[p] = nil
		infinite[p] = nil
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Breathing.TickRate)
			local t = os.clock()
			local dt = t - last
			last = t
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(tickPlayer, p, dt)
				if not ok then
					warn("[Breathing] " .. tostring(err))
				end
			end
		end
	end)
end

return Breathing
