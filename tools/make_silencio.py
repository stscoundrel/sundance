#!/usr/bin/env python3
"""Lays out Silencio and writes data/silencio.json: a mountain town snowed in for the
winter, the pass shut. One main street runs east-west through it, and the town's
split along it: the bounty hunters hold the east end (the jail, the hotel, the
bank, their horses in the stable), the outlaws they came up for hold the west end
(the cabins, the feed barn, and the old livery that's their hideout, the gold in
it), and between them the saloon, the store and the church are nobody's. A frozen
pond lies at the north-west edge, behind the outlaws' end. The stranger leaves his
horse down the south trail, among the pines, and comes up it on foot.

Twelve hunters hold the east end, sixteen outlaws the west.

Usage: tools/.venv/bin/python tools/make_silencio.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout  # noqa: E402

N = 64

STREETS = [
    [0, 29, 64, 34],      # main street, the length of the town
    [20.5, 17, 60, 20],   # the north street, from the outlaws' cross street east
    [4, 46, 60, 49],      # the south street
    [20.5, 8, 23.5, 58],  # the west cross street: where the outlaws' end stops
    [41.5, 8, 44.5, 58],  # the east cross street: where the hunters' begins
    [31, 49, 34, 64],     # the south trail, down to the horse
]

# The frozen pond, an ellipse on the tile grid (centre, radii), and the holes the
# town cuts through it to fish.
ICE = [[10.0, 8.6, 8.2, 5.8]]
ICE_HOLES = [[7.6, 7.4], [12.4, 10.6], [5.4, 10.8]]

BUILDINGS_AT = [
    # north side of main street, facing it (fronts at y = 29)
    # the outlaws' end
    ("cabin_b", 2, 25), ("feed", 8, 24), ("stable", 14.5, 24),   # (the livery: their hideout, the gold in it)
    # nobody's
    ("saloon", 24, 23), ("store", 31.5, 24), ("barber", 37, 25),
    # the hunters' end
    ("sheriff", 45, 24), ("hotel", 50.5, 23), ("cabin", 58.5, 25),
    # south of main street (their backs to it)
    ("cabin", 3, 35.5), ("cabin_b", 10, 35.5),
    ("undertaker", 25, 35), ("assay", 31.5, 35.5), ("gunsmith", 37.5, 35.5),
    ("bank", 46, 35), ("stable", 54, 35.5),
    # north of the north street
    ("church", 29, 8.5), ("water_tower", 38, 12), ("cabin", 46, 11), ("cabin_b", 53, 11.5),
    # south of the south street
    ("cabin", 7, 51), ("cabin_b", 14, 51.5), ("cabin", 24, 51), ("cabin", 46, 51), ("cabin_b", 53, 51.5),
]

PROPS = [
    # main street: wagons stood where the snow stopped them, frozen troughs, hitches
    ("wagon", 11, 31.5), ("wagon", 34.5, 29.4), ("wagon", 50, 31.8),
    ("trough", 6, 29.5), ("trough", 26.0, 33.1), ("trough", 45.5, 33.1), ("trough", 18.5, 33.1),
    ("hitch", 16, 29.4), ("hitch", 29.5, 29.4), ("hitch", 52.5, 29.4), ("hitch", 40, 33.3),
    # coffins stood up by the undertaker's back door: business is good
    ("coffin", 26.2, 40.8), ("coffin", 26.2, 41.6),
    # on the saloon's porch
    ("table", 25.2, 29.15), ("chair", 24.7, 29.2), ("chair", 25.95, 29.25),
    # firewood, split and stacked against the winter, by every door that burns it
    ("woodpile", 2.4, 23.4), ("woodpile", 7.2, 40.2), ("woodpile", 13.0, 40.2), ("woodpile", 59.0, 23.4),
    ("woodpile", 9.6, 55.8), ("woodpile", 26.0, 55.8), ("woodpile", 48.0, 55.8), ("woodpile", 55.6, 56.2),
    ("woodpile", 47.4, 16.0), ("woodpile", 19.0, 22.3), ("woodpile", 56.0, 40.8),
    ("stump", 5.0, 42.2), ("stump", 29.4, 52.2), ("stump", 50.6, 44.0), ("stump", 17.4, 17.0),
    # stores in the yards
    ("crate", 8.4, 22.6), ("barrel", 9.4, 22.6), ("crate_stack", 12.0, 22.4), ("sacks", 21.2, 25.2),   # (the outlaws': up from the feed barn)
    ("crate", 31.8, 22.4), ("barrel", 32.8, 22.6), ("crate", 36.0, 41.8), ("barrel", 37.0, 42.0),
    ("crate_stack", 46.0, 22.4), ("barrel", 49.0, 22.5), ("crate", 52.6, 41.8), ("sacks", 44.8, 41.6),
    ("barrel", 4.8, 44.0), ("crate", 15.6, 44.2), ("barrel", 39.4, 16.0), ("crate", 57.8, 16.2),
    # the pond: a boat turned over on the shore, reeds through the ice at its edge
    ("boat_over", 14.2, 15.6), ("boat_over", 2.0, 15.2),
    ("reeds", 17.0, 7.0), ("reeds_b", 17.6, 10.4), ("reeds", 3.0, 3.6), ("reeds_b", 1.6, 9.6),
    ("reeds", 9.4, 2.4), ("reeds_b", 14.6, 13.4), ("reeds", 5.6, 14.0),
    # the dead of the winter, under crosses behind the church
    ("cross", 30.0, 2.4), ("cross", 32.0, 2.0), ("cross", 34.0, 2.6), ("cross", 36.0, 2.2), ("cross", 31.0, 4.4),
    ("cross", 35.0, 4.6),
]

# The pines: thick round the edges of town, thinning in, and down both sides of the
# south trail, where the stranger comes up out of them.
PINES = [
    # the south trail
    (28.4, 61.6), (36.4, 59.0), (28.8, 58.0), (36.4, 56.8), (26.0, 61.6), (38.4, 61.6),
    (40.0, 58.4), (24.4, 59.2), (29.2, 54.0),
    # the south edge
    (2.0, 60.0), (6.0, 61.4), (11.0, 60.6), (16.0, 61.6), (20.0, 59.4), (43.0, 61.6), (48.0, 60.0),
    (53.0, 61.6), (58.0, 60.2), (61.6, 57.0), (19.4, 55.0), (3.6, 56.2),
    # the east edge, past the hunters' end
    (61.6, 44.0), (61.4, 40.0), (61.6, 36.0), (61.2, 21.6), (61.6, 16.0), (61.2, 11.0),
    (61.6, 5.0), (58.0, 3.0),
    # the north edge, behind the church and the cabins
    (24.6, 3.0), (40.6, 3.4), (45.0, 4.6), (50.0, 2.4), (55.0, 5.6), (42.6, 9.6), (27.0, 11.4),
    # round the pond and up the north-west
    (20.4, 3.0), (19.6, 12.0), (1.4, 18.6), (6.4, 19.2), (11.6, 18.8),
    # the west edge, by the pass road
    (1.6, 40.0), (1.4, 44.6), (2.0, 49.0),
]
PINES = [("pine" if i % 3 else "pine_b", x, y) for i, (x, y) in enumerate(PINES)]

# Slush where the street's been churned up: by the troughs and the saloon's steps.
MUD = [[6.8, 31.0, 1.2], [28.0, 31.4, 1.4], [47.6, 31.0, 1.0], [17.0, 32.0, 1.0], [43.0, 47.4, 0.9],
       [22.0, 47.6, 0.9], [32.4, 50.6, 0.8]]

# The gangs. Facing, as the screen goes: west along main street 206, east 26,
# north 334, south 154.
W, E, NORTH, S = 206, 26, 334, 154
# San Miguel's old timer, who'd fit either side: in winter colours, with no Spanish.
OLD_HUNTER = {"gang": "hunters", "tongue": "english", "palettes": [
    {"coat": [58, 56, 62], "shirt": [160, 152, 138], "trousers": [64, 62, 66], "boots": [36, 30, 26], "hat": [50, 46, 42],
     "band": [30, 26, 24], "skin": [200, 146, 116], "hair": [222, 218, 208]}]}
OLD_OUTLAW = {"gang": "outlaws", "tongue": "english", "palettes": [
    {"coat": [112, 86, 62], "shirt": [120, 60, 50], "trousers": [84, 72, 58], "boots": [62, 46, 32], "hat": [92, 72, 52],
     "band": [60, 46, 34], "skin": [196, 142, 110], "hair": [214, 210, 200]}]}

# The bounty hunters, twelve, at the east end: the jail their headquarters, long
# guns on the porches looking down main street, men walking their streets.
HUNTERS = [
    {"kind": "hunter_boss", "x": 48.0, "y": 29.8, "facing": W},                    # at the jail door
    {"kind": "buntline", "x": 44.0, "y": 31.5, "facing": W},                       # out in the street, at the line
    {"kind": "sharpshooter", "x": 52.0, "y": 29.7, "facing": W},                   # the hotel porch
    {"kind": "sharpshooter", "x": 58.2, "y": 29.6, "facing": W},
    {"kind": "sharpshooter", "x": 43.0, "y": 18.5, "facing": W},                   # the north street's corner
    {"kind": "manhunter", "x": 46.0, "y": 32.6, "patrol": [[46.0, 32.6], [60.0, 32.6]]},
    {"kind": "manhunter", "x": 43.0, "y": 36.0, "patrol": [[43.0, 36.0], [43.0, 46.0]]},
    {"kind": "manhunter", "x": 46.0, "y": 18.6, "patrol": [[46.0, 18.6], [58.0, 18.6]]},
    {"kind": "manhunter", "x": 46.0, "y": 47.6, "patrol": [[46.0, 47.6], [58.0, 47.6]]},
    {"kind": "manhunter", "x": 49.0, "y": 42.0, "facing": S},                      # behind the bank
    {"kind": "manhunter", "x": 26.4, "y": 29.6, "facing": E},                      # on the saloon's porch: nobody's ground
    dict({"kind": "oldtimer", "x": 61.0, "y": 31.0, "facing": E}, **OLD_HUNTER),    # watching the valley road
]
# The outlaws, sixteen, at the west end: the chief at the hideout's door with his
# heavies, trappers about the cabins and the streets, a woodsman over the pond.
OUTLAWS = [
    {"kind": "outlaw_chief", "x": 18.6, "y": 29.9, "facing": E},                   # by the gold
    {"kind": "mountainman", "x": 19.6, "y": 30.8, "facing": E},
    {"kind": "mountainman", "x": 13.0, "y": 29.8, "facing": E},                    # at the feed barn
    {"kind": "woodsman", "x": 19.0, "y": 9.0, "facing": W},                        # over the pond
    {"kind": "woodsman", "x": 6.0, "y": 46.2, "facing": E},                        # the south street's end
    {"kind": "trapper", "x": 2.0, "y": 32.6, "patrol": [[2.0, 32.6], [19.0, 32.6]]},
    {"kind": "trapper", "x": 21.8, "y": 26.4, "facing": E},
    {"kind": "trapper", "x": 12.0, "y": 12.0, "patrol": [[12.0, 12.0], [5.0, 6.0]]},   # out on the ice
    {"kind": "trapper", "x": 9.6, "y": 43.0, "facing": NORTH},
    {"kind": "trapper", "x": 22.0, "y": 36.0, "patrol": [[22.0, 36.0], [22.0, 46.0]]},
    {"kind": "trapper", "x": 18.0, "y": 47.4, "patrol": [[18.0, 47.4], [8.0, 47.4]]},
    {"kind": "trapper", "x": 1.2, "y": 30.8, "facing": W},                         # at the pass road
    {"kind": "trappeur", "x": 5.5, "y": 23.0, "facing": S},
    {"kind": "trappeur", "x": 10.6, "y": 21.6, "facing": S},
    {"kind": "trappeur", "x": 29.6, "y": 29.8, "facing": W},                       # on the saloon's porch, across from the hunter
    dict({"kind": "oldtimer", "x": 16.4, "y": 41.8, "facing": NORTH}, **OLD_OUTLAW),
]
ENEMIES = HUNTERS + OUTLAWS
# The townsfolk, what's left of them: shut in between two gangs for the winter, they
# keep to their own doorsteps on nobody's ground and the south street, and are in at
# the door the moment an armed man comes their way (see Civilian, "shy").
TOWNSFOLK = [
    {"kind": "snowbound", "x": 33.0, "y": 29.4, "facing": S, "palette": 0},           # the storekeeper, on his porch
    {"kind": "snowbound", "x": 33.6, "y": 40.4, "facing": S, "palette": 1},           # behind the assay office
    {"kind": "snowbound", "x": 39.6, "y": 40.6, "facing": W, "palette": 0},           # at the gunsmith's back door
    {"kind": "snowbound", "x": 48.0, "y": 50.6, "facing": NORTH, "palette": 1},       # at his cabin, the hunters' end
    {"kind": "snowbound_woman", "x": 31.2, "y": 16.2, "facing": NORTH, "palette": 0}, # at the church door
    {"kind": "snowbound_woman", "x": 26.4, "y": 50.6, "facing": NORTH, "palette": 1}, # by her woodpile
    {"kind": "snowbound_woman", "x": 15.6, "y": 51.0, "facing": E, "palette": 0},     # at her cabin, the outlaws' end
    {"kind": "winter_girl", "x": 25.2, "y": 29.9, "facing": S, "palette": 0},         # on the saloon's porch, in furs
    {"kind": "winter_girl", "x": 27.8, "y": 29.9, "facing": S, "palette": 2},         # (both gangs drink there)
]

HOLDOUTS = [{"name": "hideout", "x": 17.8, "y": 29.6, "gang": "outlaws"}, {"name": "jail", "x": 47.5, "y": 29.6, "gang": "hunters"},
            {"name": "church", "x": 31.0, "y": 16.4}]
ENTRIES = [{"name": "valley road", "x": 63.3, "y": 31.5}, {"name": "pass road", "x": 0.7, "y": 31.5},
           {"name": "south trail", "x": 32.5, "y": 63.3}]
CENTER = {"x": 32.0, "y": 31.5}   # (main street, before the store: nobody's ground)
PLAYER = {"x": 32.5, "y": 62.4}   # down the south trail, where he left his horse
# The outlaws' gold: a strongbox in the livery's open doorway, their hideout (the
# corner of its footprint, tiles). And his horse, tied to a post beside the trail
# (the object's corner; HORSE_AT, its middle, is where he's away with the gold).
STRONGBOX = [17.0, 29.15]
# Whose ground is whose (tiles, x0 y0 x1 y1): a body found on the other gang's is
# their doing (see game.weigh_death). Between the cross streets is nobody's.
TURF = {"outlaws": [0, 0, 22, 64], "hunters": [42, 0, 64, 64]}
# Where each gang pushes up to in a street war, by turns: its own edge of nobody's
# ground on main street, then round the backs, up the north street and the south
# street, deep towards the other end (a flank that gets round can turn it).
LINES = {"outlaws": [[25.0, 31.5], [37.0, 18.5], [37.0, 47.5]],
         "hunters": [[39.0, 31.5], [27.0, 18.5], [27.0, 47.5]]}
# Each gang's camp, off the map: where the way to it leaves the map, and how many
# come back with a runner (see Director). The outlaws' is up behind the frozen pond,
# the bounty hunters' down the valley at the far corner: fewer of them, better armed.
CAMPS = {"outlaws": {"name": "the camp behind the lake", "x": 6.0, "y": 0.6, "count": 10},
         "hunters": {"name": "the camp down the valley", "x": 63.3, "y": 47.5, "count": 5}}
HORSE = ("horse", 34.0, 61.6)
HORSE_AT = [35.15, 62.1]

BUILDING_KINDS = {k for k, *_ in BUILDINGS_AT}


def main():
    objects = [{"type": k, "x": x, "y": y} for k, x, y in BUILDINGS_AT + PROPS + PINES + [HORSE]]
    solid = layout.check(N, objects, ENEMIES + TOWNSFOLK + ENTRIES + HOLDOUTS + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")])
    posts = layout.make_posts(N, STREETS, solid, ENEMIES, PLAYER, BUILDING_KINDS)
    layout.write("silencio.json", {
        "name": "Silencio",
        "size": N,
        "ground": "ground_silencio",
        "snow": True,
        "skin": "snow",
        "weather": "snow",   # falling, out of a grey sky (scripts/snowfall.gd, the grade in post.gdshader)
        "streets": STREETS,
        "mud": MUD,
        "ice": ICE,
        "ice_holes": ICE_HOLES,
        "objects": objects,
        "player": PLAYER,
        "enemies": ENEMIES,
        "gangs": ["hunters", "outlaws"],
        "civilians": TOWNSFOLK,
        "holdouts": HOLDOUTS,
        "posts": posts,
        "entries": ENTRIES,
        "center": CENTER,
        "posse": False,
        "turf": TURF,
        "lines": LINES,
        "camps": CAMPS,
        "strongbox": STRONGBOX,
        "horse": HORSE_AT,
    })
    print("Silencio: %d buildings, %d props, %d pines, %d hunters, %d outlaws, %d townsfolk, %d guard posts" % (
        len(BUILDINGS_AT), len(PROPS), len(PINES), len(HUNTERS), len(OUTLAWS), len(TOWNSFOLK), len(posts)))


if __name__ == "__main__":
    main()
