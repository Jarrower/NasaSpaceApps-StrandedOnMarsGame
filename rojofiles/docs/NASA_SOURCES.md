# NASA sources

Every "Did you know?" card and the Mars numbers in the game were checked against these NASA pages.
The card text is our own kid-friendly wording; it lives in `src/shared/BaseShared/MissionFacts.lua`.

## Fact cards

| # | Card | When it's shown | Source |
|---|---|---|---|
| 1 | **A day on Mars** — a sol lasts about 24 hours and 39 minutes | calm sol | [NASA GISS – Mars24 Sunclock](https://www.giss.nasa.gov/tools/mars24/) |
| 2 | **Feeling light** — Mars gravity is 38% of Earth's | calm sol | [NASA JPL – Mars at a Glance](https://www.jpl.nasa.gov/news/press_kits/insight/launch/facts/mars-at-a-glance) |
| 3 | **Space salad** — in 2015 astronauts ate lettuce grown in NASA's Veggie | calm sol, food failure | [NASA NTRS – Veggie: Space Vegetables for the ISS and Beyond](https://ntrs.nasa.gov/citations/20160004060) |
| 4 | **Making air on Mars** — MOXIE made 122 g of oxygen from Mars air (a small dog's 10 hours of breathing) | calm sol, oxygen failure | [NASA JPL – MOXIE Completes Mars Mission](https://www.jpl.nasa.gov/news/nasas-oxygen-generating-experiment-moxie-completes-mars-mission/) |
| 5 | **No magnetic shield** — Mars lost its global magnetic field, so more radiation reaches the ground | solar storm, health failure | [NASA – Mars Facts](https://science.nasa.gov/mars/facts/) |
| 6 | **Hiding from radiation** — Curiosity's data helps plan how astronauts stay safe; the landscape could be a shield | calm sol, health failure | [NASA – Watches Mars Light Up During Epic Solar Storm](https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/) |
| 7 | **Fuel for the trip home** — MOXIE tested making oxygen for a rocket back to Earth | calm sol, fuel failure | [NASA – MOXIE Completes Mars Mission](https://www.nasa.gov/missions/mars-2020-perseverance/nasas-oxygen-generating-experiment-moxie-completes-mars-mission/) |
| 8 | **The storm that stopped a rover** — a 2018 global dust storm ended Opportunity (planned for 90 days, explored for almost 15 years) | dust storm | [NASA JPL – Opportunity Rover Mission on Mars Comes to End](https://www.jpl.nasa.gov/news/nasas-opportunity-rover-mission-on-mars-comes-to-end/) |
| 9 | **Dusty solar panels** — a dust storm cut InSight's power by about a third (425 → 275 watt-hours per sol) | dust storm | [NASA – InSight Waits Out Dust Storm](https://www.nasa.gov/missions/insight/nasas-insight-waits-out-dust-storm/) |
| 10 | **A real solar storm** — in May 2024 an astronaut next to Curiosity would have received about 30 chest X-rays of radiation | solar storm, health failure | [NASA – Watches Mars Light Up During Epic Solar Storm](https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/) |
| 11 | **Space rocks** — Mars air is ~1% as dense as Earth's; InSight felt a meteoroid impact in 2021 | micrometeorite | [NASA – InSight Lander Detects Stunning Meteoroid Impact on Mars](https://www.nasa.gov/missions/insight/nasas-insight-lander-detects-stunning-meteoroid-impact-on-mars/) |

## Game mechanics based on NASA data

| In the game | Based on |
|---|---|
| Gravity 74.6 studs/s² (0.38 × Roblox default) | Mars gravity 38% of Earth's (JPL, Mars at a Glance) |
| Dust storms stop the solar bonus | Opportunity (2018) and InSight (2022) lost solar power to dust |
| Solar storms + Shield Bunker | No global magnetic field, thin atmosphere; Curiosity RAD measurements |
| Micrometeorite leaks | Thin atmosphere lets meteoroids reach the surface (InSight) |
| Oxygen Generator, Fuel Plant | MOXIE: oxygen from Mars air, for breathing and rocket propellant |
| Greenhouse | NASA Veggie plant growth system on the ISS |
| "Sol" as the unit of time | NASA GISS Mars24 |

## Tools and other resources

| Resource | Link |
|---|---|
| Roblox Studio (game engine) | https://create.roblox.com |
| Luau (programming language) | https://luau.org |
| Rojo (code sync, open source) | https://rojo.space |
| Roblox built-in particle textures and sounds | https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter |
| Python (balance simulation, place-file analysis) | https://www.python.org |
| python-lz4 / python-zstandard (reading `.rbxl` files) | https://github.com/python-lz4/python-lz4 · https://github.com/indygreg/python-zstandard |
| Claude by Anthropic (AI assistant: code, planning, fact-checking) | https://www.anthropic.com/claude |

All 3D models in the game were handmade by the team in Roblox Studio. No models from the Roblox Creator Store
or other sources were used.
