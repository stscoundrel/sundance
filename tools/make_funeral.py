#!/usr/bin/env python3
"""Lays out the burial ground and writes data/funeral.json: the stranger's own
funeral, out in a wide valley under a grey sky. A great round cemetery fills the
valley floor, ring after ring of crosses round a circle of paving stones, his open
grave at its heart (Sad Hill); the mud's deep after the rain (Django). The crosses
hide nobody, so the fighting's in what stands round them: a few stone crypts and
dead trees among the graves, and out past the last ring the ruined mission to the
north, the undertaker's yard to the west, the way-station cantina and its horses to
the east, and the guests' wagons drawn up along the valley road to the south, rocks
all up the valley sides. The wake's dinner is laid out ready in the two northern
corners, long tables for the guests to come back to; and east past the cantina the
town begins, a few houses and a livery along the street out of the valley.

Fifteen of the men he crossed came to see him buried, from every town he rode
through, four factions: seven round the grave, the rest well apart about the valley.
Each faction has more men waiting past the edge of the map down its own road, and
sends a runner for them once one of its own falls (see CAMPS).

Usage: tools/.venv/bin/python tools/make_funeral.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout  # noqa: E402
import numpy as np  # noqa: E402
from world import BUILDINGS, CHUNKED  # noqa: E402

N = 100
# Everything below is laid out in the valley's own frame, then moved OX tiles east and
# OY south onto the map (the map grew round it twice: first room north for the dinners
# and east for the town; then the whole of the mission to the north, more of the town
# east, the graves on past the road to the south, the carpenter's and the mason's to
# the west). The frame runs from -OX to N - OX, and -OY to N - OY.
OX = 12.0
OY = 18.0
C = (32.0, 30.0)   # the heart of the cemetery: the circle of stones, his grave in it (valley frame)

STREETS = [
    [-OX, 50, N - OX, 53],   # the valley road, along the south, out west and on out east
    [30.5, 36.5, 33.5, 50],  # up from the road to the graves, through their gate
    [30.5, 53, 33.5, N - OY],  # on south past the road, through the older graves
    [30.5, -OY, 33.5, 23.5],  # the mission track, down through the mission past the chapel to the graves
    [65.5, -OY, 68.5, 50],   # the town's street, north off the road
    [76.5, -OY, 79.5, 50],   # the town's main street, beyond it
    [68.5, 11.5, 76.5, 13.5],  # across between the two
    [14, 28.5, 23.5, 31.5],  # in from the undertaker's yard
    [40.5, 28.5, 52, 31.5],  # in from the cantina
]

# The mud, deep after the rain: down the tracks, across the paths through the
# graves, and wherever the wagons and horses have stood.
MUD = [[32.0, 51.5, 2.2], [20.0, 51.6, 1.8], [45.0, 51.4, 2.0], [8.0, 51.8, 1.5], [57.0, 51.6, 1.6],
       [32.0, 44.0, 1.6], [32.0, 17.0, 1.4], [18.5, 30.0, 1.3], [46.0, 30.0, 1.5], [54.0, 34.0, 2.2],
       [50.4, 36.4, 1.4], [25.0, 47.0, 1.3], [38.6, 46.8, 1.4], [32.0, 8.6, 1.4], [10.4, 33.4, 1.4],
       [24.6, 36.6, 0.9], [40.0, 23.0, 0.9], [27.0, 21.4, 0.8], [37.6, 37.4, 0.8],
       [67.0, 51.6, 1.8], [67.0, 40.0, 1.4], [67.0, 26.0, 1.2], [32.0, -3.0, 1.2], [13.0, -1.5, 0.9], [53.5, -1.5, 0.9],
       [78.0, 51.6, 1.6], [78.0, 30.0, 1.4], [78.0, 4.0, 1.2], [32.0, -12.0, 1.3], [-6.0, 51.6, 1.7], [32.0, 62.0, 1.4],
       [32.0, 74.0, 1.2], [-4.0, 31.0, 1.0], [72.0, 12.5, 0.9]]

CIRCLE = (C[0] - 3, C[1] - 3)            # the stone circle's corner (6 tiles across)
GRAVE = (C[0] - 1.1, C[1] - 1.0)         # his open grave, waiting empty
COFFIN = (GRAVE[0] + 0.3, GRAVE[1] + 2.05)   # his coffin before it, with him in it (Coffin; its corner)
GRAVE_KINDS = ("cross", "headstone", "headstone_b", "mound")   # (game.GRAVES)
CRYPTS = [("crypt", 23.4, 20.6), ("crypt_b", 39.0, 21.0), ("crypt", 37.8, 37.0), ("crypt_b", 23.0, 37.4),
          ("crypt_b", 43.2, 31.6)]
OBELISKS = [(27.2, 25.0), (36.2, 25.4), (27.4, 34.6), (19.2, 26.6), (44.4, 26.4)]
TREES_IN = [("dead_tree", 41.6, 34.2), ("dead_tree_b", 21.0, 33.2), ("dead_tree", 33.6, 19.8)]


def cemetery():
    """The rings of graves, crosses mostly, a headstone or a fresh mound here and
    there, with the paths through them left clear; then the crypts, obelisks and
    dead trees among them."""
    big = [layout.footprint(k, x, y) for k, x, y in CRYPTS] \
        + [layout.footprint("obelisk", x, y) for x, y in OBELISKS] \
        + [layout.footprint(k, x, y) for k, x, y in TREES_IN]
    out = [("stone_circle", *CIRCLE), ("open_grave_empty", *GRAVE)]
    k = 0
    for r in (4.8, 6.1, 7.4, 8.7, 10.0, 11.3, 12.6, 13.9):
        n = int(2 * math.pi * r / 1.4)
        for i in range(n):
            a = i / n * 2 * math.pi + r * 0.7
            x, y = C[0] + r * math.cos(a), C[1] + r * math.sin(a)
            if abs(x - C[0]) < 1.6 or abs(y - C[1]) < 1.6:
                continue   # (the paths in, north, south, east and west)
            kind = ("cross", "cross", "headstone", "cross", "mound", "cross", "headstone_b", "cross")[k % 8]
            k += 1
            fp = layout.footprint(kind, x, y)
            if any(layout.overlaps(fp, b, 0.3) for b in big):
                continue
            out.append((kind, round(x, 2), round(y, 2)))
    out += CRYPTS + [("obelisk", x, y) for x, y in OBELISKS] + TREES_IN
    return out + old_graves(out)


# North of the rings the older graves go on in rows, out round the mission and up
# to the dinner tables; a crypt or two and an obelisk among them, the rocks left
# where they lay.
NORTH_MARKERS = [("crypt_b", 8.4, 8.6), ("crypt_b", 55.6, 8.4), ("obelisk", 17.2, 7.2), ("obelisk", 46.6, 9.4),
                 ("obelisk", 4.6, 3.0), ("crypt_b", 59.6, 15.4)]


def old_graves(rings):
    taken = [layout.footprint(k, x, y) for k, x, y in BUILDINGS_AT + PROPS + DINNERS + rings + NORTH_MARKERS]
    taken += [(x0, y0, x1, y1) for x0, y0, x1, y1 in STREETS]
    out = list(NORTH_MARKERS)
    k = 0
    for row, y in enumerate(np.arange(2.0, 19.0, 1.6)):
        for x in np.arange(3.0 + (row % 2) * 0.75, 63.0, 1.5):
            if math.hypot(x - C[0], y - C[1]) < 15.0:
                continue   # (the rings' own ground)
            kind = ("cross", "cross", "headstone", "cross", "mound", "cross", "headstone_b", "cross")[(k + row) % 8]
            k += 1
            fp = layout.footprint(kind, x, y)
            if any(layout.overlaps(fp, t, 0.5) for t in taken):
                continue
            out.append((kind, round(float(x), 2), round(float(y), 2)))
    return out


BUILDINGS_AT = [
    # the mission to the north, half fallen in: its chapel still stands
    ("chapel", 29.5, 2.2),
    ("wall_x4", 22.0, 9.0), ("wall_x4", 38.0, 9.0), ("wall_y4", 21.0, 3.0), ("wall_y4", 42.0, 4.0),
    # the undertaker's yard to the west, and the digger's hut
    ("undertaker", 6.0, 26.0), ("jacal", 6.5, 35.5),
    # the way-station to the east: the cantina, a shed for the stage
    ("cantina", 52.0, 22.0), ("jacal_b", 59.0, 24.0),
    # and past it the town begins: a few houses and the livery along its street
    ("adobe_a", 69.0, 15.0), ("store", 69.0, 21.0), ("adobe_b", 69.0, 28.0), ("stable", 69.0, 34.0),
    ("adobe_a", 69.0, 41.0), ("water_tower", 62.6, 15.0),
]


def dinner(x0, y0, tables=3):
    """The wake's dinner, laid out ready for when he's in the ground: two rows of long
    tables, a bench down each side."""
    out = []
    for y in (y0, y0 + 3.6):
        for i in range(tables):
            x = x0 + i * 4.4
            out += [("feast_x", x, y), ("bench_x", x, y - 0.6), ("bench_x", x, y + 1.15)]
    return out


# One in each northern corner, the cook fire and the drink at one end.
DINNERS = dinner(6.0, -4.8) + [("cookfire", 19.8, -4.6), ("barrel", 20.0, -2.2), ("barrel", 20.7, -2.0),
                                ("crate", 19.9, -1.2), ("table", 4.4, -4.6), ("chair", 3.8, -4.0)] \
    + dinner(46.0, -4.8) + [("cookfire", 59.8, -4.6), ("barrel", 60.0, -2.2), ("crate", 60.8, -2.0),
                             ("table", 44.0, -4.4)]

PROPS = [
    # the mission's broken walls
    ("rubble", 26.2, 9.2), ("rubble", 36.2, 9.1), ("rubble", 21.2, 7.4), ("rubble", 42.2, 8.4),
    ("well", 25.6, 4.6),
    # the undertaker's yard: coffins stood ready, the wood for more, a fresh row dug
    ("coffin", 11.0, 26.4), ("coffin", 11.0, 27.3), ("coffin", 10.6, 31.8), ("woodpile", 10.8, 24.0),
    ("crate", 5.0, 32.2), ("open_grave", 12.2, 38.6), ("open_grave", 15.0, 38.6), ("open_grave", 17.8, 38.6),
    ("wagon", 12.6, 33.8),   # (his hearse)
    # the cantina: the porch, the horses tied out front, troughs, the stage's things
    ("table", 53.2, 27.6), ("chair", 52.7, 27.7), ("chair", 53.9, 27.8), ("table", 56.0, 27.5),
    ("chair", 56.6, 27.7), ("barrel", 51.2, 27.6), ("barrel", 58.2, 21.8), ("crate_stack", 59.2, 28.6),
    ("hitch", 52.0, 32.4), ("horse", 52.0, 32.7), ("hitch", 55.4, 32.4), ("horse", 55.6, 32.7),
    ("hitch", 52.0, 37.2), ("horse", 51.8, 37.5), ("trough", 58.4, 33.0), ("trough", 48.6, 34.4),
    ("wagon", 57.4, 37.0), ("sacks", 60.0, 31.6),
    # the guests' wagons and carts, drawn up along the road and up the track, and the
    # horses they rode in on: they came a long way, from every town he crossed
    ("wagon", 22.0, 47.4), ("wagon", 18.6, 46.0), ("wagon", 36.0, 46.0), ("wagon_over", 41.6, 47.0), ("wagon", 26.8, 44.2),
    ("horse", 17.0, 48.0), ("horse", 44.0, 54.0), ("barrel", 28.6, 46.6), ("crate", 35.2, 47.6),
    ("covered_wagon", 4.0, 47.6), ("horse_grey", 7.2, 47.8), ("horse_black", 10.4, 48.0), ("carreta", 46.0, 47.4),
    ("horse_black", 52.0, 48.2), ("covered_wagon", 55.4, 47.4), ("horse_sorrel", 13.6, 48.2),
    ("wagon", 6.0, 53.8), ("horse_sorrel", 9.5, 54.0), ("covered_wagon", 13.0, 53.8), ("horse", 16.5, 54.0),
    ("wagon", 22.0, 53.8), ("horse_grey", 25.4, 54.0), ("covered_wagon", 35.5, 53.8), ("horse_black", 39.0, 54.0),
    ("wagon", 48.0, 53.8), ("horse_sorrel", 51.6, 54.0), ("covered_wagon", 56.0, 53.8), ("horse_grey", 59.6, 54.0),
    ("horse", 63.4, 53.6), ("horse_sorrel", 58.8, 48.4), ("horse_grey", 1.0, 54.0), ("horse_black", 19.0, 54.2),
    # the valley sides: rocks all the way up, and the scrub between them
    ("rock_c", 3.0, 4.0), ("rock", 8.0, 2.0), ("rock_b", 13.0, 5.0), ("rock_c", 15.6, 12.0), ("rock", 4.0, 14.0),
    ("rock_b", 9.6, 18.4), ("rock_c", 47.0, 4.0), ("rock", 52.0, 8.0), ("rock_c", 58.0, 3.0), ("rock_b", 61.0, 11.0),
    ("rock", 48.0, 14.0), ("rock_c", 56.0, 15.0), ("rock_b", 2.0, 22.0), ("rock_c", 1.4, 42.0), ("rock", 4.0, 46.0),
    ("rock_c", 60.4, 43.0), ("rock", 62.0, 47.6), ("rock_b", 46.6, 42.4), ("rock", 17.6, 43.4),
    ("rock_c", 6.0, 57.0), ("rock", 12.0, 59.6), ("rock_b", 18.4, 56.6), ("rock_c", 26.0, 59.0), ("rock", 38.0, 57.6),
    ("rock_c", 45.0, 60.0), ("rock_b", 52.0, 56.4), ("rock_c", 58.0, 59.0), ("rock", 62.0, 55.0),
    ("dead_tree", 14.0, 16.0), ("dead_tree_b", 50.0, 17.6), ("dead_tree", 8.0, 44.0), ("dead_tree_b", 57.6, 45.6),
    ("dead_tree", 30.0, 57.0), ("dead_tree_b", 2.0, 30.0),
    ("cactus", 18.0, 4.0), ("cactus", 44.6, 12.6), ("agave", 11.0, 10.0), ("agave", 60.0, 18.0), ("agave", 40.0, 55.0),
    ("agave", 22.0, 55.6), ("cactus", 3.0, 52.0), ("agave", 63.0, 36.0),
    # the town's edge: its street, a wagon left in it, the yards behind
    ("wagon", 65.8, 31.6), ("trough", 66.0, 38.6), ("hitch", 66.0, 24.0), ("barrel", 74.4, 33.2), ("crate", 74.6, 27.8),
    ("crate_stack", 73.6, 40.0), ("woodpile", 63.0, 20.6), ("barrel", 64.2, 42.6), ("well", 63.2, 37.0),
    ("washline", 70.0, 47.2), ("coop", 74.4, 46.6),
    # the far slopes, north and south, and east beyond the town
    ("rock_c", 3.0, -4.0), ("rock", 26.0, -4.0), ("rock_b", 40.0, -4.4), ("rock_c", 63.0, -3.0), ("rock", 71.0, 4.0),
    ("rock_b", 74.0, 9.0), ("rock_c", 72.0, 57.0), ("rock", 67.0, 62.0), ("rock_b", 8.0, 64.0), ("rock_c", 16.0, 66.0),
    ("rock", 34.0, 65.0), ("rock_c", 50.0, 64.0), ("rock_b", 60.0, 66.0), ("dead_tree", 22.0, 63.0),
    ("dead_tree_b", 46.0, 66.0), ("agave", 28.0, 67.0), ("cactus", 62.0, 61.0),
]

# The guests: twenty, from every town he rode through, all of one mind today. Facing,
# as the screen goes: west 206, east 26, north 334, south 154.
# Round the valley, the second time the map grew:
BEYOND = [
    # north: the whole of the mission, walled about, its house and the brothers'
    # dormitory, a well in the cloister, the workers' huts outside the wall
    ("casa_grande", 19.0, -16.5), ("barracks", 36.0, -15.5), ("well", 28.6, -12.6),
    ("wall_y8", 17.0, -16.0), ("wall_y8", 47.0, -16.0),
    ("wall_x8", 18.0, -8.0), ("wall_x4", 26.0, -8.0), ("wall_x8", 34.0, -8.0), ("wall_x4", 42.0, -8.0),
    ("rubble", 26.6, -9.4), ("rubble", 34.4, -9.4), ("olla", 28.2, -10.6), ("agave", 23.0, -9.4), ("agave", 44.6, -10.0),
    ("jacal", 4.0, -15.0), ("jacal_b", 10.0, -15.5), ("woodpile", 4.4, -11.0), ("cactus", 14.0, -12.0),
    ("rock_c", -8.0, -14.0), ("rock", -4.0, -6.0), ("dead_tree", 52.0, -12.0), ("rock_c", 56.0, -16.0), ("rock_b", 60.0, -9.0),
    # east: the town proper, on its main street: saloon, hotel, the sheriff, the
    # gunsmith, the barber and the bank, and the backs of the yards between
    ("adobe_a", 69.0, -16.0), ("adobe_b", 69.0, -9.0), ("adobe_b", 69.0, -2.0),
    ("saloon", 80.3, -16.0), ("hotel", 80.3, -8.5), ("sheriff", 81.0, -1.0), ("gunsmith", 82.0, 6.0),
    ("barber", 81.5, 14.0), ("bank", 81.0, 21.0), ("store", 81.0, 30.0), ("cabin", 81.5, 38.0),
    ("barrel", 75.2, 17.0), ("crate", 74.6, 26.0), ("barrel", 75.4, 33.0),
    ("trough", 80.0, 44.2), ("hitch", 80.2, 4.6), ("horse_grey", 79.8, 4.9), ("barrel", 75.2, -4.0),
    ("hitch", 80.2, 12.4), ("horse_sorrel", 79.8, 12.7),
    # south: the older graves on past the road (south_graves), the mortuary chapel
    # among them, crypts and needles and dead trees
    ("chapel", 40.0, 62.5), ("crypt", 18.0, 66.0), ("crypt_b", 58.0, 70.0), ("crypt", 70.0, 62.0),
    ("crypt_b", 6.0, 72.0), ("obelisk", 26.0, 71.0), ("obelisk", 38.0, 76.0), ("obelisk", 62.0, 77.0),
    ("obelisk", 12.0, 62.0), ("dead_tree_b", 52.0, 74.0), ("dead_tree", 78.0, 70.0), ("dead_tree_b", -6.0, 66.0),
    ("rock_c", 80.0, 78.0), ("rock_c", -9.0, 78.0),
    # west: the carpenter who makes the coffins, and the mason who cuts the stones,
    # their yards, and the stones waiting to be lettered
    ("carpentry", -11.0, 22.0), ("mason", -11.0, 36.0),
    ("woodpile", -5.0, 21.0), ("coffin", -5.4, 25.2), ("coffin", -5.4, 26.0), ("coffin", -5.4, 26.8),
    ("crate_stack", -10.6, 28.0), ("wagon", -7.0, 30.4), ("well", -3.6, 33.4),
    ("headstone", -10.0, 42.0), ("headstone", -8.6, 42.0), ("headstone_b", -7.2, 42.0), ("headstone", -5.8, 42.0),
    ("headstone_b", -10.0, 44.0), ("headstone", -8.6, 44.0), ("rock_b", -6.8, 43.8), ("rock_b", -5.4, 44.2),
    ("rock_c", -10.0, 46.6), ("hitch", -10.4, 16.0), ("horse", -10.6, 16.3), ("rock", -4.0, 12.0),
]
# The gate up to the graves from the road, where the path comes through the wagons;
# the guests stood their long guns in a rack beside it (RACKS: the stranger may take
# a few; they may come back for theirs).
GATE = [("cem_gate", 30.2, 45.4), ("gun_rack", 34.2, 44.9)]
BEYOND += GATE
# Cartridges lying about: a box left by a plate, at the cantina, by the wagons and
# the rack (Pickup: six to a box of Colt's, seven of rifle).
PICKUPS = [{"kind": "colt", "x": 8.6, "y": -2.6}, {"kind": "colt", "x": 17.4, "y": -2.6},
           {"kind": "colt", "x": 49.0, "y": -2.6}, {"kind": "colt", "x": 57.4, "y": -2.6},
           {"kind": "colt", "x": 53.8, "y": 28.2}, {"kind": "rifle", "x": 57.0, "y": 28.4},
           {"kind": "colt", "x": 24.6, "y": 46.6}, {"kind": "rifle", "x": 39.6, "y": 48.4},
           {"kind": "coach", "x": 21.0, "y": 49.2}, {"kind": "rifle", "x": 34.6, "y": 46.0}]


def south_graves(taken_objs):
    """The older graves on south past the road, in rows, round the chapel and the
    rocks, the path through them left clear and the ground where he comes in."""
    taken = [layout.footprint(k, x, y) for k, x, y in taken_objs]
    taken += [tuple(r) for r in STREETS]
    out = []
    k = 0
    for row, y in enumerate(np.arange(56.5, N - OY - 2.0, 2.5)):
        for x in np.arange(-OX + 2.0 + (row % 2) * 1.1, N - OX - 2.0, 2.2):
            if math.hypot(x - PLAYER["x"], y - PLAYER["y"]) < 3.0:
                continue
            kind = ("cross", "headstone", "cross", "mound", "cross", "headstone_b", "cross")[(k + row) % 7]
            k += 1
            fp = layout.footprint(kind, x, y)
            if any(layout.overlaps(fp, t, 0.5) for t in taken):
                continue
            out.append((kind, round(float(x), 2), round(float(y), 2)))
    return out


W, E, NORTH, S = 206, 26, 334, 154
# Four factions came, each from the towns he rode through, each its own road home
# and its own men waiting just past the edge of the map for word (see CAMPS): San
# Miguel's bandidos, the revolutionaries, the federales, and the northerners from
# Silencio (hunters and outlaws both, of one mind today).
BAND, REV, FED, NORTH_MEN = ({"gang": "bandidos"}, {"gang": "revolutionaries"}, {"gang": "federales"},
                             {"gang": "northerners"})


def toward(x, y, tx, ty):
    return layout.screen_deg(tx - x, ty - y)


def mourning(kind, a, side, r=3.6):
    """A guest at the graveside, round the stone circle, looking in at the grave."""
    x, y = C[0] + r * math.cos(a), C[1] + r * math.sin(a)
    return dict({"kind": kind, "x": round(x, 2), "y": round(y, 2), "facing": toward(x, y, *C), "mourning": True}, **side)


GRAVESIDE = [
    mourning("bandido", 0.4, BAND), mourning("revolucionario", 1.2, REV), mourning("manhunter", 2.0, NORTH_MEN),
    mourning("soldado", 2.9, FED), mourning("sargento", 3.7, REV), mourning("trapper", 4.6, NORTH_MEN),
    mourning("pistolero", 5.4, BAND),
]
# The rest, eight, well apart about the valley, waiting for the drink.
ABOUT = [
    dict({"kind": "cowboy", "x": 54.6, "y": 28.4, "facing": W}, **BAND),          # on the cantina's porch
    dict({"kind": "drunkard", "x": 11.0, "y": -2.6, "facing": E}, **BAND),        # at the dinner already, helping himself
    dict({"kind": "soldadera", "x": 52.6, "y": -2.6, "facing": S}, **REV),        # at the other, keeping an eye on it
    dict({"kind": "tirador", "x": 24.0, "y": 10.8, "facing": S}, **REV),          # up on the mission's broken wall
    dict({"kind": "cabo", "x": 32.0, "y": 11.4, "facing": S}, **FED),             # on the chapel steps
    dict({"kind": "rural", "x": 28.0, "y": 49.4, "facing": NORTH}, **FED),        # by the wagons on the road
    dict({"kind": "sharpshooter", "x": 49.0, "y": 11.0, "facing": W}, **NORTH_MEN),   # up the rocks to the north-east
    dict({"kind": "mountainman", "x": 67.2, "y": 36.0, "facing": W}, **NORTH_MEN),    # in the town's street
]
ENEMIES = GRAVESIDE + ABOUT

# Who else came: the padre to say the words, the undertaker and his digger, and a
# few who came to weep (or to make sure).
TOWNSFOLK = [
    # at the grave for the burial: the padre at its head, the carpenter who made the
    # box kneeling at it with his hammer and nails, a digger with his spade (Funeral)
    {"kind": "priest", "x": 32.0, "y": 28.3, "facing": S, "funeral": "sermon"},
    {"kind": "carpenter", "x": 33.5, "y": 31.4, "facing": W, "funeral": "nails"},
    {"kind": "digger", "x": 30.2, "y": 30.3, "facing": E, "funeral": "spade"},
    {"kind": "undertaker", "x": 9.2, "y": 31.4, "facing": E},
    {"kind": "digger", "x": 14.0, "y": 37.6, "facing": S},
    {"kind": "visitor", "x": 28.2, "y": 23.6, "facing": 90, "palette": 0},
    {"kind": "visitor", "x": 38.4, "y": 33.8, "facing": 200, "palette": 1},
    {"kind": "widower", "x": 27.0, "y": 30.0, "facing": E},
    # the women who cooked the wake, minding their fires, and a man of the town in his street
    {"kind": "townswoman", "x": 18.6, "y": -3.0, "facing": W},
    {"kind": "townswoman", "x": 58.6, "y": -3.0, "facing": W},
    {"kind": "townsman", "x": 67.6, "y": 30.0, "facing": W},
    # girls from the cantina, out among the guests (the real thing: townsfolk, see
    # Civilian "flirts"): one on its porch, one at each of the dinners
    {"kind": "saloon_girl", "x": 56.2, "y": 28.8, "facing": S, "palette": 0},
    {"kind": "saloon_girl", "x": 13.0, "y": -3.0, "facing": S, "palette": 1},
    {"kind": "saloon_girl", "x": 53.0, "y": -3.0, "facing": S, "palette": 2},
]

HOLDOUTS = [{"name": "chapel", "x": 32.0, "y": 8.9}, {"name": "cantina", "x": 55.0, "y": 27.4},
            {"name": "undertaker's", "x": 10.4, "y": 28.4}]
ENTRIES = [{"name": "west road", "x": 0.7 - OX, "y": 51.5}, {"name": "east road", "x": N - 0.7 - OX, "y": 51.5},
           {"name": "mission track", "x": 32.0, "y": 0.8 - OY}, {"name": "town", "x": 67.0, "y": 0.8 - OY}]
CENTER = {"x": C[0], "y": C[1] + 4.0}
PLAYER = {"x": 32.0, "y": 80.0}   # (--at, or no coffin: in from the south, through the old graves)
# Boot hill: the first is the undertaker's own plot, clear ground below his fresh row
# where the day's dead go in; the second is the old rings, for the mourners to go round.
BOOTHILLS = [[9.5, 41.2, 22.0, 46.0], [17, 15, 47, 45]]

BUILDING_KINDS = {k for k, *_ in BUILDINGS_AT} | {"crypt", "crypt_b"}


# Where the guests' long guns are, left behind for the funeral: in the scabbard on
# every saddle, in every wagon, and in the rack inside the cantina's door. A man
# who goes for his runs to the near side of one of these (see Arms).
SADDLES = ("horse", "horse_grey", "horse_sorrel", "horse_black")
WAGONS = ("wagon", "covered_wagon", "carreta_0")
RACKS = [{"x": 55.0, "y": 27.6, "kind": "rack", "count": 2},   # (the cantina's door)
         {"x": 35.0, "y": 46.0, "kind": "rack", "count": 4}]   # (the gate up to the graves: see GATE)


# Each faction's road home and the men waiting at the end of it (the map's edge, by
# the entries), fetched by a runner once one of the faction falls; they come back
# all at once down the same road, armed for it.
CAMP_COUNT = 5
CAMP_AFTER = 30.0   # s from the runner shouting for them to the first of them in (saddling up, riding over)
CAMPS_AT = {
    "bandidos": ("the west road", ["pistolero", "bandido", "cowboy", "redscarf", "rifleman", "gunslinger"]),
    "revolutionaries": ("the mission track", ["revolucionario", "sargento", "tirador", "soldadera"]),
    "federales": ("the east road", ["soldado", "cabo", "rural", "teniente"]),
    "northerners": ("the town", ["manhunter", "sharpshooter", "trapper", "trappeur", "mountainman", "woodsman"]),
}


JOINED = ("wall_x4", "wall_y4", "wall_x8", "wall_y8", "carreta_0", "carreta_1")


def arms_points(objects, solid):
    """A walkable point beside each saddle and wagon: below it, else above, else to a side."""
    out = []
    for o in objects:
        if o["type"] not in SADDLES + WAGONS:
            continue
        x0, y0, x1, y1 = layout.footprint(o["type"], o["x"], o["y"])
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        for px, py in ((cx, y1 + 0.55), (cx, y0 - 0.55), (x1 + 0.55, cy), (x0 - 0.55, cy)):
            pt = (px - 0.35, py - 0.35, px + 0.35, py + 0.35)
            if 1.0 < px < N - 1.0 and 1.0 < py < N - 1.0 and not any(layout.overlaps(pt, r) for _, r in solid):
                out.append({"x": round(px, 2), "y": round(py, 2), "kind": "saddle" if o["type"] in SADDLES else "wagon"})
                break
    return out + [_down(r) for r in RACKS]


def _down(p):
    """Someone, or a place, moved from the valley's frame onto the map."""
    q = dict(p, x=round(p["x"] + OX, 2), y=round(p["y"] + OY, 2))
    if "patrol" in q:
        q["patrol"] = [[round(x + OX, 2), round(y + OY, 2)] for x, y in q["patrol"]]
    return q


def place(kind, x, y):
    """One object, or a chunked one's pieces one after another along its axis."""
    if kind not in CHUNKED:
        return [(kind, x, y)]
    axis, n = CHUNKED[kind]
    step = BUILDINGS[kind][1][axis] / n
    return [(f"{kind}_{i}", x + (i * step if axis == 0 else 0), y + (i * step if axis == 1 else 0)) for i in range(n)]


def main():
    global STREETS, MUD, BOOTHILLS, ENEMIES, TOWNSFOLK, HOLDOUTS, ENTRIES, CENTER, PLAYER
    rest = BUILDINGS_AT + PROPS + DINNERS + BEYOND + cemetery()
    placed = [q for k, x, y in rest + south_graves(rest) for q in place(k, x, y)]
    objects = [{"type": k, "x": round(x + OX, 2), "y": round(y + OY, 2)} for k, x, y in placed]
    graves = sum(o["type"] in GRAVE_KINDS for o in objects)
    STREETS = [[x0 + OX, y0 + OY, x1 + OX, y1 + OY] for x0, y0, x1, y1 in STREETS]
    MUD = [[x + OX, y + OY, r] for x, y, r in MUD]
    BOOTHILLS = [[x0 + OX, y0 + OY, x1 + OX, y1 + OY] for x0, y0, x1, y1 in BOOTHILLS]
    ENEMIES, TOWNSFOLK, HOLDOUTS, ENTRIES = ([_down(p) for p in g] for g in (ENEMIES, TOWNSFOLK, HOLDOUTS, ENTRIES))
    roads = {e["name"]: e for e in ENTRIES}
    global CAMPS
    CAMPS = {g: {"name": road, "x": roads[road.replace("the ", "")]["x"], "y": roads[road.replace("the ", "")]["y"],
                 "count": CAMP_COUNT, "after": CAMP_AFTER, "losses": 1, "kinds": kinds}
             for g, (road, kinds) in CAMPS_AT.items()}
    CENTER, PLAYER = _down(CENTER), _down(PLAYER)
    solid = layout.check(N, objects, ENEMIES + TOWNSFOLK + ENTRIES + HOLDOUTS
                         + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")],
                         joined=JOINED)
    posts = layout.make_posts(N, STREETS, solid, ENEMIES, PLAYER, BUILDING_KINDS)
    pickups = [_down(p) for p in PICKUPS]
    layout.check(N, objects, pickups, joined=JOINED)
    arms = arms_points(objects, solid)
    layout.check(N, objects, arms, joined=JOINED)
    layout.write("funeral.json", {
        "name": "A Good Man Never Dies",
        "size": N,
        "ground": "ground_funeral",
        "weather": "grey",   # under cloud, after the rain (the grade in game.gd, the ground in gen_assets)
        "streets": STREETS,
        "mud": MUD,
        "boothills": BOOTHILLS,
        "objects": objects,
        "player": PLAYER,
        "enemies": ENEMIES,
        "civilians": TOWNSFOLK,
        "holdouts": HOLDOUTS,
        "posts": posts,
        "entries": ENTRIES,
        "center": CENTER,
        "posse": False,
        "coffin": [round(COFFIN[0] + OX, 2), round(COFFIN[1] + OY, 2)],
        "grave": [round(GRAVE[0] + OX, 2), round(GRAVE[1] + OY, 2)],
        "pickups": pickups,   # cartridges lying about the dinners, the cantina and the wagons   # (its corner: where the coffin goes down, see Funeral)
        "nails": 0,       # (the sermon drives them in, one for each of his sins: see Funeral)
        "wake": True,     # everyone's here for the funeral and the party after: slow to take alarm
        "arms": arms,     # where their long guns are: every guest has only his pistol on him
        "camps": CAMPS,   # each faction's men waiting down its road, for a runner to fetch (Director)
        "shout": 3.5,     # tiles from the map's edge: a runner this near is heard
    })
    print("burial ground: %d objects (%d graves), %d guests, %d townsfolk, %d guard posts, %d places their long guns are" % (
        len(objects), graves, len(ENEMIES), len(TOWNSFOLK), len(posts), len(arms)))


if __name__ == "__main__":
    main()
