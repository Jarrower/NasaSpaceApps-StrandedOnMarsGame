# Testing

## The dev panel

Type **The Key To Wellness** in chat to open it (other players don't see the message). Press **F8** to show/hide it.
Drag it by its header.

In Mission mode it has three tabs:

| Tab | Buttons |
|---|---|
| **Mission** | Start · Skip phase · Pause timer · Restart · Back to title · Sol length 60/20/10 s · Jump to sol · set Oxygen/Food/Health (100/30/5) · Fuel 0/3/full · +1 power cell · Dust storm / Solar storm / Meteorite · WIN now · Lose by Oxygen/Food/Health/Fuel · Show fact # · Teleport to the hub, bunker, rocket and each station |
| **Player** | WalkSpeed, JumpPower, heal, respawn |
| **World** | Time of day |

> **Before publishing:** set `Config.Dev.Enabled = false` in `Config.lua`, or put your Roblox user ID in
> `Config.Dev.AllowedUserIds`. Right now anyone who types the code can open the panel.

**Quick demo for judges:** Mission → **Sol 20s** → Start. A full mission then takes about 4 minutes.

## Test checklist

| Test | Steps | Expect |
|---|---|---|
| Setup | Run `MissionSetup.lua`, then `MapBuilder.lua`, save, Play | Output has no `WARNING` lines (or only the RocketCapsule note). No `[Stations] ... fallback` warnings. |
| Tutorial | Play | Camera tour starts after ~1.5 s; Next/Back move between stations; Skip ends it; title screen appears after |
| Title + intro | Play → Start Mission | Rocket (or placeholder) drops onto the pad, camera circles it, "Touchdown!" |
| Plug / unplug | Walk to any Power Port, press E twice | Cell tray 3→2→3, sign turns POWERED/NO POWER, light + outline on the station, toast |
| Out of cells | Plug 3 stations, press E at a 4th | "No power cells left!" toast |
| Fast sols | Mission → Sol 10s | Sols end quickly; report → fact → next sol |
| Solar bonus | Power Solar, Skip phase until next sol | Banner says 4 cells "(Solar bonus!)" |
| Dust storm | Mission → Dust storm (during a sol) | Orange haze + dust, Solar sign "Dust storm!", report says "Dust blocked the Sun", next sol 3 cells |
| Solar storm, safe | Power Shield, Mission → Solar storm, run inside | Red alert + alarm + bunker marker, door opens, "Everyone was safe" |
| Solar storm, outside | Same, stay outside | Health −20 |
| Solar storm, unpowered | Unplug Shield, trigger, try the door | Door stays shut ("LOCKED" toast), Health −40 |
| Not trapped | Power Shield, go inside, Skip phase until the next sol starts (everything unplugs), walk to the door | Door still opens from the inside |
| Micrometeorite | Mission → Meteorite | Streak + flash near a station, sparking leak, 5 clicks fix it; ignore it → Oxygen −10 |
| Each failure | Mission → Lose: Oxygen / Food / Health / Fuel | Failure screen with the right title, lines, why, tip |
| Real failure | Oxygen 5 button, leave Oxygen Generator off, Skip phase | Report shows Oxygen −40, then "Out of air!" with the sol lines |
| Fuel failure | Mission → Fuel 0, Jump to sol 7 | After the report: "Not enough rocket fuel!" |
| Victory | Mission → WIN now | Launch with flame + smoke, camera follows, then Mission Complete stats → Play again |
| Facts | Mission → Show fact # 1…11 | Each card + source |
| Pause | Pause timer ON | Timer stops, HUD shows "PAUSED" |
| Co-op | Studio → Test → Clients and Servers, 2 players | Shared cells, "by <name>" on stations, both must press Next to skip |
| Sandbox still works | Config.GameMode = "Sandbox", Play | Original game, build menu (B), no mission UI, MissionBase hidden |

## Automated checks (outside Studio)

| Command | What it checks |
|---|---|
| `python3 tools/balance_check.py` | Simulates 20,000 missions per play style and prints the win rates in [GAME_DESIGN.md](GAME_DESIGN.md) |
| `python3 tools/make_install.py` | Rebuilds `install/MarsBase7_Scripts.rbxmx` from `src/` |
