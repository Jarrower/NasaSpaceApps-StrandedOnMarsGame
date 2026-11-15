--[[
	Main  (Script)
	Location: ServerScriptService > BaseServer > Main

	Boots every system. To add a new system later (Farming, Water, ...):
	  1. Make a ModuleScript in this folder that returns a table with Init(S)
	  2. Add its name to SYSTEMS_SANDBOX or SYSTEMS_MISSION below
	Config.GameMode ("Mission" / "Sandbox") picks which list runs.
	  Inside Init you can use S.Config, S.Placement, S.Notify, S.InventoryService,
	  S.BuildService.PieceBuilt, S.NetworkService.Updated, etc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Original base-building game (Config.GameMode = "Sandbox")
local SYSTEMS_SANDBOX = {
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
	"WaterService",     -- pumps, tanks, water use (Config.Water)
	"FarmService",      -- greenhouse crop plots (Config.Farming, Config.Crops)
	"HungerService",    -- player hunger + eating (Config.Hunger)
	"DevService",       -- testing panel (Config.Dev)
}

-- Mars Base 7 mission (Config.GameMode = "Mission"). Order matters: Init runs top to bottom.
local SYSTEMS_MISSION = {
	"WeatherService",   -- only the dust storm visuals (no random cycle in Mission mode)
	"StationService",   -- power ports, shared power cells, bunker door
	"MissionEvents",    -- dust storm, solar radiation storm, micrometeorite
	"RocketService",    -- landing intro + victory launch (RocketCapsule or placeholder)
	"MissionService",   -- sols, meters, rules, reports, facts, win / lose
	"DevService",       -- testing panel (Config.Dev) with a Mission tab
}

local shared = ReplicatedStorage:WaitForChild("BaseShared")
local Config = require(shared.Config)
local SYSTEMS = Config.GameMode == "Mission" and SYSTEMS_MISSION or SYSTEMS_SANDBOX
print("[BaseServer] Game mode: " .. tostring(Config.GameMode))
if Config.GameMode ~= "Mission" then
	-- the Mars Base 7 map (setup/MissionSetup.lua) isn't used by the sandbox: hide it while playing
	local missionBase = workspace:FindFirstChild("MissionBase")
	if missionBase then
		missionBase.Parent = game:GetService("ServerStorage")
	end
end

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
	Config = Config,
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
