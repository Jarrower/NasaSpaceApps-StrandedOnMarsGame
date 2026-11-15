"""
Mars Base 7 balance check.  Run:  python3 tools/balance_check.py

Simulates the mission rules (same numbers as Config.Mission) with different
kinds of players and prints how often each one wins. Change the numbers in
RULES to try a new balance before editing Config.lua.
"""
import random

RULES = dict(
    sols=7, cells=3, solar_bonus=1, fuel_needed=4, max_meter=100,
    oxygen=(10, -40), food=(15, -30), health=(5, -10),   # (powered, not powered)
    events={"None": 20, "DustStorm": 40, "SolarStorm": 25, "Micrometeorite": 15},
    flare_unpowered=40, flare_outside=20, leak_loss=10,
)
STATIONS = ["Solar", "Oxygen", "Greenhouse", "Shield", "Fuel"]


def play(policy, rng, reach=0.9, fix=0.9, R=RULES):
    m = {"Oxygen": 100, "Food": 100, "Health": 100}
    fuel, bonus = 0, 0
    for sol in range(1, R["sols"] + 1):
        ev = "None" if sol == 1 else rng.choices(list(R["events"]), weights=list(R["events"].values()))[0]
        cells = R["cells"] + bonus
        on = set(policy(sol, cells, dict(m), fuel, ev == "DustStorm", rng))
        assert len(on) <= cells
        if ev == "SolarStorm":
            if "Shield" not in on:
                m["Health"] -= R["flare_unpowered"]
            elif rng.random() > reach:
                m["Health"] -= R["flare_outside"]
        if ev == "Micrometeorite" and rng.random() > fix:
            m["Oxygen"] -= R["leak_loss"]
        if min(m.values()) <= 0:
            return "dead"
        for meter, station in (("Oxygen", "Oxygen"), ("Food", "Greenhouse"), ("Health", "Shield")):
            up, down = R[meter.lower()]
            m[meter] = min(R["max_meter"], m[meter] + (up if station in on else down))
        if "Fuel" in on:
            fuel += 1
        if min(m.values()) <= 0:
            return "dead"
        if fuel + (R["sols"] - sol) < R["fuel_needed"]:
            return "no fuel"
        bonus = R["solar_bonus"] if ("Solar" in on and ev != "DustStorm") else 0
    return "win"


def smart(sol, cells, m, fuel, dusty, rng, R=RULES):
    """Keeps the lowest meter up, powers Solar unless a dust storm is coming, fuels in time."""
    risk = {"Oxygen": m["Oxygen"] + R["oxygen"][1], "Greenhouse": m["Food"] + R["food"][1],
            "Shield": m["Health"] + R["health"][1] - R["flare_unpowered"] * 0.6}
    order = sorted(risk, key=risk.get)
    pick = []
    need, left = R["fuel_needed"] - fuel, R["sols"] - sol + 1
    if need > 0 and need >= left:
        pick.append("Fuel")
    if not dusty and sol < R["sols"] and (cells >= 4 or risk[order[0]] > 12) and len(pick) < cells:
        pick.append("Solar")
    for k in order:
        if len(pick) < cells and (risk[k] < 60 or k == "Shield"):
            pick.append(k)
    if need > 0 and "Fuel" not in pick and len(pick) < cells:
        pick.append("Fuel")
    for k in order:
        if len(pick) < cells and k not in pick:
            pick.append(k)
    return pick[:cells]


def random_choice(sol, cells, m, fuel, dusty, rng):
    return rng.sample(STATIONS, min(cells, len(STATIONS)))


def never_solar(sol, cells, m, fuel, dusty, rng):
    return ["Oxygen", "Greenhouse", "Shield", "Fuel", "Solar"][:cells]


def skips_bunker(sol, cells, m, fuel, dusty, rng):
    return ["Fuel", "Solar", "Oxygen", "Greenhouse"][:cells]


if __name__ == "__main__":
    N = 20000
    for name, policy, kw in [
        ("Smart choices", smart, {}),
        ("Smart, but slow to reach the bunker / fix leaks (60%)", smart, {"reach": 0.6, "fix": 0.6}),
        ("Random choices", random_choice, {}),
        ("Never powers Solar", never_solar, {}),
        ("Leaves the Shield Bunker off", skips_bunker, {}),
    ]:
        rng = random.Random(1)
        results = {}
        for _ in range(N):
            r = play(policy, rng, **kw)
            results[r] = results.get(r, 0) + 1
        print(f"{name:55s} win {results.get('win', 0) / N * 100:5.1f}%   {results}")
