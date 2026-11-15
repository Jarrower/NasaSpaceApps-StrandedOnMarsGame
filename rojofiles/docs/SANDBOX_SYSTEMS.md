# Base Building scripts: setup guide

## 1. Install the scripts (pick one way)

**Quick way:** open `INSTALLER_paste_in_command_bar.lua`, copy all of it, paste it into **View → Command Bar** in Studio, and press Enter. It creates every script in the right place.

**By hand:** create these and paste in the matching file:

| Studio location | Type | File |
|---|---|---|
| ReplicatedStorage › BaseShared › **Config** | ModuleScript | Config.lua |
| ReplicatedStorage › BaseShared › **Placement** | ModuleScript | Placement.lua |
| ServerScriptService › BaseServer › **Main** | Script | Main.server.lua |
| ServerScriptService › BaseServer › **InventoryService** | ModuleScript | InventoryService.lua |
| ServerScriptService › BaseServer › **BuildService** | ModuleScript | BuildService.lua |
| ServerScriptService › BaseServer › **NetworkService** | ModuleScript | NetworkService.lua |
| ServerScriptService › BaseServer › **MiningService** | ModuleScript | MiningService.lua |
| ServerScriptService › BaseServer › **ProcessingService** | ModuleScript | ProcessingService.lua |
| ServerScriptService › BaseServer › **AirlockService** | ModuleScript | AirlockService.lua |
| ServerScriptService › BaseServer › **PowerService** | ModuleScript | PowerService.lua |
| StarterPlayer › StarterPlayerScripts › **BuildClient** | LocalScript | BuildClient.client.lua |
| StarterPlayer › StarterPlayerScripts › BuildClient › **BuildUI** | ModuleScript | BuildClient/BuildUI.lua |

## 2. Models (templates)

The scripts copy buildings from **ReplicatedStorage › BuildTemplates**. The model names must match the keys in `Config.Buildables`:

`25x25`, `50x50`, `Connector`, `Airlock`, `Wall`, `SOLAR`, `generator`, `OxygenGenerator`, `SmallRefinery`, `LargeRefinery`

(`SOLAR` and `generator` are set with `Template = "..."` in Config, so the in-game names can be "Solar Panel" / "Fuel Generator".)

**You don't have to move them yourself.** When the game starts, any model with one of those names inside `Workspace › BaseBuilding` is moved into BuildTemplates automatically. The `BaseBuilding` folders (BaseTiles, Connectors, Walls, …) then hold the pieces players place. Moving them yourself in edit mode is cleaner, though.

Model checklist:
- **Tiles:** keep the part named `Base` (the floor). The wall height and component height are measured from the top of `Base`. The `Powered?` BoolValue you already have gets updated, and an `Oxygenated?` BoolValue is added.
- **Wall:** a single Part. It gets stretched to fit each tile edge. Its height and thickness become the wall height and thickness.
- **Connector / Airlock:** the **long** horizontal side is treated as the corridor direction. Each end snaps to a tile edge.
- **Airlock:** keep the `Doors` folder with the door parts. Prompts, tweens and particles are added when the airlock is built.
- **SOLAR / generator:** found automatically in your Generator folder.
- **Ores:** a ProximityPrompt named `Mine` anywhere inside a model named `GoldOre`, `IronOxide`, `Sillica`, `SulfateOre`, `SaltOre` or `TitaniumOre`. If a copy has a different name (for example scatter-brush copies), add a string attribute `OreType` = `GoldOre` to it.
- **Drill:** your existing `Miner` BoolValue works as it is.
- Build every template at **0° rotation** (facing the default direction).

## 3. How to play

- **B** opens the build menu → pick something → a green/red outline follows the mouse
- **R** rotate • **Q** cancel • **X** delete mode • **Left click** place
- Walk to the blue outline, **hold the material tool**, and press **E** (Add Material). It builds when everything is in.
- Refinery: hold ore and press **E** to insert, then **F** to collect.
- Airlock doors: press **E** to open. They close on their own, and opening one door closes the other.

- Fuel Generator: hold Sulfur and press **E** to refuel (1 Sulfur = 60 s, holds up to 20). It only burns fuel while something needs power.
- With the menu open and nothing selected, hover any of your buildings to see its power, oxygen and fuel status.

## Costs (all in Config.Buildables)

| Building | Cost | Power |
|---|---|---|
| Small Tile | 2 Iron Oxide | |
| Large Tile | 6 Iron Oxide | |
| Connector | 2 Iron Oxide, 2 Sillica | |
| Solar Panel | 4 Iron Oxide, 6 Sillica | +40 (no walls on its tile) |
| Small Refinery | 6 Iron Oxide, 4 Sillica | −20 |
| Wall (per side) | 2 Iron | |
| Airlock | 8 Iron, 4 Sillica | |
| Fuel Generator | 6 Iron, 4 Iron Oxide | +120 (burns Sulfur) |
| Large Refinery (large slot) | 10 Iron, 6 Sillica | −50 |
| Oxygen Generator | 6 Iron, 4 Useful Salts | −25 |

Progression: mine Iron Oxide + Sillica → tiles, connector, **Solar Panel + Small Refinery** (40 ≥ 20 power) → refine Iron, Sulfur, Salts → walls, airlock, fuel generator → Large Refinery (needs about 70 power: generator, or solar + more solar) → Titanium/Gold, which are saved for suits and advanced tech later.

## 4. Rules the scripts enforce

- Tiles snap onto the open end of a connector. Connectors snap onto a free tile edge. The first tile can go anywhere on terrain.
- 25x25 = 1 small slot. 50x50 = 2 small slots (left/right) **or** 1 large.
- Power: tiles linked by built connectors share power. The network is powered if generator output ≥ total draw.
- Enclosed = all 4 sides have a built wall (or a connector/airlock). Enclosed tiles get a roof automatically.
- Oxygen: enclosed rooms linked by connectors to a room with a powered OxygenGenerator.
- Each player has their own base. You can only snap to, build on, use, and delete your own pieces. Other players' prompts are hidden from you.
- A tile with a Solar Panel can't have walls, and a Solar Panel can't go on a tile that has walls.
- Inventories save automatically (on leave, every 2 minutes, and on shutdown). To test saving in Studio: Game Settings → Security → **Enable Studio Access to API Services**.
- Deleting an **outline** refunds everything deposited. Deleting a **building** refunds nothing. Deleting a tile also deletes its walls and components.

## 5. Adding new systems later (farm, water, …)

1. Add items to `Config.Items`, buildables to `Config.Buildables` (for example `Kind = "Component"`, `PowerDraw = 15`, plus your own flags such as `Farm = true`).
2. Make a ModuleScript in `ServerScriptService › BaseServer`:
   ```lua
   local Farm = {}
   function Farm.Init(S)
       S.BuildService.PieceBuilt.Event:Connect(function(model)
           local def = S.Placement.Def(model)
           if def.Farm then
               -- model:GetAttribute("Powered"), tile "Oxygenated" etc. are kept up to date
           end
       end)
   end
   return Farm
   ```
3. Add `"FarmService"` to the `SYSTEMS` list in **Main**.

Useful hooks: `S.InventoryService.Add/Remove/Get/GetHeld`, `S.NetworkService.Updated` (fires after every power/oxygen recalculation), `S.Notify(player, text)`, `Config.Power.GetOutput` (swap this for fuel-based generators).

## 6. Dev panel (testing)

Type **The Key To Wellness** in chat to open it. Type it again, or press **F8**, to show or hide it. Other players don't see the code in chat. Drag the panel by its header.

- **Target:** use the arrows to pick which player the commands affect (you by default).
- **Items:** give or remove any item (amount 1/10/100/1000 or custom), give all items, clear inventory, live item counts.
- **Base:** free build (outlines build instantly), finish all outlines, refuel generators, recalculate power/oxygen/roofs, processing speed x1/x10/x100, respawn all ores, delete a whole base (asks you to click twice).
- **Player:** WalkSpeed, JumpPower, heal, respawn, teleport to the target's base or to the target player.
- **World:** set the time of day (for testing solar), save inventory now.

Settings are in `Config.Dev`:
- `Enabled = false` turns the dev panel off completely.
- `AllowedUserIds = { yourUserId }` means only you can unlock it, even if someone learns the code. **Do one of these two before you publish.** The code is in Config, which is in ReplicatedStorage, so exploiters can read it.
- You can also change `ChatCode` and `ToggleKey`.

To add a command, add a function to `Commands` in **DevService**, then add a button in **DevClient** that calls `run("YourCommand", ...)`.

## 7. Oxygen, suits and weather

**Breathing (BreathingService, Config.Breathing)**
- You're inside if you stand in a tile or connector that has oxygen (4 walls + roof, linked to a powered Oxygen Generator). Inside, your suit tank refills. Outside, it drains.
- Mining makes you work hard, so you use 1.5× air for 3 s.
- Empty tank = 10 damage per second. Click an **O2 Canister** in your hotbar to get +30 s of air.
- If you have a room with oxygen, you respawn inside your base. You keep your items when you die.
- Each Oxygen Generator fills **4 units** (small tile = 1, large tile = 2). Air spreads out from the generator's room. Rooms past the limit have none, and the build menu's hover info says why.
- A room that loses oxygen keeps breathable air for 10 s (`Config.Oxygen.LeakTime`).

**Suits (SuitService, Config.Suits)**
- Basic (90 s, free) → Titanium (4 min, 25% storm protection) → Gold-Visor (8 min, 75% storm protection).
- Craft and equip them at the new **Fabricator** (Machines tab, uses 15 power). It also crafts O2 Canisters.
- Look: colour tint plus a glass helmet. To use your own models, set `Config.SuitVisuals.Mode = "Model"`, give each suit `Model = "Name"`, and put Accessories or parts in `ReplicatedStorage › SuitModels › Name`.
- Your current suit and the suits you own are saved.

**Weather (WeatherService, Config.Weather)**
- Every 6–12 min: a 60 s warning, then a storm for 2–4 min.
- **Dust Storm:** outside, air drains 2.5× and you walk 30% slower. Solar output drops to 20%.
- **Severe Dust Storm** (rarer): 3.5× air drain, half speed, solar off, 3 damage/s outside.
- A suit's StormProtection reduces the penalties for the player wearing it.
- Visuals: orange haze, blowing dust, a banner with a countdown. Inside the base, the dust is much lighter.
- To add a new event, add it to `Config.Weather.Events` with Effects and Visual.

**Dev panel → Survival tab:** infinite O2, refill/set/empty tank, give suits, start/warn/clear storms.

Note: BreathingService controls WalkSpeed (it applies the storm slowdown on top of the player attribute `BaseWalkSpeed`). If you add sprinting later, change `BaseWalkSpeed` instead of `Humanoid.WalkSpeed`.

## 8. Merged rooms and sealed connectors

- **Tiles snap to tiles.** Hover a tile near a free edge of another tile and it snaps flush against it. Tiles of different sizes line up centred or flush with either end. For example, four 25x25 tiles make a 2x2 room, and two 25x25 tiles fill one edge of a 50x50.
- **One room:** tiles that touch form one room. The edges inside the room stay open (you can't put walls on them). Walls go only on the outside edges. When every outside edge is closed, the whole room gets a roof, shares power and oxygen, and each tile keeps its own component slots (four 25x25 tiles = 4 small slots).
- An edge that's only **partly** touching another tile (like a 25 against a 50) has a gap. Fill it with another tile before the room can seal.
- To join a new tile on an edge that already has a wall, delete that wall first.
- **Auto-fill around connectors and airlocks:** in a room with at least one wall, the gaps beside and above a connector or airlock are filled with free wall pieces. Turn this off with `Config.Walls.AutoFillAroundLinears = false`. Turn tile-to-tile snapping off with `Config.Build.AllowTileToTile = false`.

## 9. Drilling, water, farming, hunger (update 4)

**Setup:** run `setup/OneTimeSetup.lua` once in the Command Bar, then save. Anything it removes goes to `ServerStorage › SetupBackup`.

**Drilling (MiningService + DrillClient, Config.Drill / Config.Ores)**
- Ores are found in `Workspace › Resources` and `ScatterBrush_Placed`, by model name, an alias (`Sillicone`, `Titanium`) or an `OreType` attribute. A Mine prompt is added automatically if one is missing.
- **PC:** equip the drill and click an ore. **Mobile:** every press of the Mine prompt is one hit. A health bar shows over damaged ores.
- Tiers T0–T3 (saved). Upgrade at the Fabricator. Ore tier needed: Iron Oxide/Sillica T0, Salt/Sulfate T1, Titanium T2, Gold T3.

**Water (WaterService, Config.Water)**
- Water Pump: +2/s, uses 20 power. Water Tank: stores 500.
- Oxygen Generator uses 1 water/s. **No water = no oxygen.** The greenhouse uses 0.2/s for each growing plot.
- Shared across a base, like power. Hover a tile to see what's stored and the per-second in/out.

**Farming (FarmService, Config.Farming / Config.Crops)**
- Greenhouse Dome (Foundation tab): sealed by itself, joins the base with a connector, 8 plots, 30 power, adds 2 oxygen capacity.
- Hold a seed + E to plant. Growth pauses without power or water. E to harvest food + seeds.
- Potato 3 min, Lettuce 2 min, Tomato 5 min. New players get 3 Potato Seeds. More seeds are made at the Fabricator.

**Hunger (HungerService, Config.Hunger)**
- 100 → 0 over 20 minutes, then 2 damage/s. Click food to eat. Saved. You respawn with 50.

**Airlock (AirlockService, Config.Airlock.Mode = "Auto")**
- The door opens as the owner walks up. Stepping into the chamber closes it behind you, plays 2 s of mist, then opens the other door. Only one door is ever open.
- Mist and sounds come from `ReplicatedStorage › BaseAssets` (copied from your MistZone and metal door).
- To use the metal-door panels, put LeftDoor/RightDoor pairs into the Airlock template's `Doors` folder (one pair at each end) and set `OpenDirection = "Side"`. Set `Mode = "Prompt"` to go back to press-E doors.

**Dev panel → Survival:** infinite food / set hunger, drill tier T0–T3, grow all crops, fill/empty tanks, spawn any ore.
