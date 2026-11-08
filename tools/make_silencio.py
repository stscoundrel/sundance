#!/usr/bin/env python3
"""Lays out Silencio and writes data/silencio.json: a mountain town snowed in for the
winter, the pass shut. One main street runs east-west through it, and the town's
split along it: the bounty hunters hold the east end (the jail, the hotel, the
bank, their horses in the stable), the outlaws they came up for hold the west end
(the cabins, the feed barn, and the old livery that's their hideout, the gold in
it), and between them the saloon, the store and the church are nobody's. A frozen
pond lies at the north-west edge, behind the outlaws' end. The stranger leaves his
horse down the south trail, among the pines, and comes up it on foot.

For now (phase 1) the gang is San Miguel's, standing in for both sides.

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
    (28.4, 61.6), (36.4, 59.0), (28.8, 58.0), (36.4, 56.8), (26.0, 61.6), (38.4, 61.6), (35.0, 61.6),
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

# Stand-ins (phase 1): San Miguel's gang, the hardier sort at the hunters' end, the
# rabble at the outlaws'.
ENEMIES = [
    # the outlaws' end
    {"kind": "jefe", "x": 17.6, "y": 29.6, "facing": 90},   # at the hideout's door
    {"kind": "bandido", "x": 13.0, "y": 29.8, "facing": 60},
    {"kind": "bandido", "x": 5.0, "y": 32.4, "patrol": [[5.0, 32.4], [19.0, 32.4]]},
    {"kind": "redscarf", "x": 21.8, "y": 26.4, "facing": 90},
    {"kind": "redscarf", "x": 9.6, "y": 43.0, "facing": 270},
    {"kind": "hillbilly", "x": 12.0, "y": 12.0, "patrol": [[12.0, 12.0], [5.0, 6.0]]},   # out on the ice
    {"kind": "drunkard", "x": 16.4, "y": 41.8, "facing": 300},
    {"kind": "pistolero", "x": 22.0, "y": 36.0, "patrol": [[22.0, 36.0], [22.0, 46.0]]},
    {"kind": "bandido", "x": 18.0, "y": 47.4, "patrol": [[18.0, 47.4], [8.0, 47.4]]},
    # nobody's: a pair on the saloon's porch
    {"kind": "gambler", "x": 27.8, "y": 29.4, "facing": 100},
    {"kind": "saloon_girl", "x": 29.2, "y": 29.4, "facing": 70},
    # the hunters' end
    {"kind": "rifleman", "x": 46.4, "y": 29.6, "facing": 180},
    {"kind": "rifleman", "x": 56.0, "y": 29.6, "facing": 160},
    {"kind": "gunslinger", "x": 43.0, "y": 31.6, "patrol": [[43.0, 31.6], [60.0, 31.6]]},
    {"kind": "gunslinger", "x": 43.0, "y": 38.0, "patrol": [[43.0, 38.0], [43.0, 47.0]]},
    {"kind": "poacher", "x": 47.0, "y": 20.6, "facing": 180},
    {"kind": "cowboy", "x": 52.0, "y": 47.4, "patrol": [[52.0, 47.4], [58.0, 47.4]]},
    {"kind": "pistolero", "x": 50.0, "y": 18.4, "patrol": [[50.0, 18.4], [58.0, 18.4]]},
    {"kind": "cowboy", "x": 59.0, "y": 42.6, "facing": 200},
]

HOLDOUTS = [{"name": "hideout", "x": 17.8, "y": 29.6}, {"name": "jail", "x": 47.5, "y": 29.6},
            {"name": "church", "x": 31.0, "y": 16.4}]
ENTRIES = [{"name": "valley road", "x": 63.3, "y": 31.5}, {"name": "pass road", "x": 0.7, "y": 31.5},
           {"name": "south trail", "x": 32.5, "y": 63.3}]
CENTER = {"x": 32.0, "y": 31.5}   # (main street, before the store: nobody's ground)
PLAYER = {"x": 32.5, "y": 62.4}   # down the south trail, where he left his horse

BUILDING_KINDS = {k for k, *_ in BUILDINGS_AT}


def main():
    objects = [{"type": k, "x": x, "y": y} for k, x, y in BUILDINGS_AT + PROPS + PINES]
    solid = layout.check(N, objects, ENEMIES + ENTRIES + HOLDOUTS + [dict(CENTER, kind="centre"), dict(PLAYER, kind="stranger")])
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
        "civilians": [],
        "holdouts": HOLDOUTS,
        "posts": posts,
        "entries": ENTRIES,
        "center": CENTER,
        "posse": False,
    })
    print("Silencio: %d buildings, %d props, %d pines, %d stand-in bandits, %d guard posts" % (
        len(BUILDINGS_AT), len(PROPS), len(PINES), len(ENEMIES), len(posts)))


if __name__ == "__main__":
    main()
