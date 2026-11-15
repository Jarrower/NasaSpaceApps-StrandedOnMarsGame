# Sandbox mode (the original base-building game)

> This is the game Mars Base 7 was built from. It still ships in the project: set
> `Config.GameMode = "Sandbox"` in `src/shared/BaseShared/Config.lua` to play it.
> For Mars Base 7 itself see the main [README](../README.md). Detailed system notes: [SANDBOX_SYSTEMS.md](SANDBOX_SYSTEMS.md).

Rojo manages **only the scripts**. Models, terrain, Lighting, BuildTemplates,
the Drill tool and other scripts stay in your place file (`$ignoreUnknownInstances`).

| Folder in this project | Appears in Studio as |
|---|---|
| `src/shared/BaseShared/` | ReplicatedStorage › BaseShared (Config, Placement) |
| `src/server/BaseServer/` | ServerScriptService › BaseServer (Main + services) |
| `src/client/` | StarterPlayer › StarterPlayerScripts |
| `src/client/BuildClient/init.client.lua` | the BuildClient LocalScript (BuildUI.lua sits inside it) |
| `src/client/MissionClient/init.client.lua` | the MissionClient LocalScript (MissionUI.lua sits inside it) |

File names decide the script type:
- `X.server.lua` → Script
- `X.client.lua` → LocalScript
- `X.lua` → ModuleScript
- A folder with `init.*.lua` → a script that has children

## One-time setup
Run `setup/OneTimeSetup.lua` once in Studio's Command Bar, then save the place. It prepares the models and moves anything it removes into ServerStorage › SetupBackup. Rojo does not sync the `setup` folder.

## Daily use
1. Open this folder in VS Code and run `rojo serve` (or use the Rojo extension's "Start server").
2. In Studio, open your place → Plugins → Rojo → **Connect**.
3. Edit code in VS Code. It syncs into Studio straight away.
4. **Save the place in Studio** (Ctrl+S) so the published game has the new code.

Don't use `rojo build` to make your place. It would only contain the scripts, not your models.
