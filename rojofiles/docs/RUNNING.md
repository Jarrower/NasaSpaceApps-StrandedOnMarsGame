# Running Stranded on MARS

There are three ways to run the game. **Option 1 is the fastest** if the repository includes `NASASPACEAPPS_StrandedOnMars_Finalized.rbxl`.

## What you need

- **Roblox Studio** — free from https://create.roblox.com (Windows 10+ or macOS)
- A **Roblox account** to sign in to Studio
- Optional, for Option 3: **Rojo** (https://rojo.space) if you want to edit code in VS Code

---

## Option 1 — Open the place file

1. On GitHub press **Code → Download ZIP** and unzip it (or `git clone` the repository).
2. Open Roblox Studio and sign in.
3. **File → Open from File…** and choose **`NASASPACEAPPS_StrandedOnMars_Finalized.rbxl`** from the top of the unzipped folder (next to `rojofiles/`).
4. Press **Play** (F5).
5. A camera tour starts after about 1.5 seconds. Press **Next** to follow it or **Skip tutorial**.
6. On the title screen press **START MISSION**.

To stop, press **Stop** (Shift+F5).

## Option 2 — Play online

Open the Roblox game link in the README and press **Play**. This needs the Roblox app and an account.

## Option 3 — Build from source

Use this when you only have the code, or you changed it.

### 3a. Get the scripts into a place

Open the place you want to use (the team's place, or **File → New → Baseplate**) and save it first.

**Without Rojo (simplest)**

1. In the **Explorer**, right-click **Workspace → Insert from File…** and choose
   `install/MarsBase7_Scripts.rbxmx`. A folder **MarsBase7_Scripts** appears in Workspace.
2. Open **View → Command Bar**.
3. Open `install/InstallScripts.lua` in any text editor, copy **all** of it, paste it into the Command Bar and press
   **Enter**.
4. The **Output** window (View → Output) lists every installed script and ends with `DONE`.
   Old scripts are kept in `ServerStorage › SetupBackup › OldScripts_<time>`; they don't run there.

If you edit any code in `src/`, rebuild the pack with `python3 tools/make_install.py`.

**With Rojo**

1. Install Rojo and the Rojo Studio plugin (https://rojo.space/docs).
2. In a terminal, in this repository's folder: `rojo serve`
3. In Studio: **Plugins → Rojo → Connect**. The scripts sync into the place.
4. Save the place. (Don't use `rojo build` — it would make a place with only scripts and no models.)

### 3b. Build the map (once per place)

1. Paste all of `setup/MissionSetup.lua` into the Command Bar → **Enter**.
   It creates `Workspace › MissionBase` with the stations, Power Ports, the Shield Bunker, the rocket pad and the spawn.
2. Paste all of `setup/MapBuilder.lua` into the Command Bar → **Enter**.
   It replaces the terrain with a Mars crater (the old terrain is backed up first), lays paths, signs and lights,
   and puts everything on the ground. **Ctrl+Z** undoes it.
3. Wait for `[MapBuilder] DONE` in the Output, then **save** (Ctrl+S).
4. Press **Play**.

Both scripts are safe to run again. They never delete your models — anything they replace goes to
`ServerStorage › SetupBackup`.

### Your own rocket

Put a Model named **`RocketCapsule`** anywhere in Workspace. When the game runs, it's moved onto the rocket pad,
lands during the intro and launches on victory. Without it, a simple placeholder capsule is used.

---

## Settings you might want to change

All in `src/shared/BaseShared/Config.lua` (or `ReplicatedStorage › BaseShared › Config` in Studio):

| Setting | What it does |
|---|---|
| `Config.GameMode` | `"Mission"` = Stranded on MARS, `"Sandbox"` = the original base-building game |
| `Config.Mission.SolLength` | seconds per sol (default 60) |
| `Config.Mission.Tutorial.Enabled` | camera tour when a player first spawns |
| `Config.Mission.Stations` / `Events` | every rule number (see [GAME_DESIGN.md](GAME_DESIGN.md)) |
| `Config.Dev.Enabled` | dev panel on/off — **set to `false` for a public game** |

## Publishing to Roblox

1. **File → Publish to Roblox As…** → create a new experience.
2. Set `Config.Dev.Enabled = false` first (or fill in `Config.Dev.AllowedUserIds`).
3. In **Game Settings → Permissions**, make the experience **Public**.

---

## Troubleshooting

| You see… | Fix |
|---|---|
| A **BUILD** button and an **O₂ suit timer** | The old sandbox scripts are running. Do step 3a again. If you use Rojo, make sure it serves **this** folder, or disconnect it. |
| `Workspace.MissionBase not found` in the Output | Run `setup/MissionSetup.lua` (step 3b). |
| `[Stations] No PowerPort for ... made a fallback one` | MissionSetup couldn't find one of the team's models. The game still works with a plain post. |
| `Couldn't back up the old terrain` | Set `BACKUP_OLD_TERRAIN = false` at the top of `MapBuilder.lua` to clear it without a backup. |
| You fall through the floor | The terrain is missing. Run `setup/MapBuilder.lua`. |
| No sound for alarms | Put your own sound IDs in `Config.Mission.Sounds`. |
| The mission doesn't start | Check the Output for red errors and that `Config.GameMode = "Mission"`. |
