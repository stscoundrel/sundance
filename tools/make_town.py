#!/usr/bin/env python3
"""Lays out the town of San Miguel and writes data/town.json.

Grid units are tiles (x = gx, y = gy). Objects are placed by their footprint's
minimum corner; footprints come from world.BUILDINGS. The script refuses to write a
town where objects overlap or a bandit stands inside something.

Usage: tools/.venv/bin/python tools/make_town.py
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world import BUILDINGS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 64

STREETS = [
    [0, 28, 64, 33],      # main street, east-west through the middle of town
    [6, 13, 58, 16],      # north street
    [6, 45, 58, 48],      # south street
    [16, 4, 20, 60],      # west cross street
    [43, 4, 47, 60],      # east cross street
    [27, 33, 37, 41],     # the plaza, with the gallows
    # alleys between the buildings on main street
    [9, 16, 11.5, 28], [25.5, 16, 27.5, 28], [34.5, 16, 36.5, 28], [53, 16, 54.5, 28],
]

BUILDINGS_AT = [
    # north side of main street, facing it (fronts at y = 28)
    ("saloon", 2, 22), ("barber", 11.5, 24), ("sheriff", 20.5, 23), ("hotel", 27.5, 22),
    ("bank", 36.5, 22), ("gunsmith", 44, 24), ("store", 48, 23), ("undertaker", 54.5, 23), ("adobe_b", 59.5, 24),
    # back yards between main and north street
    ("adobe_a", 3, 16.5), ("feed", 20.5, 16.5), ("assay", 37, 16.5), ("stable", 47.5, 16.5),
    # north of the north street
    ("adobe_b", 3, 7), ("water_tower", 12, 8), ("church", 24, 5), ("adobe_a", 32, 7),
    ("adobe_a", 50, 6), ("adobe_b", 57, 8),
    # south of main street
    ("adobe_a", 3, 35), ("cantina", 9, 35), ("adobe_b", 21, 35), ("gallows", 30.5, 36.5),
    ("adobe_a", 37.5, 35), ("adobe_b", 48, 35), ("adobe_a", 55, 35),
    # south of the south street
    ("adobe_a", 22, 50), ("adobe_b", 31, 51), ("stable", 50, 50), ("adobe_b", 58, 52),
]

PROPS = [
    ("wagon", 12, 29.2), ("wagon", 31, 30.4), ("wagon", 50, 29.0), ("wagon", 34.2, 38.9),
    ("wagon", 24, 46.0), ("trough", 6, 28.6), ("trough", 23, 28.7), ("trough", 42.2, 29.4),
    ("trough", 28.5, 34), ("trough", 56, 46.2), ("hitch", 14.3, 28.7), ("hitch", 29, 28.9),
    ("hitch", 39.5, 28.9), ("hitch", 50.5, 28.6), ("coffin", 55.2, 28.8), ("coffin", 57, 29.6),
    ("coffin", 6, 54), ("coffin", 10, 57.5),
]
# crosses on boot hill
for x, y in ((4.5, 51.5), (6.5, 55), (8.2, 52.2), (4.8, 56), (8.6, 55.6), (3.2, 54), (11, 52.5), (12, 55.5)):
    PROPS.append(("cross", x, y))
# cacti scattered beyond the houses
for x, y in ((1.5, 4), (9, 2), (36, 2.5), (61, 3), (62.5, 18), (1, 42), (62, 42), (15, 61), (38, 61.5),
             (61, 61), (28, 57), (44, 62), (1.2, 25), (40, 52)):
    PROPS.append(("cactus", x, y))

# crates and barrels: stacked against walls and in the yards, by fixed seed
_rng = random.Random(3)
SPOTS = [(10, 17), (16.5, 21), (26, 17.5), (34, 19.5), (42.5, 18.5), (55, 18), (60, 21), (7.2, 10.5),
         (15, 6.5), (30.5, 11.6), (39, 11.8), (54.5, 12.3), (2.2, 33.8), (16.8, 37), (25.7, 34), (36.6, 41.5),
         (43.5, 39), (53, 39.5), (61, 39), (19, 49), (28.5, 49), (36, 50), (46, 51), (60.5, 49),
         (21, 42.5), (41, 44), (8, 43.5), (14.5, 42)]
for x, y in SPOTS:
    cx = x
    for k in range(_rng.randint(1, 3)):
        kind = "crate" if _rng.random() < 0.55 else "barrel"
        PROPS.append((kind, round(cx, 2), round(y + _rng.uniform(-0.1, 0.1), 2)))
        cx += BUILDINGS[kind][1][0] + 0.2

MUD = [[13, 30.5, 1.6], [24, 31, 1.2], [38, 30, 1.0], [55, 31.2, 1.4], [18, 40, 1.2], [45, 22, 1.1],
       [32, 14.5, 1.0], [9, 46.5, 1.2], [45, 52, 1.3], [30, 39, 0.9]]

ENEMIES = [
    # main street
    {"kind": "gunslinger", "x": 48, "y": 31.5, "patrol": [[48, 31.5], [61, 31.5]]},
    {"kind": "cowboy", "x": 22, "y": 31.6, "patrol": [[22, 31.6], [41, 31.6]]},
    {"kind": "gambler", "x": 4.5, "y": 28.5, "facing": 100},
    {"kind": "saloon_girl", "x": 8.2, "y": 28.5, "facing": 70},
    {"kind": "jefe", "x": 39.5, "y": 29.3, "facing": 135},
    # north of town
    {"kind": "rifleman", "x": 13, "y": 11.2, "facing": 45},
    {"kind": "rifleman", "x": 27, "y": 12.6, "facing": 90},
    {"kind": "poacher", "x": 62, "y": 13.6, "facing": 150},
    {"kind": "pistolero", "x": 48, "y": 14.5, "patrol": [[48, 14.5], [57, 14.5]]},
    {"kind": "cowboy", "x": 45, "y": 20, "facing": 180},
    # plaza and south of main street
    {"kind": "redscarf", "x": 28, "y": 34.3, "patrol": [[28, 34.3], [36, 34.3], [36, 40.6], [28, 40.6]]},
    {"kind": "oldtimer", "x": 34.5, "y": 42.2, "facing": 270},
    {"kind": "gunslinger", "x": 40.5, "y": 43.2, "facing": 300},
    {"kind": "drunkard", "x": 12, "y": 41, "facing": 60},
    {"kind": "pistolero", "x": 18, "y": 34, "patrol": [[18, 34], [18, 58]]},
    {"kind": "cowboy", "x": 45, "y": 34, "patrol": [[45, 34], [45, 58]]},
    # south street and beyond
    {"kind": "rifleman", "x": 52, "y": 46.6, "facing": 180},
    {"kind": "pistolero", "x": 10, "y": 46.6, "patrol": [[10, 46.6], [30, 46.6]]},
    {"kind": "drunkard", "x": 14, "y": 49, "facing": 200},
    {"kind": "redscarf", "x": 49, "y": 49, "facing": 200},
    # bandidos: the gang's rank and file, loafing about the poorer end of town
    {"kind": "bandido", "x": 17, "y": 39.5, "facing": 180},
    {"kind": "bandido", "x": 17.5, "y": 43, "patrol": [[17.5, 43], [24, 44]]},
    {"kind": "bandido", "x": 34, "y": 38.2, "facing": 225},
    {"kind": "bandido", "x": 21, "y": 13.8, "patrol": [[21, 13.8], [31, 13.8]]},
    {"kind": "hillbilly", "x": 27, "y": 55, "patrol": [[27, 55], [36, 56]]},
]

# Townsfolk, near the doors they'd run for. Fewer than the bandits.
CIVILIANS = [
    {"kind": "gunsmith", "x": 45.5, "y": 28.6, "facing": 90},
    # mourners, indoors in black until there's a fresh grave on boot hill
    {"kind": "mourner", "x": 8.4, "y": 37.4, "facing": 270, "indoors": True},
    {"kind": "mourner", "x": 25.4, "y": 37.4, "facing": 270, "indoors": True},
    {"kind": "mourner", "x": 27.4, "y": 52.4, "facing": 270, "indoors": True},
    {"kind": "saloon_girl", "x": 6.6, "y": 29.8, "facing": 60},
    {"kind": "townsman", "x": 15.2, "y": 30.2, "facing": 300},
    {"kind": "townsman", "x": 29.4, "y": 29.4, "facing": 120},
    {"kind": "gentleman", "x": 41.6, "y": 30.2, "facing": 200},
    {"kind": "townswoman", "x": 52.0, "y": 30.6, "facing": 250},
    {"kind": "townsman", "x": 58.6, "y": 30.8, "facing": 160},
    {"kind": "peon", "x": 28.6, "y": 39.8, "facing": 20},
    {"kind": "peon", "x": 35.6, "y": 34.6, "facing": 200},
    {"kind": "peon", "x": 17.4, "y": 38.6, "facing": 90},
    {"kind": "townswoman", "x": 31.4, "y": 10.4, "facing": 140},
    {"kind": "peon", "x": 48.2, "y": 47.2, "facing": 0},
    {"kind": "townswoman", "x": 22.6, "y": 47.0, "facing": 330},
    # couples out for a stroll: the first leads, the second walks on his arm
    {"kind": "gentleman", "x": 35.0, "y": 30.6, "facing": 0, "couple": 1, "wander": 150},
    {"kind": "townswoman", "x": 35.0, "y": 31.4, "facing": 0, "couple": 1},
    {"kind": "townsman", "x": 38.0, "y": 14.4, "facing": 180, "couple": 2, "wander": 150},
    {"kind": "townswoman", "x": 38.0, "y": 15.2, "facing": 180, "couple": 2},
    # the padre at the church door
    {"kind": "priest", "x": 31.2, "y": 9.0, "facing": 0},
    # the undertaker at his door, his apprentice up on boot hill
    {"kind": "undertaker", "x": 56.4, "y": 30.6, "facing": 90},
    {"kind": "apprentice", "x": 9.6, "y": 50.4, "facing": 45},
]

PLAYER = {"x": 63.2, "y": 63.2}   # the lower-right corner, hidden behind the stable and adobes


def footprint(kind, x, y):
    w, h = BUILDINGS[kind][1]
    return (x, y, x + w, y + h)


def overlaps(a, b, pad=0.0):
    return a[0] < b[2] + pad and b[0] < a[2] + pad and a[1] < b[3] + pad and b[1] < a[3] + pad


def main():
    objects = [{"type": k, "x": x, "y": y} for k, x, y in BUILDINGS_AT + PROPS]
    solid = [(o, footprint(o["type"], o["x"], o["y"])) for o in objects if BUILDINGS[o["type"]][2] != "none"]
    errors = []
    for i, (o, r) in enumerate(solid):
        if r[0] < 0.5 or r[1] < 0.5 or r[2] > N - 0.5 or r[3] > N - 0.5:
            errors.append(f"{o['type']} at {o['x']},{o['y']} leaves the map")
        for o2, r2 in solid[i + 1:]:
            if overlaps(r, r2, 0.1):
                errors.append(f"{o['type']} at {o['x']},{o['y']} overlaps {o2['type']} at {o2['x']},{o2['y']}")
    for e in ENEMIES + CIVILIANS:
        for p in [(e["x"], e["y"])] + [tuple(q) for q in e.get("patrol", [])]:
            pt = (p[0] - 0.35, p[1] - 0.35, p[0] + 0.35, p[1] + 0.35)
            for o, r in solid:
                if overlaps(pt, r):
                    errors.append(f"{e['kind']} point {p} is inside {o['type']} at {o['x']},{o['y']}")
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    town = {
        "name": "San Miguel",
        "size": N,
        "streets": STREETS,
        "mud": MUD,
        "boothills": [[2, 49, 14, 60]],
        "objects": objects,
        "player": PLAYER,
        "enemies": ENEMIES,
        "civilians": CIVILIANS,
    }
    with open(os.path.join(ROOT, "data", "town.json"), "w") as f:
        json.dump(town, f, indent=1)
    print("town: %d buildings, %d props, %d bandits, %d townsfolk" % (
        len(BUILDINGS_AT), len(PROPS), len(ENEMIES), len(CIVILIANS)))


if __name__ == "__main__":
    main()
