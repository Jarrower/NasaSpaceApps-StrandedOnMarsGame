--[[
	Config  (ModuleScript)
	Location: ReplicatedStorage > BaseShared > Config

	EVERYTHING tunable lives here: items, ores, recipes, costs, power, oxygen,
	airlocks, keybinds. Server AND client both read this file.

	To add a new item:      add it to Config.Items
	To add a new ore:       add it to Config.Ores (key = ore model name or OreType attribute)
	To add a new recipe:    add it to Config.Processing.Recipes
	To add a new buildable: add it to Config.Buildables and put a Model with the
	                        same name in ReplicatedStorage > BuildTemplates
]]

local Config = {}

------------------------------------------------------------------- GAME MODE
-- "Mission" = Mars Base 7 (kid-friendly 7-sol mission, see Config.Mission)
-- "Sandbox" = the original base-building game (building, mining, suits, ...)
-- Nothing is deleted when you switch: Main starts a different SYSTEMS list.
Config.GameMode = "Mission"

------------------------------------------------------------------------ ITEMS
-- Every item that can sit in a player's inventory (ores + processed materials)
Config.Items = {
	-- Raw ores (from mining)
	GoldOre     = { DisplayName = "Gold Ore" },
	IronOxide   = { DisplayName = "Iron Oxide" },
	Sillica     = { DisplayName = "Sillica" },
	SulfateOre  = { DisplayName = "Sulfate Ore" },
	SaltOre     = { DisplayName = "Salt Ore" },
	TitaniumOre = { DisplayName = "Titanium Ore" },

	-- Processed (from refineries)
	Iron        = { DisplayName = "Iron" },
	UsefulSalts = { DisplayName = "Useful Salts" },
	Sulfur      = { DisplayName = "Sulfur" },
	Titanium    = { DisplayName = "Titanium" },
	Gold        = { DisplayName = "Gold" },

	-- Usable items (click while holding). Usable = true makes InventoryService
	-- fire InventoryService.ItemUsed when the tool is activated.
	O2Canister  = { DisplayName = "O2 Canister", Usable = true },

	-- Farming: seeds are planted in Greenhouse plots, food is eaten (Food = hunger restored)
	PotatoSeed  = { DisplayName = "Potato Seed" },
	LettuceSeed = { DisplayName = "Lettuce Seed" },
	TomatoSeed  = { DisplayName = "Tomato Seed" },
	Potato      = { DisplayName = "Potato", Usable = true, Food = 25 },
	Lettuce     = { DisplayName = "Lettuce", Usable = true, Food = 15 },
	Tomato      = { DisplayName = "Tomato", Usable = true, Food = 40 },
}

Config.Inventory = {
	-- How the stacked tool is named in the hotbar. "%s x%d" -> "Gold x10"
	NameFormat = "%s x%d",
	-- Save inventories between sessions (needs Game Settings > Security >
	-- "Enable Studio Access to API Services" to test in Studio)
	SaveEnabled = true,
	DataStoreName = "BaseInventory_v1",
	AutoSaveInterval = 120,  -- seconds
}

----------------------------------------------------------------------- MINING
Config.Mining = {
	PromptName = "Mine",          -- ProximityPrompt name inside ore models (added automatically if missing)
	OreFolders = { "Resources", "ScatterBrush_Placed" }, -- Workspace folders scanned for ore models
	MinerValueName = "Miner",     -- BoolValue that must exist in the tool and be true
	RequireEquipped = true,       -- true = tool must be in hand; false = backpack is enough
	RespawnTime = 240,            -- seconds (4 minutes)
	DepletedTransparency = 1,     -- 1 = fully invisible while depleted
	SetPromptText = true,         -- overwrite ActionText/ObjectText on the Mine prompts

	-- How many ores one mine gives (called on the final hit).
	GetYield = function(player, tool, oreId)
		return 1
	end,
}

------------------------------------------------------------------------ DRILL
--[[
	Ores take several hits. PC: equip the drill and click an ore.
	Mobile/console: every press of the ore's "Mine" prompt is one hit.
	Your tier is saved. Upgrades are bought at the Fabricator.
	Each ore in Config.Ores has Health and Tier (the drill tier needed).
]]
Config.Drill = {
	Range = 14,               -- studs from the player to the ore
	HealAfter = 30,           -- a damaged ore heals to full if nobody hits it for this long
	ToolNameFormat = "Drill [T%d]",
	Tiers = {
		[0] = { Damage = 20,  Cooldown = 0.45 },
		[1] = { Damage = 35,  Cooldown = 0.40, Cost = { Iron = 10, Sillica = 6 } },
		[2] = { Damage = 55,  Cooldown = 0.35, Cost = { Iron = 20, Sulfur = 8, UsefulSalts = 6 } },
		[3] = { Damage = 100, Cooldown = 0.30, Cost = { Titanium = 12, Iron = 25 } },
	},
	MaxTier = 3,
}

-- Key = ore model name (e.g. "GoldOre") OR the model's "OreType" attribute.
-- Item = what goes into the inventory. RespawnTime overrides the default.
-- Health = hit points, Tier = drill tier needed.
Config.Ores = {
	IronOxide   = { Item = "IronOxide",   Health = 60,  Tier = 0 },
	Sillica     = { Item = "Sillica",     Health = 60,  Tier = 0 },
	SaltOre     = { Item = "SaltOre",     Health = 80,  Tier = 1 },
	SulfateOre  = { Item = "SulfateOre",  Health = 80,  Tier = 1 },
	TitaniumOre = { Item = "TitaniumOre", Health = 120, Tier = 2 },
	GoldOre     = { Item = "GoldOre",     Health = 150, Tier = 3 },
}
-- Other model names that mean the same ore (your models are called these)
Config.OreAliases = {
	Sillicone = "Sillica",
	Titanium = "TitaniumOre",
}

------------------------------------------------------------------- PROCESSING
Config.Processing = {
	DefaultTime = 5,       -- seconds per item (a recipe can override with Time = x)
	MaxQueue = 100,        -- max ores waiting inside one refinery
	MaxOutput = 100,       -- refinery pauses when its output is this full
	RequiresPower = true,

	-- Input item -> output. Machines = which buildables can process it.
	Recipes = {
		IronOxide   = { Output = "Iron",        Amount = 1, Machines = { SmallRefinery = true } },
		SaltOre     = { Output = "UsefulSalts", Amount = 1, Machines = { SmallRefinery = true } },
		SulfateOre  = { Output = "Sulfur",      Amount = 1, Machines = { SmallRefinery = true } },
		TitaniumOre = { Output = "Titanium",    Amount = 1, Machines = { LargeRefinery = true } },
		GoldOre     = { Output = "Gold",        Amount = 1, Machines = { LargeRefinery = true } },
	},
}

------------------------------------------------------------------------ BUILD
Config.Build = {
	RootFolder = "BaseBuilding",        -- Workspace folder that holds placed pieces
	TemplatesFolder = "BuildTemplates", -- ReplicatedStorage folder with source models

	MaxPlaceDistance = 150,  -- studs from player to placement point
	SnapRadius = 20,         -- how close the mouse must be for smart-connect to snap
	SocketTolerance = 2,     -- studs; how close two edges must be to count as connected
	HeightTolerance = 4,
	GridSize = 1,            -- grid for free-placed (unsnapped) tiles
	AllowTileToTile = true,  -- tiles can snap directly against each other to make bigger rooms
	RequireTerrainForFreeTiles = true,

	-- true  = player must HOLD the material tool and press the prompt
	-- false = pressing the prompt pulls whatever is needed from the inventory
	RequireHoldingMaterial = true,

	-- Each player has their own base:
	OwnerOnlyDelete = true,    -- only the owner can delete their pieces
	OwnerOnlyInteract = true,  -- only the owner sees/uses prompts (build, refinery, fuel, airlock doors)
	OwnerOnlySnap = true,      -- you can only snap/attach to your own pieces

	-- Tabs in the build menu (each buildable has a Category)
	Categories = { "Foundation", "Structure", "Power", "Machines" },

	-- Outline look
	BlueprintTransparency = 0.55,
	BlueprintMaterial = Enum.Material.ForceField,
	BlueprintColor = Color3.fromRGB(80, 170, 255),

	Keys = {
		Menu = Enum.KeyCode.B,
		Rotate = Enum.KeyCode.R,
		Cancel = Enum.KeyCode.Q,
		Delete = Enum.KeyCode.X,
	},
}

------------------------------------------------------------------ WALLS / ROOF
Config.Walls = {
	EdgeHoverDistance = 8,     -- how close to a tile edge the mouse must be to show a wall
	Height = nil,              -- nil = use the Wall template's height
	Thickness = nil,           -- nil = use the Wall template's thickness
	-- Does a side with a Connector/Airlock count as "covered" for enclosure & roof?
	LinearCountsAsWall = true,
	-- Fill the gaps around a connector/airlock with wall pieces (free), when the
	-- room has at least one wall. Keeps rooms airtight with no holes.
	AutoFillAroundLinears = true,
	RoofThickness = 1,
}

------------------------------------------------------------------ POWER / O2
Config.Power = {
	PoweredValueName = "Powered?",   -- BoolValue inside every tile
	SolarDaytimeOnly = false,        -- true = solar gives 0 power at night (Lighting.ClockTime)
	FuelBurnsOnlyWithDemand = true,  -- generators only use fuel while something needs power
}

-- How much power a power-producing component makes RIGHT NOW.
function Config.Power.GetOutput(component, def)
	if def.Fuel and (component:GetAttribute("FuelTime") or 0) <= 0 then
		return 0 -- out of fuel
	end
	if def.Solar and Config.Power.SolarDaytimeOnly then
		local t = game:GetService("Lighting").ClockTime
		if t < 6 or t > 18 then
			return 0
		end
	end
	local out = def.PowerOutput or 0
	if def.Solar then
		-- WeatherService lowers this during dust storms
		out *= workspace:GetAttribute("SolarMultiplier") or 1
	end
	return out
end

Config.Oxygen = {
	ValueName = "Oxygenated?",  -- BoolValue created inside every tile
	RequiresPower = true,       -- Oxygen generator only works when powered
	LeakTime = 10,              -- seconds a room keeps breathable air after losing oxygen (0 = instant)
}

-------------------------------------------------------------------- DEV PANEL
-- Type ChatCode in chat to open the dev/testing panel.
-- !! Set Enabled = false (or fill AllowedUserIds) before you publish the game !!
Config.Dev = {
	-- PRODUCTION BUILD: set Enabled = false. Right now anyone who types the
	-- code can open the panel (AllowedUserIds is empty on purpose).
	Enabled = true,                    -- false = dev panel completely off
	ChatCode = "The Key To Wellness",
	CaseSensitive = false,
	HideCodeFromChat = true,           -- other players won't see the code in chat
	AllowedUserIds = {},               -- empty = anyone who knows the code. e.g. { 12345678 }
	ToggleKey = Enum.KeyCode.F8,       -- show/hide the panel after unlocking
}

---------------------------------------------------------------------- AIRLOCK
Config.Airlock = {
	-- "Auto": doors open as you walk up, cycle through a decontamination mist,
	--         only one door open at a time. "Prompt": press E on each door.
	Mode = "Auto",
	ZoneDepth = 10,            -- how far in front of a door counts as "approaching"
	CloseDelay = 1.5,          -- seconds the doorway must be empty before closing
	MistTime = 2,              -- seconds of decontamination spray between doors
	DoorsFolderName = "Doors",
	OpenTime = 0.6,
	AutoCloseTime = 5,         -- 0 = never auto-close
	OpenDirection = "Up",      -- "Up", "Down" or "Side"
	OpenFraction = 0.95,       -- how far (fraction of door size) it slides
	Interlock = true,          -- opening one door closes the other (real airlock)
	PromptDistance = 10,
	ParticleCount = 40,
	ParticleColor = Color3.fromRGB(225, 240, 255),
	ParticleTexture = "rbxasset://textures/particles/smoke_main.dds",
	SoundId = nil,             -- e.g. "rbxassetid://123456" for a hiss sound
}

------------------------------------------------------------------- BUILDABLES
--[[
	Kind:
	  "Tile"      - floor tile placed on terrain; Slots = where components go
	                (Vector2 = fraction of tile size from the centre)
	  "Linear"    - Connector / Airlock; snaps to a tile edge
	  "Wall"      - goes on a tile edge, auto-scales to the edge length
	  "Component" - goes into a tile slot. Size "Small" = 1 slot, "Large" = whole tile (needs 2+ slots)

	KEY       = internal id (used in saves/attributes)
	Template  = model name in ReplicatedStorage > BuildTemplates (defaults to the KEY)
	Folder    = which Workspace > BaseBuilding folder placed copies go into
	Category  = build menu tab
	Description = short text on the build menu card

	Progression (Mars):
	  Mine IronOxide + Sillica -> tiles, connectors, Solar Panel, Small Refinery
	  Small Refinery -> Iron, Useful Salts, Sulfur
	  Iron -> walls, airlock, fuel generator, Large Refinery
	  Useful Salts -> Oxygen Generator (perchlorate chemistry!)
	  Sulfur -> generator fuel
	  Large Refinery -> Titanium, Gold (saved for suits / advanced tech later)
]]
Config.Buildables = {
	------------------------------------------------ Foundation
	["25x25"] = {
		DisplayName = "Small Tile", Kind = "Tile", Folder = "BaseTiles", Category = "Foundation", Order = 1,
		Description = "Fits 1 small component",
		Cost = { IronOxide = 2 },
		Slots = { C = Vector2.new(0, 0) },
		OxygenUnits = 1,  -- how much oxygen capacity this room needs
	},
	["50x50"] = {
		DisplayName = "Large Tile", Kind = "Tile", Folder = "BaseTiles", Category = "Foundation", Order = 2,
		Description = "Fits 2 small or 1 large",
		Cost = { IronOxide = 6 },
		Slots = { A = Vector2.new(-0.25, 0), B = Vector2.new(0.25, 0) },
		OxygenUnits = 2,
	},
	Connector = {
		DisplayName = "Connector", Template = { "Corridor", "Connector" }, -- first model found is used
		Kind = "Linear", Folder = "Connectors", Category = "Foundation", Order = 3,
		Description = "Links tiles: power + oxygen",
		Cost = { IronOxide = 2, Sillica = 2 },
		ConnectsTiles = true,
		Sealed = true,
	},
	Airlock = {
		DisplayName = "Airlock", Kind = "Linear", Folder = "Airlocks", Category = "Foundation", Order = 4,
		Description = "The only way in or out",
		Cost = { Iron = 8, Sillica = 4 },
		ConnectsTiles = false,
		Sealed = true,
		IsAirlock = true,
	},

	------------------------------------------------ Structure
	Wall = {
		DisplayName = "Wall", Kind = "Wall", Folder = "Walls", Category = "Structure", Order = 10,
		Description = "Hover a tile edge. 4 walls = roof",
		Cost = { Iron = 2 },
	},

	------------------------------------------------ Power
	SolarPanel = {
		DisplayName = "Solar Panel", Template = "SOLAR", Kind = "Component", Size = "Small",
		Folder = "Generator", Category = "Power", Order = 20,
		Description = "40 power, free. Tile can't have walls",
		Cost = { IronOxide = 4, Sillica = 6 },
		PowerOutput = 40,
		Solar = true,
		BlocksWalls = true,  -- needs open sky
	},
	PowerGenerator = {
		DisplayName = "Fuel Generator", Template = "generator", Kind = "Component", Size = "Small",
		Folder = "Generator", Category = "Power", Order = 21,
		Description = "120 power, burns Sulfur",
		Cost = { Iron = 6, IronOxide = 4 },
		PowerOutput = 120,
		-- 1 Sulfur = 60 seconds of running, holds up to 20 Sulfur
		Fuel = { Item = "Sulfur", SecondsPerItem = 60, MaxItems = 20 },
		Fallback = { Size = Vector3.new(8, 6, 8), Color = Color3.fromRGB(255, 200, 40) },
	},

	------------------------------------------------ Machines
	SmallRefinery = {
		DisplayName = "Small Refinery", Kind = "Component", Size = "Small", Folder = "Processing",
		Category = "Machines", Order = 30,
		Description = "Iron, Salts, Sulfur. Uses 20 power",
		Cost = { IronOxide = 6, Sillica = 4 },
		PowerDraw = 20,
		Machine = true,
	},
	LargeRefinery = {
		DisplayName = "Large Refinery", Kind = "Component", Size = "Large", Folder = "Processing",
		Category = "Machines", Order = 31,
		Description = "Titanium, Gold. Uses 50 power",
		Cost = { Iron = 10, Sillica = 6 },
		PowerDraw = 50,
		Machine = true,
	},
	OxygenGenerator = {
		DisplayName = "Oxygen Generator", Kind = "Component", Size = "Small", Folder = "OxygenGenerator",
		Category = "Machines", Order = 32,
		Description = "O2 for 4 rooms. Needs water + 25 power",
		Cost = { Iron = 6, UsefulSalts = 4 },
		PowerDraw = 25,
		OxygenSource = true,
		OxygenCapacity = 4,  -- fills 4 small tiles or 2 large tiles
		WaterUse = 1,        -- water per second (electrolysis). No water = no oxygen
	},
	WaterPump = {
		DisplayName = "Water Pump", Template = { "WaterPump", "WATER PUMP 2.0" },
		Kind = "Component", Size = "Small", Folder = "Water", Category = "Machines", Order = 34,
		Description = "Pumps ice-water: +2/s. 20 power",
		Cost = { Iron = 6, Sillica = 2 },
		PowerDraw = 20,
		WaterOutput = 2,
		Fallback = { Size = Vector3.new(5, 6, 5), Color = Color3.fromRGB(60, 90, 160) },
	},
	WaterTank = {
		DisplayName = "Water Tank", Template = { "WaterTank", "watertank" },
		Kind = "Component", Size = "Small", Folder = "Water", Category = "Machines", Order = 35,
		Description = "Stores 500 water",
		Cost = { Iron = 8 },
		WaterCapacity = 500,
		Fallback = { Size = Vector3.new(6, 8, 6), Color = Color3.fromRGB(170, 200, 220) },
	},
	Greenhouse = {
		DisplayName = "Greenhouse Dome", Kind = "Tile", Folder = "Greenhouses", Category = "Foundation", Order = 5,
		Description = "Sealed dome with 8 crop plots. 30 power",
		Cost = { Iron = 20, Sillica = 16 },
		SelfEnclosed = true,   -- already airtight: no walls / roof needed
		Slots = {},            -- no machine slots, it has crop plots instead
		OxygenUnits = 2,
		OxygenSource = true,   -- the plants make some air (needs power + water)
		OxygenCapacity = 2,
		PowerDraw = 30,
		Plots = 8,
		Fallback = { Size = Vector3.new(60, 30, 60), Color = Color3.fromRGB(200, 230, 255) },
	},
	Fabricator = {
		DisplayName = "Fabricator", Kind = "Component", Size = "Small", Folder = "Processing",
		Category = "Machines", Order = 33,
		Description = "Craft suits + O2 canisters. 15 power",
		Cost = { Iron = 8, Sillica = 4, UsefulSalts = 2 },
		PowerDraw = 15,
		IsFabricator = true,
		Fallback = { Size = Vector3.new(7, 6, 5), Color = Color3.fromRGB(150, 160, 175) },
	},
}


-------------------------------------------------------------------- BREATHING
Config.Breathing = {
	Enabled = true,
	TickRate = 0.25,           -- seconds between server checks
	DrainPerSecond = 1,        -- tank seconds used per second outside
	ExertionMultiplier = 1.5,  -- drain while mining / running
	ExertionWindow = 3,        -- seconds after mining that still count as exertion
	RefillPerSecond = 0.10,    -- fraction of the tank refilled per second inside
	InsideHeight = 30,         -- studs above a tile's floor that still count as inside
	WarnAt = 0.25,             -- tank fraction for the first warning
	CriticalAt = 0.10,         -- tank fraction for the urgent warning
	SuffocationDamage = 10,    -- health per second when the tank is empty
	RespawnAtBase = true,      -- respawn inside your oxygenated base if you have one
	StartingSuit = "Basic",
	Canister = { Item = "O2Canister", Seconds = 30 },
	-- Optional sounds (rbxassetid://...). nil = silent
	Sounds = { Warning = nil, Breathing = nil },
}

------------------------------------------------------------------------ SUITS
--[[
	TankSeconds      = seconds of air outside
	StormProtection  = 0..1, how much of the dust-storm penalty the suit ignores
	DrainMultiplier  = suit efficiency (lower = air lasts longer)
	Color / VisorColor = tint used when there is no suit model
	Model            = optional: name of a Model/Accessory folder in
	                   ReplicatedStorage > SuitModels to attach instead of the tint
]]
Config.Suits = {
	Basic = {
		DisplayName = "Basic Suit", Order = 1,
		TankSeconds = 90, StormProtection = 0, DrainMultiplier = 1,
		Color = Color3.fromRGB(225, 225, 220), VisorColor = Color3.fromRGB(120, 180, 255),
	},
	Titanium = {
		DisplayName = "Titanium Suit", Order = 2,
		TankSeconds = 240, StormProtection = 0.25, DrainMultiplier = 0.9,
		Color = Color3.fromRGB(150, 160, 175), VisorColor = Color3.fromRGB(90, 220, 200),
		Recipe = { Titanium = 6, Iron = 10, Sillica = 4 },
	},
	GoldVisor = {
		DisplayName = "Gold-Visor Suit", Order = 3,
		TankSeconds = 480, StormProtection = 0.75, DrainMultiplier = 0.8,
		Color = Color3.fromRGB(60, 62, 70), VisorColor = Color3.fromRGB(255, 190, 60),
		Recipe = { Titanium = 10, Gold = 6, Sillica = 6 },
	},
}

Config.SuitVisuals = {
	Mode = "Tint",        -- "Tint" (recolour + glass helmet), "Model" (use Suit.Model), "None"
	HideClothing = true,  -- remove Shirt/Pants while suited (Tint mode)
	Helmet = true,        -- add a glass helmet bubble
}

------------------------------------------------------------------- FABRICATOR
-- Item recipes (suits are crafted from Config.Suits[x].Recipe)
Config.Fabricator = {
	RequiresPower = true,
	Items = {
		{ Item = "O2Canister", Amount = 2, Cost = { UsefulSalts = 2, Iron = 1 } },
		{ Item = "PotatoSeed", Amount = 2, Cost = { UsefulSalts = 1 } },
		{ Item = "LettuceSeed", Amount = 2, Cost = { UsefulSalts = 2 } },
		{ Item = "TomatoSeed", Amount = 2, Cost = { UsefulSalts = 3, Sulfur = 1 } },
	},
}

------------------------------------------------------------------------ WATER
-- Water is shared across a base (like power) but is stored over time.
Config.Water = {
	TickRate = 1,  -- seconds
}

---------------------------------------------------------------------- FARMING
Config.Farming = {
	TickRate = 1,
	RequiresPower = true,
	RequiresWater = true,
	WaterPerPlot = 0.2,       -- water/s for each growing plot
	PlotSize = Vector3.new(7, 1, 7),
	StarterSeeds = { PotatoSeed = 3 },  -- given once to new players
}

-- Seed item -> crop. GrowTime in seconds, Yield = food items, Seeds = {min,max} returned
Config.Crops = {
	PotatoSeed  = { Crop = "Potato",  GrowTime = 180, Yield = 2, Seeds = { 1, 2 }, Color = Color3.fromRGB(150, 110, 70) },
	LettuceSeed = { Crop = "Lettuce", GrowTime = 120, Yield = 2, Seeds = { 1, 2 }, Color = Color3.fromRGB(120, 210, 90) },
	TomatoSeed  = { Crop = "Tomato",  GrowTime = 300, Yield = 2, Seeds = { 1, 2 }, Color = Color3.fromRGB(220, 60, 50) },
}

----------------------------------------------------------------------- HUNGER
Config.Hunger = {
	Enabled = true,
	Max = 100,
	DrainPerSecond = 100 / 1200, -- full -> empty in 20 minutes
	StarveDamage = 2,            -- health per second at 0 hunger
	RespawnHunger = 50,
}

---------------------------------------------------------------------- WEATHER
--[[
	Weather events are picked at random. Each one has Effects that other
	systems read through WeatherService.GetEffect(name):
	  O2Drain     - suit air drain multiplier for players OUTSIDE
	  WalkSpeed   - walk speed multiplier for players OUTSIDE
	  Solar       - solar panel output multiplier
	  Damage      - health per second to players OUTSIDE (reduced by StormProtection)
	Visuals are applied on the client (Lighting Atmosphere + dust particles).
]]
Config.Weather = {
	Enabled = true,
	TimeBetween = { 360, 720 },   -- seconds of clear weather between events (random)
	WarningTime = 60,              -- warning before an event hits
	RampTime = 15,                 -- seconds to build up / die down

	Events = {
		DustStorm = {
			DisplayName = "Dust Storm",
			Weight = 1,                 -- relative chance
			Duration = { 120, 240 },
			Effects = { O2Drain = 2.5, WalkSpeed = 0.7, Solar = 0.2, Damage = 0 },
			Visual = {
				AtmosphereDensity = 0.75, AtmosphereHaze = 8,
				AtmosphereColor = Color3.fromRGB(200, 120, 70),
				AtmosphereDecay = Color3.fromRGB(150, 80, 40),
				ParticleRate = 400, ParticleColor = Color3.fromRGB(190, 120, 75),
				WindSoundId = nil,
			},
		},
		SevereDustStorm = {
			DisplayName = "Severe Dust Storm",
			Weight = 0.3,
			Duration = { 90, 150 },
			Effects = { O2Drain = 3.5, WalkSpeed = 0.5, Solar = 0, Damage = 3 },
			Visual = {
				AtmosphereDensity = 0.9, AtmosphereHaze = 10,
				AtmosphereColor = Color3.fromRGB(170, 90, 50),
				AtmosphereDecay = Color3.fromRGB(110, 55, 30),
				ParticleRate = 900, ParticleColor = Color3.fromRGB(160, 95, 55),
				WindSoundId = nil,
			},
		},
	},
}

---------------------------------------------------------------------- MISSION
--[[
	MARS BASE 7  (Config.GameMode = "Mission")
	Keep the outpost alive for 7 sols. Each sol the crew shares a few power
	cells. Walk to a station's Power Port and press E to plug one in (E again
	to unplug). At the end of the sol every station changes a meter.
	Survive all sols AND make enough rocket fuel to fly home.

	Balance check (20,000 simulated games, see docs/GAME_DESIGN.md):
	  smart choices win ~100%, random choices ~47%, never powering Solar 0%.
	If you change the numbers below, keep "unpowered" much worse than
	"powered" is good, or random play starts winning again.
]]
Config.Mission = {
	Sols = 7,
	SolLength = 60,         -- seconds of play per sol (dev panel can change it live)
	BannerTime = 4,         -- "Sol 3: dust storm coming!" banner (shown during the sol)
	ReportTime = 7,         -- end-of-sol report
	FactTime = 9,           -- "Did you know?" card (everyone pressing Next skips it)
	IntroTime = 7,          -- lander touchdown at the start
	EndScreenDelay = 9,     -- rocket launch time before the victory screen

	StartCells = 3,         -- power cells every sol
	SolarBonus = 1,         -- extra cells next sol when Solar Panels were powered (and no dust storm)
	StartMeters = { Oxygen = 100, Food = 100, Health = 100 },
	MaxMeter = 100,
	FuelNeeded = 4,         -- fuel the rocket needs to launch

	-- Mars feel
	Gravity = 74.6,         -- Mars is ~0.38 g (Roblox default 196.2)
	JumpPower = 35,         -- ~8 stud jump at Mars gravity (50 would be ~17 studs)
	WalkSpeed = 16,

	-- Short camera tour when a player first spawns (skippable, "How to play" on the title screen replays it)
	Tutorial = {
		Enabled = true,
		Delay = 1.5,                -- seconds after spawning
		EvenDuringMission = false,  -- true = also show it to players who join mid-mission
	},

	HideSandboxModels = true,  -- move Workspace.BaseBuilding to ServerStorage while the mission runs
	RocketModelName = "RocketCapsule", -- your model (anywhere in Workspace). A placeholder is used if missing.

	-- Stations, in HUD order. Meter = which meter it changes.
	-- On / Off = change at the end of the sol when powered / not powered.
	Stations = {
		{
			Id = "Solar", Name = "Solar Panels", Icon = "☀️",
			OnText = "+1 power cell next sol", OffText = "No bonus cell",
			Color = Color3.fromRGB(255, 196, 70),
			FallbackPosition = Vector3.new(30, 4, -56),
		},
		{
			Id = "Oxygen", Name = "Oxygen Generator", Icon = "🫁", Meter = "Oxygen", On = 10, Off = -40,
			Color = Color3.fromRGB(90, 190, 255),
			FallbackPosition = Vector3.new(-24, 4, 68),
		},
		{
			Id = "Greenhouse", Name = "Greenhouse", Icon = "🌱", Meter = "Food", On = 15, Off = -30,
			Color = Color3.fromRGB(110, 220, 120),
			FallbackPosition = Vector3.new(26, 4, 74),
		},
		{
			Id = "Shield", Name = "Shield Bunker", Icon = "🛡️", Meter = "Health", On = 5, Off = -10,
			OnText = "Health +5, door opens for storms", OffText = "Health −10, door LOCKED",
			Color = Color3.fromRGB(190, 150, 255),
			FallbackPosition = Vector3.new(-4, 4, -34),
		},
		{
			Id = "Fuel", Name = "Rocket Fuel Plant", Icon = "⛽", Fuel = 1,
			OnText = "Rocket fuel +1", OffText = "No fuel made",
			Color = Color3.fromRGB(255, 122, 61),
			FallbackPosition = Vector3.new(100, 4, 5),
		},
	},

	Meters = {
		Oxygen = { Name = "Oxygen", Icon = "🫁", Color = Color3.fromRGB(90, 190, 255) },
		Food = { Name = "Food", Icon = "🍎", Color = Color3.fromRGB(240, 170, 80) },
		Health = { Name = "Health", Icon = "❤️", Color = Color3.fromRGB(255, 95, 110) },
	},

	-- Random events: at most one per sol. Weight = relative chance.
	CalmFirstSol = true,          -- sol 1 never has an event (learn the controls)
	EventStart = { 0.25, 0.55 },  -- surprise events start between 25% and 55% of the sol
	Events = {
		None = { Weight = 20 },
		DustStorm = {
			Weight = 40, Name = "Dust storm", Icon = "🌪️",
			Banner = "Dust storm coming!", Sub = "Dust will block the Sun. Solar Panels can't make a bonus cell this sol.",
			WeatherEvent = "DustStorm", -- WeatherService visuals (Config.Weather.Events)
		},
		SolarStorm = {
			Weight = 25, Name = "Solar radiation storm", Icon = "☢️",
			WarningTime = 15,        -- seconds to get inside the Shield Bunker
			DamageUnpowered = 40,    -- bunker has no power: door locked, nobody can shelter
			DamageOutside = 20,      -- bunker powered, but someone was caught outside
		},
		Micrometeorite = {
			Weight = 15, Name = "Micrometeorite hit", Icon = "☄️",
			Clicks = 5,              -- clicks (or E presses) to fix the leak, shared by the crew
			TimeLimit = 20,          -- seconds to fix it
			OxygenLoss = 10,         -- if not fixed in time
		},
	},

	-- Sounds. rbxasset:// sounds ship with Roblox. Put your own rbxassetid:// here if you like.
	Sounds = {
		Alarm = "rbxasset://sounds/electronicpingshort.wav",
		Plug = "rbxasset://sounds/clickfast.wav",
		Fixed = "rbxasset://sounds/electronicpingshort.wav",
		Launch = nil, -- e.g. "rbxassetid://..." rocket roar
	},
}

---------------------------------------------------------------------- HELPERS
function Config.ItemName(id)
	local item = Config.Items[id]
	return item and item.DisplayName or tostring(id)
end

function Config.CostText(cost)
	local parts = {}
	for item, n in pairs(cost or {}) do
		table.insert(parts, string.format("%dx %s", n, Config.ItemName(item)))
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "Free"
end

return Config
