# Code structure

The game is written in **Luau** for Roblox. Scripts are kept in this repository and synced into Studio with
**Rojo** (or installed with `install/`). Models, terrain and lighting live in the place file.

## Folders

```
README.md
LICENSE
default.project.json        Rojo: maps src/ into the place
src/
  shared/BaseShared/        -> ReplicatedStorage.BaseShared   (server + client)
    Config.lua                 every tunable number (Config.Mission for Mars Base 7)
    MissionFacts.lua           "Did you know?" cards with NASA sources
    Placement.lua              sandbox build-snapping maths
  server/BaseServer/        -> ServerScriptService.BaseServer
    Main.server.lua            boots the SYSTEMS list for Config.GameMode
    MissionService.lua         sols, meters, rules, reports, win / lose
    StationService.lua         Power Ports, shared power cells, bunker door
    MissionEvents.lua          dust storm, solar storm, micrometeorite
    RocketService.lua          landing intro + victory launch
    WeatherService.lua         dust storm visuals (shared with sandbox)
    DevService.lua             dev panel commands (checked on the server)
    ...                        sandbox systems (building, mining, suits, ...)
  client/                   -> StarterPlayer.StarterPlayerScripts
    MissionClient/             all Mars Base 7 UI: tutorial, HUD, reports, end screens, camera
      init.client.lua
      MissionUI.lua            theme + widgets
    DevClient.client.lua       dev panel window
    SurvivalClient.client.lua  dust storm visuals
    BuildClient/, DrillClient, FabricatorClient   sandbox only (exit in Mission mode)
setup/
  MissionSetup.lua          Command Bar: builds Workspace.MissionBase (stations, bunker, pad, spawn)
  MapBuilder.lua            Command Bar: Mars terrain, paths, signs, lights, boundary
  OneTimeSetup.lua          Command Bar: original sandbox model preparation
install/
  MarsBase7_Scripts.rbxmx   every script in one file (no Rojo needed)
  InstallScripts.lua        Command Bar: moves them into place
tools/
  balance_check.py          balance simulation
  make_install.py           rebuilds the .rbxmx from src/
docs/                       this documentation
```

`.server.lua` = Script, `.client.lua` = LocalScript, `.lua` = ModuleScript, a folder with `init.client.lua` =
a LocalScript with children.

## How it boots

`Main.server.lua` reads `Config.GameMode` and starts one of two lists. Each system is a ModuleScript with
`Init(S)`, started in order. `S` is a shared table (`S.Config`, `S.Notify`, `S.MissionService`, …).

```
Mission:  WeatherService -> StationService -> MissionEvents -> RocketService -> MissionService -> DevService
Sandbox:  InventoryService, BuildService, NetworkService, ... , DevService
```

## How a sol flows

```
MissionService.runSol
  -> StationService.BeginSol(cells)         unplug all, set the cell pool, open prompts
  -> MissionEvents.Roll / Schedule          dust now, or a surprise event later in the sol
  -> wait SolLength                         players press E at Power Ports (StationService.Toggle)
  -> StationService.SetLocked(true)
  -> resolveSol                             each station changes its meter, solar bonus, fuel
  -> Report  -> fail check -> Fact          sent to clients over BaseRemotes.MissionEvent
```

## Server -> client

- **State** is published as attributes on `ReplicatedStorage.MissionState`
  (Phase, PhaseEnds, Sol, Oxygen, Food, Health, Fuel, CellsTotal, CellsUsed, On_<Station>, Alert, …).
  The client redraws the HUD from them every frame.
- **One-off messages** go through `BaseRemotes.MissionEvent`: `Banner`, `Report`, `Fact`, `Intro`, `Launch`,
  `Victory`, `Failed`, `Toast`, `SolarStorm`, `Micrometeorite`.
- **Player actions** go through `BaseRemotes.MissionAction` (`Start`, `Again`, `Ready`, `GetEnd`).
  The server checks everything; the client only draws.

## Where to change things

| I want to… | Change |
|---|---|
| change a rule number | `Config.Mission.Stations` / `Config.Mission.Events` |
| make sols longer/shorter | `Config.Mission.SolLength` |
| add a fact card | `MissionFacts.lua` (add a table with `Tags`, `Title`, `Text`, `Source`, `Url`) |
| add a station | `Config.Mission.Stations` + a model with `StationId` and a `PowerPort` part in `MissionBase.Stations`, then handle its effect in `MissionService.resolveSol` |
| add an event | `Config.Mission.Events` + a runner in `MissionEvents.lua` (`RUNNERS` table) |
| change the UI look | `MissionUI.lua` (`UI.THEME`) |
| add a dev command | a function in `DevService.lua` `Commands` + a button in `DevClient.client.lua` |
| re-check the balance | edit `RULES` in `tools/balance_check.py` and run it |
