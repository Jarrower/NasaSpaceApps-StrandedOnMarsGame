# MarsBase (Rojo)

Rojo manages **only the scripts**. Models, terrain, Lighting, BuildTemplates,
the Drill tool and other scripts stay in your place file (`$ignoreUnknownInstances`).

| Folder in this project | Appears in Studio as |
|---|---|
| `src/shared/BaseShared/` | ReplicatedStorage › BaseShared (Config, Placement) |
| `src/server/BaseServer/` | ServerScriptService › BaseServer (Main + services) |
| `src/client/` | StarterPlayer › StarterPlayerScripts |
| `src/client/BuildClient/init.client.lua` | the BuildClient LocalScript (BuildUI.lua sits inside it) |

File names decide the script type:
- `X.server.lua` → Script
- `X.client.lua` → LocalScript
- `X.lua` → ModuleScript
- A folder with `init.*.lua` → a script that has children

## Daily use
1. Open this folder in VS Code and run `rojo serve` (or use the Rojo extension's "Start server").
2. In Studio, open your place → Plugins → Rojo → **Connect**.
3. Edit code in VS Code. It syncs into Studio straight away.
4. **Save the place in Studio** (Ctrl+S) so the published game has the new code.

Don't use `rojo build` to make your place. It would only contain the scripts, not your models.
