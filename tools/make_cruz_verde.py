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
    # the plaza made ready: tables out of the cantina thrown over round the well, each
    # top turned to the gate it's watching, for when they come pushing in from the gates
    ("upturned_w", 27.4, 29.0), ("upturned_w", 28.2, 32.4), ("upturned_e", 39.8, 29.2), ("upturned_e", 40.6, 32.4),
    ("upturned_n", 30.8, 24.8), ("upturned_s", 35.0, 35.8), ("upturned_n", 36.4, 25.6),
    # sandbags and barrels against the chapel, in the north corner
    ("sandbags_y", 24.8, 17.6), ("sandbags_x", 25.6, 22.6), ("barrel", 24.9, 20.2), ("barrel", 25.7, 20.55),
    ("barrel", 25.0, 20.9),
    # the fort's stores, stacked wherever there was room: crates, sacks and barrels
    ("crate_stack", 27.0, 15.8), ("crate", 28.8, 15.6), ("crate_stack", 26.6, 18.6), ("barrel", 28.4, 18.8),
    ("crate_stack", 35.1, 20.4), ("crate", 35.6, 22.0), ("barrel", 36.0, 18.0),
    ("crate_stack", 25.5, 37.6), ("crate", 27.4, 37.6),
    ("crate_stack", 34.2, 40.8), ("crate", 33.6, 42.2), ("barrel", 35.2, 42.4),
    ("crate", 44.0, 32.2), ("crate_stack", 42.0, 35.6), ("barrel", 37.4, 35.2), ("barrel", 38.1, 35.3),
    ("crate", 22.4, 27.0), ("crate", 23.4, 27.2),
    ("coop", 55.5, 26.0), ("coop", 27.6, 55.0), ("hencrate", 51.4, 33.4),
    ("wagon", 55.0, 31.6), ("trough", 51.0, 28.6),
    ("cactus", 60, 6), ("cactus", 58, 14), ("cactus", 61, 47), ("cactus", 50, 61), ("cactus", 14, 60),
    ("cactus", 8, 60), ("cactus", 37, 60), ("cactus", 61, 58),
    ("agave", 51, 8), ("agave", 55, 12), ("agave", 60, 34), ("agave", 49, 44), ("agave", 35, 49.5),
    ("agave", 28, 49.5), ("agave", 18, 49), ("agave", 42, 10), ("agave", 26, 9), ("agave", 13, 6),
]

# Powder kegs by the gates and the breach, each beside a plain barrel so it isn't
# too plain which is which: put a round in one as a band comes through. And three
# crates of dynamite in among the stores, which burn a while before they go.
KEG_SPOTS = [("keg", 18.75, 27.25), ("barrel", 19.4, 27.3),        # the west gate
             ("barrel", 28.6, 17.0), ("keg", 29.35, 17.15),        # the north gate
             ("keg", 45.95, 32.75), ("barrel", 46.6, 32.5),        # the east gate
             ("barrel", 29.5, 44.8), ("keg", 28.85, 44.65),        # the south gate
             ("keg", 46.05, 37.65),                                # the east breach
             ("dyn_crate", 28.2, 19.6), ("dyn_crate", 35.2, 19.4), ("dyn_crate", 34.5, 39.6)]
PROPS += KEG_SPOTS
# Last night the leaders drank to the revolution: broken bottles about the fort,
# thickest round the cantina, the general's house and the plaza tables. Two sweepers
# are at them from the start.
LITTER = [(35.6, 37.0), (36.8, 36.6), (39.6, 36.8), (41.0, 37.4), (38.2, 42.6), (40.4, 44.6),
          (36.2, 24.4), (38.8, 24.8), (41.6, 25.0), (31.6, 29.6), (33.4, 33.4), (37.6, 31.0),
          (25.4, 33.6), (44.2, 29.0), (30.0, 22.6), (23.6, 40.6)]

# Shot up in the last battle for the fort, and not all mended yet: 1 holed, 2 wrecked.
# The carpenter's working through them when the stranger arrives.
WORN = {(27.4, 29.0): 1, (40.6, 32.4): 2, (36.4, 25.6): 1, (29.5, 39.2): 1, (30.4, 40.2): 2, (29.6, 40.6): 1,
        (25.5, 37.6): 1, (33.6, 42.2): 1, (44.0, 32.2): 2, (22.4, 27.0): 1, (35.0, 35.8): 1}

# The cemetery: rings of crosses, mounds and headstones round a circle of stones,
# and rows of graves below the west road.
CIRCLE = (4.5, 19.0)   # the stone circle's corner (it's 6 tiles across)
OPEN_GRAVES = (1.2, 4.8, 8.4)   # the open graves' corners along y 31.8 (2.2 x 2 tiles)
WEST_GATE = [16.5, 30.5]   # gunfire here, or by the graves, scatters the folk in the cemetery


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
    # a fresh row being dug along the road's edge, a coffin waiting by each
    for x in OPEN_GRAVES:
        out.append(("open_grave", x, 31.8))
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

# The garrison's not as watchful as it ought to be: there was a party last night,
# after their last victory. Five on the grounds, all revolucionarios...
ENEMIES = [
    {"kind": "tirador", "x": 32.5, "y": 16.0, "look": (32.5, 8)},
    {"kind": "revolucionario", "x": 24.0, "y": 31.2, "patrol": [[24.0, 31.2], [30.0, 31.6], [41.0, 31.2]]},
    {"kind": "revolucionario", "x": 44.6, "y": 34.6, "look": (49, 35)},
    {"kind": "revolucionario", "x": 33.8, "y": 18.0, "patrol": [[33.8, 18.0], [33.8, 37.0]]},
    {"kind": "revolucionario", "x": 28.2, "y": 36.8, "look": (32, 32)},
]
# ...and ten indoors, sleeping it off with the saloon girls: once the shooting
# starts they come out of these doors, a couple who were ready at once, the rest by
# tens of seconds ("after"), spread out, El General last of all. While he lives, the garrison
# has its orders.
SLEEPERS = [
    {"kind": "revolucionario", "x": 24.0, "y": 43.6, "after": 2},     # the barracks
    {"kind": "saloon_girl", "x": 43.6, "y": 40.5, "after": 2},        # the cantina
    {"kind": "saloon_girl", "x": 43.6, "y": 40.5, "after": 12},
    {"kind": "revolucionario", "x": 21.0, "y": 43.6, "after": 12},
    {"kind": "soldadera", "x": 27.0, "y": 43.6, "after": 12},
    {"kind": "saloon_girl", "x": 43.6, "y": 40.5, "after": 20},
    {"kind": "revolucionario", "x": 24.0, "y": 43.6, "after": 20},
    {"kind": "drunkard", "x": 43.6, "y": 40.5, "after": 20},
    {"kind": "saloon_girl", "x": 43.6, "y": 40.5, "after": 30},
    {"kind": "general", "x": 41.0, "y": 23.6, "after": 30},           # his house
]
# The bands coming down the roads: mostly revolucionarios, many of them women.
WAVE_KINDS = {"revolucionario": 5, "soldadera": 3, "tirador": 2, "sargento": 1}
for e in ENEMIES:   # (written as where each looks; placements take a screen angle)
    if "look" in e:
        lx, ly = e.pop("look")
        e["facing"] = layout.screen_deg(lx - e["x"], ly - e["y"])

CIVILIANS = [
    {"kind": "saloon_girl", "x": 38.2, "y": 43.8, "facing": 120},
    {"kind": "saloon_girl", "x": 42.3, "y": 44.0, "facing": 60},
    {"kind": "saloon_girl", "x": 37.6, "y": 36.8, "facing": 200},
    {"kind": "priest", "x": 21.5, "y": 23.7, "facing": 90, "brave": True},   # he goes to the dead under fire
    {"kind": "sister", "x": 21.5, "y": 23.5, "facing": 90},   # indoors, in the chapel
    # the fort's carpenter, mending what the last battle broke: only shooting close by
    # stops him, and he's straight back to it
    {"kind": "carpenter", "x": 32.0, "y": 36.8, "facing": 300, "local": True, "palette": 1},
    # and two with brooms, sweeping up after last night
    {"kind": "sweeper", "x": 34.2, "y": 36.4, "facing": 30, "local": True, "palette": 0},
    {"kind": "sweeper", "x": 38.0, "y": 27.6, "facing": 200, "local": True, "palette": 1},
    # out in the cemetery: the grave digger at his new row, and the families of the
    # revolution's dead going from grave to grave round the stone circle
    {"kind": "digger", "x": 11.2, "y": 33.0, "facing": 180, "ward": WEST_GATE},
    {"kind": "visitor", "x": 12.4, "y": 24.4, "facing": 200, "ward": WEST_GATE, "palette": 0},
    {"kind": "visitor", "x": 11.4, "y": 27.0, "facing": 230, "ward": WEST_GATE, "palette": 1},
    {"kind": "visitor", "x": 2.6, "y": 18.4, "facing": 60, "ward": WEST_GATE, "palette": 0},
    {"kind": "widower", "x": 9.8, "y": 27.8, "facing": 250, "ward": WEST_GATE},
    {"kind": "peon", "x": 28.6, "y": 29.8, "facing": 0},
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
    for o in objects:
        if (o["x"], o["y"]) in WORN:
            o["worn"] = WORN[(o["x"], o["y"])]
    assert sum("worn" in o for o in objects) == len(WORN), "a worn spot with nothing at it"
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
        "litter": [list(p) for p in LITTER],
        "objects": objects,
        "player": PLAYER,
        "enemies": ENEMIES,
        "sleepers": SLEEPERS,
        "civilians": CIVILIANS,
        "holdouts": HOLDOUTS,
        "posts": posts,
        "entries": ENTRIES,
        "center": CENTER,
        "wave_kinds": WAVE_KINDS,
        "posse": False,   # (a fort, not a town to get lost in: the last of them just hold it)
    })
    print("Cruz Verde: %d buildings, %d props, %d bandits on guard and %d indoors, %d townsfolk, %d guard posts" % (
        len(FORT + INSIDE + OUTSIDE), len(PROPS) + len(cemetery()), len(ENEMIES), len(SLEEPERS), len(CIVILIANS), len(posts)))


if __name__ == "__main__":
    main()
