"""Characters: costumes, a two-layer rig (legs + upper body) and the animation library.

The rig is posed from plain data. A legs pose gives hip height and leg joints; an upper
pose gives lean, twist, arm joints and where the gun sits. Animations are short lists of
key poses that get interpolated into frames, so every character shares the same
animation definitions and only the upper body varies per gun.

Coordinates are metres, the model faces +X, +Y is his left. Upper-body poses are
relative to the hip; legs poses are relative to the feet.
"""
import math
import numpy as np
from render3d import (Cloud, ellipsoid, frustum, disc, box, beam, quad, rot_x, rot_y, rot_z, render,
                      PX, PY, hash01, slot)

STEEL = (70, 72, 78)
GUNMETAL = (96, 100, 112)
WOOD = (120, 74, 44)
BRASS = (205, 165, 70)
LEATHER = (92, 62, 38)
MUD = (78, 56, 40)

H_REF = 0.92          # standing hip height; the upper layer is baked at this height
CANVAS = (340, 280)   # render canvas (texels) before trimming; frames are trimmed after
ANCHOR = (170, 200)   # feet within the canvas

import json
import os

_DATA = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "enemies.json")))
TEMPLATES = _DATA["templates"]
SLOTS = _DATA["slots"]
SID = {n: i + 1 for i, n in enumerate(SLOTS)}
NEUTRAL = (200, 200, 200)   # recolourable parts are baked in grey; a shader paints them


def template_guns():
    """Which guns each body template must be baked holding (every gun its types carry).
    Townsfolk, and bandits passing as townsfolk, need it "unarmed" as well."""
    # the stranger: his own three, and what he can take off the revolution's dead
    out = {"hero": ["colt", "coach", "rifle", "schofield", "navy", "pistola", "sawnoff", "champion", "escopeta", "spencer",
                    "springfield", "rollingblock", "remington"]}

    def need(template, g, t=None):
        out.setdefault(template, [])
        if g not in out[template]:
            out[template].append(g)
        # a Colt may come out a Schofield (Enemy.SCHOFIELD, or the type's "schofield")
        if g == "colt" and (t is None or t.get("schofield", 0.3) > 0):
            need(template, "schofield")

    def champion(template, chance, guns, cut=0):
        # a man with only a sidearm may have a Champion slung too (Enemy.CHAMPION), or
        # a cut-down Rolling Block under his coat (Enemy.ROLLINGBLOCK)
        if chance > 0 and len(guns) == 1:
            need(template, "champion")
        if cut > 0 and len(guns) == 1:
            need(template, "rollingblock")
    for t in _DATA["types"].values():
        for g in t["loadout"]:
            need(t["template"], g, t)
        for option in t.get("loadouts", []):
            for g in option["guns"]:
                need(t["template"], g, t)
            champion(t["template"], option.get("champion", t.get("champion", 0)), option["guns"],
                     option.get("rollingblock", t.get("rollingblock", 0)))
        if not t.get("loadouts"):
            champion(t["template"], t.get("champion", 0), t["loadout"], t.get("rollingblock", 0))
        if t.get("concealed"):
            need(t["template"], "unarmed")
        if t.get("flag"):   # the colours, carried (or taken up from the dirt) with a Navy in the other hand
            need(t["template"], "banner")
            need(t["template"], "navy")
    for t in _DATA["civilians"]["types"].values():
        need(t["template"], {"undertaker": "tools", "priest": "prayer", "mourner": "grief", "gunsmith": "smith",
                                  "mayor": "mayor", "carpenter": "carpentry", "sweeper": "broom",
                                  "henwife": "broom", "keeper": "keeper", "sister": "nun",
                                  "barber": "barber", "visitor": "grief", "digger": "spade",
                                  "condemned": "bound", "leader": "mayor"}.get(t.get("role", ""), "unarmed"))
        if t.get("role") == "condemned":
            need(t["template"], "unarmed")   # (and cut loose, running for it)
        if t.get("role") == "carrier":
            need(t["template"], t.get("load", "case"))
            need(t["template"], "unarmed")   # (a carrier's dropped his load, running for cover)
    # a level's waves may hand their men other guns ("arms"): whoever might walk in
    # with them is baked holding them too
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    level_data = json.load(open(os.path.join(root, "data", "levels.json")))
    for lv in level_data["levels"]:
        mp = json.load(open(os.path.join(root, lv["map"].replace("res://", ""))))
        for w in lv.get("waves", []):
            for gr in w["groups"]:
                arms = gr.get("arms", w.get("arms")) or []
                if isinstance(arms, str):
                    arms = level_data["arms"][arms]
                for k in gr.get("kinds") or list(mp.get("wave_kinds", {})):
                    for option in arms:
                        for g in option["guns"]:
                            need(_DATA["types"][k]["template"], g, _DATA["types"][k])
                        champion(_DATA["types"][k]["template"], option.get("champion", 0), option["guns"])
    return out


GUN_LEN = {"remington": 1.3, "colt": 0.31, "schofield": 0.33, "coach": 0.97, "rifle": 1.1, "derringer": 0.21, "sharps": 1.32, "rollingblock": 0.72, "howdah": 0.44, "sawnoff": 0.6, "champion": 1.15, "navy": 0.36,
           "spencer": 1.0, "springfield": 1.45, "escopeta": 1.3, "pistola": 0.46}
MUZZLE_LOADERS = ("springfield", "escopeta")   # loaded standing, the butt on the ground, with the ramrod
# Loadouts drawn with another gun's model: a pair of Colts is two Colts, the second
# in the left hand (pose key "gun2").
GUN_ART = {"colts": "colt", "smith": "rifle", "rifles": "rifle", "banner": "navy"}   # the gunsmith looks over a rifle; so do the carriers


class Look:
    """A template's shape plus either a real palette (portraits) or neutral grey with
    slot tags (baking)."""

    def __init__(self, template, palette=None):
        self.template = template
        self.shape = TEMPLATES[template]
        self.palette = palette

    def get(self, key, default=None):
        return self.shape.get(key, default)

    def c(self, name):
        if self.palette is None:
            return NEUTRAL
        return tuple(self.palette.get(name, NEUTRAL))

    def tag(self, name):
        return slot(SID[name])


# ---------------------------------------------------------------- materials

def _torso_fn(look):
    style = look.get("style")
    base_slot = {"vest": "vest", "suit": "vest", "dress": "dress", "uniform": "coat"}.get(style, "shirt")
    base = np.array(look.c(base_slot), float)

    def f(P, N):
        c = np.tile(base, (len(P), 1))
        s_ = np.full(len(P), SID[base_slot], np.uint8)

        def paint(m, name):
            c[m] = look.c(name)
            s_[m] = SID[name]
        front = P[:, 0] > 0
        if style == "vest":
            paint(front & (np.abs(P[:, 1]) < 0.05), "shirt")
        elif style == "suit":
            paint(front & (np.abs(P[:, 1]) < 0.06) & (P[:, 2] > 0.18), "shirt")
            paint(front & (np.abs(P[:, 1]) < 0.012) & (P[:, 2] > 0.34), "accent")       # string tie
        elif style == "uniform":
            # a buttoned tunic: two rows of brass down the front, a coloured collar
            paint(P[:, 2] > 0.445, "accent")
            for row in (-0.045, 0.045):
                b = front & (np.abs(P[:, 1] - row) < 0.014) & ((P[:, 2] * 12.5) % 1.0 < 0.3) & (P[:, 2] > 0.1) & (P[:, 2] < 0.43)
                c[b] = BRASS
                s_[b] = 0
        elif style == "dress":
            paint(P[:, 2] > 0.4, "skin")                                                  # neckline
            lace = front & (np.abs(P[:, 1]) < 0.03) & (P[:, 2] < 0.38) & ((P[:, 2] * 40) % 1.0 < 0.35)
            paint(lace, "accent")
        if look.get("apron"):
            # a leather apron up to the chest, on a strap round the neck
            ap = (front & (np.abs(P[:, 1]) < 0.13) & (P[:, 2] < 0.38)) | \
                 (front & (np.abs(np.abs(P[:, 1]) - 0.06) < 0.018) & (P[:, 2] >= 0.38))
            paint(ap, "accent")
        if look.get("bib"):
            # bib overalls: a denim bib up the front, straps over the shoulders
            bib = (front & (np.abs(P[:, 1]) < 0.11) & (P[:, 2] < 0.34)) | \
                  ((np.abs(np.abs(P[:, 1]) - 0.085) < 0.022) & (P[:, 2] >= 0.3))
            paint(bib, "trousers")
            buttons = front & (np.abs(np.abs(P[:, 1]) - 0.085) < 0.016) & (np.abs(P[:, 2] - 0.33) < 0.016)
            c[buttons] = BRASS
            s_[buttons] = 0
        if look.get("chain"):
            # a gold watch chain looped across the waistcoat, pocket to pocket
            y = P[:, 1]
            chain = front & (np.abs(y) < 0.1) & (np.abs(P[:, 2] - (0.2 + 5.0 * y * y)) < 0.011)
            c[chain] = BRASS
            s_[chain] = 0
        if look.get("suspenders"):
            for side in (-1, 1):
                m = np.abs(P[:, 1] - side * 0.08) < 0.018
                c[m] = LEATHER
                s_[m] = 0
        if look.get("serape"):
            # a striped blanket over the left shoulder and down across to the right hip
            along = P[:, 2] - (0.24 + 1.2 * P[:, 1])
            band = np.abs(along) < 0.1
            stripe = np.floor((P[:, 2] + P[:, 1]) * 16) % 3
            paint(band & (stripe == 0), "poncho_a")
            paint(band & (stripe == 1), "poncho_b")
            paint(band & (stripe == 2), "poncho_c")
        if look.get("medals"):
            # a row of decorations on the left breast
            for i, dy in enumerate((0.05, 0.08, 0.11)):
                md = front & (np.abs(P[:, 1] - dy) < 0.012) & (np.abs(P[:, 2] - 0.36) < 0.02)
                c[md] = BRASS if i != 1 else (180, 40, 36)
                s_[md] = 0
        if look.get("crossbelt"):   # the soldier's white crossbelt, shoulder to hip
            m = np.abs(P[:, 2] - (0.26 - 0.95 * P[:, 1])) < 0.028
            c[m] = (226, 222, 208)
            s_[m] = 0
        if look.get("bandolier"):
            for sgn in ((1,) if look.get("bandolier") == "one" else (1, -1)):
                m = np.abs(P[:, 2] - (0.26 + sgn * 0.95 * P[:, 1])) < 0.035
                c[m] = LEATHER
                s_[m] = 0
                dots = m & ((P[:, 1] * 22 + P[:, 0] * 6) % 1.0 < 0.45)
                c[dots] = BRASS
        return c, s_
    return f


def _coat_fn(look, bottom):
    base = np.array(look.c("coat"), float)

    def f(P, N):
        c = np.tile(base, (len(P), 1))
        n = hash01(np.floor(P[:, 0] * 30), np.floor(P[:, 1] * 30), np.floor(P[:, 2] * 30))
        c *= (0.94 + 0.1 * n)[:, None]
        m = P[:, 2] < bottom + 0.14 + 0.05 * n
        c[m] = c[m] * 0.55 + np.array(MUD) * 0.45
        return c
    return f


def _poncho_fn(look):
    order = ["poncho_a", "poncho_b", "poncho_a", "poncho_c", "poncho_b", "poncho_c"]
    cols = np.array([look.c(n) for n in order], float)
    sids = np.array([SID[n] for n in order], np.uint8)

    def f(P, N):
        band = np.floor(P[:, 2] * 16).astype(int) % len(order)
        c = cols[band].copy()
        m = P[:, 2] < 0.16
        c[m] = c[m] * 0.7
        return c, sids[band]
    return f


def _head_fn(look, hc):
    skin = np.array(look.c("skin"), float)
    female = look.get("female", False)

    def f(P, N):
        c = np.tile(skin, (len(P), 1))
        s_ = np.full(len(P), SID["skin"], np.uint8)
        rel = P - hc
        if not female:
            stub = (rel[:, 0] > 0.02) & (rel[:, 2] < -0.035)
            c[stub] = c[stub] * 0.72 + np.array([60, 44, 34]) * 0.28
        hair = (rel[:, 0] < -0.03) & (rel[:, 2] > -0.04)
        if female:
            # hair up: over the crown and down the back, leaving the face clear
            hair |= ((rel[:, 2] > 0.055) & (rel[:, 0] < 0.03)) | ((rel[:, 0] < -0.01) & (rel[:, 2] > -0.07))
        c[hair] = look.c("hair")
        s_[hair] = SID["hair"]
        for side in (-1, 1):
            eye = (rel[:, 0] > 0.06) & (np.abs(rel[:, 1] - side * 0.035) < 0.014) & \
                  (np.abs(rel[:, 2] - 0.012) < 0.012)
            c[eye] = (30, 22, 18)
            s_[eye] = 0
        if female:
            lips = (rel[:, 0] > 0.07) & (np.abs(rel[:, 1]) < 0.025) & (np.abs(rel[:, 2] + 0.05) < 0.01)
            c[lips] = (150, 50, 50)
            s_[lips] = 0
        return c, s_
    return f


# ---------------------------------------------------------------- guns

def weapon_model(kind, butt, direction, lever=0.0, broken=0.0):
    """A gun from its butt along `direction`. lever (0..1) throws the Winchester's
    lever; broken (0..1) drops the coach gun's barrels on their hinge."""
    out = Cloud()
    butt = np.array(butt, float)
    a = np.array(direction, float)
    a /= np.linalg.norm(a)
    L = GUN_LEN[kind]
    side = np.cross(a, [0, 0, 1.0])
    if np.linalg.norm(side) < 1e-3:
        side = np.array([0, 1.0, 0])
    side /= np.linalg.norm(side)
    up = np.cross(side, a)

    def at(t, off=(0, 0), axis=None, origin=None, length=None):
        ax = a if axis is None else axis
        o = butt if origin is None else origin
        return o + ax * ((L if length is None else length) * t) + side * off[0] + up * off[1]
    # Guns are drawn a little oversized so each one reads at a glance.
    if kind == "colt":
        out += beam(at(0.0, (0, -0.08)), at(0.2, (0, 0.0)), 0.026, (214, 196, 160))   # ivory grip
        out += frustum(at(0.16), at(0.4), 0.042, 0.042, GUNMETAL)                     # frame + cylinder
        out += beam(at(0.4, (0, 0.016)), at(1.0, (0, 0.016)), 0.018, GUNMETAL)        # barrel
        out += beam(at(0.4, (0, -0.014)), at(0.78, (0, -0.014)), 0.009, STEEL)        # ejector rod
        out += beam(at(0.12, (0, 0.03)), at(0.2, (0, 0.06)), 0.01, STEEL)             # hammer spur
    elif kind == "schofield":
        # Smith & Wesson Schofield: blued, walnut grips with the hump at the top of the
        # backstrap, and a top-break: unlatched, barrel and cylinder swing down on the
        # hinge at the front of the frame and the extractor star throws the six out
        out += beam(at(0.0, (0, -0.08)), at(0.2, (0, 0.0)), 0.027, (110, 72, 44))       # walnut grip
        out += ellipsoid(at(0.14, (0, 0.022)), (0.016, 0.013, 0.014), GUNMETAL)         # the hump
        out += beam(at(0.16, (0, -0.045)), at(0.24, (0, -0.04)), 0.01, GUNMETAL)        # trigger guard
        out += beam(at(0.12, (0, 0.03)), at(0.19, (0, 0.06)), 0.01, STEEL)             # hammer spur
        hinge = at(0.22, (0, -0.03))
        ang = -1.0 * broken
        ab = a * math.cos(ang) + up * math.sin(ang)
        ub = up * math.cos(ang) - a * math.sin(ang)

        def hb(t, off):
            return hinge + ab * (L * (t - 0.22)) + ub * (off + 0.03)
        out += frustum(hb(0.2, 0.0), hb(0.42, 0.0), 0.042, 0.042, GUNMETAL)            # cylinder
        out += beam(hb(0.42, 0.016), hb(1.0, 0.016), 0.017, GUNMETAL)                  # barrel
        out += beam(hb(0.42, 0.04), hb(0.5, 0.045), 0.012, STEEL)                      # the barrel latch
        out += beam(hb(0.42, -0.012), hb(0.62, -0.012), 0.009, STEEL)                  # extractor rod
    elif kind == "navy":
        # Colt Navy 1851: walnut grip, brass frame and trigger guard, a long octagonal
        # barrel with the loading lever folded under it
        out += beam(at(0.0, (0, -0.075)), at(0.18, (0, 0.0)), 0.026, (122, 78, 46))      # walnut grip
        out += box(tuple(at(0.15) - 0.032), tuple(at(0.22) + 0.032), BRASS)            # brass frame
        out += beam(at(0.16, (0, -0.045)), at(0.24, (0, -0.04)), 0.011, BRASS)          # trigger guard
        out += frustum(at(0.21), at(0.38), 0.04, 0.04, GUNMETAL)                       # cylinder
        out += beam(at(0.38, (0, 0.012)), at(1.0, (0, 0.012)), 0.019, GUNMETAL)         # octagon barrel
        out += beam(at(0.4, (0, -0.02)), at(0.74, (0, -0.02)), 0.01, STEEL)             # loading lever
        out += beam(at(0.12, (0, 0.03)), at(0.19, (0, 0.06)), 0.01, STEEL)              # hammer
    elif kind == "pistola":
        # a percussion horse pistol: a curved walnut grip with a brass cap, the stock run
        # most of the way up a round barrel, a brass band, the ramrod swivelled beneath
        out += beam(at(0.0, (0, -0.08)), at(0.24, (0, -0.005)), 0.03, (122, 78, 46))      # grip
        out += ellipsoid(at(0.0, (0, -0.085)), (0.03, 0.03, 0.03), BRASS)                # butt cap
        out += beam(at(0.22, (0, -0.012)), at(0.82, (0, -0.012)), 0.024, (122, 78, 46))   # fore-stock
        out += beam(at(0.22, (0, 0.012)), at(1.0, (0, 0.012)), 0.019, GUNMETAL)          # barrel
        out += beam(at(0.62), at(0.66), 0.03, BRASS)                                     # band
        out += beam(at(0.3, (0, -0.034)), at(0.95, (0, -0.034)), 0.007, STEEL)          # ramrod
        out += beam(at(0.2, (0.02, 0.03)), at(0.24, (0.02, 0.065)), 0.011, STEEL)       # hammer
        out += beam(at(0.18, (0, -0.045)), at(0.27, (0, -0.04)), 0.01, BRASS)            # trigger guard
    elif kind == "derringer":
        # Remington double derringer: pearl grip, two stacked barrels that flip up
        out += beam(at(0.0, (0, -0.07)), at(0.25, (0, 0.0)), 0.022, (226, 220, 206))
        out += box(tuple(at(0.25) - 0.022), tuple(at(0.34) + 0.022), (150, 150, 158))
        hinge = at(0.34, (0, 0.03))
        ang = 1.0 * broken
        ab = a * math.cos(ang) + up * math.sin(ang)
        for o in (0.012, -0.012):
            out += beam(hinge + up * (o - 0.03), hinge + ab * (L * 0.66) + up * (o - 0.03), 0.013, (150, 150, 158))
        out += beam(at(0.2, (0, 0.025)), at(0.26, (0, 0.05)), 0.008, STEEL)            # hammer
    elif kind == "sharps":
        # Sharps 1874: long octagon barrel, case-hardened falling-block action, tang sight
        out += frustum(at(0.0, (0, -0.045)), at(0.26), 0.058, 0.03, WOOD)
        out += box(tuple(at(0.25) - 0.034), tuple(at(0.35) + 0.034), (128, 120, 112))
        drop = 0.1 * lever                                                           # block and lever
        out += beam(at(0.27, (0, -0.05 - drop)), at(0.36, (0, -0.045 - drop * 0.5)), 0.012, STEEL)
        out += beam(at(0.35, (0, 0.012)), at(1.0, (0, 0.012)), 0.02, GUNMETAL)
        out += beam(at(0.35, (0, -0.024)), at(0.58, (0, -0.024)), 0.028, WOOD)
        out += beam(at(0.22, (0, 0.04)), at(0.24, (0, 0.075)), 0.008, STEEL)            # tang sight
        out += beam(at(0.3, (0, 0.03)), at(0.33, (0, 0.06)), 0.01, STEEL)              # hammer
    elif kind == "remington":
        # the Remington Rolling Block as the army has it: a full stock, the case-hardened
        # action with its big hammer and the block that rolls back under the thumb, a
        # long barrel in a fore-end banded nearly to the muzzle
        out += frustum(at(0.0, (0, -0.045)), at(0.24), 0.056, 0.03, WOOD)
        out += box(tuple(at(0.23) - 0.034), tuple(at(0.31) + 0.034), (128, 120, 112))
        roll = 0.9 * lever
        out += beam(at(0.29, (0, 0.03)), at(0.29, (0, 0.03)) + (up * math.cos(roll) - a * math.sin(roll)) * 0.04,
                    0.012, STEEL)
        out += beam(at(0.31, (0, 0.012)), at(1.0, (0, 0.012)), 0.018, GUNMETAL)
        out += beam(at(0.31, (0, -0.02)), at(0.86, (0, -0.02)), 0.026, WOOD)
        for f in (0.52, 0.7, 0.85):   # the barrel bands
            out += beam(at(f, (0, -0.005)), at(f + 0.02, (0, -0.005)), 0.03, STEEL)
        out += beam(at(0.24, (0, 0.03)), at(0.27, (0, 0.07)), 0.012, STEEL)              # hammer
    elif kind == "rollingblock":
        # a Remington Rolling Block carbine cut down: the stock sawn to a pistol grip,
        # the case-hardened action with its big hammer and the breech block that rolls
        # back under the thumb, a short round barrel and a stub of fore-end
        out += frustum(at(0.0, (0, -0.075)), at(0.22, (0, -0.005)), 0.04, 0.03, WOOD)     # sawn grip
        out += box(tuple(at(0.22) - 0.034), tuple(at(0.36) + 0.034), (128, 120, 112))
        roll = 0.9 * lever                                                            # the block, rolled back
        out += beam(at(0.33, (0, 0.03)), at(0.33, (0, 0.03)) + (up * math.cos(roll) - a * math.sin(roll)) * 0.04,
                    0.012, STEEL)
        out += beam(at(0.36, (0, 0.012)), at(1.0, (0, 0.012)), 0.02, GUNMETAL)
        out += beam(at(0.36, (0, -0.022)), at(0.56, (0, -0.022)), 0.026, WOOD)          # fore-end stub
        out += beam(at(0.26, (0, 0.03)), at(0.29, (0, 0.07)), 0.012, STEEL)              # hammer
    elif kind == "howdah":
        # Howdah pistol: two fat side-by-side barrels on a heavy grip, breaks open
        out += beam(at(0.0, (0, -0.09)), at(0.24, (0, 0.0)), 0.03, WOOD)
        out += box(tuple(at(0.22) - 0.036), tuple(at(0.32) + 0.036), STEEL)
        hinge = at(0.32)
        ang = 0.8 * broken
        ab = a * math.cos(ang) - up * math.sin(ang)
        for o in (-0.021, 0.021):
            out += beam(hinge + side * o, hinge + ab * (L * 0.68) + side * o, 0.022, GUNMETAL)
            out += beam(at(0.17, (o * 1.3, 0.03)), at(0.22, (o * 1.5, 0.07)), 0.011, STEEL)  # hammers
    elif kind == "sawnoff":
        # a double gun cut down: the stock sawn to a pistol grip, the barrels stubby
        out += frustum(at(0.0, (0, -0.075)), at(0.2, (0, -0.005)), 0.04, 0.032, WOOD)
        out += box(tuple(at(0.2) - 0.04), tuple(at(0.27) + 0.04), STEEL)
        hinge = at(0.27)
        ang = 0.75 * broken
        ab = a * math.cos(ang) - up * math.sin(ang)
        upb = np.cross(side, ab)
        bl = L * 0.73
        for o in (-0.025, 0.025):
            out += beam(hinge + side * o + upb * 0.012, hinge + ab * bl + side * o + upb * 0.012, 0.024, GUNMETAL)
            out += beam(at(0.19, (o * 1.4, 0.03)), at(0.24, (o * 1.6, 0.075)), 0.012, STEEL)  # hammers
        out += beam(hinge - upb * 0.026, hinge + ab * (bl * 0.36) - upb * 0.026, 0.03, WOOD)
    elif kind == "champion":
        # Johnson & Bye Champion: a plain walnut stock, a long single barrel hinged to
        # swing down, the side lever that snaps it open, and one hammer
        out += frustum(at(0.0, (0, -0.042)), at(0.28), 0.056, 0.03, WOOD)
        out += box(tuple(at(0.28) - 0.035), tuple(at(0.33) + 0.035), STEEL)
        out += beam(at(0.29, (0.034, -0.01)), at(0.24, (0.036, -0.04)), 0.009, STEEL)  # side snap lever
        hinge = at(0.33)
        ang = 0.75 * broken
        ab = a * math.cos(ang) - up * math.sin(ang)
        upb = np.cross(side, ab)
        bl = L * 0.67
        out += beam(hinge + upb * 0.012, hinge + ab * bl + upb * 0.012, 0.022, GUNMETAL)
        out += beam(hinge - upb * 0.016, hinge + ab * (bl * 0.34) - upb * 0.016, 0.026, WOOD)    # fore-end
        out += beam(at(0.26, (0, 0.03)), at(0.3, (0, 0.075)), 0.012, STEEL)                   # hammer
    elif kind == "spencer":
        # Spencer carbine: walnut butt with the magazine tube's brass cap at its heel, a
        # dark case-hardened receiver, side hammer, a short fore-end and one barrel band
        out += frustum(at(0.0, (0, -0.045)), at(0.3), 0.057, 0.03, (104, 64, 40))
        out += beam(at(0.0, (0, -0.02)), at(0.02, (0, -0.02)), 0.022, BRASS)            # tube cap
        out += frustum(at(0.29), at(0.42), 0.042, 0.04, (70, 64, 60))                  # receiver
        out += beam(at(0.42, (0, 0.012)), at(1.0, (0, 0.012)), 0.017, GUNMETAL)
        out += beam(at(0.42, (0, -0.016)), at(0.66), 0.03, (104, 64, 40))              # fore-end
        out += beam(at(0.64, (0, -0.005)), at(0.67, (0, -0.005)), 0.034, STEEL)        # barrel band
        out += beam(at(0.33, (0.03, 0.025)), at(0.36, (0.03, 0.06)), 0.011, STEEL)     # side hammer
        drop = 0.08 * lever                                                          # lever / trigger guard
        out += beam(at(0.3 - 0.04 * lever, (0, -0.05 - drop)), at(0.38 - 0.07 * lever, (0, -0.095 - drop)), 0.011, STEEL)
        out += beam(at(0.38 - 0.07 * lever, (0, -0.095 - drop)), at(0.42, (0, -0.045)), 0.011, STEEL)
    elif kind == "springfield":
        # Springfield 1861 rifle-musket: a long full stock nearly to the muzzle, three
        # barrel bands, the barrel in armory bright, the ramrod under it, the lock's hammer
        bright = (176, 178, 184)
        out += frustum(at(0.0, (0, -0.05)), at(0.25), 0.055, 0.028, WOOD)
        out += box(tuple(at(0.24) - 0.03), tuple(at(0.3) + 0.03), (150, 152, 158))      # lock plate
        out += beam(at(0.29, (0, -0.012)), at(0.88, (0, -0.012)), 0.027, WOOD)        # fore-stock
        out += beam(at(0.26, (0, 0.012)), at(1.0, (0, 0.012)), 0.016, bright)
        out += beam(at(0.32, (0, -0.036)), at(0.97, (0, -0.036)), 0.007, bright)       # ramrod
        for t in (0.5, 0.68, 0.86):
            out += beam(at(t), at(t + 0.02), 0.032, bright)                            # bands
        out += beam(at(0.25, (0.025, 0.03)), at(0.28, (0.025, 0.065)), 0.011, STEEL)   # hammer
    elif kind == "escopeta":
        # escopeta: an old single-barrel fowling piece, plain dark stock run far up a
        # long thin barrel, brass butt plate and bands, a hammer on the side lock
        dark = (92, 58, 36)
        out += frustum(at(0.0, (0, -0.045)), at(0.24), 0.05, 0.026, dark)
        out += beam(at(0.0, (0, -0.045)), at(0.015, (0, -0.045)), 0.05, BRASS)          # butt plate
        out += beam(at(0.24, (0, -0.01)), at(0.74, (0, -0.01)), 0.024, dark)
        out += beam(at(0.22, (0, 0.012)), at(1.0, (0, 0.012)), 0.019, (84, 84, 90))
        for t in (0.45, 0.7):
            out += beam(at(t), at(t + 0.018), 0.028, BRASS)
        out += beam(at(0.21, (0.025, 0.03)), at(0.24, (0.025, 0.065)), 0.011, STEEL)   # hammer
    elif kind == "coach":
        out += frustum(at(0.0, (0, -0.04)), at(0.3), 0.06, 0.032, WOOD)
        out += box(tuple(at(0.3) - 0.04), tuple(at(0.34) + 0.04), STEEL)
        hinge = at(0.34)
        ang = 0.75 * broken
        ab = a * math.cos(ang) - up * math.sin(ang)       # barrels swing down when broken
        upb = np.cross(side, ab)
        bl = L * 0.66
        for o in (-0.024, 0.024):                                                     # side by side
            out += beam(hinge + side * o + upb * 0.012, hinge + ab * bl + side * o + upb * 0.012, 0.022, GUNMETAL)
            out += beam(at(0.27, (o * 1.4, 0.03)), at(0.31, (o * 1.6, 0.075)), 0.012, STEEL)  # hammers
        out += beam(hinge - upb * 0.025, hinge + ab * (bl * 0.42) - upb * 0.025, 0.03, WOOD)
    else:  # Winchester 1866 "Yellow Boy"
        out += frustum(at(0.0, (0, -0.04)), at(0.28), 0.055, 0.028, WOOD)
        out += frustum(at(0.27), at(0.43), 0.045, 0.045, (232, 186, 72))               # brass receiver
        out += beam(at(0.43, (0, 0.014)), at(1.0, (0, 0.014)), 0.015, GUNMETAL)
        out += beam(at(0.43, (0, -0.02)), at(0.93, (0, -0.02)), 0.013, STEEL)
        out += beam(at(0.43), at(0.64), 0.03, WOOD)
        drop = 0.08 * lever                                                          # lever loop
        out += beam(at(0.3 - 0.05 * lever, (0, -0.05 - drop)), at(0.4 - 0.08 * lever, (0, -0.1 - drop)), 0.011, STEEL)
        out += beam(at(0.4 - 0.08 * lever, (0, -0.1 - drop)), at(0.44, (0, -0.05)), 0.011, STEEL)
    return out


def gun_muzzle(kind, butt, direction, broken=0.0):
    a = np.array(direction, float)
    a /= np.linalg.norm(a)
    return np.array(butt, float) + a * GUN_LEN[kind]


# ---------------------------------------------------------------- rig: hats

def _hat(look, z):
    out = Cloud()
    kind = look.get("hat")
    col, band = look.c("hat"), look.c("band")
    under = tuple(int(c * 0.6) for c in col)
    if kind == "slick":
        # no hat: hair slicked down flat with pomade, a parting
        with look.tag("hair"):
            out += ellipsoid((-0.01, 0, z - 0.06), (0.1, 0.095, 0.05), look.c("hair"))
        return out
    if kind == "bare":
        # no hat (they took it off him): a man's own hair, tousled and uncombed
        def tousled(P, N):
            c = np.tile(np.array(look.c("hair"), float), (len(P), 1))
            c *= (0.8 + 0.35 * hash01(np.floor(P[:, 0] * 45), np.floor(P[:, 1] * 45), np.floor(P[:, 2] * 45)))[:, None]
            return c
        with look.tag("hair"):
            out += ellipsoid((-0.012, 0, z - 0.05), (0.1, 0.094, 0.07), tousled, zmin=z - 0.075)
            out += ellipsoid((-0.06, 0, z - 0.1), (0.06, 0.09, 0.07), tousled)   # down the back of his head
        return out
    if kind == "hood":
        # the hangman's black hood: a sack over the whole head with holes cut for the
        # eyes, peaked a little on top, its skirt falling over his shoulders
        with look.tag("hat"):
            hc = (0.01, 0, z - 0.07)
            hood = ellipsoid(hc, (0.106, 0.097, 0.124), col)
            rel = hood.P - np.array(hc)
            eyes = (rel[:, 0] > 0.05) & (np.abs(np.abs(rel[:, 1]) - 0.035) < 0.022) & (np.abs(rel[:, 2] - 0.012) < 0.02)
            out += Cloud(hood.P[~eyes], hood.N[~eyes], hood.C[~eyes], hood.S[~eyes])
            out += frustum((0.0, 0, z + 0.02), (-0.01, 0, z + 0.1), 0.06, 0.012, col)
            out += frustum((0.0, 0, z - 0.17), (-0.01, 0, z - 0.27), 0.1, 0.17, col, su=0.8, caps=False)
        return out
    if kind == "none":
        # hair up in a bun, with a flower
        with look.tag("hair"):
            out += ellipsoid((-0.07, 0, z - 0.04), (0.07, 0.07, 0.06), look.c("hair"))
        with look.tag("accent"):
            out += ellipsoid((-0.03, 0.07, z - 0.02), (0.03, 0.03, 0.03), look.c("accent"))
        return out
    if kind == "rebozo":
        # a black shawl drawn up over the head, open at the face, falling down the back
        with look.tag("hat"):
            hood = ellipsoid((-0.005, 0, z - 0.075), (0.112, 0.104, 0.135), col)
            keep = ~((hood.P[:, 0] > 0.035) & (hood.P[:, 2] < z - 0.01))
            out += Cloud(hood.P[keep], hood.N[keep], hood.C[keep], hood.S[keep])
            out += frustum((-0.05, 0, z - 0.1), (-0.07, 0, z - 0.4), 0.09, 0.17, col, su=0.8, caps=False)
        return out
    if kind == "habit":
        # a nun's black veil over the head and down the back, and under it the white
        # coif framing her face
        with look.tag("hat"):
            hood = ellipsoid((-0.005, 0, z - 0.075), (0.114, 0.106, 0.137), col)
            keep = ~((hood.P[:, 0] > 0.03) & (hood.P[:, 2] < z - 0.0))
            out += Cloud(hood.P[keep], hood.N[keep], hood.C[keep], hood.S[keep])
            out += frustum((-0.05, 0, z - 0.1), (-0.08, 0, z - 0.42), 0.09, 0.16, col, su=0.8, caps=False)
        coif = ellipsoid((0.0, 0, z - 0.075), (0.108, 0.1, 0.13), (236, 234, 228))
        face = (coif.P[:, 0] > 0.07) & (np.abs(coif.P[:, 1]) < 0.06) & (coif.P[:, 2] < z - 0.035) & (coif.P[:, 2] > z - 0.17)
        keep = (coif.P[:, 0] > 0.0) & ~face
        out += Cloud(coif.P[keep], coif.N[keep], coif.C[keep], coif.S[keep])
        return out
    if kind in ("kepi", "cap"):
        # an officer's kepi, its crown tipped forward; or a general's peaked cap,
        # wide on top; each with a braided band and a short leather visor
        with look.tag("hat"):
            if kind == "kepi":
                out += frustum((-0.01, 0, z - 0.03), (0.03, 0, z + 0.13), 0.108, 0.088, col)
            else:
                out += frustum((0, 0, z - 0.03), (0, 0, z + 0.07), 0.104, 0.135, col)
                out += ellipsoid((0, 0, z + 0.07), (0.135, 0.13, 0.02), col)
        with look.tag("band"):
            out += frustum((0, 0, z - 0.03), (0, 0, z + 0.01), 0.11, 0.11, band, caps=False)
        out += ellipsoid((0.1, 0, z - 0.03), (0.07, 0.085, 0.012), (30, 26, 24))   # the visor
        return out
    if kind == "fur":
        # coonskin cap with the tail hanging down the back
        def fur(P, N):
            c = np.tile(np.array(col, float), (len(P), 1))
            c *= (0.82 + 0.3 * hash01(np.floor(P[:, 0] * 60), np.floor(P[:, 1] * 60), np.floor(P[:, 2] * 60)))[:, None]
            return c
        with look.tag("hat"):
            out += ellipsoid((0, 0, z + 0.02), (0.125, 0.118, 0.11), fur, zmin=z - 0.03)

        def tail(P, N):
            c = np.tile(np.array(band, float), (len(P), 1))
            stripes = (P[:, 2] * 22) % 1.0 < 0.45
            c[stripes] = np.array(col, float) * 0.7
            return c
        with look.tag("band"):
            out += frustum((-0.11, 0, z + 0.04), (-0.17, 0.02, z - 0.24), 0.035, 0.028, tail)
        return out
    with look.tag("hat"):
        if kind == "flat":
            out += disc((0.01, 0, z), 0.36, col, curl=0.035, front_curl=0.6, underside=under)
        elif kind == "sombrero":
            out += disc((0, 0, z), 0.5, col, curl=0.14, front_curl=0.55, underside=under)
        elif kind == "slouch":
            out += disc((0.01, 0, z), 0.33, col, curl=-0.07, front_curl=0.9, underside=under)   # brim droops
        elif kind == "top":
            out += disc((0, 0, z), 0.17, col, curl=0.03, front_curl=0.3, underside=under)
        else:  # bowler
            out += disc((0, 0, z), 0.165, col, curl=0.035, front_curl=0.2, underside=under)
    with look.tag("band"):
        r0 = {"sombrero": 0.13, "bowler": 0.112, "top": 0.11}.get(kind, 0.118)
        out += frustum((0, 0, z), (0, 0, z + (0.05 if kind == "sombrero" else 0.035)), r0, r0 - 0.003, band, caps=False)
    with look.tag("hat"):
        if kind == "flat":
            out += frustum((0, 0, z + 0.04), (0, 0, z + 0.14), 0.115, 0.1, col)
        elif kind == "sombrero":
            out += frustum((0, 0, z + 0.05), (0, 0, z + 0.26), 0.125, 0.06, col)
        elif kind == "slouch":
            out += frustum((0, 0, z + 0.035), (0.02, 0, z + 0.12), 0.115, 0.09, col)
        elif kind == "top":
            out += frustum((0, 0, z + 0.035), (0, 0, z + 0.26), 0.105, 0.11, col)
        else:
            out += ellipsoid((0, 0, z + 0.02), (0.112, 0.105, 0.13), col, zmin=z + 0.02)
    return out


# ---------------------------------------------------------------- rig: legs layer

def legs_pose(kind="stand", phase=0.0, amount=1.0):
    """Leg joints for a named stance. Returns {"H": hip height, "legs": [(hip, knee,
    ankle)] (left first), "sway", "crouch"}."""
    legs = []
    if kind in ("crouch", "kneel"):
        H = 0.5
        sh = 0.04 * math.sin(phase)
        legs.append(((0, 0.1, H), (0.34 + sh, 0.11, H - 0.02), (0.3 + sh, 0.11, 0.09)))
        legs.append(((0, -0.1, H), (0.06 - sh, -0.12, 0.09), (-0.36 - sh, -0.12, 0.08)))
        if kind == "kneel":   # both knees down, sitting back on the heels
            H = 0.55
            legs = [((0, 0.1, H), (0.28, 0.11, 0.08), (-0.12, 0.11, 0.06)),
                    ((0, -0.1, H), (0.28, -0.11, 0.08), (-0.12, -0.11, 0.06))]
        return {"H": H, "legs": legs, "sway": 0.0, "crouch": True}
    if kind == "sit":
        H = 0.22
        legs = [((0, 0.1, H), (0.38, 0.12, 0.3), (0.62, 0.12, 0.07)),
                ((0, -0.1, H), (0.4, -0.12, 0.22), (0.7, -0.12, 0.07))]
        return {"H": H, "legs": legs, "sway": 0.0, "crouch": True}
    H0 = 0.92
    for side, ph in ((1, phase), (-1, phase + math.pi)):
        s = b = 0.0
        if kind == "walk":
            s = 0.42 * math.sin(ph)
            b = 0.55 * max(0.0, -math.sin(ph + 0.6))
        elif kind == "limp":
            stiff = side < 0                       # the wounded right leg barely bends
            s = (0.22 if stiff else 0.36) * math.sin(ph)
            b = 0.0 if stiff else 0.5 * max(0.0, -math.sin(ph + 0.6))
        elif kind == "stagger":
            # stumbling back a step: left leg reaches back, knees give
            s = -0.45 * amount if side > 0 else 0.15 * amount
            b = 0.35 * amount
        hip = np.array([0, 0.1 * side, H0])
        knee = hip + np.array([math.sin(s), 0, -math.cos(s)]) * 0.42
        ankle = knee + np.array([math.sin(s - b), 0, -math.cos(s - b)]) * 0.42
        legs.append((hip, knee, ankle))
    lowest = min(l[2][2] for l in legs)
    dz = 0.1 - lowest
    if kind == "limp":
        dz -= 0.04 * max(0.0, math.sin(phase + math.pi))   # dips onto the bad leg
    legs = [tuple(np.array(v, float) + [0, 0, dz] for v in leg) for leg in legs]
    sway = 0.05 * math.sin(phase * 2) if kind in ("walk", "limp") else (0.06 * amount if kind == "stagger" else 0.0)
    return {"H": H0 + dz, "legs": legs, "sway": sway, "crouch": False}


def _fringe(look, H, z, r, su, yoke=False):
    """Buckskin fringe: a row of short thongs hanging from a hem (or across the yoke)."""
    out = Cloud()
    col = tuple(int(c * 0.82) for c in look.c("coat"))
    n = 22
    for i in range(n):
        a = i / n * 2 * math.pi
        if abs(math.atan2(math.sin(a), math.cos(a))) < (0.45 if not yoke else 0.0) and not yoke:
            continue
        x, y = math.cos(a) * r * su, math.sin(a) * r
        top = np.array([x, y, z if yoke else z + 0.0])
        out += beam(top, top + [x * 0.12, y * 0.12, -0.085], 0.009, col)
    return out


def build_legs(look, lp):
    """Trousers, boots, spurs and the skirt of a coat (or a dress)."""
    m = Cloud()
    H = lp["H"]
    style = look.get("style")
    crouch = lp["crouch"]
    for hip, knee, ankle in lp["legs"]:
        hip, knee, ankle = (np.array(v, float) for v in (hip, knee, ankle))
        if style != "dress":
            with look.tag("trousers"):
                m += frustum(hip, knee, 0.078, 0.064, look.c("trousers"))
                m += frustum(knee, ankle, 0.064, 0.052, look.c("trousers"))
        toe = 1.0 if ankle[0] >= knee[0] - 0.2 or not crouch else -1.0
        with look.tag("boots"):
            m += ellipsoid(ankle + [0.05 * toe, 0, -0.035], (0.125, 0.055, 0.06), look.c("boots"))
        if style not in ("dress", "suit"):
            m += frustum(ankle + [-0.09 * toe, -0.012, -0.03], ankle + [-0.09 * toe, 0.012, -0.03],
                         0.03, 0.03, (176, 176, 168))  # spur rowel
    if look.get("apron"):
        with look.tag("accent"):
            for x, n in ((0.1, 1.0), (0.085, -1.0)):
                m += quad((x, -0.15, H + 0.02), (0, 0.3, 0), (0.02, 0, -0.5 if not crouch else -0.3),
                          tuple(int(c * 0.92) for c in look.c("accent")), normal=(n, 0, 0))
    if style == "buckskin":
        bottom = H - 0.24 if not crouch else H - 0.2
        with look.tag("coat"):
            m += frustum((0, 0, H + 0.02), (-0.02 - lp["sway"] * 0.5, 0, bottom), 0.2, 0.24,
                         _coat_fn(look, -5.0), su=0.75, gap=(0.0, 0.4), caps=False)
            m += _fringe(look, H, bottom, 0.24, 0.75)
    if style == "uniform":   # the tunic's skirt, short and closed
        with look.tag("coat"):
            m += frustum((0, 0, H + 0.04), (-0.01, 0, H - (0.12 if crouch else 0.2)), 0.17, 0.2,
                         look.c("coat"), su=0.72, caps=False)
    if style in ("duster", "suit"):
        bottom = 0.05 if crouch else (max(0.04, H - 0.55) if style == "duster" else H - 0.32)
        with look.tag("coat"):
            m += frustum((0, 0, H + 0.02), (-0.04 - lp["sway"], 0, bottom), 0.21,
                         (0.38 if crouch else 0.31) if style == "duster" else 0.25,
                         _coat_fn(look, bottom), su=0.95 if crouch else 0.72,
                         gap=(0.0, 0.8 if style == "duster" else 0.45), caps=False)
    elif style == "dress":
        # long skirt to the ground with a darker hem; sways as she walks
        def skirt(P, N):
            c = np.tile(np.array(look.c("dress"), float), (len(P), 1))
            c[P[:, 2] < 0.12] *= 0.72
            return c
        with look.tag("dress"):
            m += frustum((0, 0, H + 0.04), (-0.03 - lp["sway"], 0, 0.04), 0.17,
                         0.42 if crouch else 0.36, skirt, su=0.95 if crouch else 0.85, caps=False)
    return m


# ---------------------------------------------------------------- rig: upper layer

def _colours():
    """The federal army's colours: the tricolour, green at the staff, white with the
    eagle on its cactus, red, on a staff carried in the crook of the left arm, the
    cloth streaming back behind him."""
    m = Cloud()
    base, top = np.array([0.08, 0.27, -0.55]), np.array([0.12, 0.27, 1.5])
    m += beam(base, top, 0.016, (120, 92, 60))
    m += ellipsoid(top + [0, 0, 0.03], (0.025, 0.025, 0.03), BRASS)                   # the finial
    cols = np.array([(46, 112, 66), (232, 228, 214), (188, 40, 36)], float)
    u = np.linspace(0, 1, 70)
    v = np.linspace(0, 1, 46)
    U, Vv = np.meshgrid(u, v, indexing="ij")
    W, Hh = 0.72, 0.46
    P_ = np.stack([top[0] - U * W, top[1] + 0.05 * np.sin(U * 7.0 + Vv * 1.5) * U, top[2] - 0.04 - Vv * Hh - U * 0.08], -1)
    C = cols[np.minimum((U * 3).astype(int), 2)]
    eagle = (np.abs(U - 0.5) < 0.07) & (np.abs(Vv - 0.5) < 0.18)
    C[eagle] = (120, 86, 52)
    C[eagle & (Vv > 0.6)] = (70, 120, 70)   # the cactus under it
    n = P_.size // 3
    for side in (1.0, -1.0):   # both faces of the cloth, a hair apart
        m += Cloud(P_.reshape(-1, 3) + [0, 0.003 * side, 0], np.tile([0.0, side, 0.0], (n, 1)), C.reshape(-1, 3),
                   np.zeros(n, np.uint8))
    return m


def build_upper(look, weapon, up, H=H_REF, with_gun=True, extra=None):
    """Belt and up: torso, coat body and cape, arms, head, hat and gun, posed by `up`
    (hip-relative) and placed with the hip at height H. Returns (cloud, muzzle point);
    a left-hand gun's muzzle goes in extra["muzzle2"] when `extra` is given."""
    m = Cloud()
    style = look.get("style")
    if style != "dress":
        m += frustum((0, 0, -0.05), (0, 0, 0.06), 0.168, 0.168, LEATHER, su=0.74)
        m += box((0.11, -0.03, -0.03), (0.135, 0.03, 0.04), BRASS)  # buckle
        if look.get("sash"):   # a cloth sash wound over the belt, the ends hanging at the hip
            with look.tag("accent"):
                m += frustum((0, 0, -0.02), (0, 0, 0.09), 0.175, 0.172, look.c("accent"), su=0.74)
                m += frustum((0.02, 0.15, 0.0), (0.0, 0.17, -0.2), 0.03, 0.022, look.c("accent"))
        if look.get("holsters", 1) > 0:
            m += box((-0.05, -0.2, -0.22), (-0.05 + 0.1, -0.16, -0.02), LEATHER)  # holster
        if look.get("holsters", 1) > 1:
            m += box((-0.05, 0.16, -0.22), (-0.05 + 0.1, 0.2, -0.02), LEATHER)
    m += frustum((0, 0, 0.04), (0, 0, 0.5), 0.15 if style != "dress" else 0.13, 0.19, _torso_fn(look), su=0.62)
    sleeve = forearm = "shirt"
    if style == "uniform":
        sleeve = forearm = "coat"
    if style == "buckskin":
        with look.tag("coat"):
            m += frustum((0, 0, 0.52), (0, 0, 0.0), 0.2, 0.21, _coat_fn(look, -5.0), su=0.7, gap=(0.0, 0.45), caps=False)
            m += frustum((0, 0, 0.5), (0, 0, 0.6), 0.1, 0.085, _coat_fn(look, -5.0), caps=False)
            m += _fringe(look, 0.0, 0.42, 0.2, 0.7, yoke=True)
        sleeve = forearm = "coat"
    if style in ("duster", "suit"):
        with look.tag("coat"):
            coat = _coat_fn(look, -5.0)
            m += frustum((0, 0, 0.52), (0, 0, 0.0), 0.2, 0.22, coat, su=0.7,
                         gap=(0.0, 0.8 if style == "duster" else 0.5), caps=False)
            if style == "duster":
                m += frustum((0, 0, 0.58), (0, 0, 0.36), 0.12, 0.27, coat, su=0.82, caps=False)
            m += frustum((0, 0, 0.5), (0, 0, 0.6), 0.1, 0.085, coat, caps=False)
        sleeve = forearm = "coat"
    elif style == "poncho":
        m += frustum((0, 0, 0.6), (0, 0, 0.12), 0.09, 0.42, _poncho_fn(look), su=0.92, caps=False)
        sleeve = forearm = "poncho_a"
    elif style == "dress":
        if look.get("shawl", True):
            with look.tag("accent"):   # shawl over the shoulders
                m += frustum((0, 0, 0.6), (0, 0, 0.38), 0.11, 0.26, look.c("accent"), su=0.8, caps=False)
        sleeve, forearm = "dress", "dress" if look.get("sleeves") else "skin"

    with look.tag("skin"):
        m += frustum((0, 0, 0.5), (0, 0, 0.63), 0.05, 0.05, look.c("skin"))
    if look.get("collar"):   # a priest's white collar
        m += frustum((0, 0, 0.585), (0, 0, 0.625), 0.092, 0.088, (232, 228, 218))
    if look.get("wimple"):   # a nun's white wimple, close round the throat and over the shoulders
        m += frustum((0, 0, 0.66), (0, 0, 0.5), 0.085, 0.16, (236, 234, 228), su=0.85, caps=False)
    if look.get("rosary"):   # wooden beads hung from her belt, a small cross at the end
        for i in range(9):
            f = i / 8.0
            m += ellipsoid((0.1 + 0.03 * f, 0.13 - 0.02 * f, 0.18 - 0.3 * f), (0.013, 0.013, 0.013), (70, 46, 30))
        m += beam((0.135, 0.11, -0.13), (0.135, 0.11, -0.2), 0.009, (70, 46, 30))
        m += beam((0.135, 0.085, -0.155), (0.135, 0.135, -0.155), 0.009, (70, 46, 30))
    if look.get("scarf"):
        with look.tag("accent"):
            m += frustum((0, 0, 0.5), (0, 0, 0.6), 0.1, 0.075, look.c("accent"))
            m += frustum((0.06, -0.02, 0.5), (0.1, -0.03, 0.36), 0.05, 0.025, look.c("accent"))
    hc = np.array([0.01, 0, 0.72])
    head = Cloud()
    head += ellipsoid(hc, (0.095, 0.085, 0.11), _head_fn(look, hc))
    with look.tag("skin"):
        head += ellipsoid(hc + [0.09, 0, -0.005], (0.025, 0.02, 0.03), look.c("skin"))  # nose
    if look.get("mustache"):
        with look.tag("hair"):
            head += ellipsoid(hc + [0.085, 0, -0.045], (0.02, 0.06, 0.015), look.c("hair"))
    if look.get("beard"):
        with look.tag("hair"):
            # a full beard spilling down the chest, so it shows from under a hat brim
            head += ellipsoid(hc + [0.065, 0, -0.1], (0.065, 0.085, 0.085), look.c("hair"))
            head += ellipsoid(hc + [0.1, 0, -0.19], (0.05, 0.075, 0.08), look.c("hair"))
            head += ellipsoid(hc + [0.13, 0, -0.27], (0.035, 0.05, 0.06), look.c("hair"))
    if look.get("spectacles"):
        for side in (-1, 1):
            head += ellipsoid(hc + [0.088, side * 0.036, 0.012], (0.008, 0.02, 0.016), (210, 220, 226))
        head += beam(hc + [0.094, -0.016, 0.014], hc + [0.094, 0.016, 0.014], 0.005, (120, 110, 90))
    if look.get("cigar"):
        head += beam(hc + [0.08, 0.02, -0.06], hc + [0.16, 0.035, -0.075], 0.011, (196, 180, 150))
        head += ellipsoid(hc + [0.165, 0.036, -0.076], (0.014, 0.014, 0.014), (255, 120, 40))
    head += _hat(look, 0.79)
    nod = up.get("nod", 0.0)
    if nod:
        head.transform(rot_y(nod), pivot=(0, 0, 0.6))
    m += head

    sL = np.array([0, 0.21, 0.48])
    sR = np.array([0, -0.21, 0.48])
    for s, e, h in ((sL, up["eL"], up["hL"]), (sR, up["eR"], up["hR"])):
        e, h = np.array(e, float), np.array(h, float)
        with look.tag(sleeve):
            m += frustum(s, e, 0.058, 0.05, look.c(sleeve))
        if look.get("garters"):   # sleeve garters, holding his cuffs up out of the lather
            with look.tag("band"):
                m += frustum(s + (e - s) * 0.5, s + (e - s) * 0.64, 0.062, 0.058, look.c("band"))
        with look.tag(forearm):
            m += frustum(e, h, 0.05, 0.042, look.c(forearm))
        with look.tag("skin"):
            m += ellipsoid(h, (0.045, 0.04, 0.045), look.c("skin"))
    with look.tag(sleeve):
        m += ellipsoid((0, 0.17, 0.46), (0.08, 0.07, 0.07), look.c(sleeve))
        m += ellipsoid((0, -0.17, 0.46), (0.08, 0.07, 0.07), look.c(sleeve))
    if look.get("epaulettes"):   # gold on the shoulders, with a fringe
        for side in (-1, 1):
            m += ellipsoid((0, side * 0.18, 0.51), (0.07, 0.065, 0.022), BRASS)
            for k in range(5):
                a = (k - 2) * 0.03
                m += beam((a, side * 0.235, 0.505), (a, side * 0.25, 0.44), 0.008, BRASS)
    if look.get("sabre"):   # a cavalry sabre in its scabbard, hung at the left hip
        m += beam((-0.02, 0.2, -0.02), (-0.3, 0.27, -0.74), 0.018, (52, 50, 54))
        m += beam((-0.3, 0.27, -0.74), (-0.31, 0.272, -0.78), 0.02, (150, 140, 120))
        m += beam((-0.02, 0.2, -0.02), (0.05, 0.19, 0.1), 0.014, BRASS)   # the hilt
        m += ellipsoid((-0.01, 0.2, 0.0), (0.04, 0.03, 0.02), BRASS)
    if up.get("finger"):
        h = np.array(up["hL"], float)
        with look.tag("skin"):
            m += beam(h + [0.03, 0, 0], h + [0.12, -0.01, 0.01], 0.014, look.c("skin"))
    if up.get("book"):   # the priest's breviary, held to his chest
        h = np.array(up["hL"], float)
        m += box(tuple(h + [-0.03, -0.05, -0.02]), tuple(h + [0.04, 0.03, 0.11]), (34, 26, 24))
        m += box(tuple(h + [-0.031, -0.01, 0.03]), tuple(h + [0.041, -0.005, 0.07]), (200, 170, 80))
    if up.get("armful"):   # guns gathered up, cradled across his chest
        c = (np.array(up["hL"], float) + np.array(up["hR"], float)) / 2
        for i, (kind, d) in enumerate((("rifle", (0.25, 1.0, 0.25)), ("coach", (0.2, 1.0, 0.45)),
                                        ("colt", (0.1, 1.0, 0.0)))):
            dv = np.array(d) / np.linalg.norm(d)
            m += weapon_model(kind, c + [0.03 * i, 0, 0.03 * i] - dv * GUN_LEN[kind] * 0.5, dv)
    if up.get("rifles"):   # loose rifles gathered up in his arms, the barrels up over his shoulder
        c = (np.array(up["hL"], float) + np.array(up["hR"], float)) / 2
        for i in range(5):   # fanned out, so it reads as an armful and not one gun
            d = rot_z((i - 2) * 0.22) @ np.array([0.25, 1.0, 0.5 - 0.06 * i])
            d /= np.linalg.norm(d)
            m += weapon_model("rifle", c + [0.04 * (i - 2), 0.05 * (i - 2), 0.03 * i] - d * GUN_LEN["rifle"] * 0.45, d)
    if up.get("case") is not None:   # a case of rifles held in front of him, across his chest
        c = np.array(up["case"], float)
        pine = lambda P, N: np.where((np.abs(P[:, 2] - c[2]) < 0.025)[:, None], [[96, 74, 52]], [[182, 148, 102]])
        m += box(tuple(c - [0.16, 0.4, 0.12]), tuple(c + [0.16, 0.4, 0.12]), pine)
        for side in (-1, 1):   # the rope handles
            m += beam(c + [-0.06, side * 0.41, 0.04], c + [0.06, side * 0.41, 0.04], 0.012, (190, 170, 120))
    if up.get("knife"):   # a Bowie knife in the off hand, blade forward
        e, h = np.array(up["eL"], float), np.array(up["hL"], float)
        d = (h - e) / np.linalg.norm(h - e)
        m += beam(h - d * 0.04, h + d * 0.03, 0.016, (70, 46, 30))         # handle
        m += beam(h + d * 0.03, h + d * 0.22, 0.012, (214, 214, 220))      # blade
    if up.get("stick"):   # a stick of dynamite in the off hand, its fuse fizzing
        h = np.array(up["hL"], float)
        m += beam(h + [0, 0, -0.07], h + [0, 0, 0.09], 0.026, (168, 38, 30))
        m += beam(h + [0, 0, -0.005], h + [0, 0, 0.015], 0.028, (214, 198, 160))   # the paper band
        m += beam(h + [0, 0, 0.09], h + [0.02, 0, 0.13], 0.007, (48, 40, 32))      # the fuse
        m += ellipsoid(h + [0.022, 0, 0.14], (0.018, 0.018, 0.018), (255, 226, 120))
    if up.get("roll"):   # a bandage: a roll of it in the right hand, wound round the left forearm
        e, h = np.array(up["eL"], float), np.array(up["hL"], float)
        m += frustum(e + (h - e) * 0.45, e + (h - e) * 0.8, 0.058, 0.052, (232, 228, 216))
        m += ellipsoid(np.array(up["hR"], float) + [0.02, 0, 0], (0.035, 0.035, 0.035), (240, 236, 226))
    if up.get("hammer"):   # a claw hammer in the right hand, head across the end of the haft
        e, h = np.array(up["eR"], float), np.array(up["hR"], float)
        d = (h - e) / np.linalg.norm(h - e)
        end = h + d * 0.2
        side = np.cross(d, [0, 0, 1.0])
        side = side / (np.linalg.norm(side) + 1e-6) if np.linalg.norm(side) > 0.1 else np.array([0, 1.0, 0])
        m += beam(h - d * 0.04, end, 0.014, (120, 84, 52))
        m += beam(end - side * 0.06, end + side * 0.05, 0.022, (70, 70, 76))
    if up.get("broom") is not None:   # a broom: straw head at `broom`, the haft up through his hand
        head = np.array(up["broom"], float)
        grip = np.array(up["hR"], float)
        d = (grip - head) / np.linalg.norm(grip - head)
        m += frustum(head, head + d * 0.2, 0.08, 0.03, (206, 176, 106))
        m += beam(head + d * 0.18, head + d * 1.3, 0.016, (150, 112, 70))
    if up.get("spade") is not None:   # a long-handled spade: blade at `spade`, the haft up through both hands
        blade = np.array(up["spade"], float)
        grip = np.array(up["hR"], float)
        d = (grip - blade) / np.linalg.norm(grip - blade)
        m += frustum(blade, blade + d * 0.24, 0.075, 0.05, (120, 116, 112))
        m += beam(blade + d * 0.22, blade + d * 1.35, 0.016, (150, 112, 70))
        m += beam(blade + d * 1.3, blade + d * 1.38, 0.03, (150, 112, 70))   # the D grip
        if up.get("dirt"):
            m += ellipsoid(blade + d * 0.06, (0.07, 0.07, 0.04), (92, 64, 42))
    if up.get("towel"):   # a bar towel over his arm
        h = np.array(up["hL"], float)
        m += box(tuple(h + [-0.05, -0.04, -0.12]), tuple(h + [0.04, 0.04, 0.02]), (232, 228, 214))
    if up.get("bag"):   # the barber-surgeon's black leather bag, hanging from his hand
        h = np.array(up["hL"], float)
        m += box(tuple(h + [-0.09, -0.04, -0.17]), tuple(h + [0.09, 0.04, -0.04]), (30, 24, 22))
        m += beam(h + [-0.03, 0, -0.04], h + [0.03, 0, -0.04], 0.01, BRASS)
    if up.get("gauze"):   # a roll of lint bandage in his right hand, a strip of it run to the left
        hL, hR = np.array(up["hL"], float), np.array(up["hR"], float)
        m += ellipsoid(hR + [0.02, 0, 0], (0.035, 0.035, 0.035), (240, 236, 226))
        m += beam(hR, hL, 0.012, (236, 232, 222))
    if up.get("hanky"):   # a white handkerchief pressed to her eyes
        h = np.array(up["hR"], float)
        m += box(tuple(h + [-0.02, -0.03, -0.04]), tuple(h + [0.03, 0.03, 0.03]), (232, 228, 220))
    if up.get("bonds"):   # rope round his wrists, tied behind his back
        hL, hR = np.array(up["hL"], float), np.array(up["hR"], float)
        rope = (176, 156, 112)
        for h in (hL, hR):
            m += ellipsoid(h + [0.0, 0, 0.03], (0.035, 0.035, 0.022), rope)
        m += beam(hL + [0, 0, 0.03], hR + [0, 0, 0.03], 0.016, rope)
        m += beam((hL + hR) * 0.5 + [0, 0, 0.03], (hL + hR) * 0.5 + [-0.02, 0, -0.1], 0.01, rope)   # the loose end
    if up.get("tape"):   # the undertaker's tape measure, stretched between his hands
        m += beam(np.array(up["hL"], float), np.array(up["hR"], float), 0.009, (226, 204, 120))

    if weapon == "banner":
        m += _colours()
    if up.get("rod"):   # a ramrod held in the right fist, its end down the barrel
        h, gd = np.array(up["hR"], float), up["gun"]["D"]
        m += beam(h + gd * 0.05, h - gd * 0.5, 0.007, (176, 178, 184))
    muzzle = muzzle2 = None
    g = up.get("gun")
    art = GUN_ART.get(weapon, weapon)
    if with_gun and g is not None:
        m += weapon_model(art, g["B"], g["D"], up.get("lever", 0.0), up.get("broken", 0.0))
        muzzle = gun_muzzle(art, g["B"], g["D"])
    g2 = up.get("gun2")
    if with_gun and g2 is not None:
        m += weapon_model(art, g2["B"], g2["D"])
        muzzle2 = gun_muzzle(art, g2["B"], g2["D"])

    # lean (pitch, + forward) and twist (yaw) about the hip
    R = rot_z(up.get("twist", 0.0)) @ rot_y(up.get("lean", 0.0))
    m.transform(R)
    m.translate((0, 0, H))
    if muzzle is not None:
        muzzle = R @ muzzle + [0, 0, H]
    if extra is not None and muzzle2 is not None:
        extra["muzzle2"] = R @ muzzle2 + [0, 0, H]
    return m, muzzle


# ---------------------------------------------------------------- pose library

def V(*a):
    return np.array(a, float)


def G(B, D):
    D = np.array(D, float)
    return {"B": np.array(B, float), "D": D / np.linalg.norm(D)}


HANG_L = dict(eL=V(-0.02, 0.25, 0.2), hL=V(0.03, 0.23, -0.04))
BELT_L = dict(eL=V(0.0, 0.27, 0.22), hL=V(0.06, 0.17, 0.02))       # reaching for cartridges


def P(base, **kw):
    """A pose: `base` with overrides."""
    out = dict(base)
    out.update(kw)
    return out


def _key_poses(w):
    """The handful of key poses each gun needs; animations are built from these."""
    if w == "sharps":
        k = _key_poses("rifle")
        k["kick"] = P(k["kick"], lean=-0.17, gun=G((-0.16, -0.12, 0.48), (0.95, 0.07, 0.22)))
        k["cock"] = P(k["aim"], hR=V(0.14, -0.1, 0.42))                              # thumb on the hammer
        k["load"] = P(k["load"], lever=1.0)
        k["eject_a"] = P(k["load"], hR=V(0.1, -0.11, 0.28))
        k["eject_b"] = P(k["load"], hR=V(0.16, -0.08, 0.36))
        k["insert_a"] = P(k["insert_a"], lever=1.0)
        k["insert_b"] = P(k["insert_b"], lever=1.0)
        return k
    if w == "remington":
        return _key_poses("sharps")   # a full-length single shot, held and loaded like the Sharps
    if w == "banner":
        # the colours: the staff in the crook of the left arm, the left hand on it while
        # he shoots (one-handed, a Navy), off it only to load
        k = _key_poses("colt")
        for name in ("aim", "kick", "cock"):
            k[name] = P(k[name], eL=V(0.0, 0.27, 0.24), hL=V(0.1, 0.25, 0.14))
        return k
    if w == "rollingblock":
        # worked like the Sharps, but the short gun sits forward, its sawn grip in the
        # right hand where a full stock's wrist would be
        k = _key_poses("sharps")
        for name, pose in list(k.items()):
            if pose.get("gun") is not None:
                pose = P(pose, gun=G(pose["gun"]["B"] + pose["gun"]["D"] * 0.2, pose["gun"]["D"]))
            k[name] = pose
        return k
    if w == "spencer":
        k = _key_poses("rifle")
        k["cock"] = P(k["aim"], eR=V(-0.04, -0.28, 0.3), hR=V(0.16, -0.08, 0.44))     # thumb back on the hammer
        return k
    if w in MUZZLE_LOADERS:
        # shouldered like a rifle; loaded standing, the butt by his left foot and the
        # muzzle at his chest: powder poured in, then the ball (or wad and shot) rammed
        k = _key_poses("rifle")
        k["kick"] = P(k["kick"], lean=-0.16, gun=G((-0.16, -0.12, 0.48), (0.95, 0.07, 0.22)))
        k["cock"] = P(k["aim"], hR=V(0.14, -0.1, 0.42))
        D = V(-0.1, -0.02, 1.0)
        D /= np.linalg.norm(D)
        B = V(0.3, 0.06, -0.9)
        mz = B + D * GUN_LEN[w]
        hold = dict(eL=V(0.12, 0.27, 0.27), hL=B + D * GUN_LEN[w] * 0.72, gun=G(B, D))
        k["load"] = dict(eR=V(0.08, -0.3, 0.3), hR=V(0.18, -0.16, 0.3), **hold)
        k["pour_a"] = dict(eR=V(0.1, -0.34, 0.34), hR=mz + V(0.02, -0.03, 0.07), **hold)
        k["pour_b"] = dict(eR=V(0.1, -0.33, 0.36), hR=mz + V(0.01, -0.02, 0.1), **hold)
        k["ram_hi"] = dict(eR=V(0.12, -0.3, 0.6 + mz[2] * 0.3), hR=mz + V(0.0, -0.02, 0.36), rod=True, **hold)
        k["ram_lo"] = dict(eR=V(0.1, -0.33, 0.36), hR=mz + V(0.0, -0.02, 0.07), rod=True, **hold)
        return k
    if w == "howdah":
        k = _key_poses("colt")
        k["kick"] = P(k["kick"], lean=-0.16, gun=G((0.36, -0.07, 0.62), (0.15, 0, 0.3)))
        for name in ("load", "eject_a", "eject_b", "insert_a", "insert_b"):
            k[name] = P(k[name], broken=1.0, gun=G((0.24, -0.1, 0.27), (0.3, 0.08, 0.05)))
        k["load_half"] = P(k["load"], broken=0.5)
        return k
    if w == "colts":
        return _twin_poses()
    if w == "prayer":
        # empty hands, a book in the left, and the sign of the cross with the right:
        # up, down, across
        k = _key_poses("unarmed")
        book = dict(eL=V(0.08, 0.25, 0.3), hL=V(0.22, 0.1, 0.36), book=True)
        k["aim"] = P(k["aim"], **book)
        base = dict(eR=V(0.22, -0.2, 0.45), lean=0.25, nod=0.25, **book)
        k["bless_a"] = P(base, hR=V(0.44, -0.06, 0.66))
        k["bless_b"] = P(base, hR=V(0.44, -0.06, 0.36), eR=V(0.2, -0.22, 0.32))
        k["bless_c"] = P(base, hR=V(0.42, 0.1, 0.52))
        k["bless_d"] = P(base, hR=V(0.42, -0.24, 0.52))
        return k
    if w == "carpentry":
        # the carpenter: a hammer in hand; down at a job, steadying it with the left
        # and driving nails with the right
        k = _key_poses("unarmed")
        k["aim"] = P(k["aim"], hammer=True)
        base = dict(eL=V(0.2, 0.22, 0.2), hL=V(0.44, 0.08, 0.06), lean=0.35, nod=0.3, hammer=True)
        k["hammer_a"] = P(base, eR=V(0.08, -0.26, 0.4), hR=V(0.3, -0.12, 0.56))
        k["hammer_b"] = P(base, eR=V(0.22, -0.24, 0.22), hR=V(0.46, -0.05, 0.1))
        return k
    if w == "broom":
        # a broom: carried upright; swept side to side along the dirt; or raised and
        # swatted down to shoo hens along
        k = _key_poses("unarmed")
        g = -H_REF + 0.04   # the ground, from the hip
        k["aim"] = P(k["aim"], eR=V(0.02, -0.26, 0.22), hR=V(0.12, -0.2, 0.3), broom=V(0.16, -0.24, g))
        sweep = dict(eL=V(0.14, 0.2, 0.3), hL=V(0.26, 0.04, 0.34), eR=V(0.12, -0.2, 0.14),
                     lean=0.25, nod=0.25)
        k["sweep_a"] = P(sweep, hR=V(0.28, -0.04, 0.08), broom=V(0.62, 0.32, g))
        k["sweep_m"] = P(sweep, hR=V(0.3, -0.06, 0.08), broom=V(0.68, 0.02, g))
        k["sweep_b"] = P(sweep, hR=V(0.28, -0.1, 0.08), broom=V(0.6, -0.3, g))
        shoo = dict(eL=V(0.16, 0.2, 0.42), hL=V(0.3, 0.04, 0.56), eR=V(0.14, -0.2, 0.36))
        k["shoo_a"] = P(shoo, hR=V(0.3, -0.06, 0.5), broom=V(0.5, 0.0, 1.2), lean=-0.1)
        k["shoo_b"] = P(shoo, hR=V(0.36, -0.04, 0.34), broom=V(0.95, 0.0, -0.3), lean=0.2)
        return k
    if w == "keeper":
        # the saloon keeper: a towel over his arm; bent over a table setting it right
        k = _key_poses("unarmed")
        k["aim"] = P(k["aim"], eL=V(0.08, 0.26, 0.28), hL=V(0.22, 0.1, 0.3), eR=V(0.08, -0.26, 0.28),
                     hR=V(0.22, -0.08, 0.32), towel=True)
        base = dict(eL=V(0.24, 0.22, 0.26), eR=V(0.24, -0.22, 0.26), lean=0.38, nod=0.3, towel=True)
        k["tidy_a"] = P(base, hL=V(0.48, 0.14, 0.1), hR=V(0.5, -0.1, 0.14))
        k["tidy_b"] = P(base, hL=V(0.44, 0.2, 0.06), hR=V(0.54, -0.02, 0.1))
        return k
    if w == "mayor":
        # the mayor: thumbs in his waistcoat; on his soapbox, arms wide, a hand raised
        # to heaven, palms down to calm them; and touring the damage, hands behind his
        # back, looking this way and that
        k = _key_poses("unarmed")
        k["aim"] = P(k["aim"], eL=V(0.0, 0.3, 0.32), hL=V(0.12, 0.11, 0.3), eR=V(0.0, -0.3, 0.32),
                     hR=V(0.12, -0.11, 0.3))
        k["orate_a"] = dict(eL=V(0.14, 0.34, 0.46), hL=V(0.26, 0.48, 0.6), eR=V(0.14, -0.34, 0.46),
                            hR=V(0.26, -0.48, 0.6), lean=-0.06, nod=-0.1)
        k["orate_b"] = dict(eL=V(0.1, 0.3, 0.3), hL=V(0.2, 0.4, 0.2), eR=V(0.12, -0.24, 0.66),
                            hR=V(0.2, -0.16, 0.92), lean=-0.1, nod=-0.18)
        k["orate_c"] = dict(eL=V(0.22, 0.24, 0.36), hL=V(0.44, 0.2, 0.32), eR=V(0.22, -0.24, 0.36),
                            hR=V(0.44, -0.2, 0.32), lean=0.1)
        back = dict(eL=V(-0.08, 0.26, 0.24), hL=V(-0.18, 0.06, 0.1), eR=V(-0.08, -0.26, 0.24),
                    hR=V(-0.18, -0.06, 0.1), nod=0.25)
        k["survey_a"] = P(back, twist=0.18)
        k["survey_b"] = P(back, twist=-0.18)
        return k
    if w == "smith":
        # the gunsmith: empty hands; bent to the dirt for a gun, holding it up to the
        # light, and carrying an armful of them home
        k = _key_poses("unarmed")
        k["pick_a"] = dict(eL=V(0.18, 0.24, 0.12), hL=V(0.4, 0.1, -0.16), eR=V(0.18, -0.24, 0.12),
                           hR=V(0.4, -0.08, -0.16), lean=0.45, nod=0.3, gun=None)
        k["pick_b"] = dict(eL=V(0.2, 0.22, 0.26), hL=V(0.42, 0.08, 0.4), eR=V(0.06, -0.26, 0.26),
                           hR=V(0.22, -0.12, 0.36), nod=0.15,
                           gun=G((0.14, -0.14, 0.34), (0.95, 0.28, 0.12)))
        k["carry"] = dict(eL=V(0.1, 0.24, 0.22), hL=V(0.26, 0.12, 0.3), eR=V(0.1, -0.24, 0.22),
                          hR=V(0.26, -0.12, 0.3), armful=True, gun=None)
        return k
    if w == "rifles":
        # a carrier of loose rifles: like the gunsmith, bent to the pile for them, and
        # an armful of them to the wagon
        k = _key_poses("smith")
        k["carry"] = P(k["carry"], armful=False, rifles=True)
        return k
    if w == "case":
        # a carrier of cases: bent to the pile, up with it, and off with it held across
        # his chest, arms under it
        k = _key_poses("unarmed")
        k["pick_a"] = dict(eL=V(0.2, 0.25, 0.08), hL=V(0.42, 0.24, -0.2), eR=V(0.2, -0.25, 0.08),
                           hR=V(0.42, -0.24, -0.2), lean=0.5, nod=0.3, gun=None)
        k["carry"] = dict(eL=V(0.1, 0.26, 0.24), hL=V(0.3, 0.26, 0.18), eR=V(0.1, -0.26, 0.24),
                          hR=V(0.3, -0.26, 0.18), case=(0.32, 0.0, 0.27), lean=-0.06, gun=None)
        k["pick_b"] = P(k["carry"], lean=0.25, eL=V(0.16, 0.26, 0.14), hL=V(0.36, 0.26, 0.02),
                        eR=V(0.16, -0.26, 0.14), hR=V(0.36, -0.26, 0.02), case=(0.38, 0.0, 0.1))
        return k
    if w == "nun":
        # the sister: hands folded before her; at the chapel door beckoning them in;
        # hauling the padre by the shoulders; and blessing the dead as he would have
        k = _key_poses("unarmed")
        k["aim"] = P(k["aim"], eL=V(0.05, 0.22, 0.26), hL=V(0.18, 0.03, 0.2), eR=V(0.05, -0.22, 0.26),
                     hR=V(0.18, -0.03, 0.21), nod=0.12)
        k["beckon_a"] = dict(eR=V(0.16, -0.3, 0.42), hR=V(0.4, -0.3, 0.62), **HANG_L)
        k["beckon_b"] = dict(eR=V(0.08, -0.32, 0.4), hR=V(0.14, -0.26, 0.66), **HANG_L)
        k["drag"] = dict(eL=V(-0.12, 0.24, 0.14), hL=V(-0.32, 0.12, -0.2), eR=V(-0.12, -0.24, 0.14),
                         hR=V(-0.32, -0.12, -0.2), lean=0.3, nod=0.1)
        base = dict(eL=V(0.06, 0.25, 0.28), hL=V(0.2, 0.08, 0.32), eR=V(0.22, -0.2, 0.45), lean=0.25, nod=0.25)
        k["bless_a"] = P(base, hR=V(0.44, -0.06, 0.66))
        k["bless_b"] = P(base, hR=V(0.44, -0.06, 0.36), eR=V(0.2, -0.22, 0.32))
        k["bless_c"] = P(base, hR=V(0.42, 0.1, 0.52))
        k["bless_d"] = P(base, hR=V(0.42, -0.24, 0.52))
        return k
    if w == "spade":
        # the grave digger: his spade stood by him; driven into the ground with both
        # hands, levered, and the earth thrown up onto the heap over his left shoulder
        k = _key_poses("unarmed")
        g = -H_REF + 0.04   # the ground, from the hip
        k["aim"] = P(k["aim"], eR=V(0.02, -0.26, 0.22), hR=V(0.12, -0.2, 0.3), spade=V(0.18, -0.26, g))
        two = dict(eL=V(0.16, 0.22, 0.28), eR=V(0.14, -0.22, 0.14))
        k["dig_a"] = P(two, hL=V(0.3, 0.06, 0.5), hR=V(0.28, -0.06, 0.22), spade=V(0.52, 0.0, g - 0.06),
                       lean=0.2, nod=0.3)
        k["dig_b"] = P(two, hL=V(0.24, 0.08, 0.2), hR=V(0.18, -0.08, 0.04), spade=V(0.58, 0.02, g + 0.04),
                       lean=0.42, nod=0.35, dirt=True)
        k["dig_c"] = dict(eL=V(0.1, 0.28, 0.34), hL=V(0.18, 0.22, 0.48), eR=V(0.06, -0.12, 0.3),
                          hR=V(0.12, 0.06, 0.3), spade=V(0.3, 0.62, 0.62), lean=0.05, nod=0.1, twist=0.35)
        return k
    if w == "barber":
        # the barber-surgeon: his bag in hand; binding a man up where he stands, and
        # down on one knee over one lying in the dirt
        k = _key_poses("unarmed")
        k["aim"] = P(k["aim"], bag=True)
        stand = dict(eL=V(0.2, 0.2, 0.32), eR=V(0.2, -0.2, 0.32), lean=0.1, nod=0.2, gauze=True)
        k["treat_a"] = P(stand, hL=V(0.44, 0.08, 0.4), hR=V(0.46, -0.1, 0.5))
        k["treat_b"] = P(stand, hL=V(0.46, 0.12, 0.44), hR=V(0.5, 0.02, 0.34))
        low = dict(eL=V(0.16, 0.25, 0.14), eR=V(0.16, -0.25, 0.14), lean=0.5, nod=0.35, gauze=True)
        k["tend_a"] = P(low, hL=V(0.4, 0.14, -0.12), hR=V(0.42, -0.08, -0.06))
        k["tend_b"] = P(low, hL=V(0.38, 0.1, -0.14), hR=V(0.44, 0.06, -0.14))
        return k
    if w == "bound":
        # a prisoner: hands tied behind his back, whatever happens; straining at the
        # rope as he kicks on the gallows, then hanging still, his head fallen forward
        k = _key_poses("unarmed")
        tied = dict(eL=V(-0.07, 0.24, 0.24), hL=V(-0.17, 0.05, 0.09), eR=V(-0.07, -0.24, 0.24),
                    hR=V(-0.17, -0.05, 0.09), bonds=True, nod=0.12)
        for name in list(k):
            if isinstance(k[name], dict) and "eL" in k[name]:
                k[name] = P(tied, lean=k[name].get("lean", 0.0), twist=k[name].get("twist", 0.0))
        k["aim"] = k["low"] = tied
        k["strain_a"] = P(tied, eL=V(-0.1, 0.27, 0.27), eR=V(-0.1, -0.27, 0.27), lean=-0.15, twist=0.2, nod=-0.2)
        k["strain_b"] = P(tied, eL=V(-0.1, 0.27, 0.27), eR=V(-0.1, -0.27, 0.27), lean=-0.1, twist=-0.2, nod=-0.1)
        k["hang"] = P(tied, nod=0.6, lean=0.08, twist=0.1)
        return k
    if w == "grief":
        # empty hands clasped before her, head bowed; now and then a handkerchief
        k = _key_poses("unarmed")
        k["mourn_a"] = dict(eL=V(0.05, 0.22, 0.24), hL=V(0.17, 0.03, 0.14), eR=V(0.05, -0.22, 0.24),
                            hR=V(0.17, -0.03, 0.15), nod=0.38, lean=0.08)
        k["mourn_b"] = P(k["mourn_a"], eR=V(0.14, -0.22, 0.42), hR=V(0.15, -0.06, 0.64), hanky=True, nod=0.25)
        return k
    if w == "tools":
        # the undertaker's trade on top of empty hands: bent over a body with the tape,
        # and hauling one along behind him by the boots
        k = _key_poses("unarmed")
        k["measure_a"] = dict(eL=V(0.16, 0.27, 0.14), hL=V(0.38, 0.2, -0.12), eR=V(0.16, -0.27, 0.14),
                              hR=V(0.38, -0.2, -0.12), lean=0.5, nod=0.35, tape=True)
        k["measure_b"] = P(k["measure_a"], hL=V(0.4, 0.36, -0.14), eL=V(0.18, 0.32, 0.12), hR=V(0.34, -0.12, -0.1))
        k["drag"] = dict(eL=V(-0.12, 0.24, 0.14), hL=V(-0.32, 0.12, -0.2), eR=V(-0.12, -0.24, 0.14),
                         hR=V(-0.32, -0.12, -0.2), lean=0.3, nod=0.1)
        return k
    if w == "unarmed":
        # arms easy at his sides; the shared poses (point, flinch, cower, hits) do the rest
        aim = dict(eR=V(-0.02, -0.25, 0.2), hR=V(0.03, -0.23, -0.04), **HANG_L)
        k = {"aim": aim, "low": aim, "up": {"gun": None}, "cower": {"gun": None}, "clutch_r": {"gun": None},
             "belly": dict(eR=V(0.08, -0.27, 0.2), hR=V(0.17, -0.07, 0.08))}
        return _shared_poses(k)
    if w == "sawnoff":
        # held at the hip like the coach gun, but by its grip: the short gun sits forward
        k = _key_poses("coach")
        for name, pose in list(k.items()):
            for g in ("gun", "gun2"):
                if pose.get(g) is not None:
                    pose = P(pose, **{g: G(pose[g]["B"] + pose[g]["D"] * 0.17, pose[g]["D"])})
            k[name] = pose
        return k
    if w == "champion":
        # held at the hip and broken open like the coach gun; the thumb up to the hammer
        k = _key_poses("coach")
        k["cock"] = P(k["aim"], eR=V(-0.06, -0.29, 0.24), hR=V(0.08, -0.16, 0.2))
        return k
    if w in ("navy", "pistola"):
        return _key_poses("colt")   # held and loaded like any Colt
    if w in ("derringer", "schofield"):   # held like a Colt; broken open to load
        k = _key_poses("colt")
        for name in ("load", "eject_a", "eject_b", "insert_a", "insert_b"):
            k[name] = P(k[name], broken=1.0)
        k["load_half"] = P(k["load"], broken=0.5)
        return k
    k = {}
    if w == "colt":
        k["aim"] = dict(eR=V(0.27, -0.14, 0.45), hR=V(0.5, -0.07, 0.43), **HANG_L,
                        gun=G((0.47, -0.07, 0.37), (0.3, 0, 0.06)))
        k["kick"] = P(k["aim"], eR=V(0.22, -0.15, 0.56), hR=V(0.4, -0.07, 0.64),
                      gun=G((0.38, -0.07, 0.58), (0.18, 0, 0.26)), lean=-0.1)
        k["cock"] = P(k["aim"], eR=V(0.22, -0.15, 0.44), hR=V(0.42, -0.08, 0.45),
                      gun=G((0.4, -0.08, 0.39), (0.27, 0, 0.12)))
        k["fan_a"] = P(k["aim"], eL=V(0.22, 0.1, 0.36), hL=V(0.42, -0.02, 0.5))
        k["fan_b"] = P(k["aim"], eL=V(0.28, 0.06, 0.36), hL=V(0.55, -0.04, 0.44))
        k["load"] = dict(eR=V(0.1, -0.25, 0.22), hR=V(0.27, -0.1, 0.32), eL=V(0.14, 0.22, 0.24),
                         hL=V(0.3, -0.02, 0.36), gun=G((0.26, -0.1, 0.27), (0.12, 0.08, 0.28)))
        k["eject_a"] = P(k["load"], hL=V(0.31, -0.04, 0.42))
        k["eject_b"] = P(k["load"], eL=V(0.18, 0.18, 0.36), hL=V(0.34, -0.05, 0.52))
        k["insert_a"] = P(k["load"], **BELT_L)
        k["insert_b"] = P(k["load"], hL=V(0.29, -0.04, 0.33))
        k["low"] = dict(eR=V(0.02, -0.26, 0.2), hR=V(0.1, -0.24, -0.02), **HANG_L,
                        gun=G((0.08, -0.24, 0.03), (0.85, 0, -0.5)))
        k["up"] = dict(gun=G((0.2, -0.08, 0.59), (0.25, 0, 0.97)))
        k["clutch_r"] = dict(gun=G((0.3, -0.5, 0.25), (0.45, -0.6, -0.5)))
        k["belly"] = dict(eR=V(0.08, -0.27, 0.2), hR=V(0.17, -0.07, 0.08), gun=G((0.16, -0.07, 0.12), (0.5, 0, -0.85)))
        k["cower"] = dict(gun=G((0.05, -0.11, 0.84), (-0.4, -0.1, 0.9)))
    elif w == "rifle":
        k["aim"] = dict(eR=V(-0.02, -0.27, 0.28), hR=V(0.12, -0.1, 0.38), eL=V(0.25, 0.14, 0.28),
                        hL=V(0.42, -0.03, 0.36), gun=G((-0.1, -0.12, 0.44), (1.1, 0.08, -0.11)))
        k["kick"] = P(k["aim"], hR=V(0.09, -0.1, 0.42), hL=V(0.38, -0.03, 0.44),
                      gun=G((-0.14, -0.12, 0.47), (1.0, 0.07, 0.1)), lean=-0.1)
        k["lever"] = P(k["aim"], eR=V(-0.05, -0.29, 0.18), hR=V(0.13, -0.11, 0.25),
                       gun=G((-0.08, -0.12, 0.42), (1.1, 0.08, -0.13)), lever=1.0)
        k["lever_half"] = P(k["lever"], hR=V(0.13, -0.11, 0.31), lever=0.5)
        gb, gd = (-0.06, -0.22, 0.1), (0.55, 0.45, 0.7)
        k["load"] = dict(eR=V(-0.02, -0.3, 0.18), hR=V(0.13, -0.08, 0.32), eL=V(0.14, 0.24, 0.26),
                         hL=V(0.25, 0.04, 0.45), gun=G(gb, gd))
        k["insert_a"] = P(k["load"], eR=V(-0.02, -0.3, 0.16), hR=V(0.05, -0.21, 0.02))
        k["insert_b"] = P(k["load"], hR=V(0.15, -0.06, 0.3))
        k["low"] = dict(eR=V(-0.05, -0.28, 0.2), hR=V(0.02, -0.22, 0.05), **HANG_L,
                        gun=G((-0.2, -0.22, 0.25), (0.85, -0.02, -0.5)))
        k["up"] = dict(gun=G((0.05, -0.3, 0.13), (0.25, 0.7, 0.75)))
        k["clutch_r"] = dict(gun=G((-0.1, -0.45, 0.1), (0.75, -0.15, -0.6)))
        k["belly"] = dict(eR=V(0.06, -0.28, 0.2), hR=V(0.12, -0.12, 0.06), gun=G((-0.25, -0.2, 0.2), (0.85, 0, -0.55)))
        k["cower"] = dict(gun=G((-0.2, 0.18, 0.05), (0.0, -0.55, 0.83)))
    else:  # coach gun, carried at the hip
        k["aim"] = dict(eR=V(-0.08, -0.29, 0.2), hR=V(0.04, -0.17, 0.13), eL=V(0.16, 0.12, 0.18),
                        hL=V(0.4, -0.07, 0.21), gun=G((-0.16, -0.18, 0.08), (0.94, 0.13, 0.17)))
        k["kick"] = P(k["aim"], hR=V(0.0, -0.17, 0.17), hL=V(0.33, -0.07, 0.36),
                      gun=G((-0.21, -0.18, 0.1), (0.85, 0.12, 0.52)), lean=-0.18)
        k["load"] = dict(eR=V(-0.06, -0.29, 0.2), hR=V(0.05, -0.18, 0.14), eL=V(0.18, 0.2, 0.12),
                         hL=V(0.36, -0.06, 0.06), gun=G((-0.13, -0.2, 0.12), (0.95, 0.1, 0.1)), broken=1.0)
        k["break_half"] = P(k["load"], broken=0.45)
        k["eject_a"] = P(k["load"], hL=V(0.26, -0.06, 0.24), gun=G((-0.1, -0.2, 0.06), (0.8, 0.1, 0.55)))
        k["eject_b"] = P(k["eject_a"], gun=G((-0.1, -0.2, 0.04), (0.7, 0.1, 0.7)))
        k["insert_a"] = P(k["load"], **BELT_L)
        k["insert_b"] = P(k["load"], eL=V(0.12, 0.18, 0.16), hL=V(0.2, -0.1, 0.18))
        k["low"] = dict(eR=V(-0.05, -0.28, 0.2), hR=V(0.02, -0.22, 0.05), **HANG_L,
                        gun=G((-0.2, -0.22, 0.25), (0.85, -0.02, -0.5)))
        k["up"] = dict(gun=G((0.05, -0.3, 0.13), (0.25, 0.7, 0.75)))
        k["clutch_r"] = dict(gun=G((-0.15, -0.45, 0.05), (0.75, -0.15, -0.6)))
        k["belly"] = dict(eR=V(0.06, -0.28, 0.2), hR=V(0.12, -0.12, 0.06), gun=G((-0.25, -0.2, 0.2), (0.85, 0, -0.55)))
        k["cower"] = dict(gun=G((-0.2, 0.18, 0.05), (0.0, -0.55, 0.83)))
    return _shared_poses(k)


def _shared_poses(k):
    """Shared, gun-agnostic arm poses; the gun placement comes from the gun's keys."""
    low = k["low"]
    k["point_half"] = P(low, eL=V(0.14, 0.24, 0.34), hL=V(0.32, 0.16, 0.42))
    k["point"] = P(low, eL=V(0.26, 0.14, 0.51), hL=V(0.54, 0.05, 0.58), finger=True)
    k["flinch_half"] = P(low, eL=V(0.12, 0.3, 0.38), hL=V(0.18, 0.12, 0.52), lean=-0.08)
    k["flinch"] = dict(eL=V(0.12, 0.32, 0.43), hL=V(0.2, 0.1, 0.68), eR=V(0.1, -0.32, 0.4), hR=V(0.2, -0.08, 0.62),
                       gun=k["up"]["gun"], lean=-0.16)
    k["cower_a"] = dict(eL=V(0.16, 0.3, 0.66), hL=V(0.05, 0.09, 0.86), eR=V(0.16, -0.3, 0.66),
                        hR=V(0.05, -0.09, 0.86), gun=k["cower"]["gun"], lean=0.38, nod=0.25)
    k["cower_b"] = P(k["cower_a"], hL=V(0.06, 0.1, 0.83), hR=V(0.06, -0.1, 0.83), lean=0.42)
    # hits: the struck side snaps back and he grabs at it
    k["hit_r"] = dict(eR=V(0.05, -0.38, 0.4), hR=V(0.15, -0.48, 0.3), eL=V(0.2, 0.1, 0.25), hL=V(0.08, -0.13, 0.45),
                      gun=k["clutch_r"]["gun"], twist=-0.45, lean=-0.12)
    k["hit_l"] = P(low, eL=V(-0.1, 0.3, 0.25), hL=V(-0.16, 0.32, 0.0), twist=0.45, lean=-0.12)
    k["hit_l"].update(eR=V(0.2, -0.12, 0.3), hR=V(0.09, 0.13, 0.44))      # clutching the left shoulder
    k["hit_gut"] = P(k["belly"], eL=V(0.1, 0.24, 0.25), hL=V(0.17, 0.04, 0.1), lean=0.5, nod=0.2)
    # the knife: gun hand down, the blade drawn back in the other, then driven in
    k["stab_a"] = P(low, eL=V(-0.06, 0.27, 0.28), hL=V(0.02, 0.22, 0.4), knife=True, twist=0.25)
    k["stab_b"] = P(low, eL=V(0.28, 0.14, 0.36), hL=V(0.56, 0.02, 0.3), knife=True, twist=-0.2, lean=0.2)
    # bandaging: down on one knee (the legs crouch), the gun set aside, winding a
    # strip round the left forearm, over and under
    k["band_a"] = dict(eL=V(0.12, 0.25, 0.26), hL=V(0.32, 0.06, 0.3), eR=V(0.12, -0.22, 0.32),
                       hR=V(0.3, -0.02, 0.44), roll=True, gun=None, nod=0.3, lean=0.15)
    k["band_b"] = P(k["band_a"], eR=V(0.16, -0.2, 0.2), hR=V(0.36, 0.12, 0.24))
    # hauling a downed comrade to cover by his collar: bent, both hands low behind
    k["haul"] = dict(eL=V(-0.12, 0.24, 0.16), hL=V(-0.3, 0.1, -0.16), eR=V(-0.12, -0.24, 0.16),
                     hR=V(-0.3, -0.1, -0.16), lean=0.35, nod=0.15, gun=None)
    # dynamite: lit at the chest, drawn back over the shoulder, then lobbed high
    k["light"] = P(low, eL=V(0.12, 0.27, 0.3), hL=V(0.24, 0.1, 0.44), stick=True, nod=0.15)
    k["wind"] = P(low, eL=V(-0.12, 0.3, 0.6), hL=V(-0.2, 0.26, 0.82), stick=True, twist=0.4, lean=-0.12)
    k["lob"] = P(low, eL=V(0.24, 0.16, 0.62), hL=V(0.48, 0.08, 0.8), twist=-0.3, lean=0.15)
    if "gun2" in low:   # a man with two guns flinches and cowers with both
        for name in ("point_half", "point", "flinch_half", "hit_l", "hit_gut"):
            k[name].pop("gun2", None)
        k["point"]["finger"] = False
    return k


def _left_gun(p):
    """The left hand's gun, held along the forearm (for poses that don't place it)."""
    e, h = np.array(p["eL"], float), np.array(p["hL"], float)
    d = (h - e) / np.linalg.norm(h - e) + V(0, 0, 0.15)
    return G(h + V(-0.03, 0, -0.06), d)


HOLSTERED_L = G((-0.01, 0.2, -0.04), (0.12, 0.04, -1.0))   # the left gun put away in its holster


def _twin_poses():
    """A gun in each hand. Both arms out in front to shoot; for the reload the left
    gun goes back in its holster and the free hand works the right gun's gate."""
    k = _key_poses("colt")
    aim = dict(eR=V(0.27, -0.2, 0.45), hR=V(0.5, -0.13, 0.43), gun=G((0.47, -0.13, 0.37), (0.3, -0.02, 0.06)),
               eL=V(0.27, 0.2, 0.45), hL=V(0.5, 0.13, 0.43), gun2=G((0.47, 0.13, 0.37), (0.3, 0.02, 0.06)))
    k["aim"] = aim
    k["kick"] = P(aim, eR=V(0.22, -0.2, 0.56), hR=V(0.4, -0.13, 0.64),
                  gun=G((0.38, -0.13, 0.58), (0.18, -0.02, 0.26)), lean=-0.06, twist=0.08)
    k["kick_l"] = P(aim, eL=V(0.22, 0.2, 0.56), hL=V(0.4, 0.13, 0.64),
                    gun2=G((0.38, 0.13, 0.58), (0.18, 0.02, 0.26)), lean=-0.06, twist=-0.08)
    # both guns low and ready, muzzles down in front of him
    k["low"] = dict(eR=V(0.04, -0.26, 0.2), hR=V(0.16, -0.22, 0.02), gun=G((0.13, -0.22, -0.04), (0.8, -0.05, -0.55)),
                    eL=V(0.04, 0.26, 0.2), hL=V(0.16, 0.22, 0.02), gun2=G((0.13, 0.22, -0.04), (0.8, 0.05, -0.55)))
    k["holster"] = P(k["load"], eL=V(-0.03, 0.28, 0.2), hL=V(0.0, 0.22, 0.0), gun2=HOLSTERED_L)
    for name in ("load", "eject_a", "eject_b", "insert_a", "insert_b"):
        k[name] = P(k[name], gun2=HOLSTERED_L)
    k = _shared_poses(k)
    for p in k.values():
        if "gun2" not in p and "hL" in p and "eL" in p:
            p["gun2"] = _left_gun(p)
    return k


def lerp_pose(a, b, t):
    out = {}
    for key in set(a) | set(b):
        va, vb = a.get(key, b.get(key)), b.get(key, a.get(key))
        if key in ("gun", "gun2"):
            if va is None or vb is None:
                out[key] = va or vb
            else:
                D = va["D"] * (1 - t) + vb["D"] * t
                out[key] = {"B": va["B"] * (1 - t) + vb["B"] * t, "D": D / np.linalg.norm(D)}
        elif isinstance(va, bool):
            out[key] = va if t < 0.5 else vb
        else:
            out[key] = np.asarray(va, float) * (1 - t) + np.asarray(vb, float) * t
    for key in ("lean", "twist", "nod", "lever", "broken"):
        if key not in a and key not in b:
            continue
        out[key] = float(a.get(key, 0.0)) * (1 - t) + float(b.get(key, 0.0)) * t
    return out


def _frames(keys, n, loop=False):
    """Sample n frames through a list of key poses (evenly spaced)."""
    if n == 1:
        return [keys[0]]
    out = []
    segs = len(keys) - (0 if loop else 1)
    for i in range(n):
        u = i / n * segs if loop else i / (n - 1) * segs
        j = min(int(u), segs - 1)
        kb = keys[(j + 1) % len(keys)]
        out.append(lerp_pose(keys[j], kb, u - j))
    return out


def upper_anims(w):
    """{name: {"poses": [...], "fps", "loop", "events": {frame: name}}} for one gun."""
    k = _key_poses(w)
    a = {}

    def add(name, poses, fps, loop=False, events=None):
        a[name] = {"poses": poses, "fps": fps, "loop": loop, "events": events or {}}
    add("aim", [k["aim"]], 1, True)
    if w not in ("unarmed", "tools", "prayer", "grief", "smith", "mayor", "carpentry", "broom", "keeper", "nun", "barber", "spade", "bound", "rifles", "case"):
        add("fire", [k["kick"], lerp_pose(k["kick"], k["aim"], 0.4), k["aim"]], 12)
    if w == "unarmed":
        pass
    elif w == "prayer":
        add("bless", [k["bless_a"], k["bless_b"], k["bless_c"], k["bless_d"]], 2.5, True)
    elif w == "carpentry":
        add("hammer", [k["hammer_a"], k["hammer_a"], lerp_pose(k["hammer_a"], k["hammer_b"], 0.6), k["hammer_b"]], 6, True)
    elif w == "broom":
        add("sweep", [k["sweep_a"], k["sweep_m"], k["sweep_b"], k["sweep_m"]], 3.5, True)
        add("shoo", [k["shoo_a"], lerp_pose(k["shoo_a"], k["shoo_b"], 0.5), k["shoo_b"], k["shoo_b"]], 4, True)
    elif w == "keeper":
        add("tidy", [k["tidy_a"], k["tidy_a"], k["tidy_b"], k["tidy_b"]], 2, True)
    elif w == "mayor":
        a_, b_, c_ = k["orate_a"], k["orate_b"], k["orate_c"]
        add("orate", [a_, a_, lerp_pose(a_, c_, 0.5), c_, c_, lerp_pose(c_, b_, 0.5), b_, b_, lerp_pose(b_, a_, 0.5)],
            3, True)
        add("survey", [k["survey_a"], k["survey_a"], k["survey_b"], k["survey_b"]], 1.4, True)
    elif w in ("smith", "rifles", "case"):
        add("pick", [k["pick_a"], k["pick_a"], lerp_pose(k["pick_a"], k["pick_b"], 0.5), k["pick_b"], k["pick_b"]],
            2.5, True)
        add("carry", [k["carry"]], 1, True)
    elif w == "bound":
        add("struggle", [k["strain_a"], lerp_pose(k["strain_a"], k["strain_b"], 0.5), k["strain_b"],
                         lerp_pose(k["strain_a"], k["strain_b"], 0.5)], 7, True)
        add("hang", [k["hang"]], 1, True)
    elif w == "grief":
        a_, b_ = k["mourn_a"], k["mourn_b"]
        add("mourn", [a_, a_, a_, a_, lerp_pose(a_, b_, 0.5), b_, b_, b_, lerp_pose(a_, b_, 0.5)], 1.5, True)
    elif w == "nun":
        add("beckon", [k["beckon_a"], k["beckon_a"], lerp_pose(k["beckon_a"], k["beckon_b"], 0.5), k["beckon_b"],
                       k["beckon_b"], lerp_pose(k["beckon_a"], k["beckon_b"], 0.5)], 5, True)
        add("drag", [k["drag"]], 1, True)
        add("bless", [k["bless_a"], k["bless_b"], k["bless_c"], k["bless_d"]], 2.5, True)
    elif w == "spade":
        a_, b_, c_ = k["dig_a"], k["dig_b"], k["dig_c"]
        add("dig", [a_, a_, lerp_pose(a_, b_, 0.5), b_, b_, lerp_pose(b_, c_, 0.5), c_, lerp_pose(c_, a_, 0.5)], 4, True)
    elif w == "barber":
        add("treat", [k["treat_a"], k["treat_a"], lerp_pose(k["treat_a"], k["treat_b"], 0.5), k["treat_b"], k["treat_b"],
                      lerp_pose(k["treat_b"], k["treat_a"], 0.5)], 4, True)
        add("tend", [k["tend_a"], k["tend_a"], lerp_pose(k["tend_a"], k["tend_b"], 0.5), k["tend_b"], k["tend_b"],
                     lerp_pose(k["tend_b"], k["tend_a"], 0.5)], 4, True)
    elif w == "tools":
        add("measure", [k["measure_a"], k["measure_b"]], 2, True)
        add("drag", [k["drag"]], 1, True)
    elif w in ("sharps", "rollingblock", "remington"):
        add("cock", [k["cock"], k["aim"]], 5)
        add("reload_open", _frames([k["aim"], k["load"]], 2), 6)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 6, events={1: "brass"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 4, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 6)
    elif w == "spencer":
        # the lever thrown and back, then the hammer thumbed: two motions a shot
        add("lever", [k["lever_half"], k["lever"], k["lever_half"], k["aim"], k["cock"], k["aim"]], 7, events={1: "brass"})
        add("reload_open", _frames([k["aim"], k["load"]], 2), 8)
        add("reload_insert", [k["insert_a"], k["insert_b"]], 4, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 8)
    elif w in MUZZLE_LOADERS:
        add("cock", [k["cock"], k["aim"]], 5)
        add("reload_open", _frames([k["aim"], k["load"]], 2), 4)
        add("reload_eject", [k["pour_a"], k["pour_b"], k["pour_b"]], 3)
        add("reload_insert", [k["ram_lo"], lerp_pose(k["ram_lo"], k["ram_hi"], 0.5), k["ram_hi"],
                              lerp_pose(k["ram_lo"], k["ram_hi"], 0.5)], 4, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 4)
    elif w == "howdah":
        add("cock", [k["cock"], k["aim"]], 6)
        add("reload_open", [k["load_half"], k["load"]], 5)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 6, events={1: "brass"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 4.5, True)
        add("reload_close", [k["load_half"], k["aim"]], 6)
    elif w == "schofield":
        # unlatched and tipped open, a flick that throws all six, six in quick, snapped shut
        add("cock", [k["cock"], k["aim"]], 7)
        add("reload_open", [k["load_half"], k["load"]], 5)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 7)
        add("reload_insert", [k["insert_a"], k["insert_b"]], 9, True)
        add("reload_close", [k["load_half"], k["aim"]], 6)
    elif w == "derringer":
        add("cock", [k["cock"], k["aim"]], 7)
        add("reload_open", [k["load_half"], k["load"]], 6)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 7, events={1: "brass"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 5, True)
        add("reload_close", [k["load_half"], k["aim"]], 7)
    elif w == "colts":
        add("fire_l", [k["kick_l"], lerp_pose(k["kick_l"], k["aim"], 0.4), k["aim"]], 12)
        add("reload_open", [k["holster"], k["load"]], 6)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 8, events={1: "brass"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 5.5, True)
        add("reload_close", [k["holster"], k["aim"]], 7)
    elif w == "pistola":
        # one charge: powder poured, the ball rammed home with the swivel rod, a cap
        add("cock", [k["cock"], k["aim"]], 6)
        add("reload_open", _frames([k["aim"], k["load"]], 2), 4)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 3)
        add("reload_insert", [k["insert_a"], k["insert_b"], k["eject_b"], k["insert_b"]], 2.6, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 4)
    elif w in ("navy", "banner"):
        # no brass to shake out: a spent cap picked off, then each chamber charged and rammed
        add("cock", [k["cock"], k["aim"]], 6)
        add("reload_open", _frames([k["aim"], k["load"]], 2), 5)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 8)
        add("reload_insert", [k["insert_a"], k["insert_b"], k["eject_b"], k["insert_b"]], 2.6, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 6)
    elif w == "colt":
        add("cock", [k["cock"], k["aim"]], 7)
        add("fan", [k["fan_a"], k["fan_b"]], 12, True)
        add("reload_open", _frames([k["aim"], k["load"]], 2), 6)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 8, events={1: "brass"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 5.5, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 7)
    elif w == "rifle":
        add("lever", [k["lever_half"], k["lever"], k["lever_half"], k["aim"]], 9, events={1: "brass"})
        add("reload_open", _frames([k["aim"], k["load"]], 2), 8)
        add("reload_insert", [k["insert_a"], k["insert_b"]], 5, True)
        add("reload_close", _frames([k["load"], k["aim"]], 2), 8)
    elif w == "champion":
        add("cock", [k["cock"], k["aim"]], 6)
        add("reload_open", [k["break_half"], k["load"]], 6)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 6, events={1: "shells"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 5, True)
        add("reload_close", [k["break_half"], k["aim"]], 6)
    else:
        add("reload_open", [k["break_half"], k["load"]], 5)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 6, events={1: "shells"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 4.8, True)
        add("reload_close", [k["break_half"], k["aim"]], 6)
    add("point", [k["point_half"], k["point"], k["point"]], 6)
    if w in PISTOLS:   # a round into the air, for the noise of it: arm straight up, the gun at the sky
        sky = dict(eR=V(0.06, -0.26, 0.76), hR=V(0.1, -0.2, 1.02), eL=V(0.0, 0.27, 0.22), hL=V(0.04, 0.22, -0.02),
                   gun=G((0.06, -0.2, 0.98), (0.12, 0.0, 1.0)))
        kick = P(sky, hR=V(0.06, -0.2, 1.06), gun=G((0.02, -0.2, 1.02), (-0.15, 0.0, 1.0)))
        add("salute", [lerp_pose(k["aim"], sky, 0.5), sky, sky, kick, kick, sky, sky, lerp_pose(sky, k["aim"], 0.5)], 6)
    add("stab", [k["stab_a"], k["stab_b"], k["stab_b"], lerp_pose(k["stab_b"], k["aim"], 0.5)], 12)
    if w not in ("unarmed", "tools", "prayer", "grief", "smith", "mayor", "carpentry", "broom", "keeper", "nun", "barber", "spade", "bound", "rifles", "case"):
        add("bandage", [k["band_a"], k["band_a"], lerp_pose(k["band_a"], k["band_b"], 0.5), k["band_b"], k["band_b"],
                        lerp_pose(k["band_b"], k["band_a"], 0.5)], 4, True)
        add("haul", [k["haul"]], 1, True)
        # 7 fps: it leaves his hand on frame 4, Enemy.WINDUP (0.57 s) after lighting
        add("throw", [k["light"], k["light"], lerp_pose(k["light"], k["wind"], 0.6), k["wind"], k["lob"],
                      lerp_pose(k["lob"], k["aim"], 0.4), lerp_pose(k["lob"], k["aim"], 0.8)], 7)
    add("flinch", [k["flinch_half"], k["flinch"]], 6)
    add("cower", [k["cower_a"], k["cower_b"]], 4, True)
    for side in ("hit_l", "hit_r", "hit_gut"):
        add(side, [k[side], lerp_pose(k[side], k["aim"], 0.25), lerp_pose(k[side], k["aim"], 0.65)], 6)
    return a


def legs_anims():
    a = {}

    def add(name, poses, fps, loop=False, speed=False):
        a[name] = {"poses": poses, "fps": fps, "loop": loop, "speed": speed, "events": {}}
    add("idle", [legs_pose("stand")], 1, True)
    add("walk", [legs_pose("walk", i * math.pi / 4) for i in range(8)], 9, True, True)
    add("crouch", [legs_pose("crouch")], 1, True)
    add("cwalk", [legs_pose("crouch", i * math.pi / 2) for i in range(4)], 5, True, True)
    add("stagger", [legs_pose("stagger", amount=x) for x in (0.6, 1.0, 0.4)], 6)
    add("limp", [legs_pose("limp", i * math.pi / 3) for i in range(6)], 7, True, True)
    return a


# ---------------------------------------------------------------- full-body deaths

DEAD_ARMS = dict(eR=V(0.05, -0.46, 0.58), hR=V(0.1, -0.71, 0.73), eL=V(0.05, 0.46, 0.53), hL=V(0.12, 0.69, 0.63))
FLUNG = dict(eR=V(0.25, -0.3, 0.7), hR=V(0.38, -0.33, 0.9), eL=V(0.25, 0.3, 0.7), hL=V(0.38, 0.33, 0.9))
CLUTCH = dict(eR=V(0.1, -0.25, 0.25), hR=V(0.17, -0.06, 0.15), eL=V(0.1, 0.25, 0.25), hL=V(0.17, 0.06, 0.18))
SAG = dict(eR=V(0.02, -0.25, 0.2), hR=V(0.06, -0.25, -0.05), eL=V(0.02, 0.25, 0.2), hL=V(0.06, 0.25, -0.05))


def _body(look, legs, upper, fall=None):
    """A whole man (no gun) in a death pose. fall = (kind, angle, pivot, shift)."""
    m = build_legs(look, legs)
    up, _ = build_upper(look, None, upper, legs["H"], with_gun=False)
    m += up
    if fall:
        kind, ang, pivot, shift = fall
        R = {"back": rot_y(-ang), "forward": rot_y(ang), "side": rot_x(ang)}[kind]
        m.transform(R, pivot=pivot)
        m.translate(shift)
    lift = -m.P[:, 2].min()
    if lift > 0:
        m.translate((0, 0, lift))
    return m


def death_anims(look):
    """Four ways to die, 5-6 frames each, ending on the corpse."""
    stand, crouch = legs_pose("stand"), legs_pose("crouch")
    kneel, sit = legs_pose("kneel"), legs_pose("sit")
    stag = legs_pose("stagger")
    hurt = P(CLUTCH, lean=0.35, nod=0.2)
    lying = math.pi / 2 - 0.02
    d = {}
    # Thrown back off his feet (the coach gun up close).
    d["death_back"] = [
        _body(look, stag, P(FLUNG, lean=-0.3)),
        _body(look, stag, P(FLUNG, lean=-0.3), ("back", 0.45, (-0.1, 0, 0), (-0.12, 0, 0))),
        _body(look, stand, P(FLUNG, lean=-0.2), ("back", 0.95, (-0.1, 0, 0), (-0.3, 0, 0))),
        _body(look, stand, P(DEAD_ARMS, lean=-0.1), ("back", 1.35, (-0.1, 0, 0), (-0.45, 0, 0))),
        _body(look, stand, DEAD_ARMS, ("back", lying, (0, 0, 0), (-0.5, 0, 0))),
    ]
    # Folding at the gut, down onto his knees, then face down.
    d["death_knees"] = [
        _body(look, stand, hurt),
        _body(look, kneel, P(CLUTCH, lean=0.3, nod=0.25)),
        _body(look, kneel, P(SAG, lean=0.12, nod=0.4)),
        _body(look, kneel, P(SAG, lean=0.2, nod=0.3), ("forward", 0.6, (0.25, 0, 0.08), (0, 0, 0))),
        _body(look, kneel, P(SAG, lean=0.2), ("forward", 1.2, (0.25, 0, 0.08), (0.1, 0, 0))),
        _body(look, stand, SAG, ("forward", lying, (0, 0, 0), (0.45, 0, 0))),
    ]
    # Spun half round by the hit and dropped on his side.
    spin = []
    for i, (tw, roll) in enumerate(((0.5, 0.0), (1.1, 0.25), (1.7, 0.6), (2.2, 1.05), (2.5, lying))):
        b = _body(look, stag if i < 2 else stand, P(FLUNG if i < 3 else DEAD_ARMS, twist=tw * 0.3), ("side", roll, (0, 0, 0), (0, 0.15 * i, 0)))
        b.transform(rot_z(tw * 0.7))
        spin.append(b)
    d["death_spin"] = spin
    # The slow one: looks at the wound, sinks to a knee, sits, and topples.
    d["death_slump"] = [
        _body(look, stand, P(CLUTCH, lean=-0.12, nod=0.35)),
        _body(look, stag, P(CLUTCH, lean=0.15, nod=0.45)),
        _body(look, crouch, P(CLUTCH, lean=0.25, nod=0.4)),
        _body(look, sit, P(SAG, lean=-0.2, nod=0.3)),
        _body(look, sit, P(SAG, lean=-0.3), ("side", 0.8, (0, 0, 0), (0, 0, 0))),
        _body(look, stand, SAG, ("side", lying, (0, 0, 0), (-0.3, 0.2, 0))),
    ]
    return d


DEATH_FPS = {"death_back": 9, "death_knees": 6, "death_spin": 8, "death_slump": 4.5}


# ---------------------------------------------------------------- the last gasp

# A downed man with a pistol to hand may prop himself up on an elbow, feet towards
# the stranger, and get a round or two off before he sinks back. One-handed guns only.
PISTOLS = ("colt", "colts", "schofield", "navy", "derringer", "howdah", "pistola")
LYING = {"H": 0.13, "sway": 0.0, "crouch": True,
         "legs": [((0, 0.1, 0.13), (0.42, 0.13, 0.12), (0.82, 0.15, 0.08)),
                  ((0, -0.1, 0.13), (0.38, -0.12, 0.2), (0.76, -0.17, 0.08))]}   # one knee half up


def _propped(lean, eR, hR, gun_d, eL, hL, nod=0.0):
    """An upper-body pose for a man lying back at `lean`, his joints given as they
    end up (hip-relative, after the lean), so arms can be put on the ground."""
    R = rot_y(lean).T
    hR = V(*hR)
    return dict(lean=lean, nod=nod, eR=R @ V(*eR), hR=R @ hR, eL=R @ V(*eL), hL=R @ V(*hL),
                gun=G(R @ (hR + V(-0.03, 0, -0.05)), R @ V(*gun_d)))


GASP_POSES = {
    # flat on his back, the gun in the hand by his side
    "flat": _propped(-1.45, (-0.25, -0.3, -0.08), (0.0, -0.32, -0.09), (1, -0.1, -0.1),
                     (-0.25, 0.3, -0.08), (0.0, 0.32, -0.09)),
    # up on the left elbow, the gun coming up
    "half": _propped(-1.15, (-0.36, -0.3, 0.06), (-0.1, -0.28, 0.12), (1, 0, 0.3),
                     (-0.5, 0.3, -0.05), (-0.3, 0.3, -0.11), nod=0.35),
    # pushed up on a straight left arm, the right out at the stranger over his boots
    "aim": _propped(-0.8, (-0.08, -0.17, 0.4), (0.18, -0.12, 0.42), (1, 0, 0.04),
                    (-0.43, 0.3, 0.07), (-0.52, 0.32, -0.11), nod=0.5),
    "kick": _propped(-0.88, (-0.1, -0.17, 0.44), (0.12, -0.12, 0.52), (0.6, 0, 0.45),
                     (-0.43, 0.3, 0.07), (-0.52, 0.32, -0.11), nod=0.45),
}


def gasp_anims():
    """{name: (poses, fps, loop)}: up onto the elbow (slowly: he's dying), holding
    the aim, a shot, sinking back down after, and dropping where he's hit."""
    k = GASP_POSES
    return {
        "gasp_rise": ([k["flat"], lerp_pose(k["flat"], k["half"], 0.5), k["half"],
                       lerp_pose(k["half"], k["aim"], 0.5), k["aim"]], 4, False),
        "gasp_aim": ([k["aim"]], 1, True),
        "gasp_fire": ([k["kick"], lerp_pose(k["kick"], k["aim"], 0.4), k["aim"]], 8, False),
        "gasp_sink": ([k["aim"], k["half"], lerp_pose(k["half"], k["flat"], 0.5), k["flat"]], 3, False),
        "gasp_die": ([k["kick"], k["half"], k["flat"]], 7, False),
    }


def gasp_body(look, weapon, up):
    """The whole man lying propped up with his pistol. Returns (cloud, muzzle)."""
    m = build_legs(look, LYING)
    u, muzzle = build_upper(look, GUN_ART.get(weapon, weapon), up, LYING["H"])
    m += u
    lift = max(0.0, -m.P[:, 2].min())
    m.translate((0, 0, lift))
    return m, muzzle + [0, 0, lift]


# ---------------------------------------------------------------- baking

def yaw_for_dir(d):
    """World yaw that appears as screen direction d*45 deg (0 = right, 2 = down)."""
    a = d * math.pi / 4
    dx, dy = math.cos(a), math.sin(a)
    X = (dx / PX + dy / PY) / 2
    Y = (dy / PY - dx / PX) / 2
    return math.atan2(Y, X)


def blood_pool(seed):
    rng = np.random.default_rng(seed)
    pts = []
    for _ in range(4):
        cx, cy = rng.normal(0.1, 0.25), rng.normal(0, 0.2)
        r = rng.uniform(0.15, 0.32)
        g = np.mgrid[-r:r:0.01, -r:r:0.01].reshape(2, -1).T
        g = g[(g ** 2).sum(1) < r * r]
        pts.append(np.column_stack([g[:, 0] + cx, g[:, 1] + cy, np.zeros(len(g))]))
    Pt = np.concatenate(pts)
    C = np.tile([104.0, 18, 16], (len(Pt), 1))
    C[hash01(Pt[:, 0] * 50, Pt[:, 1] * 50) > 0.8] = (130, 26, 22)
    return Cloud(Pt, np.tile([0, 0, 1.0], (len(Pt), 1)), C)


def pool_sprite(death, d):
    """The blood under a body that died `death` facing direction d, on its own so the
    game can lay it on the ground (and leave it there if the body is moved).
    Returns (img, anchor): the same pixels the body's last frame used to carry."""
    from render3d import project, PIX
    pool = blood_pool(d + 7 * len(death))
    pool.transform(rot_z(yaw_for_dir(d)))
    sx, sy = project(pool.P)
    sx, sy = sx * PIX, sy * PIX
    x0, y0 = math.floor(sx.min()) - 1, math.floor(sy.min()) - 1
    W, H = math.ceil(sx.max()) - x0 + 2, math.ceil(sy.max()) - y0 + 2
    img = np.zeros((H, W, 4), np.uint8)
    px = np.floor(sx - x0).astype(int)
    py = np.floor(sy - y0).astype(int)
    img[py, px, :3] = pool.C.astype(np.uint8)
    img[py, px, 3] = 235
    return img, (-x0, -y0)


def lie_line(death, d):
    """Where a body that died `death` facing direction d lies on the ground: the two
    ends of it (texels from his feet), so the game can put his hurtbox on the body.
    "gasp" is a man propped up for a last shot."""
    look = Look(next(iter(TEMPLATES)))
    if death == "gasp":
        body = gasp_body(look, "colt", GASP_POSES["aim"])[0]
    else:
        body = death_anims(look)[death][-1]
    body = body.copy().transform(rot_z(yaw_for_dir(d)))
    xy = body.P[:, :2]
    mid = xy.mean(0)
    axis = np.linalg.svd(xy - mid, full_matrices=False)[2][0]
    t = (xy - mid) @ axis
    lo, hi = np.percentile(t, 4), np.percentile(t, 96)
    return [_project([*(mid + axis * k), 0.0]) for k in (lo, hi)]


def _trim(img, slots_):
    a = img[..., 3]
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return img[:1, :1], slots_[:1, :1], 0, 0
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return img[y0:y1, x0:x1], slots_[y0:y1, x0:x1], int(x0 - ANCHOR[0]), int(y0 - ANCHOR[1])


def _project(p):
    from render3d import PX as px, PY as py, PZ as pz, PIX
    return [round(float((p[0] - p[1]) * px * PIX), 1), round(float(((p[0] + p[1]) * py - p[2] * pz) * PIX), 1)]


def bake_job(job):
    """Render one animation in 8 directions. job = (template, layer, weapon, name).
    Returns (template, key, info, [[(img, slots, ox, oy) per frame] per dir])."""
    template, layer, weapon, name = job
    look = Look(template)
    if layer == "legs":
        anim = legs_anims()[name]
        poses = anim["poses"]
        info = {"fps": anim["fps"], "loop": anim["loop"], "speed": anim["speed"],
                "hip": [round(p["H"], 3) for p in poses]}
        ref_up = _key_poses("colt")["aim"]
        models = [(build_legs(look, p), build_upper(look, None, ref_up, p["H"], with_gun=False)[0]) for p in poses]
    elif layer == "upper":
        anim = upper_anims(weapon)[name]
        info = {"fps": anim["fps"], "loop": anim["loop"], "events": {str(k): v for k, v in anim["events"].items()}}
        extras = [{} for _ in anim["poses"]]
        models = [build_upper(look, weapon, p, extra=x) for p, x in zip(anim["poses"], extras)]
    elif layer == "gasp":
        poses, fps, loop = gasp_anims()[name]
        info = {"fps": fps, "loop": loop}
        models = [gasp_body(look, weapon, p) for p in poses]
    else:
        bodies = death_anims(look)[name]
        info = {"fps": DEATH_FPS[name], "loop": False}
        models = [(b, None) for b in bodies]
    dirs, muzzles, muzzles2 = [], [], []
    for d in range(8):
        R = rot_z(yaw_for_dir(d))
        frames, mz, mz2 = [], [], []
        for i, (cloud, extra) in enumerate(models):
            c = cloud.copy().transform(R)
            ground = shadow_extra = None
            if layer == "legs":
                shadow_extra = extra.copy().transform(R)     # the whole man casts the shadow
            img, _, slots_ = render(c, size=CANVAS, anchor=ANCHOR, ground=ground, want_slots=True,
                                    shadow=layer != "upper", shadow_extra=shadow_extra)
            frames.append(_trim(img, slots_))
            if layer in ("upper", "gasp"):
                mz.append(_project(R @ extra) if extra is not None else None)
            if layer == "upper":
                m2 = extras[i].get("muzzle2")
                mz2.append(_project(R @ m2) if m2 is not None else None)
        dirs.append(frames)
        muzzles.append(mz)
        muzzles2.append(mz2)
    if layer == "gasp":
        info["muzzle"] = muzzles
    if layer == "upper":
        info["muzzle"] = muzzles
        if any(m is not None for mz in muzzles2 for m in mz):
            info["muzzle2"] = muzzles2
    key = {"upper": f"upper/{weapon}/{name}", "gasp": f"full/{weapon}/{name}"}.get(layer, f"{layer}/{name}")
    return template, key, info, dirs


def jobs_for(template, guns):
    jobs = [(template, "legs", None, n) for n in legs_anims()]
    for w in guns:
        jobs += [(template, "upper", w, n) for n in upper_anims(w)]
    jobs += [(template, "full", None, n) for n in DEATH_FPS]
    # the stranger's last stand: his Colt, or a revolver from his boot if he rode in without one
    for w in dict.fromkeys(list(guns) + (["colt", "schofield", "navy"] if template == "hero" else [])):
        if w in PISTOLS:
            jobs += [(template, "gasp", w, n) for n in gasp_anims()]
    return jobs


def pack(entries, width=4096):
    """Shelf-pack trimmed frames. entries: list of (key, dir, idx, img, slots, ox, oy).
    Returns (atlas RGBA, slot atlas, {key: [[ [x, y, w, h, ox, oy] per frame ] per dir]})."""
    order = sorted(range(len(entries)), key=lambda i: -entries[i][3].shape[0])
    x = y = shelf = 0
    placed = {}
    for i in order:
        img = entries[i][3]
        h, w = img.shape[:2]
        if x + w + 1 > width:
            x, y, shelf = 0, y + shelf + 1, 0
        placed[i] = (x, y)
        x += w + 1
        shelf = max(shelf, h)
    H = y + shelf + 1
    atlas = np.zeros((H, width, 4), np.uint8)
    slot_atlas = np.zeros((H, width), np.uint8)
    rects = {}
    for i, (key, d, idx, img, sl, ox, oy) in enumerate(entries):
        px_, py_ = placed[i]
        h, w = img.shape[:2]
        atlas[py_:py_ + h, px_:px_ + w] = img
        slot_atlas[py_:py_ + h, px_:px_ + w] = sl
        rects.setdefault(key, {}).setdefault(d, {})[idx] = [px_, py_, w, h, ox, oy]
    out = {}
    for key, dd in rects.items():
        out[key] = [[dd[d][i] for i in sorted(dd[d])] for d in sorted(dd)]
    return atlas, slot_atlas, out


# ---------------------------------------------------------------- props and UI

def dropped_gun(kind, variant):
    """The gun lying in the dirt where it fell."""
    ang = variant * math.pi / 2 + 0.4
    d = (math.cos(ang), math.sin(ang), 0.0)
    b = (-math.cos(ang) * GUN_LEN[kind] / 2, -math.sin(ang) * GUN_LEN[kind] / 2, 0.035)
    return weapon_model(kind, b, d)


def portrait():
    look = Look("hero", _DATA["player"]["palette"])
    m = build_legs(look, legs_pose("stand"))
    m += build_upper(look, "colt", _key_poses("colt")["aim"])[0]
    m.transform(rot_y(-0.5), pivot=(0, 0, 1.6))
    m.transform(rot_z(yaw_for_dir(2) - 0.3))
    img, anc = render(m, size=(80, 80), anchor=(40, 276), scale=8.4, shadow=False, edges=False)  # UI: fixed 2x
    return img
