# Game design

## The challenge

> *Design and build an interactive game or app that lets students run a lunar or Martian outpost, balancing
> competing demands like life support, radiation shielding, power, and food production, so they experience
> firsthand the decisions that determine whether a mission fails or succeeds.*

Our answer: give the crew **fewer power cells than stations**, every sol, and make every choice show a clear
consequence. The game is about **trade-offs**, not reflexes.

## Design goals

1. **One core decision** a young learner can understand in seconds: *which stations get power?*
2. **Cause → effect on every screen.** The sol report lists each station, ON/OFF, and exactly what changed.
3. **Real engineering ideas:** investing in power, life support first, radiation shelter, planning for the trip home.
4. **Real science:** every fact card is checked against a NASA source ([NASA_SOURCES.md](NASA_SOURCES.md)).
5. **Short and replayable:** ~9 minutes per mission, random events make each run different.
6. **Solo or co-op:** the crew shares the cells and the meters, so friends have to talk and split jobs.

## Rules and numbers

All numbers live in `Config.Mission` (`src/shared/BaseShared/Config.lua`).

| Setting | Value |
|---|---|
| Sols | 7 (60 s each) |
| Power cells per sol | 3 (+1 next sol if Solar Panels were powered and no dust storm) |
| Meters | Oxygen, Food, Health start at 100, max 100 |
| Fuel needed | 4 |
| Gravity | 74.6 studs/s² (Mars ≈ 0.38 g; Roblox default is 196.2) |

| Station | Powered | Not powered |
|---|---|---|
| ☀️ Solar Panels | +1 cell next sol | — |
| 🫁 Oxygen Generator | Oxygen +10 | Oxygen −40 |
| 🌱 Greenhouse | Food +15 | Food −30 |
| 🛡️ Shield Bunker | Health +5, door opens | Health −10, door locked |
| ⛽ Rocket Fuel Plant | Fuel +1 | — |

Meters change at the **end** of the sol, from what is plugged in at that moment.
The mission fails as soon as a meter hits 0 or the remaining sols can't make enough fuel.

### Events

Sol 1 is calm. Then one roll per sol: none 20 · dust storm 40 · solar storm 25 · micrometeorite 15.

| Event | Effect | Science behind it |
|---|---|---|
| 🌪️ Dust storm | Announced; Solar gives no bonus cell | A 2018 global dust storm ended the solar-powered Opportunity rover |
| ☢️ Solar storm | 15 s to reach the bunker. Powered + inside: 0 · powered + someone outside: −20 Health · unpowered: −40 Health | Mars has no global magnetic field; Curiosity's RAD measured a big storm in 2024 |
| ☄️ Micrometeorite | Fix a leak (5 clicks in 20 s) or Oxygen −10 | Mars air is ~1% as dense as Earth's, so space rocks reach the ground |

**Why the bunker needs power:** real radiation shielding is mass (walls, soil, water), not electricity. In the game,
power runs the bunker's **door, air and lights** — without power the crew can't get in. That keeps the science
honest and the rule simple.

## Balance

We wanted thoughtful play to almost always win, and random play to fail often.
`python3 tools/balance_check.py` simulates 20,000 missions per play style:

| How the crew plays | Wins |
|---|---|
| Smart: keeps the lowest meter up, powers Solar unless dusty, makes fuel in time | **100%** |
| Smart, but slow to reach the bunker / fix leaks (60% success) | **100%** |
| Random stations every sol | **47%** |
| Never powers Solar | **0%** (never enough fuel) |
| Leaves the Shield Bunker off | **14%** |

### What we changed after testing the numbers

Our first design had **4 stations** (no Fuel Plant) with gentler numbers (+20 / −25 and so on).
The simulation showed **random choices won 99.99%** of the time: with 3 cells you already power 3 of 4 stations,
and once Solar is on you have 4 cells every sol. There was no real decision.

Adding the **Rocket Fuel Plant** as a 5th demand fixed this: the crew always has more needs than cells, and the
"get home" goal competes with survival. It also ties into NASA's MOXIE experiment, which tested making oxygen for a
return rocket on Mars.

## Kid-friendly choices

- Big text, short sentences, emoji icons for every station and meter.
- Every station has a sign: *ON: Oxygen +10 / OFF: Oxygen −40*.
- The failure screen says **what** ran out, **why** (with the sols it happened), and a **tip**.
- A skippable camera-tour tutorial on first spawn.
- No fall damage, no character health — the crew meters are the only "health".
- Lower jump (`JumpPower = 35`, about 8 studs at Mars gravity) so players stay on the ground.

## Accessibility and classroom notes

- Works with keyboard, gamepad and touch (proximity prompts + click detectors).
- UI scales to the screen size.
- Teachers can shorten sols, trigger events and jump to any sol with the dev panel ([TESTING.md](TESTING.md)).
