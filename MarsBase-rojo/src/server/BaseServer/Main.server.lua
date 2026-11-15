--[[
	Main  (Script)
	Location: ServerScriptService > BaseServer > Main

	Boots every system. To add a new system later (Farming, Water, ...):
	  1. Make a ModuleScript in this folder that returns a table with Init(S)
	  2. Add its name to SYSTEMS below
	  Inside Init you can use S.Config, S.Placement, S.Notify, S.InventoryService,
	  S.BuildService.PieceBuilt, S.NetworkService.Updated, etc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SYSTEMS = {
	"InventoryService",
	"BuildService",
	"NetworkService",   -- power, oxygen, enclosure, roofs
	"PowerService",     -- generator fuel (Sulfur), solar day/night
	"MiningService",
	"ProcessingService",
	"AirlockService",
	"WeatherService",   -- dust storms (Config.Weather)
	"SuitService",      -- suits + fabricator (Config.Suits, Config.Fabricator)
	"BreathingService", -- player oxygen, suffocation, storm effects (Config.Breathing)
	"DevService",       -- testing panel (Config.Dev)
	-- "FarmService",
	-- "WaterService",
}

local shared = ReplicatedStorage:WaitForChild("BaseShared")

-- Remotes
local remotes = ReplicatedStorage:FindFirstChild("BaseRemotes") or Instance.new("Folder")
remotes.Name = "BaseRemotes"
remotes.Parent = ReplicatedStorage
local function remote(class, name)
	local r = remotes:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end

local S = {
	Config = require(shared.Config),
	Placement = require(shared.Placement),
	Remotes = {
		PlaceRequest = remote("RemoteFunction", "PlaceRequest"),
		DeleteRequest = remote("RemoteFunction", "DeleteRequest"),
		Notify = remote("RemoteEvent", "Notify"),
	},
}

function S.Notify(player, message)
	if player and player.Parent then
		S.Remotes.Notify:FireClient(player, message)
	end
end

for _, name in ipairs(SYSTEMS) do
	local module = script.Parent:FindFirstChild(name)
	if module then
		S[name] = require(module)
	else
		warn("[BaseServer] Missing system module: " .. name)
	end
end

for _, name in ipairs(SYSTEMS) do
	local system = S[name]
	if system and system.Init then
		local ok, err = pcall(system.Init, S)
		if not ok then
			warn("[BaseServer] " .. name .. " failed to start: " .. tostring(err))
		end
	end
end

print("[BaseServer] All systems started")
