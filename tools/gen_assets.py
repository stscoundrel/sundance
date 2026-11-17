#!/usr/bin/env python3
"""Generates every sprite, sound and the asset metadata for Sundance.

Usage: tools/.venv/bin/python tools/gen_assets.py
Requires numpy and Pillow (see tools/requirements.txt).
"""
import json
import math
import os
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chars  # noqa: E402
import world  # noqa: E402
import render3d  # noqa: E402
from render3d import render, noise2, PIX, PX, PY  # noqa: E402

UI_PIX = 2  # the HUD art is drawn at 2x its 640x360 layout

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
SR = 44100


def save(img, rel):
    path = os.path.join(ASSETS, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (Image.fromarray(img) if isinstance(img, np.ndarray) else img).save(path)
    return "res://assets/" + rel


# ---------------------------------------------------------------- sprites

def gen_characters(meta):
    """Bake every character's animations (in parallel) and pack each into one atlas."""
    from multiprocessing import Pool
    # SUNDANCE_TEMPLATES=veteran,buckskin re-bakes only those and keeps the rest.
    only = [t for t in os.environ.get("SUNDANCE_TEMPLATES", "").split(",") if t]
    if not only:
        meta["chars"] = {}
    guns = chars.template_guns()
    jobs = []
    for template in (only or chars.TEMPLATES):
        jobs += chars.jobs_for(template, guns.get(template, ["colt"]))
    print("  baking %d animations x 8 directions..." % len(jobs))
    with Pool() as pool:
        results = pool.map(chars.bake_job, jobs, chunksize=1)
    by_template = {}
    for template, key, info, dirs in results:
        by_template.setdefault(template, []).append((key, info, dirs))
    for template, anims in by_template.items():
        entries = []
        for key, info, dirs in anims:
            for d, frames in enumerate(dirs):
                for i, (img, sl, ox, oy) in enumerate(frames):
                    entries.append((key, d, i, img, sl, ox, oy))
        atlas, slot_atlas, rects = chars.pack(entries)
        path = save(atlas, f"sprites/chars/{template}.png")
        slot_path = save(slot_atlas, f"sprites/chars/{template}_slots.png")
        out = {}
        for key, info, dirs in anims:
            out[key] = dict(info, frames=rects[key])
        meta["chars"][template] = {"atlas": path, "slots": slot_path, "h_ref": chars.H_REF,
                                   "guns": guns.get(template, ["colt"]), "anims": out}
        print("  %s: %d frames, atlas %dx%d" % (template, len(entries), atlas.shape[1], atlas.shape[0]))
    meta["neutral"] = chars.NEUTRAL[0]
    # Blood pools, apart from the bodies: by death and direction, for every body.
    meta["pools"] = {}
    for death in chars.DEATH_FPS:
        meta["pools"][death] = []
        for d in range(8):
            img, anchor = chars.pool_sprite(death, d)
            meta["pools"][death].append({"file": save(img, f"sprites/fx/pool_{death}_{d}.png"), "anchor": list(anchor)})
    # Where each body lies (for hitting a man who's down): its two ends, by death and direction.
    meta["lie"] = {death: [chars.lie_line(death, d) for d in range(8)] for death in [*chars.DEATH_FPS, "gasp"]}
    # Guns dropped by the dead, lying in the dirt in four orientations.
    meta["guns"] = {}
    for kind in chars.GUN_LEN:
        meta["guns"][kind] = []
        for v in range(4):
            img, anchor = render(chars.dropped_gun(kind, v))
            meta["guns"][kind].append({"file": save(img, f"sprites/fx/gun_{kind}_{v}.png"), "anchor": list(anchor)})


# The buildings with mud-brick walls (the rest are timber).
ADOBE = {"adobe_a", "adobe_b", "cantina", "wall_x8", "wall_x4", "wall_y8", "wall_y4", "gate_x", "gate_y",
         "bastion", "chapel", "barracks", "casa_grande", "jacal", "jacal_b"}


# Silencio's sky: snow falling out of cloud, so its skins are lit flat, their shadows faint.
OVERCAST = {"overcast": True, "shadow_alpha": 40}


def gen_world(meta):
    # SUNDANCE_OBJECTS=coop,hencrate re-bakes only those objects and keeps the rest.
    only = [o for o in os.environ.get("SUNDANCE_OBJECTS", "").split(",") if o]
    if not only or "objects" not in meta:
        meta["objects"] = {}
    for name, (fn, fp, collide, fade, colliders) in world.BUILDINGS.items():
        if fn is None or (only and name not in only):
            continue   # (a piece of a chunked model: baked with the whole)
        print("  object", name)
        world.DOORS.clear()
        world.CHIMNEY.clear()
        world.WINDOWS.clear()
        world.GLAZED.clear()
        world.LANTERNS.clear()
        world.SIGNS.clear()
        world.WASHING.clear()
        model = fn()
        if name in world.CHUNKED:
            _bake_chunks(meta, name, model)
            continue
        img, anchor = render(model, edges=True)
        path = save(img, f"sprites/world/{name}.png")
        meta["objects"][name] = {"file": path, "anchor": list(anchor), "footprint": list(fp),
                                 "collide": collide, "fade": fade,
                                 "colliders": colliders or [[0, 0, fp[0], fp[1]]],
                                 "doors": _doorsteps(world.DOORS)}
        if world.CHIMNEY:   # (where the smoke comes out, when there's a fire lit: Hearth)
            meta["objects"][name]["chimney"] = list(world.CHIMNEY)
        if collide == "wall":   # what a round or a blast lays bare: raw planks, or mud brick
            meta["objects"][name]["paint"] = "adobe" if name in ADOBE else "wood"
        if name in world.FRAGILE:   # each hit a step further gone
            meta["objects"][name]["states"] = []
            for i, sm in enumerate(world.FRAGILE[name]()[1:]):
                im, anc = render(sm, edges=True)
                meta["objects"][name]["states"].append({"file": save(im, f"sprites/world/{name}_{i + 1}.png"),
                                                        "anchor": list(anc)})
            meta["objects"][name]["fragile"] = True
        if name in world.BREAKABLE:   # shot up, then shot to pieces
            meta["objects"][name]["states"] = []
            for i, sm in enumerate(world.prop_states(name)[1:]):
                im, anc = render(sm, edges=True)
                meta["objects"][name]["states"].append({"file": save(im, f"sprites/world/{name}_{i + 1}.png"),
                                                        "anchor": list(anc)})
        if name in world.SNOWY:   # Silencio's look: the same thing under snow (a map's "skin")
            seed = sum(map(ord, name))
            im, anc = render(world.snowed(model, seed, **world.SNOWY[name]), edges=True, **OVERCAST)
            skin = {"file": save(im, f"sprites/world/snow/{name}.png"), "anchor": list(anc)}
            looks = world.FRAGILE[name]()[1:] if name in world.FRAGILE \
                else world.prop_states(name)[1:] if name in world.BREAKABLE else []
            if looks:
                skin["states"] = []
                for i, sm in enumerate(looks):
                    im, anc = render(world.snowed(sm, seed, **world.SNOWY[name]), edges=True, **OVERCAST)
                    skin["states"].append({"file": save(im, f"sprites/world/snow/{name}_{i + 1}.png"), "anchor": list(anc)})
            meta["objects"][name]["skins"] = {"snow": skin}
        if world.WINDOWS:
            meta["objects"][name]["shutters"] = _shutters(name, list(world.WINDOWS), model)
            panes = [i for i, g in enumerate(world.GLAZED) if g]
            meta["objects"][name]["glass"] = _overlays(name, "glass", model,
                                                       [[world.broken_glass(world.WINDOWS[i], i)] for i in panes])
            for g, i in zip(meta["objects"][name]["glass"], panes):
                g["shutter"] = i   # the shutters over it, which keep the rounds off it when shut
                face, (u0, u1), (z0, z1), W, D = world.WINDOWS[i]
                ends = [[u0, D], [u1, D]] if face == "+y" else [[W, u0], [W, u1]]
                g["span"] = [[a / world.T, b / world.T] for a, b in ends]   # its foot, in tiles
                g["z"] = [z0, z1]
        if world.LANTERNS:
            meta["objects"][name]["lanterns"] = _overlays(name, "lantern", model,
                                                          [[world.lantern(l), world.lantern(l, True)] for l in world.LANTERNS])
            for o, l in zip(meta["objects"][name]["lanterns"], world.LANTERNS):
                o["at"] = [l[0] / world.T, l[1] / world.T]
        if world.SIGNS:   # a frame for each angle of swing, and one hanging askew
            meta["objects"][name]["signs"] = _overlays(name, "sign", model,
                                                       [[world.hanging_sign(sg, a) for a in world.SIGN_SWING]
                                                        + [world.hanging_sign(sg, askew=True)] for sg in world.SIGNS])
            for o, sg in zip(meta["objects"][name]["signs"], world.SIGNS):
                o["at"] = [sg[0] / world.T, sg[1] / world.T]
        if world.WASHING:   # flapping, then shot through and flapping, then down in the dirt
            meta["objects"][name]["laundry"] = _overlays(name, "laundry", model,
                                                         [[world.garment(pg, f, holed) for f, holed in world.LAUNDRY_LOOKS]
                                                          + [world.garment(pg, down=True)] for pg in world.WASHING])
            for o, pg in zip(meta["objects"][name]["laundry"], world.WASHING):
                o["at"] = [pg[0] / world.T, pg[1] / world.T]
                o["kind"] = pg[3]
    meta["shutter_paint"] = world.SHUTTER_PAINT
    if not only or "mgun" in only:
        gen_mgun(meta)
    if not only or "plunger" in only:   # the blasting machine at Paso Esperanza: up, and pushed home
        meta["plunger"] = []
        for i, down in enumerate((False, True)):
            img, anchor = render(world.plunger(down), edges=True)
            meta["plunger"].append({"file": save(img, f"sprites/world/plunger_{i}.png"), "anchor": list(anchor)})
    if only:
        return
    frames = []
    for f in range(4):
        img, anchor = render(world.tumbleweed(f), size=(24 * PIX, 24 * PIX), anchor=(12 * PIX, 18 * PIX))
        frames.append(img)
    path = save(np.concatenate(frames, 1), "sprites/world/tumbleweed.png")
    meta["tumbleweed"] = {"file": path, "cell": [24 * PIX, 24 * PIX], "anchor": [12 * PIX, 18 * PIX], "frames": 4}


def _bake_chunks(meta, name, model):
    """Render a long model once and cut the sprite into its pieces along the axis
    (world.CHUNKED): each pixel goes to the piece holding the point it shows; the
    outline to the piece it rings, the shadow to where it falls on the ground."""
    axis, n = world.CHUNKED[name]
    img, anchor, coord = render(model, edges=True, want_coord=axis)
    step = world.BUILDINGS[name][1][axis] / n * world.T   # metres
    lab = np.full(coord.shape, -1, int)
    has = ~np.isnan(coord)
    lab[has] = np.clip((coord[has] // step).astype(int), 0, n - 1)
    seen = img[..., 3] > 0
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb = np.roll(np.roll(lab, dy, 0), dx, 1)
        take = seen & (lab < 0) & (nb >= 0)
        lab[take] = nb[take]
    ys, xs = np.nonzero(seen & (lab < 0))
    d = (xs + 0.5 - anchor[0]) / (PX * PIX)   # X - Y on the ground
    s_ = (ys + 0.5 - anchor[1]) / (PY * PIX)  # X + Y
    g = (s_ + d) / 2 if axis == 0 else (s_ - d) / 2
    lab[ys, xs] = np.clip((g // step).astype(int), 0, n - 1)
    doors = _doorsteps(world.DOORS)
    for i in range(n):
        ys, xs = np.nonzero(lab == i)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        piece = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        piece[ys - y0, xs - x0] = img[ys, xs]
        o = i * step   # the piece's corner, along the axis, as a pixel of the whole
        ox, oy = (o * PX * PIX, o * PY * PIX) if axis == 0 else (-o * PX * PIX, o * PY * PIX)
        cname = f"{name}_{i}"
        _, fp, collide, fade, colliders = world.BUILDINGS[cname]
        lo, hi = i * step / world.T, (i + 1) * step / world.T
        cdoors = [[p[0] - lo, p[1]] if axis == 0 else [p[0], round(p[1] - lo, 2)] for p in doors if lo <= p[axis] < hi]
        meta["objects"][cname] = {"file": save(piece, f"sprites/world/{cname}.png"),
                                  "anchor": [int(round(anchor[0] + ox - x0)), int(round(anchor[1] + oy - y0))],
                                  "footprint": list(fp), "collide": collide, "fade": fade,
                                  "colliders": colliders, "doors": cdoors, "chunk": [name, i]}
        if collide == "wall":
            meta["objects"][cname]["paint"] = "wood"


HEN_COLORS = [(236, 230, 218), (150, 86, 44), (52, 46, 46)]   # white, red-brown, black
HEN_FRAMES = [("stand", 0.0), ("walk", 0.25), ("walk", 0.75), ("peck", 0.0), ("flap", 0.0), ("flap", 0.5)]


def gen_animals(meta):
    """The town's hens: a sheet of frames across (stand, walk x2, peck, flap x2) and,
    down, each colour's eight directions."""
    import chars
    print("  hens")
    cell, anchor = (16 * PIX, 16 * PIX), (8 * PIX, 12 * PIX)
    rows = []
    for col in HEN_COLORS:
        for d in range(8):
            row = []
            for pose, ph in HEN_FRAMES:
                m = world.hen(col, pose, ph)
                m.P = m.P * 1.35   # a shade larger than life, to read at this size
                m.transform(chars.rot_z(chars.yaw_for_dir(d)))
                row.append(render(m, size=cell, anchor=anchor)[0])
            rows.append(np.concatenate(row, 1))
    meta["hens"] = {"file": save(np.concatenate(rows, 0), "sprites/world/hens.png"), "cell": list(cell),
                    "anchor": list(anchor), "frames": len(HEN_FRAMES), "colors": len(HEN_COLORS)}


def _shutters(name, windows, building):
    """Each window's shutters as a strip of frames, open to slammed shut, drawn in
    neutral grey (the game paints them) and anchored at the building's own origin.
    Each frame is rendered with the building around it and keeps only what shows, so
    a porch post or roof in front of a window stays in front of its shutters."""
    bare, anchor = render(building, shadow=False, edges=True)
    size = (bare.shape[1], bare.shape[0])
    out = []
    for i, w in enumerate(windows):
        frames = []
        for a in world.SHUTTER_SWING:
            m = building.copy()
            m += world.shutter(w, a, (226, 226, 226))
            im = render(m, size=size, anchor=anchor, shadow=False, edges=True)[0]
            shows = np.any(im != bare, axis=2)
            frames.append(np.where(shows[..., None], im, 0).astype(np.uint8))
        ys, xs = np.nonzero(np.any(np.stack(frames)[..., 3] > 0, axis=0))
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        strip = np.concatenate([f[y0:y1, x0:x1] for f in frames], 1)
        face, (u0, u1), (z0, z1), W, D = w
        out.append({"file": save(strip, f"sprites/world/shutters/{name}_{i}.png"),
                    "cell": [int(x1 - x0), int(y1 - y0)], "frames": len(frames),
                    "anchor": [int(anchor[0] - x0), int(anchor[1] - y0)],
                    "at": [W / world.T, (u0 + u1) / 2 / world.T] if face == "+x" else [(u0 + u1) / 2 / world.T, D / world.T],
                    "z": z0})
    return out


def _overlays(name, what, building, looks):
    """Fixtures on a building that change when shot (broken panes, lanterns): for
    each, a strip of its looks, each rendered with the building around it keeping
    only the pixels it changes (so posts and roofs in front stay in front), anchored
    at the building's own origin."""
    bare, anchor = render(building, shadow=False, edges=True)
    size = (bare.shape[1], bare.shape[0])
    out = []
    for i, ms in enumerate(looks):
        frames = []
        for extra in ms:
            m = building.copy()
            m += extra
            im = render(m, size=size, anchor=anchor, shadow=False, edges=True)[0]
            shows = np.any(im != bare, axis=2)
            frames.append(np.where(shows[..., None], im, 0).astype(np.uint8))
        ys, xs = np.nonzero(np.any(np.stack(frames)[..., 3] > 0, axis=0))
        if len(xs) == 0:
            xs, ys = np.array([0]), np.array([0])   # hidden entirely (a window round the back)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        strip = np.concatenate([f[y0:y1, x0:x1] for f in frames], 1)
        out.append({"file": save(strip, f"sprites/world/{what}/{name}_{i}.png"),
                    "cell": [int(x1 - x0), int(y1 - y0)], "frames": len(frames),
                    "anchor": [int(anchor[0] - x0), int(anchor[1] - y0)]})
    return out


def _doorsteps(doors):
    """Doorways as tile points just outside the building, relative to its corner."""
    out = []
    for face, u, W, D in doors:
        T, o = world.T, 0.4
        p = {"+y": (u / T, D / T + o), "-y": (u / T, -o), "+x": (W / T + o, u / T), "-x": (-o, u / T)}[face]
        p = [round(p[0], 2), round(p[1], 2)]
        if p not in out:
            out.append(p)
    return out


def _hash(ix, iy, seed):
    """Deterministic 0..1 noise for integer lattice points (any shape)."""
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0


def lnoise(xs, ys, scale, seed):
    """Smooth value noise in [0,1] at absolute pixel positions, so the ground can be
    built strip by strip without seams. xs: (W,), ys: (H,) -> (H, W)."""
    fx, fy = xs / scale, ys / scale
    x0, y0 = np.floor(fx), np.floor(fy)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    X0, Y0 = np.meshgrid(x0, y0)
    a = _hash(X0, Y0, seed)
    b = _hash(X0 + 1, Y0, seed)
    c = _hash(X0, Y0 + 1, seed)
    d = _hash(X0 + 1, Y0 + 1, seed)
    top = a + (b - a) * tx[None, :]
    bot = c + (d - c) * tx[None, :]
    return (top + (bot - top) * ty[:, None]).astype(np.float32)


# The ground's colours, by the map's weather (or its snow): sand, the streets' dirt,
# the mud, and the haze it fades to past the map's edge. The desert sun by default;
# Silencio's snow for sand, the streets trodden grey, slush for mud, a white haze; the
# burial ground's wet earth under cloud, the mud deep and dark.
GROUND_PALETTES = {
    "sun": {"sand": [[166, 124, 84], [182, 140, 96], [196, 156, 108], [210, 172, 122]],
            "dirt": [[132, 96, 66], [146, 108, 74], [158, 118, 82], [170, 130, 90]],
            "mud": [[74, 52, 38], [88, 62, 44], [102, 74, 52]], "haze": [150, 112, 80]},
    "snow": {"sand": [[204, 212, 226], [216, 223, 235], [227, 233, 242], [238, 242, 248]],
             "dirt": [[164, 160, 160], [178, 175, 174], [192, 190, 190], [206, 205, 206]],
             "mud": [[112, 100, 92], [128, 116, 106], [144, 134, 124]], "haze": [200, 208, 222]},
    "grey": {"sand": [[118, 104, 90], [128, 114, 98], [138, 122, 104], [148, 132, 112]],
             "dirt": [[96, 82, 68], [106, 90, 74], [114, 98, 80], [124, 106, 86]],
             "mud": [[56, 44, 36], [66, 52, 42], [76, 60, 48]], "haze": [120, 116, 112]},
}


def gen_ground(meta, level, key="ground"):
    """The ground: sand, streets with wheel ruts, mud and puddles, boot hill, scrub,
    fading to haze beyond town. Built in horizontal strips to keep memory flat. Each
    map bakes its own under its "ground" key (San Miguel's is plain "ground")."""
    N = level["size"]
    M = 8
    span = N + 2 * M
    K = PIX
    W, H = span * 32 * K, span * 16 * K
    ox, oy = span * 16, 2 * M * 8          # world position of the image's top-left corner (negated)
    out = np.zeros((H, W, 3), np.uint8)
    snow = level.get("snow", False)
    pal = GROUND_PALETTES["snow" if snow else level.get("weather", "sun")]
    sand, dirt, mud = (np.array(pal[k], np.float32) for k in ("sand", "dirt", "mud"))
    haze = np.array(pal["haze"])
    ice = np.array([[132, 160, 178], [146, 172, 190], [160, 186, 202]], np.float32)
    xs = np.arange(W, dtype=np.float32)
    band = 256
    for y_start in range(0, H, band):
        ys = np.arange(y_start, min(H, y_start + band), dtype=np.float32)
        h = len(ys)
        PXg, PYg = np.meshgrid(xs, ys)
        sx, sy = (PXg + 0.5) / K - ox, (PYg + 0.5) / K - oy
        gx = (sx / 16 + sy / 8) / 2
        gy = (sy / 8 - sx / 16) / 2
        n_big = lnoise(xs, ys, 90 * K, 1)
        n_mid = lnoise(xs, ys, 24 * K, 2)
        n_small = lnoise(xs, ys, 6 * K, 3)
        fine = _hash(PXg.astype(np.int64), PYg.astype(np.int64), 4)
        tone = 0.25 * n_big + 0.15 + 0.3 * n_mid + 0.15 * n_small + 0.1 * fine
        img = sand[np.clip((tone - 0.25) / 0.5 * 4, 0, 3.99).astype(int)]
        inside = (gx >= 0) & (gx < N) & (gy >= 0) & (gy < N)

        for bx0, by0, bx1, by1 in [] if snow else level.get("boothills", [level["boothill"]] if "boothill" in level else []):
            bh = (gx > bx0) & (gx < bx1) & (gy > by0) & (gy < by1)
            img[bh] = img[bh] * 0.9 + np.array([170, 100, 70]) * 0.1

        road = np.zeros((h, W), bool)
        rut = np.zeros((h, W), bool)
        edge_n = (n_mid - 0.5) * 0.9 + (n_small - 0.5) * 0.4
        for x0, y0, x1, y1 in level.get("streets", []):
            dd = np.maximum.reduce([x0 - gx, gx - x1, y0 - gy, gy - y1])
            road |= dd < edge_n * 0.8
            inrect = (gx > x0) & (gx < x1) & (gy > y0) & (gy < y1)
            if (x1 - x0) > (y1 - y0):
                c = (y0 + y1) / 2
                offs = (-0.85, 0.85, -2.1, 2.1) if (y1 - y0) >= 4.5 else (-0.85, 0.85)
                for off in offs:
                    rut |= inrect & (np.abs(gy - c - off - (n_mid - 0.5) * 0.3) < 0.07)
            else:
                c = (x0 + x1) / 2
                for off in (-0.85, 0.85):
                    rut |= inrect & (np.abs(gx - c - off - (n_mid - 0.5) * 0.3) < 0.07)
        rq = np.clip((0.6 * n_small + 0.4 * fine - 0.2) / 0.6 * 4, 0, 3.99).astype(int)
        img[road] = dirt[rq[road]]
        img[rut & road] *= 0.8
        img[road & (fine > 0.985)] *= 0.75            # hoof prints

        for cx, cy, r in level.get("mud", []):
            dd = np.hypot(gx - cx, gy - cy) / r + (n_small - 0.5) * 0.5 + (n_mid - 0.5) * 0.4
            core = dd < 1.0
            if not core.any():
                continue
            img[core] = mud[np.clip((n_small * 0.7 + fine * 0.3) * 3, 0, 2.99).astype(int)[core]]
            rim = (dd >= 1.0) & (dd < 1.18)
            img[rim] *= 0.82
            puddle = dd < 0.3 - (n_small - 0.5) * 0.4
            img[puddle] = np.array([104, 104, 94], np.float32) * (0.9 + 0.15 * n_small[puddle])[:, None]
            img[puddle & (fine > 0.93)] = (150, 150, 136)

        # frozen water: grey-blue ice, dusted with snow in drifts, cracked, a pale
        # rim where the snow's banked up on the shore; holes cut through it, black
        for cx, cy, rx, ry in level.get("ice", []):
            dd = np.hypot((gx - cx) / rx, (gy - cy) / ry) + (n_mid - 0.5) * 0.25 + (n_small - 0.5) * 0.08
            core = dd < 1.0
            if not core.any():
                continue
            it = np.clip(0.75 * n_big + 0.35 * n_mid - 0.1 + 0.05 * fine, 0, 1)[core][:, None]   # (smooth: stepped tones went blotchy)
            img[core] = ice[0] + (ice[2] - ice[0]) * it
            dust = np.clip((n_mid * 0.8 + n_small * 0.3 - 0.62 - 0.25 * (1 - dd)) / 0.2, 0, 1)[core][:, None]
            img[core] = img[core] * (1 - 0.6 * dust) + sand[1] * 0.6 * dust
            crack = core & ((np.abs(n_small - 0.5) < 0.012) | (np.abs(lnoise(xs, ys, 40 * K, 5) - 0.5) < 0.008))
            img[crack] *= 0.72
            glint = core & (fine > 0.996)
            img[glint] = (236, 244, 250)
            rim = (dd >= 1.0) & (dd < 1.07)
            img[rim] = img[rim] * 0.8 + np.array([150, 160, 176]) * 0.2
        for hx, hy in level.get("ice_holes", []):
            dd = np.hypot(gx - hx, gy - hy) + (n_small - 0.5) * 0.08
            img[dd < 0.42] = (238, 242, 248)                         # the chips heaped round it
            img[dd < 0.3] = np.array([30, 40, 50]) + 14 * n_small[dd < 0.3][:, None]

        # the railroad: ballast, ties and two rails; where it's been torn up ("gaps"),
        # the rails gone, the ties scattered, the ballast kicked about
        gravel = np.array([[70, 64, 60], [82, 76, 70], [96, 88, 80]], np.float32)   # dark, cindery: it doesn't read as sand
        for r in level.get("rails", []):
            c = r["x"]
            along = (gy > r["y0"]) & (gy < r["y1"])
            gap = np.zeros_like(along)
            for a, b in r.get("gaps", []):
                gap |= (gy > a) & (gy < b)
            edge = np.abs(gx - c) - (1.6 + (n_small - 0.5) * 0.3)
            bed = along & (edge < 0) & ~(gap & (n_mid > 0.5))
            shoulder = along & (edge >= 0) & (edge < 0.3) & ~gap   # the bank's foot, darkened with cinders
            img[shoulder] = img[shoulder] * 0.7 + gravel[1] * 0.3 * (1 - edge[shoulder] / 0.3)[:, None] \
                + img[shoulder] * 0.3 * (edge[shoulder] / 0.3)[:, None]
            img[bed] = gravel[np.clip((0.5 * n_small + 0.5 * fine) * 3, 0, 2.99).astype(int)[bed]]
            ti = np.floor(gy * 1.9).astype(np.int64)
            h1 = _hash(ti, np.zeros_like(ti), 17)
            h2 = _hash(ti, np.ones_like(ti), 23)
            cc = np.where(gap, c + (h2 - 0.5) * 1.2, c)
            tie = along & (np.abs(gx - cc) < 1.05) & ((gy * 1.9 - ti) < 0.32) & (~gap | (h1 > 0.5))
            img[tie] = np.array([104, 78, 56], np.float32) * (0.8 + 0.35 * n_small[tie])[:, None]
            off = np.abs(np.abs(gx - c) - 0.575)
            rail = along & ~gap
            img[rail & (off < 0.05)] = (150, 146, 140)
            img[rail & (off < 0.018)] = (196, 192, 184)                  # the worn top, catching the sun
            east = (gx - c - np.sign(gx - c) * 0.575) > 0
            img[rail & (off >= 0.05) & (off < 0.085) & east] *= 0.6      # each rail's shadow, to the east

        img[(fine > 0.992) & ~road] *= 0.7               # pebbles
        peb2 = fine < 0.006
        img[peb2] = np.minimum(img[peb2] * 1.18, 255)

        dist = np.maximum.reduce([-gx, gx - N, -gy, gy - N, np.zeros_like(gx)])
        fade = np.clip(dist / M, 0, 1)
        img = img * (1 - 0.35 * fade[..., None]) + haze * 0.35 * fade[..., None]
        border = inside & ((np.minimum.reduce([gx, N - gx, gy, N - gy])) < 0.06)
        img[border] *= 0.9
        out[y_start:y_start + h] = np.clip(img, 0, 255).astype(np.uint8)

        # tufts of dry grass, away from the streets
        tuft = (_hash(PXg.astype(np.int64), PYg.astype(np.int64), 9) > 1 - 0.0015 / (K * K)) & ~road
        tuft &= ~inside | (n_big > 0.55)
        rng = np.random.default_rng(y_start)
        for y, x in zip(*np.nonzero(tuft)):
            y += y_start
            for _ in range(rng.integers(4, 10)):
                dx = int(rng.integers(-2 * K, 2 * K + 1))
                hgt = int(rng.integers(1, 3 * K + 1))
                col = ((134, 128, 66) if rng.random() < 0.5 else (110, 104, 56)) if not snow \
                    else ((120, 100, 72) if rng.random() < 0.5 else (92, 78, 60))   # (dead stalks up through the snow)
                for j in range(hgt):
                    yy, xx = y - j, x + dx + (j * np.sign(dx) if hgt > 2 else 0)
                    if 0 <= yy < H and 0 <= xx < W:
                        out[yy, xx] = col

    meta[key] = dict(ground_files(out, key), origin=[-ox, -oy])
    meta["tex_scale"] = 1.0 / K


MAX_TEX = 8192   # the widest texture an older card takes (DX10-era); newer ones take 16384


def ground_files(out, key):
    """Save a baked ground: one file, or, wider than MAX_TEX, side-by-side strips of it
    ("strips": [[file, x], ...], with its whole "size"), which the game lays edge to edge."""
    H, W = out.shape[:2]
    n = 1 if W <= MAX_TEX else -(-W // MAX_TEX)
    keep = {f"{key}.png"} if n == 1 else {f"{key}_{i}.png" for i in range(n)}
    for old in os.listdir(os.path.join(ASSETS, "sprites")):   # (the whole, or strips, of an earlier bake cut otherwise)
        png = old.removesuffix(".import")
        rest = png[len(key):].removesuffix(".png")
        if png.startswith(key) and png.endswith(".png") and (rest == "" or (rest[:1] == "_" and rest[1:].isdigit())) \
                and png not in keep:
            os.remove(os.path.join(ASSETS, "sprites", old))
    if n == 1:
        return {"file": _compressed(save(out, f"sprites/{key}.png"))}
    step = -(-W // n)
    strips = [[_compressed(save(out[:, x:x + step], f"sprites/{key}_{i}.png")), x] for i, x in enumerate(range(0, W, step))]
    return {"strips": strips, "size": [W, H]}


def _compressed(res_path):
    """Have Godot import a ground compressed on the card (DXT1 on the desktop: a sixth of
    plain colour, the grain barely touched at the size it's seen), not lossless like the
    rest, whose outlines it would smear. Returns the path."""
    imp = os.path.join(ASSETS, res_path[len("res://assets/"):]) + ".import"
    if os.path.exists(imp):
        text = open(imp).read()
        text = text.replace("compress/mode=0", "compress/mode=2")
    else:
        text = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=2\nmipmaps/generate=false\n'
    open(imp, "w").write(text)
    return res_path


def gen_mgun(meta):
    """The Colt-Browning on its tripod, turned each of 16 ways (screen angles, 0 = right)."""
    meta["mgun"] = []
    for i in range(16):
        sa = i / 16 * 2 * math.pi
        sx, sy = math.cos(sa), math.sin(sa)          # a screen direction, back to the grid
        gx, gy = sx / 16 + sy / 8, sy / 8 - sx / 16
        img, anchor = render(world.mgun(math.atan2(gy, gx)), edges=True)
        meta["mgun"].append({"file": save(img, f"sprites/world/mgun_{i}.png"), "anchor": list(anchor)})


def gen_fx(meta):
    frames = []
    rng = np.random.default_rng(3)
    for f in range(3):
        im = Image.new("RGBA", (24 * PIX, 24 * PIX), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        c = 12 * PIX
        size = [10 * PIX, 8 * PIX, 5 * PIX][f]
        for i in range(7):
            a = i / 7 * math.tau + rng.uniform(-0.2, 0.2)
            r = size * rng.uniform(0.6, 1.1)
            d.line([(c, c), (c + math.cos(a) * r, c + math.sin(a) * r * 0.7)],
                   fill=(255, 170, 60, 255), width=PIX + 1)
        d.ellipse([c - size * 0.45, c - size * 0.35, c + size * 0.45, c + size * 0.35],
                  fill=(255, 236, 170, 255))
        d.ellipse([c - PIX * 1.5, c - PIX * 1.5, c + PIX * 1.5, c + PIX * 1.5], fill=(255, 255, 240, 255))
        frames.append(np.array(im))
    meta["muzzle"] = {"file": save(np.concatenate(frames, 1), "sprites/fx/muzzle.png"),
                      "cell": [24 * PIX, 24 * PIX], "frames": 3}


def paint_portrait(dress=None):
    """The stranger in the HUD's corner, painted like the eyes close-up: head and
    shoulders against a dusk sky, the flat brim pulled low so its shadow takes his
    eyes, light from the left, stubble, the cigar in the corner of his mouth, the
    duster's collar and the bandolier across it. Laid out on the HUD's 40x40 box.
    `dress`: a level's own colours for him (levels.json's "stranger"), over his usual."""
    pal = {k: np.array(v, float) for k, v in {**chars._DATA["player"]["palette"], **(dress or {})}.items()}
    K = UI_PIX
    S = 40 * K
    rng = np.random.default_rng(23)
    v, u = (np.mgrid[0:S, 0:S].astype(float) + 0.5) / K
    fine = rng.random((S, S))
    felt = noise2(S, S, 3 * K, 3)
    lit = lambda a, b: np.clip(1.12 - 0.42 * (u - a) / (b - a), 0.6, 1.15)[..., None]   # sun from the left
    # the sky: dusk going down behind the hills
    img = (np.array([168, 92, 48], float) * (1 - v / 40)[..., None]
           + np.array([92, 44, 30], float) * (v / 40)[..., None])
    sun = np.hypot(u - 6, v - 23.5) < 3.6
    img[sun] = img[sun] * 0.5 + np.array([236, 186, 110]) * 0.5
    hills = v > 28.5 + 1.6 * np.sin(u / 4.3) + 0.8 * np.sin(u / 1.7)
    img[hills] = (70, 36, 28)
    fig = np.zeros((S, S), bool)

    def put(mask, col):
        img[mask] = col[mask] if np.ndim(col) == 3 else col
        fig[mask] = True

    # shoulders: the duster, its collar turned up, the shirt in the V
    sh = (v > 28.6) & (np.abs(u - 20) < 8.5 + (v - 28.6) * 2.6)
    put(sh, pal["coat"] * lit(8, 34) * (0.92 + 0.12 * felt)[..., None])
    vee = sh & (np.abs(u - 20) < (v - 29.5) * 0.42 + 1.4)
    put(vee, pal["shirt"] * lit(16, 25) * 0.9)
    lapel = sh & ~vee & (np.abs(u - 20) < (v - 29.5) * 0.42 + 2.4)
    put(lapel, pal["coat"] * 0.62)
    seam = sh & (np.abs(np.abs(u - 20) - (9.2 + (v - 28.6) * 2.6)) < 0.7)   # the shoulder's edge
    put(seam, pal["coat"] * 0.55)
    # the bandolier: left shoulder down to his right hip, brass in its loops
    d = (u - 10.5) * 0.55 - (v - 30.5) * 0.83   # across the strap
    t = (u - 10.5) * 0.83 + (v - 30.5) * 0.55   # along it
    strap = sh & (np.abs(d) < 1.5) & (t > -2)
    put(strap, np.array([96, 64, 40], float) * lit(8, 34))
    shell = strap & (np.abs(d) < 0.9) & (np.mod(t, 2.0) < 1.0)
    put(shell, np.array([212, 168, 80], float) * lit(8, 34))
    # neck, in the jaw's shadow
    put((np.abs(u - 20) < 3.3) & (v > 24) & (v < 30), pal["skin"] * 0.62)
    # hair at his neck and temples, under the brim
    hair = (np.abs(u - 20) < 7.0) & (np.abs(u - 20) > 4.5) & (v > 13) & (v < 21.5)
    put(hair & (fine > 0.1), pal["hair"] * lit(13, 27))
    # the head: a long face, a hard jaw
    half = 6.0 - np.clip(v - 21.5, 0, None) * 0.42
    head = (np.abs(u - 20) < half) & (v > 11) & (v < 28.2) & (((v - 19) / 9.2) ** 2 + ((u - 20) / 6.4) ** 2 < 1.05)
    face = pal["skin"] * lit(14, 26) * (0.94 + 0.1 * felt)[..., None]
    put(head, face)
    ear = (np.hypot((u - 13.7) / 1.1, (v - 19.5) / 2.0) < 1)
    put(ear, pal["skin"] * 0.95)
    put(ear & (np.hypot((u - 13.9) / 0.5, (v - 19.6) / 1.1) < 1), pal["skin"] * 0.7)
    # the nose: its lit side, its shadowed side, the dark under it
    ridge = head & (v > 18) & (v < 23)
    put(ridge & (u > 18.4) & (u < 19.6), face * 1.14)
    put(ridge & (u >= 19.6) & (u < 21.2) & (v > 19 + (u - 19.6)), face * 0.72)
    put(head & (v >= 22.6) & (v < 23.4) & (np.abs(u - 19.8) < 1.4), face * 0.55)
    # hollow cheeks under the cheekbones
    put(head & (v > 21) & (v < 25.5) & (np.abs(u - 24.0 + (v - 21) * 0.15) < 0.8), face * 0.78)
    put(head & (v > 21) & (v < 25) & (np.abs(u - 15.7 - (v - 21) * 0.15) < 0.6), face * 0.9)
    # the mouth, a hard line, and stubble on his chin and jaw
    put(head & (np.abs(v - 25.2 - 0.12 * (u - 20)) < 0.45) & (np.abs(u - 20) < 2.6), np.array([92, 52, 40], float))
    put(head & (v > 25.6) & (v < 26.3) & (np.abs(u - 20) < 1.8), face * 1.06)
    stub = head & (v > 23.2) & (fine > 0.55) & ~(np.abs(v - 25.2) < 0.5)
    img[stub] *= 0.78
    put(head & (v > 27.0), face * 0.8)
    # the brim's shadow: everything above his nose's tip is dark, the eyes gone in it
    edge = 19.6 + 0.35 * np.sin(u * 1.3) + 0.06 * (u - 20)
    dark = fig & (v < edge) & (v > 11)
    img[dark] = img[dark] * 0.26 + np.array([26, 16, 14]) * 0.3
    soft = fig & (v >= edge) & (v < edge + 1.0)
    img[soft] *= 0.65
    # the faintest catch of light in one eye, under there
    glint = (np.hypot(u - 17.4, v - 18.0) < 0.5)
    img[glint] = (120, 96, 70)
    # the cigar from the corner of his mouth, its coal and a thread of smoke
    cd = (u - 21.6) * 0.26 - (v - 25.3) * 0.97
    ct = (u - 21.6) * 0.97 + (v - 25.3) * 0.26
    cig = (np.abs(cd) < 0.8) & (ct > 0) & (ct < 5.2)
    put(cig, np.array([150, 98, 58], float) * (1.1 - 0.3 * (cd < 0))[..., None])
    put((np.abs(cd) < 0.8) & (ct >= 5.2) & (ct < 5.9), np.array([168, 160, 150], float))
    put((np.abs(cd) < 0.7) & (ct >= 5.9) & (ct < 6.6), np.array([240, 110, 40], float))
    for i in range(14):
        sx, sy = 28.0 + 0.9 * math.sin(i * 0.7), 26.2 - i * 0.75
        m = np.hypot(u - sx, v - sy) < 0.5 + i * 0.03
        img[m] = img[m] * (0.55 + i * 0.03) + np.array([200, 190, 176]) * (0.45 - i * 0.03)
    # the hat: a flat crown, the band, the wide brim tipped down at the front
    tilt = 0.07 * (u - 20)
    crown = (np.abs(u - 20) < 7.3 - (13.5 - v) * 0.06) & (v > 4.6 + tilt * 0.5) & (v < 13.5)
    put(crown, pal["hat"] * lit(12, 28) * (0.88 + 0.22 * felt)[..., None])
    put(crown & (v < 5.8 + tilt * 0.5), pal["hat"] * 1.35 * lit(12, 28))
    put(crown & (v > 11.0) & (v < 13.2), pal["band"] * lit(12, 28))
    put(crown & (np.abs(u - 20 + 0.3 * (v - 5)) < 0.45) & (v > 6) & (v < 10.8), pal["hat"] * 0.7)   # the crease
    rim = np.hypot((u - 20) / 17.5, (v - 14.4 - tilt) / 3.2) < 1
    top = rim & (v < 14.4 + tilt)
    put(rim, pal["hat"] * 0.5 * (0.9 + 0.2 * felt)[..., None])   # the underside, towards us
    put(top & ~crown, pal["hat"] * lit(2, 38) * 1.1 * (0.88 + 0.22 * felt)[..., None])
    put(rim & (np.abs(v - 14.4 - tilt) < 0.45), pal["hat"] * 0.85 * lit(2, 38))   # the brim's edge
    # a dark outline round him, as the sprites have
    out = ~fig & (np.roll(fig, 1, 0) | np.roll(fig, -1, 0) | np.roll(fig, 1, 1) | np.roll(fig, -1, 1))
    img[out] = img[out] * 0.4 + np.array([24, 14, 12]) * 0.6
    img = (np.floor(np.clip(img, 0, 255) / 12) * 12).astype(np.uint8)
    return np.dstack([img, np.full((S, S), 255, np.uint8)])


def gen_ui(meta):
    meta["ui"] = {}
    # portrait
    meta["ui"]["portrait"] = save(paint_portrait(), "sprites/ui/portrait.png")
    # and one for each level that dresses him differently, so the corner matches the man
    meta["ui"]["portraits"] = {}
    for lv in json.load(open(os.path.join(ROOT, "data", "levels.json")))["levels"]:
        if "stranger" in lv:
            meta["ui"]["portraits"][lv["id"]] = save(paint_portrait(lv["stranger"]), "sprites/ui/portrait_%s.png" % lv["id"])
    # the guns the stranger can carry, side-on, for the loadout screen (Player.SLOT)
    meta["ui"]["guns"] = {}
    for kind in ("colts", "colt", "buntline", "schofield", "navy", "howdah", "derringer", "pistola", "coach", "spencer82", "sawnoff", "champion", "escopeta", "colt55", "rifle", "henry", "spencer",
                 "springfield", "rollingblock", "remington", "sharps"):
        L = chars.GUN_LEN[kind]
        d = np.array([1.0, -1.0, 0.0]) / math.sqrt(2)   # along the screen, muzzle to the right
        base = PIX * (2.4 if kind in chars.PISTOLS else 1.2)
        w = render(chars.weapon_model(kind, -d * L / 2, d), scale=base, shadow=False)[0].shape[1]
        # the card shows it up to 140 points wide (and never past twice this size); bake it
        # at just the screen pixels that makes, sampled that much finer, so it stands sharp
        k = min(2.0, 140.0 / w) * UI_PIX
        render3d.PIX = PIX * k
        try:
            model = chars.weapon_model(kind, -d * L / 2, d, detail=True)
        finally:
            render3d.PIX = PIX
        img, _ = render(model, scale=base * k, shadow=False, pad=round(6 * k))
        meta["ui"]["guns"][kind] = save(img, f"sprites/ui/gun_{kind}.png")

    # extreme close-up of the hero's eyes
    K = UI_PIX
    W, H = 320 * K, 64 * K
    rng = np.random.default_rng(11)
    yy, xx = np.mgrid[0:H, 0:W].astype(float) / K
    n = noise2(H, W, 10 * K, 4)
    fine = rng.random((H, W))
    skin = np.array([186, 126, 88], float)
    img = skin * (0.82 + 0.25 * n + 0.06 * fine)[..., None]
    # cheek/nose shading
    nose = np.exp(-((xx - 160) / 16) ** 2) * np.clip((yy - 20) / 44, 0, 1)
    img = img * (1 + 0.12 * nose[..., None])
    side = np.clip(np.abs(xx - 160) / 160, 0, 1) ** 2
    img *= (1 - 0.35 * side)[..., None]
    # hat brim shadow
    brim = 13 + 3 * np.sin(xx / 47) + (fine > 0.6)
    shadow = yy < brim
    img[shadow] = img[shadow] * 0.32 + np.array([30, 20, 18]) * 0.2
    edge = (yy >= brim) & (yy < brim + 4)
    img[edge] *= 0.7
    for cx in (98, 222):
        flip = 1 if cx > 160 else -1
        ex = (xx - cx) / 30
        ey = (yy - 37) / 7.5
        # almond eye shape, squinting: the upper lid is low
        upper = -0.55 + 0.75 * ex ** 2
        lower = 1.0 - 1.0 * ex ** 2
        eye = (np.abs(ex) < 1) & (ey > upper) & (ey < lower)
        white = np.array([214, 196, 170], float) * (0.85 + 0.15 * (1 - np.abs(ex)))[..., None]
        img[eye] = white[eye]
        ir = np.hypot(xx - (cx - 3 * flip), yy - 37)
        iris = eye & (ir < 6.5)
        img[iris] = np.array([86, 96, 70]) * (0.8 + 0.3 * fine[iris])[:, None]
        img[eye & (ir < 2.8)] = (16, 12, 10)
        img[eye & (np.hypot(xx - (cx - 3 * flip) - 2, yy - 35) < 1.2)] = (240, 236, 220)
        lid_shadow = eye & (ey < upper + 0.35)
        img[lid_shadow] *= 0.6
        lid = (np.abs(ex) < 1.08) & (np.abs(ey - upper) < 0.22)
        img[lid] = (52, 30, 24)
        low = (np.abs(ex) < 0.9) & (np.abs(ey - lower) < 0.13)
        img[low] = img[low] * 0.7
        # heavy brow
        by = 24 + 3 * ex ** 2 - 2 * flip * ex
        brow = (np.abs(ex) < 1.15) & (np.abs(yy - by) < 2.6 - np.abs(ex)) & (fine > 0.15)
        img[brow] = np.array([54, 38, 30]) * (0.8 + 0.4 * fine[brow])[:, None]
        # crow's feet
        for k in (-1, 0, 1):
            ang = k * 0.35
            for t in range(10 * K):
                x = int((cx + flip * (33 + t / K)) * K)
                y = int((37 + k * 2 + math.sin(ang) * t / K) * K)
                if 0 <= x < W and 0 <= y < H:
                    img[y, x] *= 0.72
    stub = (yy > 50) & (fine > 0.7)
    img[stub] *= 0.75
    grime = n > 0.72
    img[grime] *= 0.88
    sweat = (fine > 0.9985) & (yy > 18)
    img[sweat] = (236, 220, 196)
    # posterise to a pixel-art palette
    img = (np.floor(np.clip(img, 0, 255) / 12) * 12).astype(np.uint8)
    rgba = np.dstack([img, np.full((H, W), 255, np.uint8)])
    meta["ui"]["eyes"] = save(rgba, "sprites/ui/eyes.png")

    # title in the style of opening credits
    font = None
    for idx in range(6):
        try:
            f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Rockwell.ttc", 54 * UI_PIX, index=idx)
        except Exception:
            break
        if "Bold" in " ".join(f.getname()) and "Italic" not in " ".join(f.getname()):
            font = f
            break
    if font is None:
        font = ImageFont.load_default()
    text = "SUNDANCE"
    tmp = Image.new("L", (600 * UI_PIX, 120 * UI_PIX), 0)
    d = ImageDraw.Draw(tmp)
    d.fontmode = "1"
    d.text((10, 10), text, font=font, fill=255)
    bb = tmp.getbbox()
    mask = np.array(tmp.crop(bb)) > 128
    h, w = mask.shape
    sd = 2 * UI_PIX
    out = np.zeros((h + 3 * sd, w + 3 * sd, 4), np.uint8)
    grad = np.linspace(0, 1, h)[:, None]
    col = np.array([236, 196, 88]) * (1 - grad[..., None]) + np.array([200, 60, 30]) * grad[..., None]
    col = np.broadcast_to(col, (h, w, 3))
    sh = np.zeros((h + 3 * sd, w + 3 * sd), bool)
    sh[2 * sd:2 * sd + h, 2 * sd:2 * sd + w] = mask
    out[sh] = (70, 14, 10, 255)
    region = out[sd // 2:sd // 2 + h, sd // 2:sd // 2 + w]
    region[mask] = np.dstack([col.astype(np.uint8), np.full((h, w), 255, np.uint8)])[mask]
    meta["ui"]["title"] = save(out, "sprites/ui/title.png")


# ---------------------------------------------------------------- sound

def lowpass(x, fc):
    a = math.exp(-2 * math.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    b = 1 - a
    for i in range(len(x)):
        acc = b * x[i] + a * acc
        y[i] = acc
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def t_of(dur):
    return np.arange(int(SR * dur)) / SR


def delay(x, sec, gain, fc=None):
    k = int(SR * sec)
    y = np.zeros(len(x) + k)
    src = lowpass(x, fc) if fc else x
    y[k:] = src * gain
    y[:len(x)] += x
    return y


def write(name, x, meta, peak=0.9, drive=1.0):
    """Write a mono (n,) or stereo (n, 2) clip, normalised to `peak`. drive > 1
    soft-clips it first for a louder, denser sound."""
    x = np.asarray(x, float)
    m = np.abs(x).max()
    if m > 0:
        x = x / m
    if drive > 1.0:
        x = np.tanh(x * drive) / np.tanh(drive)
    x = x * peak
    path = os.path.join(ASSETS, "sfx", name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    meta["sfx"][name] = "res://assets/sfx/" + name + ".wav"


def convolve(x, h):
    n = len(x) + len(h) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(h, N), N)[:n]


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def canyon_ir(rng, tau, echoes=(), dur=None):
    """Outdoor reverb: a diffuse tail that darkens as it decays, plus discrete
    slap-back echoes off distant walls and mesas."""
    dur = dur or tau * 4
    t = t_of(dur)
    n = rng.normal(0, 1, len(t))
    bright = highpass(n, 1500) * np.exp(-t / (tau * 0.25))
    dark = lowpass(n, 700) * np.exp(-t / tau) * 2.2
    h = 0.35 * bright + dark
    h[:int(SR * 0.012)] *= np.linspace(0, 1, int(SR * 0.012))
    for d, g, fc in echoes:
        k = int(SR * d)
        burst = lowpass(rng.normal(0, 1, int(SR * 0.06)), fc) * np.exp(-t_of(0.06) / 0.015)
        if k + len(burst) < len(h):
            h[k:k + len(burst)] += burst * g * 6
    h[0] = 0
    return h / np.abs(h).sum() * 40


def modal(rng, freqs, decays, amps, dur):
    """Struck-metal resonance: a bank of damped, slightly detuned partials."""
    t = t_of(dur)
    out = np.zeros(len(t))
    for f, d, a in zip(freqs, decays, amps):
        f *= rng.uniform(0.97, 1.03)
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return out


def metal(rng, base, weight=1.0, dur=0.12):
    """A steel-on-steel click as it really sounds: a sub-millisecond strike through
    a dense cluster of short, inharmonic high modes, so no single pitch is heard,
    plus a dull knock from the frame. weight > 1 is heavier: lower, a little
    longer, more knock."""
    t = t_of(dur)
    nm = 32
    freqs = base * rng.uniform(0.7, 3.4, nm) / weight
    freqs = np.minimum(freqs, 16000)
    decays = rng.uniform(0.0008, 0.004, nm) * weight
    amps = rng.uniform(0.2, 1.0, nm) / math.sqrt(nm)
    x = np.zeros(len(t))
    for f, d, a in zip(freqs, decays, amps):
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    n = rng.normal(0, 1, len(t))
    x += highpass(n, 2500) * np.exp(-t / 0.00035) * 1.2
    x += lowpass(rng.normal(0, 1, len(t)), 1100 / weight) * np.exp(-t / (0.0025 * weight)) * 0.7 * weight
    return x


def tink(rng, center, ring, amp=1.0, dur=0.12):
    """Brass or a spur rowel struck lightly: a cluster of close, inharmonic partials
    around `center` that shimmer instead of beeping."""
    t = t_of(dur)
    x = np.zeros(len(t))
    for i in range(10):
        f = center * rng.uniform(0.65, 1.7)
        x += rng.uniform(0.3, 1.0) * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (ring * rng.uniform(0.3, 1.0)))
    x += highpass(rng.normal(0, 1, len(t)), 3000) * np.exp(-t / 0.0004) * 1.5
    return x * amp / 4


def knock(rng, fc, tau, dur=0.08):
    """Wood or a heavy frame taking the blow: a short, dull, unpitched thud."""
    t = t_of(dur)
    return lowpass(lowpass(rng.normal(0, 1, len(t)), fc), fc) * np.exp(-t / tau) * 3


def room(x, rng, tau=0.07, wet=0.3):
    w = convolve(x, canyon_ir(rng, tau)) * wet
    w[:len(x)] += x
    return w


def gun_ir(rng, tau, echoes, dur):
    """Canyon reverb for gunfire: a diffuse wash that swells and dies slowly, plus
    discrete slap-back echoes off the mesas, each darker than the last."""
    t = t_of(dur)
    h = lowpass(rng.normal(0, 1, len(t)), 1600) * np.exp(-t / tau) * (1 - np.exp(-t / 0.04)) * 0.012
    for d, g, fc in echoes:
        k = int(SR * d)
        n = int(SR * 0.05)
        burst = lowpass(rng.normal(0, 1, n), fc) * np.exp(-t_of(0.05) / 0.01)
        if k + n < len(h):
            h[k:k + n] += burst * g * 0.06
    return h


def gunshot(rng, crack, blast_fc, blast_tau, boom_fc, boom_tau, sub_f, drive, tau, delay_scale):
    """Spaghetti-western gunshot, in stereo: a hard crack, a saturated powder
    blast and a low boom, then a long canyon tail whose echoes bounce left and
    right. All noise, no pitched sweeps."""
    t = t_of(0.7)
    n = rng.normal(0, 1, len(t))
    c = highpass(n, 3000) * np.exp(-t / crack)
    c[:int(SR * 0.0007)] += 5.0
    blast = lowpass(n, blast_fc) * np.exp(-t / blast_tau) * 2.0
    boom = lowpass(rng.normal(0, 1, len(t)), boom_fc) * np.exp(-t / boom_tau) * 3.5
    sub = np.sin(2 * np.pi * sub_f * t) * np.exp(-t / 0.12) * (1 - np.exp(-t / 0.003)) * 1.4
    dry = 1.3 * c + blast + boom + sub
    dry = np.tanh(dry / np.abs(dry).max() * drive)
    dur = 3.6
    ds = delay_scale
    left = convolve(dry, gun_ir(rng, tau, [(0.27 * ds, 1.0, 2400), (0.63 * ds, 0.6, 1500),
                                           (1.04 * ds, 0.36, 1000), (1.5 * ds, 0.2, 700)], dur))
    right = convolve(dry, gun_ir(rng, tau, [(0.36 * ds, 0.9, 2200), (0.8 * ds, 0.5, 1300),
                                            (1.24 * ds, 0.3, 900), (1.75 * ds, 0.16, 600)], dur))
    wet = np.stack([left, right], 1)
    wet = wet / np.abs(wet).max() * 0.6
    out = wet.copy()
    out[:len(dry)] += dry[:, None] * [1.0, 0.94]
    return out


def steps_crunch(rng):
    out = np.zeros(int(SR * 0.12))
    for i in range(7):
        k = int(rng.uniform(0, 0.07) * SR)
        g = bandpass(rng.normal(0, 1, int(SR * 0.01)), 700, 3000) * np.exp(-t_of(0.01) / 0.002)
        out[k:k + len(g)] += g * rng.uniform(0.3, 1.0)
    out += lowpass(rng.normal(0, 1, len(out)), 300) * np.exp(-t_of(0.12) / 0.02) * 0.6
    return out


def place(total, parts):
    out = np.zeros(int(SR * total))
    for start, sig in parts:
        k = int(SR * start)
        n = min(len(sig), len(out) - k)
        out[k:k + n] += sig[:n]
    return out


def karplus(rng, f, dur, decay=0.996, bright=0.5):
    n = int(SR * dur)
    p = int(SR / f)
    buf = rng.uniform(-1, 1, p)
    buf = lowpass(buf, 4000 * bright + 400)
    out = np.empty(n)
    for i in range(n):
        j = i % p
        out[i] = buf[j]
        buf[j] = decay * 0.5 * (buf[j] + buf[(j + 1) % p])
    return out


def spring(x):
    for d, g in ((0.045, 0.35), (0.083, 0.25), (0.131, 0.18), (0.19, 0.12)):
        x = delay(x, d, g, 2500)
    return x


def gen_sfx(meta):
    meta["sfx"] = {}
    rng = np.random.default_rng(5)
    print("  sfx")
    # newer guns get their own random streams, so the others stay exactly as they were
    drng, srng, hrng = (np.random.default_rng(s) for s in (77, 78, 79))
    # Three takes of each gun so repeated shots don't sound identical.
    mrng = np.random.default_rng(1895)   # (the machine gun's own: the rest come out as they were)
    for i in range(3):
        write("mg" + ("" if i == 0 else "_%d" % (i + 1)),   # the Colt-Browning: a short hard crack, quick to die
              gunshot(mrng, 0.0016, 3900, 0.02, 300, 0.06, 72, 3.2, 0.55, mrng.uniform(0.95, 1.05)), meta, 0.95, 1.5)
    for i in range(3):
        sfx = "" if i == 0 else "_%d" % (i + 1)
        j = rng.uniform(0.92, 1.08)
        write("colt" + sfx, gunshot(rng, 0.0025, 2600, 0.035, 220, 0.12, 55, 3.0, 0.9, j), meta, 0.98, 1.6)
        write("rifle" + sfx, gunshot(rng, 0.0018, 3600, 0.03, 260, 0.1, 62, 3.0, 1.1, 1.15 * j), meta, 0.98, 1.6)
        write("coach" + sfx, gunshot(rng, 0.004, 1500, 0.09, 150, 0.26, 44, 3.6, 1.3, 1.05 * j), meta, 0.98, 1.8)
        # the derringer: a short, flat pop with little behind it
        write("derringer" + sfx, gunshot(drng, 0.0015, 3200, 0.018, 320, 0.05, 90, 2.4, 0.7, 0.9 * j), meta, 0.8, 1.4)
        # the Sharps: a deep, heavy buffalo-gun boom that rolls a long way
        write("sharps" + sfx, gunshot(srng, 0.0022, 2200, 0.055, 190, 0.18, 46, 3.4, 1.5, 1.3 * j), meta, 0.98, 1.8)
        # the howdah: a hand cannon, short and thunderous
        write("howdah" + sfx, gunshot(hrng, 0.003, 1700, 0.07, 165, 0.21, 44, 3.6, 1.1, j), meta, 0.98, 1.8)

    t = t_of(0.7)
    f = 3600 * np.exp(-t / 0.45) + 900
    vib = 1 + 0.025 * np.sin(2 * np.pi * 38 * t)
    ric = np.sin(2 * np.pi * np.cumsum(f * vib) / SR)
    ric += 0.4 * np.sin(2 * np.pi * np.cumsum(f * 1.51 * vib) / SR)
    ric *= np.minimum(1, t / 0.004) * np.exp(-t / 0.25)
    ric += highpass(rng.normal(0, 1, len(t)), 2500) * np.exp(-t / 0.006)
    write("ricochet", room(ric, rng, 0.4, 0.5), meta, 0.5)

    def thunk(f, tau, dur=0.12):
        tt = t_of(dur)
        return lowpass(rng.normal(0, 1, len(tt)), f) * np.exp(-tt / tau)

    def rasp(dur, lo, hi):
        n = int(SR * dur)
        return bandpass(rng.normal(0, 1, n), lo, hi) * np.sin(np.linspace(0, np.pi, n)) ** 0.5

    # Colt SAA: thumbing the hammer gives the four famous clicks ("C-O-L-T"),
    # the last one the heavy click of the sear locking.
    cock = place(0.2, [(0.0, metal(rng, 3200) * 0.6), (0.03, metal(rng, 2900) * 0.65),
                       (0.058, metal(rng, 3300) * 0.7),
                       (0.095, metal(rng, 2300, 1.6) * 1.3 + thunk(900, 0.012) * 0.8)])
    write("cock", room(cock, rng, 0.05, 0.25), meta, 0.85, 1.5)
    # Hammer falling on an empty chamber or a spent case: a hollow, final clack.
    dry = place(0.2, [(0.0, metal(rng, 1500, 2.0) * 1.2 + thunk(700, 0.02) * 1.5)])
    write("dry", room(dry, rng, 0.06, 0.3), meta, 0.9, 1.8)
    # The Colt's loading gate flipped open at half-cock.
    write("gate", room(place(0.12, [(0, metal(rng, 2700, 1.1)), (0.01, rasp(0.04, 2000, 5000) * 0.4)]), rng),
          meta, 0.7, 1.4)
    # Winchester lever: action thrown open with a rasp, then slammed shut.
    lever = place(0.34, [(0.0, metal(rng, 1400, 1.9) * 1.1 + thunk(800, 0.015)),
                         (0.012, rasp(0.09, 1200, 4500) * 0.6),
                         (0.17, metal(rng, 1150, 2.3) * 1.5 + thunk(500, 0.025) * 1.3),
                         (0.17, knock(rng, 600, 0.012))])
    write("lever", room(lever, rng, 0.06, 0.25), meta, 0.92, 1.6)
    # A cartridge pushed home past the loading gate.
    shell = place(0.14, [(0, rasp(0.05, 2500, 6500) * 0.7), (0.05, metal(rng, 3700, 0.9) + thunk(1500, 0.006) * 0.6)])
    write("shell_in", room(shell, rng, 0.05, 0.2), meta, 0.75, 1.4)
    # Ejector rod, then the brass case tinkling onto the boards.
    parts = [(0.0, metal(rng, 2200) * 0.8)]
    for st, a in ((0.11, 1.0), (0.19, 0.55), (0.24, 0.3), (0.27, 0.15)):
        parts.append((st, tink(rng, 5200, 0.015, a)))
    write("eject", room(place(0.45, parts), rng), meta, 0.65, 1.3)
    # Coach gun: hinge creak and clack breaking open, a solid snap closing.
    creak = rasp(0.12, 500, 1800) * (0.6 + 0.4 * np.sin(np.linspace(0, 40, int(SR * 0.12))))
    write("break_open", room(place(0.25, [(0, metal(rng, 900, 2.4) * 1.3 + thunk(400, 0.03)),
                                          (0.03, creak * 0.5)]), rng), meta, 0.88, 1.6)
    write("close", room(place(0.22, [(0, metal(rng, 800, 2.8) * 1.6 + thunk(350, 0.04) * 1.5),
                                     (0.004, knock(rng, 400, 0.015))]), rng),
          meta, 0.92, 1.7)
    t = t_of(0.15)
    thud = lowpass(rng.normal(0, 1, len(t)), 450) * np.exp(-t / 0.025) * 2
    thud += np.sin(2 * np.pi * (110 + 80 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.05)
    write("hit", room(thud, rng, 0.1, 0.2), meta, 0.9, 1.5)
    write("pickup", room(place(0.3, [(0, tink(rng, 4500, 0.01)), (0.06, tink(rng, 5000, 0.01, 0.8)),
                                     (0.1, tink(rng, 4800, 0.008, 0.5))]), rng), meta, 0.6)
    write("step", steps_crunch(rng), meta, 0.45)
    # Spurs: the rowels jingle as he walks.
    spur = place(0.2, [(st, tink(rng, 6500, 0.005, a, 0.06)) for st, a in ((0.0, 1.0), (0.03, 0.6), (0.055, 0.35))])
    write("spur", spur, meta, 0.4)

    # church bell
    def bell(f0, dur):
        t = t_of(dur)
        s = np.zeros(len(t))
        for ratio, amp, tau in ((0.5, 0.5, 4.0), (1.0, 1.0, 3.0), (1.19, 0.6, 2.4), (1.5, 0.35, 1.8),
                                (2.0, 0.5, 1.5), (2.52, 0.25, 1.0), (3.0, 0.2, 0.8), (4.2, 0.12, 0.5)):
            s += amp * np.sin(2 * np.pi * f0 * ratio * t + rng.uniform(0, 6)) * np.exp(-t / tau)
        s += lowpass(rng.uniform(-1, 1, len(t)), 2000) * np.exp(-t / 0.01) * 0.6
        return s
    tolls = place(6.5, [(0, bell(196, 5)), (1.9, bell(196, 4.5))])
    write("bell", room(tolls, rng, 0.8, 0.35)[:int(SR * 7)], meta, 0.7)

    # wind loop
    dur = 8.0
    t = t_of(dur)
    nz = lowpass(rng.uniform(-1, 1, len(t)), 380)
    gust = 0.55 + 0.3 * np.sin(2 * np.pi * t / dur) + 0.15 * np.sin(2 * np.pi * 3 * t / dur + 1)
    whistle = np.sin(2 * np.pi * np.cumsum(620 + 60 * np.sin(2 * np.pi * 2 * t / dur)) / SR) * 0.02 * gust ** 3
    w = nz * gust + whistle
    k = int(SR * 1.0)
    fade = np.linspace(0, 1, k)
    w[:k] = w[:k] * fade + w[-k:] * (1 - fade)
    w = w[:-k]
    write("wind", w, meta, 0.35)

    # spaghetti twang: low E with tremolo and spring reverb
    tw = karplus(rng, 82.4, 2.2, 0.9985, 0.8)
    tw += karplus(rng, 164.8, 2.2, 0.998, 0.6) * 0.5
    tw *= 1 + 0.35 * np.sin(2 * np.pi * 6 * t_of(2.2))
    write("twang", spring(tw), meta, 0.7)

    # sting for the close-up: whistle glide + low guitar
    t = t_of(2.4)
    f = np.where(t < 0.35, 494 + (659 - 494) * (t / 0.35) ** 2, 659)
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.5) / 0.4, 0, 1)
    wh = np.sin(2 * np.pi * np.cumsum(f * vib) / SR)
    wh += 0.15 * np.sin(2 * 2 * np.pi * np.cumsum(f * vib) / SR)
    env = np.minimum(1, t / 0.05) * np.where(t > 1.8, np.exp(-(t - 1.8) / 0.2), 1)
    wh = wh * env + highpass(rng.uniform(-1, 1, len(t)), 3000) * env * 0.02
    sting = wh * 0.6 + np.pad(karplus(rng, 82.4, 2.4, 0.9985, 0.8), (0, 0))[:len(t)] * 0.7
    write("sting", spring(sting), meta, 0.75)

    # win: strummed E minor + whistle
    parts = []
    for i, fr in enumerate((82.4, 123.5, 164.8, 196.0, 246.9, 329.6)):
        parts.append((i * 0.06, karplus(rng, fr, 3.0, 0.9988, 0.7) * 0.6))
    t = t_of(1.6)
    whf = np.where(t < 0.2, 659 + (988 - 659) * t / 0.2, 988)
    wh = np.sin(2 * np.pi * np.cumsum(whf * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * t))) / SR)
    wh *= np.minimum(1, t / 0.05) * np.exp(-np.maximum(t - 1.0, 0) / 0.25)
    parts.append((0.6, wh * 0.4))
    write("win", spring(place(3.4, parts)), meta, 0.75)

    # lose: falling low strings
    parts = [(i * 0.4, karplus(rng, fr, 2.2, 0.998, 0.5)) for i, fr in enumerate((110, 98, 82.4, 73.4))]
    write("lose", spring(place(3.6, parts)), meta, 0.75)
    # Shutters slammed: a short creak of the hinges, the first leaf banging home and
    # the second right after it.
    hinge = rasp(0.1, 600, 2200) * (0.6 + 0.4 * np.sin(np.linspace(0, 30, int(SR * 0.1))))
    write("shutter", room(place(0.5, [(0, hinge * 0.35),
                                      (0.09, knock(rng, 260, 0.03, 0.12) * 1.6 + thunk(180, 0.05) * 1.4),
                                      (0.17, knock(rng, 300, 0.025, 0.12) * 1.2 + thunk(200, 0.04))]), rng, 0.09, 0.4),
          meta, 0.85, 1.4)
    # A round into wood: a dry crack and a spray of splinters.
    write("wood_hit", room(place(0.25, [(0, knock(rng, 1400, 0.012, 0.12) * 1.4 + thunk(900, 0.015)),
                                        (0.006, rasp(0.06, 2500, 7000) * 0.5)]), rng, 0.05, 0.25), meta, 0.7, 1.4)
    # A crate, barrel or wagon giving way: boards cracking and clattering down.
    parts = [(0.0, knock(rng, 600, 0.03, 0.12) * 1.6 + thunk(300, 0.05) * 1.4)]
    for st in (0.08, 0.15, 0.21, 0.3, 0.38):
        parts.append((st, knock(rng, rng.uniform(700, 1500), 0.015, 0.08) * rng.uniform(0.5, 1.0)))
    write("wood_break", room(place(0.6, parts), rng, 0.08, 0.35), meta, 0.85, 1.5)

    # Dynamite (its own stream, so everything above stays as it was). The fuse: a
    # dry fizz with sputters and crackles, long enough for the whole burn.
    xrng = np.random.default_rng(91)
    t = t_of(3.6)
    fizz = bandpass(xrng.normal(0, 1, len(t)), 2500, 9000) * np.clip(0.6 + lowpass(xrng.normal(0, 1, len(t)), 6) * 20, 0.2, 1.2)
    for st in np.sort(xrng.uniform(0, 3.5, 40)):
        k = int(SR * st)
        n = int(SR * 0.012)
        fizz[k:k + n] += highpass(xrng.normal(0, 1, n), 3000) * np.exp(-t_of(0.012) / 0.003) * xrng.uniform(1.5, 4)
    fizz *= np.minimum(1, t / 0.05) * np.minimum(1, (t[-1] - t) / 0.05)
    write("fuse", fizz, meta, 0.45)
    # The blast: a hard crack, a long saturated roar and a deep thump that rolls
    # round the canyon for seconds, in stereo like the guns.
    t = t_of(1.6)
    n = xrng.normal(0, 1, len(t))
    crack = highpass(n, 2500) * np.exp(-t / 0.006)
    crack[:int(SR * 0.001)] += 6.0
    roar = lowpass(n, 900) * np.exp(-t / 0.22) * 2.5
    rumble = lowpass(xrng.normal(0, 1, len(t)), 140) * np.exp(-t / 0.55) * 6.0
    sub = np.sin(2 * np.pi * (30 + 40 * np.exp(-t / 0.08)) * t) * np.exp(-t / 0.35) * (1 - np.exp(-t / 0.004)) * 2.0
    dry = np.tanh((1.2 * crack + roar + rumble + sub) / np.abs(1.2 * crack + roar + rumble + sub).max() * 4.0)
    left = convolve(dry, gun_ir(xrng, 2.2, [(0.4, 1.0, 1600), (0.95, 0.6, 1000), (1.6, 0.35, 700), (2.3, 0.2, 500)], 4.6))
    right = convolve(dry, gun_ir(xrng, 2.2, [(0.52, 0.9, 1500), (1.15, 0.5, 900), (1.85, 0.3, 650), (2.6, 0.16, 450)], 4.6))
    wet = np.stack([left, right], 1)
    wet = wet / np.abs(wet).max() * 0.7
    boom = wet.copy()
    boom[:len(dry)] += dry[:, None] * [1.0, 0.95]
    write("boom", boom, meta, 0.98, 1.6)

    # Breakables (again their own stream). Glass: a bright crash, then shards
    # tinkling down for a moment.
    grng = np.random.default_rng(92)
    t = t_of(0.08)
    crash = highpass(grng.normal(0, 1, len(t)), 3500) * np.exp(-t / 0.018) * 2.0
    parts = [(0.0, crash), (0.0, tink(grng, 5800, 0.02, 1.0))]
    for st in np.sort(grng.uniform(0.02, 0.5, 14)):
        parts.append((st, tink(grng, grng.uniform(4200, 8200), grng.uniform(0.006, 0.02), grng.uniform(0.2, 0.8))))
    write("glass", room(place(0.7, parts), grng, 0.05, 0.25), meta, 0.7, 1.3)
    # Crockery: a dull clay crack and the pieces knocking down, and a splash.
    parts = [(0.0, knock(grng, 900, 0.02, 0.05) * 1.6 + highpass(grng.normal(0, 1, int(SR * 0.05)), 1500)
              * np.exp(-t_of(0.05) / 0.012))]
    for st in np.sort(grng.uniform(0.04, 0.35, 6)):
        parts.append((st, knock(grng, grng.uniform(1200, 2400), 0.01, 0.06) * grng.uniform(0.3, 0.8)))
    splash = lowpass(grng.normal(0, 1, int(SR * 0.3)), 2500) * np.exp(-t_of(0.3) / 0.08) * 0.5
    parts.append((0.03, splash))
    write("crock", room(place(0.6, parts), grng, 0.06, 0.3), meta, 0.75, 1.3)
    # Hens: a contented cluck, and a panicked squawk (a harsh rising "bawk!").
    hrng2 = np.random.default_rng(93)

    def bawk(f0, f1, dur, rough):
        t = t_of(dur)
        f = f0 + (f1 - f0) * np.sin(np.pi * np.minimum(t / dur, 1.0)) ** 0.7
        ph = 2 * np.pi * np.cumsum(f) / SR
        s = sum(np.sin(ph * k) / k ** 0.8 for k in range(1, 9))
        s *= 1 + rough * lowpass(hrng2.normal(0, 1, len(t)), 300) * 6
        s = bandpass(s, 400, 4000)
        return s * np.minimum(1, t / 0.01) * np.exp(-np.maximum(t - dur * 0.6, 0) / (dur * 0.2))
    clk = place(0.45, [(0.0, bawk(330, 380, 0.07, 0.3)), (0.13, bawk(320, 360, 0.06, 0.3)),
                       (0.24, bawk(360, 460, 0.12, 0.4))])
    write("cluck", room(clk, hrng2, 0.04, 0.2), meta, 0.5, 1.2)
    sq = place(0.7, [(0.0, bawk(500, 1050, 0.16, 0.9)), (0.2, bawk(620, 1250, 0.3, 1.0)),
                     (0.52, bawk(560, 900, 0.12, 0.8))])
    sq += np.pad(highpass(hrng2.normal(0, 1, int(SR * 0.4)), 2000) * np.exp(-t_of(0.4) / 0.1) * 0.15,
                 (0, len(sq) - int(SR * 0.4)))   # wings beating
    write("squawk", room(sq, hrng2, 0.05, 0.25), meta, 0.6, 1.4)
    # Cloth torn for a bandage: a ragged rip in a few quick jerks.
    trng = np.random.default_rng(94)
    parts = []
    for st, dur in ((0.0, 0.12), (0.16, 0.09), (0.28, 0.16)):
        n = int(SR * dur)
        rip = bandpass(trng.normal(0, 1, n), 900, 6000) * (0.5 + 0.5 * (trng.random(n) < 0.35))
        parts.append((st, rip * np.sin(np.linspace(0, np.pi, n)) ** 0.6))
    write("tear", room(place(0.5, parts), trng, 0.04, 0.2), meta, 0.6, 1.3)
    # The town's odd-job men. A hammer driving a nail home: three sharp knocks.
    wrng = np.random.default_rng(95)
    parts = [(st, knock(wrng, 1800, 0.008, 0.05) * 1.4 + tink(wrng, 2600, 0.01, 0.4, 0.05)) for st in (0.0, 0.22, 0.4)]
    write("hammer", room(place(0.6, parts), wrng, 0.05, 0.3), meta, 0.6, 1.3)
    # A broom across the dirt: a soft, dry swish.
    n = int(SR * 0.45)
    sw = bandpass(wrng.normal(0, 1, n), 1500, 7000) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
    write("sweep", sw, meta, 0.35, 1.0)
    # A wounded man groaning in the dirt: a low, breathy "uhhh" that sags.
    grng2 = np.random.default_rng(96)
    t = t_of(0.9)
    f = 125 * (1 - 0.18 * t / 0.9) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    v = sum(np.sin(ph * k) / k ** 1.2 for k in range(1, 12))
    v = bandpass(v, 200, 1400) + bandpass(grng2.normal(0, 1, len(t)), 300, 2500) * 0.25
    v *= np.minimum(1, t / 0.15) * np.exp(-np.maximum(t - 0.4, 0) / 0.25)
    write("groan", room(v, grng2, 0.05, 0.2), meta, 0.5, 1.2)
    # The revolution's guns. The Spencer: a rifle's crack with a heavier, duller body.
    # The Springfield rifle-musket: a deep black-powder thump with a long tail.
    arng = np.random.default_rng(97)
    for i in range(3):
        sfx = "" if i == 0 else "_%d" % (i + 1)
        j = arng.uniform(0.92, 1.08)
        write("spencer" + sfx, gunshot(arng, 0.002, 2900, 0.04, 220, 0.13, 52, 3.1, 1.15, 1.2 * j), meta, 0.98, 1.6)
        write("musket" + sfx, gunshot(arng, 0.003, 1800, 0.075, 160, 0.24, 40, 3.5, 1.6, 1.35 * j), meta, 0.98, 1.8)
    # Powder (and shot) poured down the barrel: a dry hiss, then a patter.
    n = int(SR * 0.5)
    hiss = bandpass(arng.normal(0, 1, n), 2500, 9000) * np.sin(np.linspace(0, np.pi, n)) ** 0.8 * 0.5
    parts = [(0.0, hiss)] + [(0.3 + 0.025 * k, tink(arng, 4200 + 300 * k, 0.006, 0.25, 0.04)) for k in range(5)]
    write("pour", room(place(0.6, parts), arng, 0.04, 0.2), meta, 0.45, 1.2)
    # The ramrod: steel scraping down the bore, two firm thumps on the charge, out again.
    def scrape(dur, lo, hi):
        n = int(SR * dur)
        return bandpass(arng.normal(0, 1, n), lo, hi) * np.sin(np.linspace(0, np.pi, n)) ** 0.5 * \
            (0.7 + 0.3 * np.sin(np.linspace(0, 60, n)))
    parts = [(0.0, scrape(0.3, 1800, 6500) * 0.5), (0.3, knock(arng, 700, 0.02, 0.1) * 1.4 + metal(arng, 1300, 1.2, 0.1) * 0.4),
             (0.52, knock(arng, 700, 0.02, 0.1) * 1.2), (0.62, scrape(0.25, 2200, 7000) * 0.4)]
    write("ram", room(place(0.95, parts), arng, 0.05, 0.25), meta, 0.65, 1.3)
    # A heartbeat, for the stranger bleeding in the dirt: lub-dub, low and muffled.
    hrng3 = np.random.default_rng(98)

    def beat(f, amp):
        tt = t_of(0.16)
        return (np.sin(2 * np.pi * f * tt * (1 - 0.3 * tt / 0.16)) * np.exp(-tt / 0.045)
                + lowpass(hrng3.normal(0, 1, len(tt)), 160) * np.exp(-tt / 0.02) * 0.6) * amp
    write("heart", place(0.5, [(0.0, beat(52, 1.0)), (0.18, beat(46, 0.7))]), meta, 0.8, 1.2)
    # A silver peso landing in the street: a bright strike, a bounce or two closing
    # up, then the coin rolling on its rim and shivering flat. Two takes.
    crng = np.random.default_rng(99)
    for take in ("clink", "clink_2"):
        f0 = crng.uniform(3300, 3900)
        parts = [(0.0, tink(crng, f0, 0.03, 1.0, 0.25))]
        at, gap, a = 0.0, crng.uniform(0.09, 0.12), 0.6
        for _ in range(3):
            at += gap
            parts.append((at, tink(crng, f0 * crng.uniform(0.97, 1.03), 0.02, a, 0.2)))
            gap *= 0.62
            a *= 0.6
        spin = t_of(0.3)
        rate = 18 + 70 * spin / 0.3   # (faster and faster as it settles)
        shiver = np.sin(2 * np.pi * f0 * 1.1 * spin) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(rate) / SR)))
        parts.append((at + 0.03, shiver * np.exp(-spin / 0.12) * 0.12))
        write(take, room(place(0.75, parts), crng, 0.04, 0.2), meta, 0.6)
    # A match struck on a thumbnail or a boot heel: a short scratch, the head catching
    # with a sputter, then the soft roar of the flame a moment. Two takes.
    frng = np.random.default_rng(100)
    for take in ("match", "match_2"):
        sd = frng.uniform(0.06, 0.1)
        st = t_of(sd)
        scratch = highpass(lowpass(frng.normal(0, 1, len(st)), 6500), 1500) * (0.4 + 0.6 * np.sin(np.pi * st / sd))
        ft = t_of(0.7)
        flare = lowpass(frng.normal(0, 1, len(ft)), 900) * (1 - np.exp(-ft / 0.02)) * np.exp(-ft / 0.25)
        pops = [(sd + frng.uniform(0.0, 0.08), highpass(frng.normal(0, 1, int(SR * 0.006)), 2500) * frng.uniform(0.3, 0.7))
                for _ in range(4)]
        write(take, room(place(0.9, [(0.0, scratch * 0.8), (sd, flare * 1.4)] + pops), frng, 0.03, 0.15), meta, 0.45)
    # An axe biting into a log on the block: the dull thock of the blade going in, a
    # crack as the wood splits, the halves knocking down. Three takes.
    arng2 = np.random.default_rng(101)
    for take in ("chop", "chop_2", "chop_3"):
        hit = place(0.15, [(0.0, thunk(arng2.uniform(160, 220), 0.03) * 1.6),
                           (0.0, knock(arng2, arng2.uniform(500, 700), 0.02) * 1.2)])
        tt = t_of(0.05)
        crack = highpass(arng2.normal(0, 1, len(tt)), 1800) * np.exp(-tt / 0.01)
        drop = knock(arng2, arng2.uniform(350, 450), 0.03) * 0.5
        write(take, room(place(0.6, [(0.0, hit), (0.02, crack * 0.7), (arng2.uniform(0.22, 0.3), drop)]), arng2, 0.05, 0.25),
              meta, 0.6, 1.3)
    # A campfire going: a low breathy roar and the snap of the wood, a couple of
    # seconds of it, played over and over (Campfire).
    krng = np.random.default_rng(102)
    ft = t_of(2.4)
    roar = lowpass(krng.normal(0, 1, len(ft)), 380) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.7 * ft))
    snaps = [(krng.uniform(0.0, 2.3), highpass(krng.normal(0, 1, int(SR * 0.004)), 2200) * krng.uniform(0.4, 1.0))
             for _ in range(14)]
    fade = np.minimum(1.0, np.minimum(ft / 0.15, (2.4 - ft) / 0.15))
    write("crackle", place(2.4, [(0.0, roar * fade * 0.5)] + snaps), meta, 0.4)
    # Rain on the burial ground (the funeral's, Snowfall in its rain): a hiss over a
    # low wash, and the patter of near drops on hats, wood and puddles; looped, it
    # takes the wind's place and swells in a downpour.
    qrng = np.random.default_rng(103)
    dur = 6.0
    rt = t_of(dur + 1.0)
    hiss = highpass(lowpass(qrng.normal(0, 1, len(rt)), 6000), 900) * 0.5
    wash = lowpass(qrng.normal(0, 1, len(rt)), 500) * (0.8 + 0.2 * np.sin(2 * np.pi * rt / (dur + 1.0)))
    pat = [(qrng.uniform(0.0, dur + 0.9), highpass(qrng.normal(0, 1, int(SR * 0.003)), 2500) * qrng.uniform(0.15, 0.6))
           for _ in range(900)]
    r = place(dur + 1.0, [(0.0, hiss + wash * 0.6)] + pat)
    k = int(SR * 1.0)
    fade = np.linspace(0, 1, k)
    r[:k] = r[:k] * fade + r[-k:] * (1 - fade)
    write("rain", r[:-k], meta, 0.35)
    # Thunder as a downpour comes in (Snowfall in its rain): the near crack of it,
    # then a long rolling rumble that grumbles and dies away; three takes.
    hrng = np.random.default_rng(104)
    for take in ("thunder", "thunder_2", "thunder_3"):
        dur = hrng.uniform(4.5, 6.5)
        ht = t_of(dur)
        crack = highpass(hrng.normal(0, 1, len(ht)), 700) * np.exp(-ht / 0.12) * hrng.uniform(0.4, 0.9)
        rumble = lowpass(lowpass(hrng.normal(0, 1, len(ht)), 160), 120)
        rolls = sum(np.exp(-((ht - hrng.uniform(0.2, dur * 0.6)) / hrng.uniform(0.3, 0.9)) ** 2) * hrng.uniform(0.5, 1.0)
                    for _ in range(5))
        env = (1 - np.exp(-ht / 0.15)) * np.exp(-ht / (dur * 0.35)) * (0.5 + rolls)
        write(take, room(crack + rumble * env * 3.0, hrng, 0.6, 0.4), meta, 0.85, 1.4)


def gen_music(meta):
    print("  music")
    import music
    music.bake(meta, ASSETS)


def main():
    with open(os.path.join(ROOT, "data", "town.json")) as f:
        level = json.load(f)
    meta = {}
    only = set(sys.argv[1:])
    print("Generating assets into", ASSETS)
    meta_path = os.path.join(ASSETS, "meta.json")
    if only and os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    steps = {"chars": gen_characters, "world": gen_world, "fx": gen_fx, "ui": gen_ui, "sfx": gen_sfx,
             "animals": gen_animals, "music": gen_music}
    for key, fn in steps.items():
        if not only or key in only:
            fn(meta)
    # SUNDANCE_GROUNDS=train,cruz_verde bakes only those maps' grounds (by file name).
    grounds = [g for g in os.environ.get("SUNDANCE_GROUNDS", "").split(",") if g]
    if not only or "ground" in only:
        if not grounds or "town" in grounds:
            print("  ground")
            gen_ground(meta, level)
        for name in sorted(os.listdir(os.path.join(ROOT, "data"))):   # and every other map with a ground of its own
            if grounds and name[:-5] not in grounds:
                continue
            if name.endswith(".json") and name != "town.json":
                with open(os.path.join(ROOT, "data", name)) as f:
                    other = json.load(f)
                if "ground" in other and "size" in other:
                    print("  ground for", other.get("name", name))
                    gen_ground(meta, other, other["ground"])
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
    print("Done.")


if __name__ == "__main__":
    main()
