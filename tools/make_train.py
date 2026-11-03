#!/usr/bin/env python3
"""Lays out Paso Esperanza and writes data/train.json: a freight the revolution has
stopped out in the scrub by tearing the rails up under her. The engine lies on her
side in the middle of the map, the cars standing behind her to the north with their
doors open; the stranger holds a breastwork of sandbags and ties in the angle
between the engine and the line south, facing south and east, where the army will
come from. The revolution's wagons wait on the west edge for the cargo.

Usage: tools/.venv/bin/python tools/make_train.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout  # noqa: E402
from world import BUILDINGS, CHUNKED  # noqa: E402

N = 64

# The line runs north-south down x = 30 (top right to bottom left on screen). The
# rails were levered up south of the engine: that's where she went over.
TRACK_X = 30.0
RAILS = [{"x": TRACK_X, "y0": 0.0, "y1": 64.0, "gaps": [[38.4, 43.6]]}]

# The train, north to south, each car 2.4 tiles across, centred on the line.
CAR_X = TRACK_X - 1.2
TRAIN = [
    ("flatcar", CAR_X, 1.0),         # the last of them: cases under a canvas
    ("boxcar_a", CAR_X, 6.1),
    ("boxcar_burnt", CAR_X, 12.7),   # the guards' car, burnt out round them
    ("boxcar_b", CAR_X, 19.3),
    ("tender", CAR_X, 25.9),         # off the rails, leaning after the engine
    ("loco_wreck", 26.4, 30.5),      # over on her side, west of the line, wheels to the east
]

# The breastwork, in the angle between the engine's east flank and the line south:
# a front facing south along y 40, a flank facing east along x 38, the machine gun's
# corner where they meet (left empty for now), open at the back (north) to the tender.
# The front runs on west past the engine's nose to a pocket on the revolution's side,
# looking up the west of the train at the cargo (for any who slip past the train
# after it); and a post by the tender looks north up the cars' east side.
DEFENCES = [
    ("ties_x", 30.6, 40.3), ("sandbags_x", 32.8, 40.3), ("ties_x", 35.0, 40.3),
    ("sandbags_y", 37.6, 38.0), ("ties_y", 37.6, 35.8), ("sandbags_y", 37.6, 33.6), ("rifle_crates", 37.6, 32.6),
    ("ammo_box", 33.2, 36.2), ("ammo_box", 34.0, 36.6), ("crate", 31.0, 33.6),
    ("rifle_crate", 32.0, 30.6),
    # the west pocket, across the torn-up line
    ("ties_x", 28.4, 40.3), ("sandbags_x", 26.2, 40.3), ("ties_x", 24.0, 40.3), ("sandbags_y", 22.8, 38.0),
    ("crate", 22.7, 36.8),
    # the post by the tender
    ("crate_stack", 32.6, 26.2), ("sandbags_x", 34.4, 26.4), ("barrel", 36.7, 26.6),
]
MG_SPOT = [36.3, 39.3]   # where the Colt-Browning will stand

# The cargo: cases piled by the west doors for the carriers, a few broken open in
# the hurry, the carretas waiting along the west edge (mules facing out).
CARGO = [
    ("rifle_crates", 26.4, 1.8), ("rifle_crate", 26.0, 3.4), ("rifle_crates", 26.2, 7.8),
    ("rifle_crate_open", 25.0, 11.9), ("rifle_crate", 26.1, 11.2), ("rifle_crates", 26.3, 21.0),
    ("rifle_crate", 25.2, 23.4), ("ammo_box", 26.8, 23.0), ("rifle_crate_open", 20.6, 16.4),
    ("rifle_crate", 14.0, 20.2),     # dropped on the way
    # and a heap of it already out, by the engine's cab, where the stranger sees it go
    ("rifle_crates", 22.0, 26.4), ("rifle_crates", 20.6, 28.2), ("rifle_crates", 22.6, 28.6),
    ("rifle_crate", 21.0, 30.2), ("rifle_crate_open", 19.4, 26.6), ("ammo_box", 23.4, 27.4),
    ("rifle_crates", 21.4, 32.0), ("ammo_box", 20.0, 31.4),
    ("carreta", 1.0, 26.6), ("carreta", 1.0, 13.0), ("carreta", 9.0, 1.0),
    # loose rifles heaped where cases broke open, and the guards' own by their car
    ("rifle_pile", 18.4, 27.6), ("rifle_pile", 26.0, 17.6), ("rifle_pile", 20.6, 41.4),
]

# What the carriers take, a load a trip (see scripts/cargo.gd): each pile (the
# object, and how many loads are in it: a case, or an armful of rifles) or a boxcar's
# west door, with the boxcar's own load behind it. More than the level asks for, so a
# pile or two lost to the fight doesn't decide it.
PILES = [
    ("case", ("rifle_crates", 22.0, 26.4), 5), ("case", ("rifle_crates", 20.6, 28.2), 5),
    ("case", ("rifle_crates", 22.6, 28.6), 5), ("case", ("rifle_crates", 21.4, 32.0), 5),
    ("case", ("rifle_crate", 21.0, 30.2), 1), ("case", ("rifle_crates", 26.4, 1.8), 5),
    ("case", ("rifle_crate", 26.0, 3.4), 1), ("case", ("rifle_crates", 26.2, 7.8), 5),
    ("case", ("rifle_crate", 26.1, 11.2), 1), ("case", ("rifle_crates", 26.3, 21.0), 5),
    ("case", ("rifle_crate", 25.2, 23.4), 1), ("case", ("rifle_crate", 14.0, 20.2), 1),
    ("rifles", ("rifle_pile", 18.4, 27.6), 6), ("rifles", ("rifle_pile", 26.0, 17.6), 5),
    ("rifles", ("rifle_pile", 20.6, 41.4), 4), ("rifles", ("rifle_crate_open", 25.0, 11.9), 3),
    ("rifles", ("rifle_crate_open", 19.4, 26.6), 3),
]
DOORS = [("case", (28.4, 9.1), 8), ("case", (28.4, 22.3), 8)]   # the two boxcars
# The wagons, in the order they load: the far one first, the last (by the wagon
# trail) waiting for the stranger.
WAGONS = [{"x": 9.0, "y": 1.0}, {"x": 1.0, "y": 13.0}, {"x": 1.0, "y": 26.6}]
# The carriers, three on cases and two on rifles, and their comandante by the heap
# at the cab.
CARRIERS = [
    {"kind": "cargador", "x": 20.0, "y": 24.8, "look": (22, 26)},
    {"kind": "cargador", "x": 17.8, "y": 30.6, "look": (21, 30)},
    {"kind": "cargador", "x": 23.8, "y": 20.4, "look": (28, 22)},
    {"kind": "cargador_armas", "x": 19.2, "y": 25.0, "look": (19, 28)},
    {"kind": "cargadora", "x": 17.2, "y": 28.4, "look": (18, 28)},
    {"kind": "comandante", "x": 23.4, "y": 25.2, "look": (21, 28)},
]
for c in CARRIERS:
    lx, ly = c.pop("look")
    c["facing"] = layout.screen_deg(lx - c["x"], ly - c["y"])


def piles():
    """The cargo's sources, each with the spot a carrier stands to lift from it (on
    the pile's west side, towards the wagons)."""
    out = []
    for kind, (obj, x, y), n in PILES:
        w, h = BUILDINGS[obj][1]
        out.append({"kind": kind, "x": round(x - 0.45, 2), "y": round(y + h / 2, 2), "count": n, "object": [obj, x, y]})
    for kind, (x, y), n in DOORS:
        out.append({"kind": kind, "x": x, "y": y, "count": n})
    return out

# What the ambush left: the rails they tore up, the wire they cut, the coal off the
# tender, a wheelset, crates shot through and the guards where they fell.
WRECKAGE = [
    ("rail_bent", 31.2, 41.3), ("rail_bent", 27.2, 44.2), ("tie", 25.6, 46.0), ("tie", 32.2, 44.6),
    ("tie", 23.8, 43.0), ("tie", 33.6, 42.6), ("coal", 31.6, 27.2), ("wheelset", 34.8, 22.8),
    ("crate", 32.6, 14.0), ("crate", 33.2, 15.0), ("barrel", 33.8, 13.6),
    ("telegraph_down", 23.9, 33.0),
    # where the guards fought it out along the cars: their wagon over on its side, a
    # mess table or two thrown down for a barricade, stores and barrels about
    ("wagon_over", 34.6, 19.8), ("upturned_s", 35.2, 7.0), ("upturned_e", 34.4, 10.2), ("sacks", 33.4, 4.0),
    ("sacks", 36.2, 23.6), ("barrel", 36.4, 12.4), ("crate", 36.8, 15.6), ("crate_stack", 35.4, 2.6),
    # thrown off the front of the train when she went over, and the section gang's handcar
    ("crate", 26.0, 42.4), ("crate", 29.0, 46.8), ("rifle_crate", 22.8, 44.8), ("barrel", 31.8, 46.6),
    ("sacks", 34.6, 44.0), ("handcar", 32.6, 48.6), ("crate_stack", 35.8, 47.0),
]
# The telegraph along the west side of the line, a pole every seven tiles, cut on
# either side of the one they felled.
POLE_X = 24.8
POLES = [("telegraph", POLE_X, y) for y in (3.0, 10.0, 17.0, 24.0)] \
    + [("telegraph_cut_s", POLE_X, 31.0), ("telegraph_cut_n", POLE_X, 45.0)] \
    + [("telegraph", POLE_X, y) for y in (52.0, 59.0)]

# The scrub the army will come through: rocks, cactus and agave to the east and
# south, thinner the nearer the train (the guards cleared it, or never needed to).
SCRUB = [
    ("rock", 46.0, 22.0), ("rock_b", 47.2, 23.4), ("rock", 52.0, 34.0), ("rock_b", 44.4, 30.6),
    ("rock", 42.6, 47.0), ("rock_b", 50.0, 44.0), ("rock", 36.0, 53.0), ("rock_b", 26.0, 55.0),
    ("rock", 56.4, 50.4), ("rock", 58.0, 26.0), ("rock_b", 48.0, 12.0), ("rock", 44.0, 59.0),
    ("rock", 17.0, 48.0), ("rock_b", 54.0, 8.0), ("rock_c", 52.0, 20.0), ("rock_c", 47.0, 28.0),
    ("rock_c", 20.0, 50.0), ("rock_c", 40.4, 24.6), ("rock_b", 38.6, 29.0),
    ("cactus", 50.0, 27.0), ("cactus", 61.6, 33.6), ("cactus", 40.0, 57.0), ("cactus", 31.0, 59.0),
    ("cactus", 56.0, 16.0), ("cactus", 12.0, 40.0), ("cactus", 6.0, 52.0), ("cactus", 18.0, 6.0),
    ("agave", 44.4, 41.6), ("agave", 47.0, 51.0), ("agave", 55.0, 42.0), ("agave", 39.0, 45.0),
    ("agave", 60.0, 20.0), ("agave", 52.0, 58.0), ("agave", 34.0, 49.0), ("agave", 41.0, 18.0),
    ("agave", 20.0, 36.0), ("agave", 10.0, 30.0), ("agave", 15.0, 10.0), ("agave", 6.0, 40.0),
]
# The road in from the east, straight at the breastwork's flank, and the revolution's
# ambush positions along it (sandbags where they lay waiting for the train), rocks,
# and what the fight scattered: the army will come down it from cover to cover.
EAST_ROAD = [
    ("sandbags_y", 41.2, 32.6), ("rock_c", 43.0, 39.2), ("crate", 45.0, 34.0), ("sandbags_x", 47.0, 39.0),
    ("rock", 49.0, 33.2), ("rifle_crates", 51.0, 39.6), ("sandbags_y", 54.4, 33.0), ("rock_c", 56.0, 39.4),
    ("wagon_over", 58.0, 32.4), ("crate_stack", 60.6, 40.6), ("sacks", 45.4, 40.8),
]
# And from the south: more of the same, up to the front.
SOUTH = [
    ("sandbags_x", 37.6, 45.0), ("rock_c", 40.6, 50.0), ("sandbags_x", 33.0, 53.2), ("crate_stack", 38.4, 58.4),
    ("rock_b", 35.0, 60.4), ("wagon_over", 42.0, 55.0), ("sandbags_y", 45.0, 44.6),
]

# Shot up in the fight for the train: 1 holed, 2 wrecked.
WORN = {(32.6, 14.0): 2, (33.2, 15.0): 1, (33.8, 13.6): 1, (25.2, 23.4): 1, (36.8, 15.6): 1, (26.0, 42.4): 1,
        (29.0, 46.8): 2, (31.8, 46.6): 1, (45.0, 34.0): 1, (34.4, 10.2): 1}

# The train's guards and crew, where the ambush left them (stripped of their guns:
# the revolution had those first). Bodies only: nobody hauls or buries them.
DEAD = [
    {"template": "shirt", "x": 25.6, "y": 29.4, "facing": 200, "death": "death_back",   # the engineer, thrown from the cab
     "palette": {"shirt": [92, 104, 132], "trousers": [70, 80, 110], "hat": [60, 66, 84], "band": [40, 40, 44], "boots": [50, 38, 30], "skin": [196, 150, 112], "hair": [90, 70, 50]}},
    {"template": "shirt", "x": 22.4, "y": 34.6, "facing": 120, "death": "death_slump",  # his fireman
     "palette": {"shirt": [150, 140, 120], "trousers": [70, 80, 110], "hat": [90, 84, 70], "band": [40, 40, 44], "boots": [50, 38, 30], "skin": [176, 126, 92], "hair": [40, 30, 24]}},
    {"template": "duster_bowler", "x": 32.0, "y": 17.8, "facing": 0, "death": "death_knees",  # the guards, out of the burning car
     "palette": {"coat": [96, 84, 66], "shirt": [190, 180, 160], "trousers": [64, 60, 58], "hat": [44, 40, 38], "boots": [40, 32, 26], "skin": [200, 150, 110], "hair": [70, 50, 34]}},
    {"template": "duster_bowler", "x": 37.7, "y": 21.4, "facing": 330, "death": "death_back",
     "palette": {"coat": [70, 66, 60], "shirt": [170, 160, 140], "trousers": [90, 76, 60], "hat": [60, 50, 40], "boots": [40, 32, 26], "skin": [190, 140, 100], "hair": [120, 90, 60]}},
    {"template": "vest", "x": 31.8, "y": 11.4, "facing": 30, "death": "death_spin",
     "palette": {"vest": [60, 56, 50], "shirt": [200, 196, 180], "trousers": [70, 74, 96], "hat": [100, 84, 60], "band": [40, 34, 30], "boots": [50, 36, 28], "skin": [186, 130, 92], "hair": [40, 30, 24]}},
    {"template": "vest", "x": 27.0, "y": 15.8, "facing": 160, "death": "death_slump",
     "palette": {"vest": [110, 60, 44], "shirt": [180, 170, 150], "trousers": [86, 70, 56], "hat": [70, 60, 50], "band": [150, 120, 70], "boots": [50, 36, 28], "skin": [206, 156, 120], "hair": [150, 110, 60]}},
]

# Sticks of dynamite from the cargo, inside the breastwork: one at a time on him.
PICKUPS = [{"kind": "dynamite", "x": 33.6, "y": 34.6}, {"kind": "dynamite", "x": 35.8, "y": 32.4},
           {"kind": "dynamite", "x": 24.2, "y": 38.6}]
# Smoke still going up from the burnt car, and steam from the engine's boiler.
SMOKE = [{"x": 31.4, "y": 14.6, "dark": True}, {"x": 31.4, "y": 17.2, "dark": True},
         {"x": 30.2, "y": 33.6, "dark": False}]

# The wagon trail the revolution came in on, from the west edge up to the cars.
STREETS = [[0.0, 19.5, 24.0, 22.5], [39.0, 35.4, 64.0, 38.4]]
ENTRIES = [{"name": "east road", "x": 63.3, "y": 36.9}, {"name": "north-east", "x": 63.3, "y": 22.0}, {"name": "south-east", "x": 63.3, "y": 46.0},
           {"name": "south", "x": 44.0, "y": 63.3}, {"name": "line south", "x": 31.5, "y": 63.3}]
CENTER = {"x": 34.0, "y": 35.0}
PLAYER = {"x": 34.6, "y": 35.6}   # in the breastwork, behind the gun's corner


def place(kind, x, y):
    """One object, or a chunked one's pieces one after another along its axis."""
    if kind not in CHUNKED:
        return [(kind, x, y)]
    axis, n = CHUNKED[kind]
    step = BUILDINGS[kind][1][axis] / n
    return [(f"{kind}_{i}", x + (i * step if axis == 0 else 0), y + (i * step if axis == 1 else 0)) for i in range(n)]


def main():
    placed = []
    for k, x, y in TRAIN + DEFENCES + CARGO + WRECKAGE + POLES + SCRUB + EAST_ROAD + SOUTH:
        placed += place(k, x, y)
    objects = [{"type": k, "x": round(x, 4), "y": round(y, 4)} for k, x, y in placed]
    for o in objects:
        if (o["x"], o["y"]) in WORN:
            o["worn"] = WORN[(o["x"], o["y"])]
    assert sum("worn" in o for o in objects) == len(WORN), "a worn spot with nothing at it"
    joined = {k for k, *_ in placed if k.rsplit("_", 1)[0] in CHUNKED}
    layout.check(N, objects, DEAD + PICKUPS + ENTRIES + CARRIERS + piles()
                 + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")],
                 joined=joined)
    layout.write("train.json", {
        "name": "Paso Esperanza",
        "size": N,
        "ground": "ground_train",
        "streets": STREETS,
        "rails": RAILS,
        "mud": [],
        "objects": objects,
        "player": PLAYER,
        "enemies": [],
        "civilians": CARRIERS,
        "cargo": {"sources": piles(), "wagons": WAGONS},
        "dead": DEAD,
        "pickups": PICKUPS,
        "smoke": SMOKE,
        "mg": MG_SPOT,
        "holdouts": [],
        "entries": ENTRIES,
        "center": CENTER,
        "posse": False,
    })
    print("Paso Esperanza: %d objects, %d dead, %d sticks of dynamite" % (len(objects), len(DEAD), len(PICKUPS)))


if __name__ == "__main__":
    main()
