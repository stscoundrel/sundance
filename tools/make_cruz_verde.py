#!/usr/bin/env python3
"""Lays out Cruz Verde and writes data/cruz_verde.json: a revolutionary garrison's
walled town (gates open on every side, two breaches), a village of jacales round
it, and a great cemetery to the west, a ring of stones at its heart. The stranger
starts outside the west gate: an ambush, most of the garrison indoors.

Usage: tools/.venv/bin/python tools/make_cruz_verde.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout  # noqa: E402

N = 64

# The walls: x 16..49, y 14..47; a bastion at each corner, a gate mid-way along each
# side, the south and east walls breached.
FORT = [
    ("bastion", 16, 14), ("bastion", 47, 14), ("bastion", 16, 45), ("bastion", 47, 45),
    # north
    ("wall_x8", 18, 14), ("wall_x4", 26, 14), ("gate_x", 30, 14), ("wall_x4", 35, 14), ("wall_x8", 39, 14),
    # south: a breach where the wall's been knocked through (x 39..43)
    ("wall_x8", 18, 46), ("wall_x4", 26, 46), ("gate_x", 30, 46), ("wall_x4", 35, 46), ("wall_x4", 43, 46),
    # west
    ("wall_y8", 16, 16), ("wall_y4", 16, 24), ("gate_y", 16, 28), ("wall_y4", 16, 33), ("wall_y8", 16, 37),
    # east: a breach at y 33..37
    ("wall_y8", 48, 16), ("wall_y4", 48, 24), ("gate_y", 48, 28), ("wall_y8", 48, 37),
]
INSIDE = [
    ("chapel", 19, 17), ("casa_grande", 37, 17), ("barracks", 19, 39), ("cantina", 37, 38),
    ("adobe_a", 19, 33.5), ("adobe_b", 43, 24),
]
OUTSIDE = [
    ("jacal", 52, 18), ("jacal_b", 56, 22.5), ("jacal", 52.5, 35.5), ("jacal_b", 57, 40), ("adobe_b", 53, 49),
    ("jacal", 22, 51), ("jacal_b", 40, 52), ("adobe_a", 45, 56), ("jacal", 26, 57),
    ("jacal_b", 38, 6), ("jacal", 44, 4), ("adobe_b", 22, 5),
]
PROPS = [
    ("well", 31.4, 29.4), ("flagpole", 34.5, 26.5), ("cannon", 25.5, 33.6),
    ("sandbags_x", 30.5, 16.8), ("sandbags_y", 18.6, 29.6), ("sandbags_y", 45.8, 30.0), ("sandbags_x", 31.0, 44.6),
    ("wagon", 36.5, 33.6), ("wagon", 22.0, 25.4), ("trough", 25.0, 28.4),
    ("crate", 29.5, 39.2), ("crate", 30.4, 40.2), ("barrel", 29.6, 40.6), ("barrel", 30.3, 41.4), ("crate", 46.2, 39.2),
    ("barrel", 36.0, 39.0), ("barrel", 36.0, 40.0),
    ("rubble", 40.0, 46.0), ("rubble", 48.0, 34.5),
    ("table", 39.0, 43.9), ("chair", 38.5, 44.0), ("olla", 23.3, 37.8), ("olla", 45.5, 28.2),
    ("coop", 55.5, 26.0), ("coop", 27.6, 55.0), ("hencrate", 51.4, 33.4),
    ("wagon", 55.0, 31.6), ("trough", 51.0, 28.6),
    ("cactus", 60, 6), ("cactus", 58, 14), ("cactus", 61, 47), ("cactus", 50, 61), ("cactus", 14, 60),
    ("cactus", 8, 60), ("cactus", 37, 60), ("cactus", 61, 58),
    ("agave", 51, 8), ("agave", 55, 12), ("agave", 60, 34), ("agave", 49, 44), ("agave", 35, 49.5),
    ("agave", 28, 49.5), ("agave", 18, 49), ("agave", 42, 10), ("agave", 26, 9), ("agave", 13, 6),
]

# The cemetery: rings of crosses, mounds and headstones round a circle of stones,
# and rows of graves below the west road.
CIRCLE = (4.5, 19.0)   # the stone circle's corner (it's 6 tiles across)


def cemetery():
    out = [("stone_circle", *CIRCLE)]
    cx, cy = CIRCLE[0] + 3, CIRCLE[1] + 3
    k = 0
    for r in (4.6, 6.0, 7.4, 8.8, 10.2):
        n = int(2 * math.pi * r / 1.5)
        for i in range(n):
            a = i / n * 2 * math.pi + r
            x, y = cx + r * math.cos(a), cy + r * math.sin(a)
            if not (0.8 < x < 14.4 and 1.0 < y < 27.6):
                continue
            kind = ("cross", "cross", "mound", "headstone", "cross", "headstone_b")[k % 6]
            out.append((kind, round(x, 2), round(y, 2)))
            k += 1
    for row, y in enumerate((34.0, 36.4, 38.8, 41.2, 43.6, 46.0, 48.4)):
        for i, x in enumerate(range(2, 14, 2)):
            kind = ("cross", "headstone", "cross", "mound", "headstone_b", "cross")[(i + row) % 6]
            out.append((kind, x + (row % 2) * 0.6, y))
    return out


STREETS = [
    [0, 29.5, 16, 31.5],     # the west road, past the cemetery to the west gate
    [49, 29.5, 64, 31.5],    # the east road
    [31.5, 0, 33.5, 14],     # the north road
    [31.5, 47, 33.5, 64],    # the south road
    [17, 28, 48, 33],        # the plaza, gate to gate
    [30, 15, 35, 46],
]
MUD = [[31.8, 31.4, 0.8], [50.0, 30.6, 1.0], [25.6, 29.4, 0.6]]

# The garrison's not as watchful as it ought to be: seven on the grounds...
ENEMIES = [
    {"kind": "rifleman", "x": 32.5, "y": 16.0, "look": (32.5, 8)},
    {"kind": "rifleman", "x": 46.0, "y": 44.4, "look": (41, 47)},
    {"kind": "saloon_girl", "x": 40.2, "y": 44.4, "look": (34, 44)},
    {"kind": "bandido", "x": 24.0, "y": 31.2, "patrol": [[24.0, 31.2], [30.0, 31.6], [41.0, 31.2]]},
    {"kind": "bandido", "x": 44.6, "y": 34.6, "look": (49, 35)},
    {"kind": "pistolero", "x": 33.8, "y": 18.0, "patrol": [[33.8, 18.0], [33.8, 37.0]]},
    {"kind": "drunkard", "x": 28.2, "y": 36.8, "look": (32, 32)},
]
# ...and the rest indoors, resting: they come out of these doors once the shooting
# starts. The ready ones in a couple of seconds; the rest have to wake and find
# their boots (El Jefe among them).
SLEEPERS = [
    {"kind": "pistolero", "x": 21.0, "y": 43.6, "ready": True},     # the barracks
    {"kind": "cowboy", "x": 24.0, "y": 43.6, "ready": True},
    {"kind": "redscarf", "x": 27.0, "y": 43.6, "ready": False},
    {"kind": "oldtimer", "x": 21.0, "y": 43.6, "ready": False},
    {"kind": "bandido", "x": 24.0, "y": 43.6, "ready": False},
    {"kind": "gunslinger", "x": 43.6, "y": 40.5, "ready": True},     # the cantina
    {"kind": "bandido", "x": 43.6, "y": 40.5, "ready": False},
    {"kind": "jefe", "x": 41.0, "y": 23.6, "ready": False},          # the general's house
]
for e in ENEMIES:   # (written as where each looks; placements take a screen angle)
    if "look" in e:
        lx, ly = e.pop("look")
        e["facing"] = layout.screen_deg(lx - e["x"], ly - e["y"])

CIVILIANS = [
    {"kind": "saloon_girl", "x": 38.2, "y": 43.8, "facing": 120},
    {"kind": "saloon_girl", "x": 42.3, "y": 44.0, "facing": 60},
    {"kind": "saloon_girl", "x": 37.6, "y": 36.8, "facing": 200},
    {"kind": "priest", "x": 21.5, "y": 23.7, "facing": 90},
    {"kind": "peon", "x": 27.4, "y": 29.6, "facing": 0},
    {"kind": "peon", "x": 39.4, "y": 27.4, "facing": 180},
    {"kind": "peon", "x": 54.0, "y": 21.8, "facing": 120},
    {"kind": "peon", "x": 23.8, "y": 54.6, "facing": 300},
    {"kind": "townswoman", "x": 30.2, "y": 34.6, "facing": 300},
    {"kind": "townswoman", "x": 56.0, "y": 39.2, "facing": 200},
    {"kind": "townswoman", "x": 41.2, "y": 51.0, "facing": 270},
    {"kind": "henwife", "x": 55.0, "y": 27.4, "facing": 300, "palette": 0},
    {"kind": "henwife", "x": 29.0, "y": 54.6, "facing": 200, "palette": 1},
]

HOLDOUTS = [{"name": "chapel", "x": 21.5, "y": 24.2}, {"name": "general's house", "x": 39.0, "y": 24.4},
            {"name": "barracks", "x": 23.5, "y": 44.6}, {"name": "cantina", "x": 43.6, "y": 44.4}]
ENTRIES = [{"name": "west road", "x": 0.7, "y": 30.5}, {"name": "east road", "x": 63.3, "y": 30.5},
           {"name": "north road", "x": 32.5, "y": 0.8}, {"name": "south road", "x": 32.5, "y": 63.2},
           {"name": "cemetery", "x": 0.8, "y": 32.6}]
CENTER = {"x": 34.2, "y": 31.4}
PLAYER = {"x": 15.0, "y": 26.2}   # outside the west gate, flat against the wall beside it


def main():
    placed = FORT + INSIDE + OUTSIDE + PROPS + cemetery()
    objects = [{"type": k, "x": x, "y": y} for k, x, y in placed]
    solid = layout.check(N, objects, ENEMIES + SLEEPERS + CIVILIANS + ENTRIES + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")],
                         joined={k for k, *_ in FORT})
    kinds = {k for k, *_ in INSIDE + OUTSIDE}
    posts = layout.make_posts(N, STREETS, solid, ENEMIES, PLAYER, kinds, wanted=56, keep_off=9.0, seed=21)
    layout.write("cruz_verde.json", {
        "name": "Cruz Verde",
        "size": N,
        "ground": "ground_cruz_verde",
        "streets": STREETS,
        "mud": MUD,
        "boothills": [[0.5, 14.0, 15.0, 50.0]],
        "objects": objects,
        "player": PLAYER,
        "enemies": ENEMIES,
        "sleepers": SLEEPERS,
        "civilians": CIVILIANS,
        "holdouts": HOLDOUTS,
        "posts": posts,
        "entries": ENTRIES,
        "center": CENTER,
    })
    print("Cruz Verde: %d buildings, %d props, %d bandits on guard and %d indoors, %d townsfolk, %d guard posts" % (
        len(FORT + INSIDE + OUTSIDE), len(PROPS) + len(cemetery()), len(ENEMIES), len(SLEEPERS), len(CIVILIANS), len(posts)))


if __name__ == "__main__":
    main()
