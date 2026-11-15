--[[
	DevService  (ModuleScript)
	Location: ServerScriptService > BaseServer > DevService

	Testing panel. A player unlocks it by typing Config.Dev.ChatCode in chat.
	Every command is checked HERE on the server, so a locked player can't
	fire the remote and cheat.

	Turn it off: Config.Dev.Enabled = false
	Lock it to you: Config.Dev.AllowedUserIds = { yourUserId }

	Add a command: add a function to Commands below, then a button in
	DevClient that calls  run("YourCommand", args...)
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TextChatService = game:GetService("TextChatService")

local Dev = {}
local S, Config, Placement, Inventory, Build
local unlocked = {}
local lastToggle = {}
local remotes = {}

------------------------------------------------------------------ access
local function normalize(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return Config.Dev.CaseSensitive and text or string.lower(text)
end

local function isCode(text)
	return normalize(text) == normalize(Config.Dev.ChatCode)
end

local function isAllowed(player)
	local list = Config.Dev.AllowedUserIds
	if not list or #list == 0 then
		return true
	end
	return table.find(list, player.UserId) ~= nil
end

function Dev.IsUnlocked(player)
	return unlocked[player] == true
end

local function tryUnlock(player, text)
	if not isCode(text) or not isAllowed(player) then
		return
	end
	if not unlocked[player] then
		unlocked[player] = true
		print("[Dev] Panel unlocked for " .. player.Name)
	end
	-- Typing the code again toggles the panel. (Chat is detected two ways,
	-- so ignore the duplicate that arrives right after.)
	local now = os.clock()
	if lastToggle[player] and now - lastToggle[player] < 1.5 then
		return
	end
	lastToggle[player] = now
	remotes.State:FireClient(player, "Toggle")
end

------------------------------------------------------------------ helpers
local function targetOf(player, target)
	if typeof(target) == "Instance" and target:IsA("Player") and target.Parent == Players then
		return target
	end
	return player
end

local function num(v, default, min, max)
	v = tonumber(v) or default
	return math.clamp(v, min, max)
end

local function myPieces(player)
	local list = {}
	for _, m in ipairs(Placement.GetPieces()) do
		if m:GetAttribute("Owner") == player.UserId then
			table.insert(list, m)
		end
	end
	return list
end

local function humanoid(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid"), char
end

------------------------------------------------------------------ commands
-- Each returns: ok (bool), message (string)
local Commands = {}

-- Inventory ------------------------------------------------------
function Commands.GiveItem(player, target, itemId, amount)
	if not Config.Items[itemId] then
		return false, "Unknown item"
	end
	amount = math.floor(num(amount, 1, 1, 100000))
	Inventory.Add(target, itemId, amount)
	return true, string.format("Gave %d %s to %s", amount, Config.ItemName(itemId), target.Name)
end

function Commands.RemoveItem(player, target, itemId, amount)
	if not Config.Items[itemId] then
		return false, "Unknown item"
	end
	amount = math.floor(num(amount, 1, 1, 100000))
	local removed = Inventory.Remove(target, itemId, amount)
	return true, string.format("Removed %d %s from %s", removed, Config.ItemName(itemId), target.Name)
end

function Commands.GiveAll(player, target, amount)
	amount = math.floor(num(amount, 100, 1, 100000))
	for itemId in pairs(Config.Items) do
		Inventory.Add(target, itemId, amount)
	end
	return true, string.format("Gave %d of every item to %s", amount, target.Name)
end

function Commands.ClearInventory(player, target)
	Inventory.Clear(target)
	return true, "Cleared " .. target.Name .. "'s inventory"
end

function Commands.GetInventory(player, target)
	return true, Inventory.GetAll(target)
end

function Commands.SaveInventory(player, target)
	if not Config.Inventory.SaveEnabled then
		return false, "Saving is off (Config.Inventory.SaveEnabled)"
	end
	task.spawn(Inventory.Save, target)
	return true, "Saving " .. target.Name .. "'s inventory..."
end

-- Base -----------------------------------------------------------
function Commands.FinishOutlines(player, target)
	local n = 0
	for _, m in ipairs(myPieces(target)) do
		if m:GetAttribute("State") == "Blueprint" then
			Build.Complete(m)
			n += 1
		end
	end
	return true, string.format("Finished %d outline(s)", n)
end

function Commands.SetFreeBuild(player, target, on)
	Build.FreeBuild[target] = on == true or nil
	return true, "Free build " .. (on and "ON: outlines build instantly" or "OFF")
end

function Commands.RefuelAll(player, target)
	local n = 0
	for _, m in ipairs(myPieces(target)) do
		local def = Placement.Def(m)
		if def.Fuel and m:GetAttribute("State") == "Built" then
			m:SetAttribute("FuelTime", def.Fuel.SecondsPerItem * def.Fuel.MaxItems)
			n += 1
		end
	end
	S.NetworkService.Request()
	return true, string.format("Refueled %d generator(s)", n)
end

function Commands.SetProcessingSpeed(player, target, mult)
	mult = num(mult, 1, 1, 1000)
	S.ProcessingService.SpeedMultiplier = mult
	return true, string.format("Processing speed x%g (whole server)", mult)
end

function Commands.RecomputeNetwork()
	S.NetworkService.Recompute()
	return true, "Power / oxygen / roofs recalculated"
end

function Commands.DeleteBase(player, target)
	local pieces = myPieces(target)
	for _, m in ipairs(pieces) do
		Build.ForceRemove(m)
	end
	return true, string.format("Deleted %s's base (%d pieces)", target.Name, #pieces)
end

function Commands.RespawnOres()
	return true, string.format("Respawned %d ore(s)", S.MiningService.RespawnAll())
end

-- Player ---------------------------------------------------------
function Commands.SetWalkSpeed(player, target, speed)
	local hum = humanoid(target)
	if not hum then
		return false, "No character"
	end
	hum.WalkSpeed = num(speed, 16, 0, 500)
	target:SetAttribute("BaseWalkSpeed", hum.WalkSpeed) -- weather slows from this value
	return true, "WalkSpeed = " .. hum.WalkSpeed
end

function Commands.SetJumpPower(player, target, power)
	local hum = humanoid(target)
	if not hum then
		return false, "No character"
	end
	hum.UseJumpPower = true
	hum.JumpPower = num(power, 50, 0, 1000)
	return true, "JumpPower = " .. hum.JumpPower
end

function Commands.Heal(player, target)
	local hum = humanoid(target)
	if not hum then
		return false, "No character"
	end
	hum.Health = hum.MaxHealth
	return true, "Healed " .. target.Name
end

function Commands.Respawn(player, target)
	target:LoadCharacter()
	return true, "Respawned " .. target.Name
end

function Commands.TeleportToBase(player, target)
	local _, char = humanoid(player)
	if not char then
		return false, "No character"
	end
	for _, m in ipairs(myPieces(target)) do
		if Placement.Def(m).Kind == "Tile" then
			local cf = m:GetAttribute("Center")
			local floorY = m:GetAttribute("FloorY") or cf.Position.Y
			char:PivotTo(CFrame.new(cf.Position.X, floorY + 5, cf.Position.Z))
			return true, "Teleported to " .. target.Name .. "'s base"
		end
	end
	return false, target.Name .. " has no tiles yet"
end

function Commands.TeleportToPlayer(player, target)
	local _, char = humanoid(player)
	local _, tchar = humanoid(target)
	if not char or not tchar or target == player then
		return false, "Pick another player as the target first"
	end
	char:PivotTo(tchar:GetPivot() * CFrame.new(0, 0, 5))
	return true, "Teleported to " .. target.Name
end

-- Survival -------------------------------------------------------
function Commands.SetInfiniteO2(player, target, on)
	S.BreathingService.SetInfinite(target, on == true)
	return true, "Infinite oxygen " .. (on and "ON (no drain, no suffocation, no storm effects)" or "OFF")
end

function Commands.RefillO2(player, target)
	S.BreathingService.SetTank(target, target:GetAttribute("O2Max") or 999)
	return true, "Refilled " .. target.Name .. "'s tank"
end

function Commands.SetO2(player, target, seconds)
	S.BreathingService.SetTank(target, num(seconds, 10, 0, 10000))
	return true, string.format("%s's tank set to %ds", target.Name, math.floor(target:GetAttribute("O2") or 0))
end

function Commands.GiveSuit(player, target, suitId)
	if not Config.Suits[suitId] then
		return false, "Unknown suit"
	end
	S.SuitService.Give(target, suitId)
	S.SuitService.Equip(target, suitId)
	return true, "Equipped " .. Config.Suits[suitId].DisplayName .. " on " .. target.Name
end

function Commands.StartWeather(player, target, eventId, duration)
	if not S.WeatherService.Start(eventId, duration and num(duration, 120, 10, 3600)) then
		return false, "Unknown weather event"
	end
	return true, Config.Weather.Events[eventId].DisplayName .. " started"
end

function Commands.WarnWeather(player, target, eventId)
	if not S.WeatherService.Warn(eventId) then
		return false, "Unknown weather event"
	end
	return true, "Warning: " .. Config.Weather.Events[eventId].DisplayName .. " incoming"
end

function Commands.ClearWeather()
	S.WeatherService.Clear()
	return true, "Weather clearing"
end

-- World ----------------------------------------------------------
function Commands.SetTime(player, target, clock)
	Lighting.ClockTime = num(clock, 12, 0, 24)
	return true, string.format("Time set to %02d:00", math.floor(Lighting.ClockTime))
end

------------------------------------------------------------------ init
function Dev.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	Build = S.BuildService

	if not (Config.Dev and Config.Dev.Enabled) then
		return -- dev panel disabled: no remotes are created, client script stops
	end

	local folder = game:GetService("ReplicatedStorage"):WaitForChild("BaseRemotes")
	local function remote(class, name)
		local r = folder:FindFirstChild(name) or Instance.new(class)
		r.Name = name
		r.Parent = folder
		return r
	end
	remotes.Command = remote("RemoteFunction", "DevCommand")
	remotes.State = remote("RemoteEvent", "DevState")
	remotes.Chat = remote("RemoteEvent", "DevChat")

	remotes.Command.OnServerInvoke = function(player, name, target, ...)
		if not unlocked[player] or not isAllowed(player) then
			return false, "Dev panel is locked"
		end
		local fn = Commands[name]
		if typeof(name) ~= "string" or not fn then
			return false, "Unknown command"
		end
		local ok, a, b = pcall(fn, player, targetOf(player, target), ...)
		if not ok then
			warn("[Dev] " .. name .. " error: " .. tostring(a))
			return false, "Error: " .. tostring(a)
		end
		return a, b
	end

	-- Chat detection (legacy chat + TextChatService both fire Player.Chatted;
	-- the client also reports what it sent, as a backup)
	local function hook(player)
		player.Chatted:Connect(function(msg)
			tryUnlock(player, msg)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	remotes.Chat.OnServerEvent:Connect(function(player, text)
		if typeof(text) == "string" and #text < 200 then
			tryUnlock(player, text)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		unlocked[p] = nil
		lastToggle[p] = nil
		Build.FreeBuild[p] = nil
	end)

	-- Hide the code from everyone's chat
	if Config.Dev.HideCodeFromChat and TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		task.spawn(function()
			local channels = TextChatService:WaitForChild("TextChannels", 30)
			if not channels then
				return
			end
			local function guard(ch)
				if ch:IsA("TextChannel") then
					ch.ShouldDeliverCallback = function(message)
						return not isCode(message.Text)
					end
				end
			end
			for _, ch in ipairs(channels:GetChildren()) do
				guard(ch)
			end
			channels.ChildAdded:Connect(guard)
		end)
	end
end

return Dev
