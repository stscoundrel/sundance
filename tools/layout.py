"""What every map's layout script shares: footprints and overlaps, the checks that
refuse a broken map, and the guard posts for a shuffled gang.

Grid units are tiles. Objects are placed by their footprint's minimum corner;
footprints come from world.BUILDINGS.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world import BUILDINGS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Guard posts for a shuffled town: the hand-placed gang's own, and more along the
# streets, the alleys and the yards, spaced out. A shuffled level takes as many as
# it has bandits (seeded by that count). Tags say who suits a post: "boss" (El
# Jefe), "porch" (the ones passing as townsfolk), "lookout" (long views: riflemen),
# "street", "alley", "yard".
POST_TAG = {"jefe": "boss", "general": "boss", "gambler": "porch", "saloon_girl": "porch", "rifleman": "lookout",
            "poacher": "lookout", "tirador": "lookout"}


def footprint(kind, x, y):
    w, h = BUILDINGS[kind][1]
    return (x, y, x + w, y + h)


def overlaps(a, b, pad=0.0):
    return a[0] < b[2] + pad and b[0] < a[2] + pad and a[1] < b[3] + pad and b[1] < a[3] + pad


def screen_deg(dx, dy):
    """A direction on the grid as the screen angle placements use (0 right, 90 down)."""
    return round(math.degrees(math.atan2((dx + dy) * 8.0, (dx - dy) * 16.0))) % 360


SIGHT_PX = 200.0 * 1.2   # a wary bandit's sight (Enemy.VIEW), on screen


def to_screen(x, y):
    return ((x - y) * 16.0, (x + y) * 8.0)


def _crosses(a, b, r):
    """Does the segment a-b (tiles) pass through rectangle r?"""
    for i in range(41):
        t = i / 40
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        if r[0] < x < r[2] and r[1] < y < r[3]:
            return True
    return False


def sees(a, b, solid):
    """Could a bandit at `a` see `b` (tiles): near enough, and no wall between."""
    sa, sb = to_screen(*a), to_screen(*b)
    if math.hypot(sa[0] - sb[0], sa[1] - sb[1]) > SIGHT_PX:
        return False
    return not any(BUILDINGS[o["type"]][2] == "wall" and _crosses(a, b, r) for o, r in solid)


def solids(objects):
    return [(o, footprint(o["type"], o["x"], o["y"])) for o in objects if BUILDINGS[o["type"]][2] != "none"]


def check(n, objects, people, joined=()):
    """Exit with the list of what's wrong if anything solid leaves the map or overlaps
    something else, or anyone (or any point on a patrol) stands inside something.
    Kinds in `joined` (lengths of a wall) may butt up against one another."""
    solid = solids(objects)
    errors = []
    for i, (o, r) in enumerate(solid):
        if r[0] < 0.5 or r[1] < 0.5 or r[2] > n - 0.5 or r[3] > n - 0.5:
            errors.append(f"{o['type']} at {o['x']},{o['y']} leaves the map")
        for o2, r2 in solid[i + 1:]:
            abut = o["type"] in joined and o2["type"] in joined
            if overlaps(r, r2, -0.01 if abut else 0.1):
                errors.append(f"{o['type']} at {o['x']},{o['y']} overlaps {o2['type']} at {o2['x']},{o2['y']}")
    for e in people:
        for p in [(e["x"], e["y"])] + [tuple(q) for q in e.get("patrol", [])]:
            pt = (p[0] - 0.35, p[1] - 0.35, p[0] + 0.35, p[1] + 0.35)
            for o, r in solid:
                if overlaps(pt, r):
                    errors.append(f"{e.get('kind', e.get('name'))} point {p} is inside {o['type']} at {o['x']},{o['y']}")
    if errors:
        print("\n".join(errors))
        sys.exit(1)
    return solid


def make_posts(n, streets, solid, enemies, player, building_kinds, wanted=64, spacing=4.0, keep_off=18.0, seed=9):
    """The hand-placed gang's posts and more, `wanted` in all, `spacing` tiles apart,
    none within `keep_off` tiles of where the stranger starts."""
    def street_of(x, y):
        for r in streets:
            if r[0] <= x <= r[2] and r[1] <= y <= r[3]:
                return r
        return None

    def clear(x, y, pad=0.45):
        if not (1.0 < x < n - 1.0 and 1.0 < y < n - 1.0):
            return False
        pt = (x - pad, y - pad, x + pad, y + pad)
        return not any(overlaps(pt, r) for _, r in solid)

    def near_town(x, y):
        return any(overlaps((x - 3, y - 3, x + 3, y + 3), r) for o, r in solid if o["type"] in building_kinds)

    posts = []
    for e in enemies:
        tag = POST_TAG.get(e["kind"], "street" if street_of(e["x"], e["y"]) else "yard")
        p = {"x": e["x"], "y": e["y"], "tag": tag}
        for k in ("patrol", "facing"):
            if k in e:
                p[k] = e[k]
        posts.append(p)
    rng = random.Random(seed)
    cands = []
    for r in streets:
        alley = (r[2] - r[0]) < 3 or (r[3] - r[1]) < 3
        along_x = (r[2] - r[0]) >= (r[3] - r[1])
        for i in range(400):
            x, y = rng.uniform(r[0] + 0.7, r[2] - 0.7), rng.uniform(r[1] + 0.7, r[3] - 0.7)
            if clear(x, y):
                cands.append((x, y, "alley" if alley else "street", along_x, r))
    for i in range(3000):
        x, y = rng.uniform(1.5, n - 1.5), rng.uniform(1.5, n - 1.5)
        if street_of(x, y) is None and clear(x, y, 0.6) and near_town(x, y):
            cands.append((x, y, "yard", True, None))
    rng.shuffle(cands)
    for x, y, tag, along_x, r in cands:
        if len(posts) >= wanted:
            break
        if any(math.hypot(x - q["x"], y - q["y"]) < spacing for q in posts):
            continue
        if math.hypot(x - player["x"], y - player["y"]) < keep_off or sees((x, y), (player["x"], player["y"]), solid):
            continue   # (nobody posted where he'd see the stranger come in)
        x, y = round(x, 1), round(y, 1)
        p = {"x": x, "y": y, "tag": tag}
        if r is not None:
            cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
            if tag == "street" and len(posts) % 3 == 0:   # every third walks up and down
                a, b = ((max(r[0] + 0.8, x - 5), y), (min(r[2] - 0.8, x + 5), y)) if along_x \
                    else ((x, max(r[1] + 0.8, y - 5)), (x, min(r[3] - 0.8, y + 5)))
                steps = [(a[0] + (b[0] - a[0]) * t / 8, a[1] + (b[1] - a[1]) * t / 8) for t in range(9)]
                if all(clear(*q) for q in steps):
                    p["patrol"] = [[round(a[0], 1), round(a[1], 1)], [round(b[0], 1), round(b[1], 1)]]
            if "patrol" not in p:   # looking along the street, the longer way
                dx, dy = (1 if x < cx else -1, 0) if along_x else (0, 1 if y < cy else -1)
                p["facing"] = screen_deg(dx, dy)
        else:   # a yard: looking out at the nearest street
            best = min(streets, key=lambda s_: math.hypot(min(max(x, s_[0]), s_[2]) - x, min(max(y, s_[1]), s_[3]) - y))
            tx, ty = min(max(x, best[0]), best[2]), min(max(y, best[1]), best[3])
            p["facing"] = screen_deg(tx - x, ty - y) if (tx, ty) != (x, y) else 90
        posts.append(p)
    return posts


def write(name, data):
    with open(os.path.join(ROOT, "data", name), "w") as f:
        json.dump(data, f, indent=1)
