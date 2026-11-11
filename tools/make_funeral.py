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

Twenty of the men he crossed came to see him buried, from every town he rode
through: a few round the grave, the rest about the valley.

Usage: tools/.venv/bin/python tools/make_funeral.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout  # noqa: E402
import numpy as np  # noqa: E402
from world import BUILDINGS, CHUNKED  # noqa: E402

N = 76
# Everything below is laid out in the valley's own frame, then moved OY tiles south
# onto the map (the map grew round it: room north for the dinners, east for the town).
OY = 6.0
C = (32.0, 30.0)   # the heart of the cemetery: the circle of stones, his grave in it (valley frame)

STREETS = [
    [0, 50, 76, 53],        # the valley road, along the south and on out east
    [30.5, 36.5, 33.5, 50],  # up from the road to the graves
    [30.5, -6, 33.5, 23.5],  # the mission track, down past the chapel to the graves
    [65.5, -6, 68.5, 50],    # the town's street, north off the road
    [14, 28.5, 23.5, 31.5],  # in from the undertaker's yard
    [40.5, 28.5, 52, 31.5],  # in from the cantina
]

# The mud, deep after the rain: down the tracks, across the paths through the
# graves, and wherever the wagons and horses have stood.
MUD = [[32.0, 51.5, 2.2], [20.0, 51.6, 1.8], [45.0, 51.4, 2.0], [8.0, 51.8, 1.5], [57.0, 51.6, 1.6],
       [32.0, 44.0, 1.6], [32.0, 17.0, 1.4], [18.5, 30.0, 1.3], [46.0, 30.0, 1.5], [54.0, 34.0, 2.2],
       [50.4, 36.4, 1.4], [25.0, 47.0, 1.3], [38.6, 46.8, 1.4], [32.0, 8.6, 1.4], [10.4, 33.4, 1.4],
       [24.6, 36.6, 0.9], [40.0, 23.0, 0.9], [27.0, 21.4, 0.8], [37.6, 37.4, 0.8],
       [67.0, 51.6, 1.8], [67.0, 40.0, 1.4], [67.0, 26.0, 1.2], [32.0, -3.0, 1.2], [13.0, -1.5, 0.9], [53.5, -1.5, 0.9]]

CIRCLE = (C[0] - 3, C[1] - 3)            # the stone circle's corner (6 tiles across)
GRAVE = (C[0] - 1.1, C[1] - 1.0)         # his open grave, the coffin waiting beside it
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
    out = [("stone_circle", *CIRCLE), ("open_grave", *GRAVE)]
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
W, E, NORTH, S = 206, 26, 334, 154
ONE = {"gang": ""}   # (Silencio's hunters and outlaws stand together for this)


def toward(x, y, tx, ty):
    return layout.screen_deg(tx - x, ty - y)


def mourning(kind, a, r=2.4):
    """A guest at the graveside, round the stone circle, looking in at the grave."""
    x, y = C[0] + r * math.cos(a), C[1] + r * math.sin(a)
    return {"kind": kind, "x": round(x, 2), "y": round(y, 2), "facing": toward(x, y, *C)}


GRAVESIDE = [
    mourning("bandido", 0.4), mourning("revolucionario", 1.2), dict(mourning("manhunter", 2.0), **ONE),
    mourning("soldado", 2.9), mourning("sargento", 3.7), dict(mourning("trapper", 4.6), **ONE),
    mourning("pistolero", 5.4),
]
ABOUT = [
    # the cantina: on the porch, and at the horses
    {"kind": "cowboy", "x": 54.6, "y": 28.4, "facing": W},
    # at the dinners already: one helping himself, one keeping an eye on him
    {"kind": "drunkard", "x": 11.0, "y": -2.6, "facing": E},
    {"kind": "soldadera", "x": 52.6, "y": -2.6, "facing": S},
    {"kind": "rural", "x": 54.0, "y": 35.6, "facing": W},
    dict({"kind": "mountainman", "x": 49.6, "y": 32.4, "facing": W}, **ONE),
    # the mission: on the chapel steps, and up on its broken wall
    {"kind": "cabo", "x": 32.0, "y": 11.4, "facing": S},
    {"kind": "tirador", "x": 24.0, "y": 10.8, "facing": S},
    dict({"kind": "sharpshooter", "x": 49.0, "y": 11.0, "facing": W}, **ONE),   # up the rocks to the north-east
    # the wagons by the road
    {"kind": "rifleman", "x": 28.0, "y": 49.4, "facing": NORTH},
    {"kind": "hillbilly", "x": 39.0, "y": 49.2, "facing": NORTH},
    {"kind": "teniente", "x": 33.6, "y": 45.2, "facing": NORTH},
    # walking the road, and round the outer graves
    {"kind": "redscarf", "x": 12.0, "y": 51.6, "patrol": [[12.0, 51.6], [50.0, 51.6]]},
    {"kind": "gunslinger", "x": 17.6, "y": 22.0, "patrol": [[17.6, 22.0], [17.6, 38.0], [46.4, 40.0], [46.6, 21.0]]},
]
ENEMIES = GRAVESIDE + ABOUT

# Who else came: the padre to say the words, the undertaker and his digger, and a
# few who came to weep (or to make sure).
TOWNSFOLK = [
    {"kind": "priest", "x": 34.0, "y": 31.2, "facing": toward(34.0, 31.2, *C)},
    {"kind": "undertaker", "x": 9.2, "y": 31.4, "facing": E},
    {"kind": "digger", "x": 14.0, "y": 37.6, "facing": S},
    {"kind": "visitor", "x": 28.2, "y": 23.6, "facing": 90, "palette": 0},
    {"kind": "visitor", "x": 38.4, "y": 33.8, "facing": 200, "palette": 1},
    {"kind": "widower", "x": 27.0, "y": 30.0, "facing": E},
    # the women who cooked the wake, minding their fires, and a man of the town in his street
    {"kind": "townswoman", "x": 18.6, "y": -3.0, "facing": W},
    {"kind": "townswoman", "x": 58.6, "y": -3.0, "facing": W},
    {"kind": "townsman", "x": 67.6, "y": 30.0, "facing": W},
]

HOLDOUTS = [{"name": "chapel", "x": 32.0, "y": 8.9}, {"name": "cantina", "x": 55.0, "y": 27.4},
            {"name": "undertaker's", "x": 10.4, "y": 28.4}]
ENTRIES = [{"name": "west road", "x": 0.7, "y": 51.5}, {"name": "east road", "x": 75.3, "y": 51.5},
           {"name": "mission track", "x": 32.0, "y": 0.8 - OY}, {"name": "town", "x": 67.0, "y": 0.8 - OY}]
CENTER = {"x": C[0], "y": C[1] + 4.0}
PLAYER = {"x": 32.0, "y": 68.6}   # for now: in from the south, down off the rocks
# Boot hill: the first is the undertaker's own plot, clear ground below his fresh row
# where the day's dead go in; the second is the old rings, for the mourners to go round.
BOOTHILLS = [[9.5, 41.2, 22.0, 46.0], [17, 15, 47, 45]]

BUILDING_KINDS = {k for k, *_ in BUILDINGS_AT} | {"crypt", "crypt_b"}


def _down(p):
    """Someone, or a place, moved from the valley's frame onto the map."""
    q = dict(p, y=round(p["y"] + OY, 2))
    if "patrol" in q:
        q["patrol"] = [[x, round(y + OY, 2)] for x, y in q["patrol"]]
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
    placed = [q for k, x, y in BUILDINGS_AT + PROPS + DINNERS + cemetery() for q in place(k, x, y)]
    objects = [{"type": k, "x": x, "y": round(y + OY, 2)} for k, x, y in placed]
    for o in objects:   # his grave is nobody's work today: the digger keeps to his own row
        if o["type"] == "open_grave" and (o["x"], o["y"]) == (GRAVE[0], round(GRAVE[1] + OY, 2)):
            o["his"] = True
    graves = sum(o["type"] in GRAVE_KINDS for o in objects)
    STREETS = [[x0, y0 + OY, x1, y1 + OY] for x0, y0, x1, y1 in STREETS]
    MUD = [[x, y + OY, r] for x, y, r in MUD]
    BOOTHILLS = [[x0, y0 + OY, x1, y1 + OY] for x0, y0, x1, y1 in BOOTHILLS]
    ENEMIES, TOWNSFOLK, HOLDOUTS, ENTRIES = ([_down(p) for p in g] for g in (ENEMIES, TOWNSFOLK, HOLDOUTS, ENTRIES))
    CENTER, PLAYER = _down(CENTER), _down(PLAYER)
    solid = layout.check(N, objects, ENEMIES + TOWNSFOLK + ENTRIES + HOLDOUTS
                         + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")],
                         joined=("wall_x4", "wall_y4", "carreta_0", "carreta_1"))
    posts = layout.make_posts(N, STREETS, solid, ENEMIES, PLAYER, BUILDING_KINDS)
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
    })
    print("burial ground: %d objects (%d graves), %d guests, %d townsfolk, %d guard posts" % (
        len(objects), graves, len(ENEMIES), len(TOWNSFOLK), len(posts)))


if __name__ == "__main__":
    main()
