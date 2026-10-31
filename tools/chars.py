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
from render3d import (Cloud, ellipsoid, frustum, disc, box, beam, rot_x, rot_y, rot_z, render,
                      PX, PY, hash01)

STEEL = (70, 72, 78)
GUNMETAL = (96, 100, 112)
WOOD = (120, 74, 44)
BRASS = (205, 165, 70)
LEATHER = (92, 62, 38)
MUD = (78, 56, 40)

H_REF = 0.92          # standing hip height; the upper layer is baked at this height
CANVAS = (340, 280)   # render canvas (texels) before trimming; frames are trimmed after
ANCHOR = (170, 200)   # feet within the canvas

SPECS = {
    "hero": dict(style="duster", coat=(172, 142, 100), shirt=(120, 130, 140), trousers=(94, 80, 64),
                 boots=(56, 38, 26), hat="flat", hat_col=(52, 38, 30), band=(104, 72, 46),
                 skin=(196, 138, 98), hair=(68, 48, 34), cigar=True, bandolier=True, scarf=None,
                 mustache=False),
    "pistolero": dict(style="poncho", poncho=[(168, 58, 40), (214, 172, 92), (88, 58, 40),
                                             (226, 208, 168), (168, 58, 40), (60, 44, 36)],
                      shirt=(204, 192, 160), trousers=(124, 102, 72), boots=(70, 48, 32),
                      hat="sombrero", hat_col=(156, 124, 74), band=(92, 40, 30),
                      skin=(168, 110, 76), hair=(30, 24, 20), cigar=False, bandolier=False,
                      scarf=None, mustache=True),
    "rifleman": dict(style="duster", coat=(58, 54, 52), shirt=(192, 186, 170), trousers=(82, 80, 84),
                     boots=(40, 30, 24), hat="bowler", hat_col=(38, 34, 32), band=(60, 50, 44),
                     skin=(202, 150, 116), hair=(110, 70, 40), cigar=False, bandolier=False,
                     scarf=None, mustache=True),
    "redscarf": dict(style="vest", vest=(82, 60, 46), shirt=(206, 196, 172), trousers=(104, 86, 66),
                     boots=(60, 42, 30), hat="flat", hat_col=(92, 72, 54), band=(164, 30, 26),
                     skin=(184, 126, 90), hair=(50, 36, 28), cigar=False, bandolier=True,
                     scarf=(172, 30, 26), mustache=False),
    "jefe": dict(style="duster", coat=(142, 32, 28), shirt=(44, 38, 36), trousers=(44, 38, 36),
                 boots=(30, 22, 18), hat="sombrero", hat_col=(42, 34, 30), band=(196, 156, 64),
                 skin=(170, 114, 80), hair=(20, 16, 14), cigar=True, bandolier=True,
                 scarf=None, mustache=True),
}
# Which guns each character carries (the hero all three).
LOADOUT = {"hero": ["colt", "coach", "rifle"], "pistolero": ["colt"], "rifleman": ["rifle"],
           "redscarf": ["coach"], "jefe": ["coach"]}
GUN_LEN = {"colt": 0.31, "coach": 0.97, "rifle": 1.1}


# ---------------------------------------------------------------- materials

def _torso_fn(spec, H):
    base = np.array(spec["vest"] if spec["style"] == "vest" else spec["shirt"], float)
    shirt = np.array(spec["shirt"], float)

    def f(P, N):
        c = np.tile(base, (len(P), 1))
        if spec["style"] == "vest":
            m = (P[:, 0] > 0) & (np.abs(P[:, 1]) < 0.05)
            c[m] = shirt
        if spec.get("bandolier"):
            zz = P[:, 2] - H
            for sgn in (1, -1):
                m = np.abs(zz - (0.26 + sgn * 0.95 * P[:, 1])) < 0.035
                c[m] = LEATHER
                dots = m & ((P[:, 1] * 22 + P[:, 0] * 6) % 1.0 < 0.45)
                c[dots] = BRASS
        return c
    return f


def _coat_fn(color, bottom):
    base = np.array(color, float)

    def f(P, N):
        c = np.tile(base, (len(P), 1))
        n = hash01(np.floor(P[:, 0] * 30), np.floor(P[:, 1] * 30), np.floor(P[:, 2] * 30))
        c *= (0.94 + 0.1 * n)[:, None]
        m = P[:, 2] < bottom + 0.14 + 0.05 * n
        c[m] = c[m] * 0.55 + np.array(MUD) * 0.45
        return c
    return f


def _poncho_fn(stripes, H):
    cols = np.array(stripes, float)

    def f(P, N):
        band = np.floor((P[:, 2] - H) * 16).astype(int) % len(cols)
        c = cols[band]
        m = P[:, 2] < H + 0.16
        c[m] = c[m] * 0.7
        return c
    return f


def _head_fn(spec, hc):
    skin = np.array(spec["skin"], float)

    def f(P, N):
        c = np.tile(skin, (len(P), 1))
        rel = P - hc
        stub = (rel[:, 0] > 0.02) & (rel[:, 2] < -0.035)
        c[stub] = c[stub] * 0.72 + np.array([60, 44, 34]) * 0.28
        hair = (rel[:, 0] < -0.03) & (rel[:, 2] > -0.04)
        c[hair] = spec["hair"]
        for side in (-1, 1):
            eye = (rel[:, 0] > 0.06) & (np.abs(rel[:, 1] - side * 0.035) < 0.014) & \
                  (np.abs(rel[:, 2] - 0.012) < 0.012)
            c[eye] = (30, 22, 18)
        return c
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

def _hat(spec, z):
    out = Cloud()
    col, band = spec["hat_col"], spec["band"]
    under = tuple(int(c * 0.6) for c in col)
    if spec["hat"] == "flat":
        out += disc((0.01, 0, z), 0.36, col, curl=0.035, front_curl=0.6, underside=under)
        out += frustum((0, 0, z), (0, 0, z + 0.04), 0.118, 0.115, band, caps=False)
        out += frustum((0, 0, z + 0.04), (0, 0, z + 0.14), 0.115, 0.1, col)
    elif spec["hat"] == "sombrero":
        out += disc((0, 0, z), 0.5, col, curl=0.14, front_curl=0.55, underside=under)
        out += frustum((0, 0, z), (0, 0, z + 0.05), 0.13, 0.125, band, caps=False)
        out += frustum((0, 0, z + 0.05), (0, 0, z + 0.26), 0.125, 0.06, col)
    else:  # bowler
        out += disc((0, 0, z), 0.165, col, curl=0.035, front_curl=0.2, underside=under)
        out += frustum((0, 0, z), (0, 0, z + 0.03), 0.112, 0.112, band, caps=False)
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


def build_legs(spec, lp):
    """Trousers, boots, spurs and the skirt of a duster."""
    m = Cloud()
    H = lp["H"]
    trous = spec["trousers"]
    for hip, knee, ankle in lp["legs"]:
        hip, knee, ankle = (np.array(v, float) for v in (hip, knee, ankle))
        m += frustum(hip, knee, 0.078, 0.064, trous)
        m += frustum(knee, ankle, 0.064, 0.052, trous)
        toe = 1.0 if ankle[0] >= knee[0] - 0.2 or not lp["crouch"] else -1.0
        m += ellipsoid(ankle + [0.05 * toe, 0, -0.035], (0.125, 0.055, 0.06), spec["boots"])
        m += frustum(ankle + [-0.09 * toe, -0.012, -0.03], ankle + [-0.09 * toe, 0.012, -0.03],
                     0.03, 0.03, (176, 176, 168))  # spur rowel
    if spec["style"] == "duster":
        crouch = lp["crouch"]
        bottom = 0.05 if crouch else max(0.04, H - 0.55)
        coat = _coat_fn(spec["coat"], bottom)
        m += frustum((0, 0, H + 0.02), (-0.04 - lp["sway"], 0, bottom), 0.21,
                     0.38 if crouch else 0.31, coat, su=0.95 if crouch else 0.72, gap=(0.0, 0.8), caps=False)
    return m


# ---------------------------------------------------------------- rig: upper layer

def build_upper(spec, weapon, up, H=H_REF, with_gun=True):
    """Belt and up: torso, coat body and cape, arms, head, hat and gun, posed by `up`
    (hip-relative) and placed with the hip at height H. Returns (cloud, muzzle point)."""
    m = Cloud()
    m += frustum((0, 0, -0.05), (0, 0, 0.06), 0.168, 0.168, LEATHER, su=0.74)
    m += box((0.11, -0.03, -0.03), (0.135, 0.03, 0.04), BRASS)  # buckle
    m += frustum((0, 0, 0.04), (0, 0, 0.5), 0.15, 0.19, _torso_fn(spec, 0.0), su=0.62)
    m += box((-0.05, -0.2, -0.22), (0.05, -0.16, -0.02), LEATHER)  # holster
    if spec["style"] == "duster":
        coat = _coat_fn(spec["coat"], -5.0)
        m += frustum((0, 0, 0.52), (0, 0, 0.0), 0.2, 0.22, coat, su=0.7, gap=(0.0, 0.8), caps=False)
        m += frustum((0, 0, 0.58), (0, 0, 0.36), 0.12, 0.27, coat, su=0.82, caps=False)
        m += frustum((0, 0, 0.5), (0, 0, 0.6), 0.1, 0.085, coat, caps=False)
        sleeve = spec["coat"]
    elif spec["style"] == "poncho":
        m += frustum((0, 0, 0.6), (0, 0, 0.12), 0.09, 0.42, _poncho_fn(spec["poncho"], 0.0), su=0.92, caps=False)
        sleeve = spec["poncho"][0]
    else:
        sleeve = spec["shirt"]

    m += frustum((0, 0, 0.5), (0, 0, 0.63), 0.05, 0.05, spec["skin"])
    if spec.get("scarf"):
        m += frustum((0, 0, 0.5), (0, 0, 0.6), 0.1, 0.075, spec["scarf"])
        m += frustum((0.06, -0.02, 0.5), (0.1, -0.03, 0.36), 0.05, 0.025, spec["scarf"])
    hc = np.array([0.01, 0, 0.72])
    head = Cloud()
    head += ellipsoid(hc, (0.095, 0.085, 0.11), _head_fn(spec, hc))
    head += ellipsoid(hc + [0.09, 0, -0.005], (0.025, 0.02, 0.03), spec["skin"])  # nose
    if spec.get("mustache"):
        head += ellipsoid(hc + [0.085, 0, -0.045], (0.02, 0.06, 0.015), spec["hair"])
    if spec.get("cigar"):
        head += beam(hc + [0.08, 0.02, -0.06], hc + [0.16, 0.035, -0.075], 0.011, (196, 180, 150))
        head += ellipsoid(hc + [0.165, 0.036, -0.076], (0.014, 0.014, 0.014), (255, 120, 40))
    head += _hat(spec, 0.79)
    nod = up.get("nod", 0.0)
    if nod:
        head.transform(rot_y(nod), pivot=(0, 0, 0.6))
    m += head

    sL = np.array([0, 0.21, 0.48])
    sR = np.array([0, -0.21, 0.48])
    for s, e, h in ((sL, up["eL"], up["hL"]), (sR, up["eR"], up["hR"])):
        e, h = np.array(e, float), np.array(h, float)
        m += frustum(s, e, 0.058, 0.05, sleeve)
        m += frustum(e, h, 0.05, 0.042, sleeve)
        m += ellipsoid(h, (0.045, 0.04, 0.045), spec["skin"])
    m += ellipsoid((0, 0.17, 0.46), (0.08, 0.07, 0.07), sleeve)
    m += ellipsoid((0, -0.17, 0.46), (0.08, 0.07, 0.07), sleeve)
    if up.get("finger"):
        h = np.array(up["hL"], float)
        m += beam(h + [0.03, 0, 0], h + [0.12, -0.01, 0.01], 0.014, spec["skin"])

    muzzle = None
    g = up.get("gun")
    if with_gun and g is not None:
        m += weapon_model(weapon, g["B"], g["D"], up.get("lever", 0.0), up.get("broken", 0.0))
        muzzle = gun_muzzle(weapon, g["B"], g["D"])

    # lean (pitch, + forward) and twist (yaw) about the hip
    R = rot_z(up.get("twist", 0.0)) @ rot_y(up.get("lean", 0.0))
    m.transform(R)
    if muzzle is not None:
        muzzle = R @ muzzle
    m.translate((0, 0, H))
    if muzzle is not None:
        muzzle = muzzle + [0, 0, H]
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
    # Shared, gun-agnostic arm poses; the gun placement comes from the keys above.
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
    return k


def lerp_pose(a, b, t):
    out = {}
    for key in set(a) | set(b):
        va, vb = a.get(key, b.get(key)), b.get(key, a.get(key))
        if key == "gun":
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
    add("fire", [k["kick"], lerp_pose(k["kick"], k["aim"], 0.4), k["aim"]], 12)
    if w == "colt":
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
    else:
        add("reload_open", [k["break_half"], k["load"]], 5)
        add("reload_eject", [k["eject_a"], k["eject_b"]], 6, events={1: "shells"})
        add("reload_insert", [k["insert_a"], k["insert_b"]], 4.8, True)
        add("reload_close", [k["break_half"], k["aim"]], 6)
    add("point", [k["point_half"], k["point"], k["point"]], 6)
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


def _body(spec, legs, upper, fall=None):
    """A whole man (no gun) in a death pose. fall = (kind, angle, pivot, shift)."""
    m = build_legs(spec, legs)
    up, _ = build_upper(spec, None, upper, legs["H"], with_gun=False)
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


def death_anims(spec):
    """Four ways to die, 5-6 frames each, ending on the corpse."""
    stand, crouch = legs_pose("stand"), legs_pose("crouch")
    kneel, sit = legs_pose("kneel"), legs_pose("sit")
    stag = legs_pose("stagger")
    hurt = P(CLUTCH, lean=0.35, nod=0.2)
    lying = math.pi / 2 - 0.02
    d = {}
    # Thrown back off his feet (the coach gun up close).
    d["death_back"] = [
        _body(spec, stag, P(FLUNG, lean=-0.3)),
        _body(spec, stag, P(FLUNG, lean=-0.3), ("back", 0.45, (-0.1, 0, 0), (-0.12, 0, 0))),
        _body(spec, stand, P(FLUNG, lean=-0.2), ("back", 0.95, (-0.1, 0, 0), (-0.3, 0, 0))),
        _body(spec, stand, P(DEAD_ARMS, lean=-0.1), ("back", 1.35, (-0.1, 0, 0), (-0.45, 0, 0))),
        _body(spec, stand, DEAD_ARMS, ("back", lying, (0, 0, 0), (-0.5, 0, 0))),
    ]
    # Folding at the gut, down onto his knees, then face down.
    d["death_knees"] = [
        _body(spec, stand, hurt),
        _body(spec, kneel, P(CLUTCH, lean=0.3, nod=0.25)),
        _body(spec, kneel, P(SAG, lean=0.12, nod=0.4)),
        _body(spec, kneel, P(SAG, lean=0.2, nod=0.3), ("forward", 0.6, (0.25, 0, 0.08), (0, 0, 0))),
        _body(spec, kneel, P(SAG, lean=0.2), ("forward", 1.2, (0.25, 0, 0.08), (0.1, 0, 0))),
        _body(spec, stand, SAG, ("forward", lying, (0, 0, 0), (0.45, 0, 0))),
    ]
    # Spun half round by the hit and dropped on his side.
    spin = []
    for i, (tw, roll) in enumerate(((0.5, 0.0), (1.1, 0.25), (1.7, 0.6), (2.2, 1.05), (2.5, lying))):
        b = _body(spec, stag if i < 2 else stand, P(FLUNG if i < 3 else DEAD_ARMS, twist=tw * 0.3), ("side", roll, (0, 0, 0), (0, 0.15 * i, 0)))
        b.transform(rot_z(tw * 0.7))
        spin.append(b)
    d["death_spin"] = spin
    # The slow one: looks at the wound, sinks to a knee, sits, and topples.
    d["death_slump"] = [
        _body(spec, stand, P(CLUTCH, lean=-0.12, nod=0.35)),
        _body(spec, stag, P(CLUTCH, lean=0.15, nod=0.45)),
        _body(spec, crouch, P(CLUTCH, lean=0.25, nod=0.4)),
        _body(spec, sit, P(SAG, lean=-0.2, nod=0.3)),
        _body(spec, sit, P(SAG, lean=-0.3), ("side", 0.8, (0, 0, 0), (0, 0, 0))),
        _body(spec, stand, SAG, ("side", lying, (0, 0, 0), (-0.3, 0.2, 0))),
    ]
    return d


DEATH_FPS = {"death_back": 9, "death_knees": 6, "death_spin": 8, "death_slump": 4.5}


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


def _trim(img):
    a = img[..., 3]
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return img[:1, :1], 0, 0
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return img[y0:y1, x0:x1], int(x0 - ANCHOR[0]), int(y0 - ANCHOR[1])


def _project(p):
    from render3d import PX as px, PY as py, PZ as pz, PIX
    return [round(float((p[0] - p[1]) * px * PIX), 1), round(float(((p[0] + p[1]) * py - p[2] * pz) * PIX), 1)]


def bake_job(job):
    """Render one animation in 8 directions. job = (char, layer, weapon, name).
    Returns (key, info, [ [ (img, ox, oy) per frame ] per dir ])."""
    char, layer, weapon, name = job
    spec = SPECS[char]
    info = {}
    if layer == "legs":
        anim = legs_anims()[name]
        poses = anim["poses"]
        info = {"fps": anim["fps"], "loop": anim["loop"], "speed": anim["speed"],
                "hip": [round(p["H"], 3) for p in poses]}
        ref_up = _key_poses("colt")["aim"]
        models = [(build_legs(spec, p), build_upper(spec, None, ref_up, p["H"], with_gun=False)[0]) for p in poses]
    elif layer == "upper":
        anim = upper_anims(weapon)[name]
        info = {"fps": anim["fps"], "loop": anim["loop"], "events": {str(k): v for k, v in anim["events"].items()}}
        models = [build_upper(spec, weapon, p) for p in anim["poses"]]
    else:
        bodies = death_anims(spec)[name]
        info = {"fps": DEATH_FPS[name], "loop": False}
        models = [(b, None) for b in bodies]
    dirs, muzzles = [], []
    for d in range(8):
        yaw = yaw_for_dir(d)
        R = rot_z(yaw)
        frames, mz = [], []
        for i, (cloud, extra) in enumerate(models):
            c = cloud.copy().transform(R)
            ground = None
            shadow_extra = None
            if layer == "legs":
                shadow_extra = extra.copy().transform(R)     # the whole man casts the shadow
            if layer == "full" and i == len(models) - 1:
                ground = blood_pool(d + 7 * len(name))
                ground.transform(R)
            img, _ = render(c, size=CANVAS, anchor=ANCHOR, ground=ground,
                            shadow=layer != "upper", shadow_extra=shadow_extra)
            frames.append(_trim(img))
            if layer == "upper":
                mz.append(_project(R @ extra) if extra is not None else None)
        dirs.append(frames)
        muzzles.append(mz)
    if layer == "upper":
        info["muzzle"] = muzzles
    key = f"{layer}/{name}" if layer != "upper" else f"upper/{weapon}/{name}"
    return char, key, info, dirs


def jobs_for(char):
    jobs = [(char, "legs", None, n) for n in legs_anims()]
    for w in LOADOUT[char]:
        jobs += [(char, "upper", w, n) for n in upper_anims(w)]
    jobs += [(char, "full", None, n) for n in DEATH_FPS]
    return jobs


def pack(entries, width=4096):
    """Shelf-pack trimmed frames. entries: list of (key, dir, idx, img, ox, oy).
    Returns (atlas RGBA, {key: [[ [x, y, w, h, ox, oy] per frame ] per dir]})."""
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
    rects = {}
    for i, (key, d, idx, img, ox, oy) in enumerate(entries):
        px_, py_ = placed[i]
        h, w = img.shape[:2]
        atlas[py_:py_ + h, px_:px_ + w] = img
        rects.setdefault(key, {}).setdefault(d, {})[idx] = [px_, py_, w, h, ox, oy]
    out = {}
    for key, dd in rects.items():
        out[key] = [[dd[d][i] for i in sorted(dd[d])] for d in sorted(dd)]
    return atlas, out


# ---------------------------------------------------------------- props and UI

def dropped_gun(kind, variant):
    """The gun lying in the dirt where it fell."""
    ang = variant * math.pi / 2 + 0.4
    d = (math.cos(ang), math.sin(ang), 0.0)
    b = (-math.cos(ang) * GUN_LEN[kind] / 2, -math.sin(ang) * GUN_LEN[kind] / 2, 0.035)
    return weapon_model(kind, b, d)


def portrait():
    spec = SPECS["hero"]
    m = build_legs(spec, legs_pose("stand"))
    m += build_upper(spec, "colt", _key_poses("colt")["aim"])[0]
    m.transform(rot_y(-0.5), pivot=(0, 0, 1.6))
    m.transform(rot_z(yaw_for_dir(2) - 0.3))
    img, anc = render(m, size=(80, 80), anchor=(40, 276), scale=8.4, shadow=False, edges=False)  # UI: fixed 2x
    return img
