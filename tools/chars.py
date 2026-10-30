"""Character models: the hero and the bandits, posed per weapon and animation frame."""
import math
import numpy as np
from render3d import (Cloud, ellipsoid, frustum, disc, box, beam, rot_z, rot_y, render,
                      PX, PY, hash01)

STEEL = (70, 72, 78)
GUNMETAL = (96, 100, 112)
WOOD = (120, 74, 44)
BRASS = (205, 165, 70)
LEATHER = (92, 62, 38)
MUD = (78, 56, 40)

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

# Sheet columns. Names ending in a digit are frames of one animation ("walk0".."walk3").
COLS = ["idle", "walk0", "walk1", "walk2", "walk3", "crouch", "cwalk0", "cwalk1", "dead",
        "point0", "point1", "flinch", "cower0", "cower1", "hurt0", "hurt1", "fire", "fall"]


def anims():
    """{animation: [first column, frame count]} derived from COLS."""
    out = {}
    for i, c in enumerate(COLS):
        name = c.rstrip("0123456789")
        if name in out:
            out[name][1] += 1
        else:
            out[name] = [i, 1]
    return out
CELL = (192, 168)
ANCHOR = (96, 138)


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


def _legs(H, phase, pose):
    """Returns list of (hip, knee, ankle) per leg (y=+0.1 left, y=-0.1 right)."""
    legs = []
    if pose in ("crouch", "cwalk"):
        sh = 0.04 * math.sin(phase)
        legs.append(((0, 0.1, H), (0.34 + sh, 0.11, H - 0.02), (0.3 + sh, 0.11, 0.09)))
        legs.append(((0, -0.1, H), (0.06 - sh, -0.12, 0.09), (-0.36 - sh, -0.12, 0.08)))
        return legs
    for side, ph in ((1, phase), (-1, phase + math.pi)):
        s = 0.42 * math.sin(ph) if pose == "walk" else 0.0
        b = 0.55 * max(0.0, -math.sin(ph + 0.6)) if pose == "walk" else 0.0
        hip = np.array([0, 0.1 * side, H])
        knee = hip + np.array([math.sin(s), 0, -math.cos(s)]) * 0.42
        ankle = knee + np.array([math.sin(s - b), 0, -math.cos(s - b)]) * 0.42
        legs.append((hip, knee, ankle))
    return legs


def _weapon(kind, butt, muzzle, dead=False):
    out = Cloud()
    butt = np.array(butt, float)
    muzzle = np.array(muzzle, float)
    d = muzzle - butt
    L = np.linalg.norm(d)
    a = d / L
    side = np.cross(a, [0, 0, 1.0])
    if np.linalg.norm(side) < 1e-3:
        side = np.array([0, 1.0, 0])
    side /= np.linalg.norm(side)
    up = np.cross(side, a)

    def at(t, off=(0, 0)):
        return butt + a * (L * t) + side * off[0] + up * off[1]
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
        for o in (-0.024, 0.024):                                                     # side by side
            out += beam(at(0.34, (o, 0.012)), at(1.0, (o, 0.012)), 0.022, GUNMETAL)
            out += beam(at(0.27, (o * 1.4, 0.03)), at(0.31, (o * 1.6, 0.075)), 0.012, STEEL)  # hammers
        out += beam(at(0.34, (0, -0.025)), at(0.62, (0, -0.025)), 0.03, WOOD)
    else:  # Winchester 1866 "Yellow Boy"
        out += frustum(at(0.0, (0, -0.04)), at(0.28), 0.055, 0.028, WOOD)
        out += frustum(at(0.27), at(0.43), 0.045, 0.045, (232, 186, 72))               # brass receiver
        out += beam(at(0.43, (0, 0.014)), at(1.0, (0, 0.014)), 0.015, GUNMETAL)
        out += beam(at(0.43, (0, -0.02)), at(0.93, (0, -0.02)), 0.013, STEEL)
        out += beam(at(0.43), at(0.64), 0.03, WOOD)
        out += beam(at(0.3, (0, -0.05)), at(0.4, (0, -0.1)), 0.011, STEEL)            # lever loop
        out += beam(at(0.4, (0, -0.1)), at(0.44, (0, -0.05)), 0.011, STEEL)
    return out


def _hat(spec, z, sp=0.02):
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


def build(spec, weapon, pose="idle", phase=0.0):
    """Model facing +X, feet at the origin."""
    standing = pose not in ("crouch", "cwalk", "cower")
    walk = pose == "walk"
    H = 0.92 if standing else 0.5
    m = Cloud()

    legs = _legs(H, 0.0 if pose == "cower" else phase, "walk" if walk else ("crouch" if not standing else "idle"))
    lowest = min(l[2][2] for l in legs)
    dz = 0.1 - lowest if standing else 0.0
    if walk:
        dz += 0.0
    H += dz
    trous = spec["trousers"]
    for hip, knee, ankle in legs:
        hip, knee, ankle = (np.array(v, float) + [0, 0, dz] for v in (hip, knee, ankle))
        m += frustum(hip, knee, 0.078, 0.064, trous)
        m += frustum(knee, ankle, 0.064, 0.052, trous)
        toe = 1.0 if ankle[0] >= -0.2 or standing else -1.0
        m += ellipsoid(ankle + [0.05 * toe, 0, -0.035], (0.125, 0.055, 0.06), spec["boots"])
        m += frustum(ankle + [-0.09 * toe, -0.012, -0.03], ankle + [-0.09 * toe, 0.012, -0.03],
                     0.03, 0.03, (176, 176, 168))  # spur rowel

    # belt and torso
    m += frustum((0, 0, H - 0.05), (0, 0, H + 0.06), 0.168, 0.168, LEATHER, su=0.74)
    m += box((0.11, -0.03, H - 0.03), (0.135, 0.03, H + 0.04), BRASS)  # buckle
    m += frustum((0, 0, H + 0.04), (0, 0, H + 0.5), 0.15, 0.19, _torso_fn(spec, H), su=0.62)
    if weapon != "colt" or True:
        m += box((-0.05, -0.2, H - 0.22), (0.05, -0.16, H - 0.02), LEATHER)  # holster

    bottom = max(0.04, H - 0.55) if standing else 0.05
    sway = 0.05 * math.sin(phase * 2) if walk else 0.0
    if spec["style"] == "duster":
        coat = _coat_fn(spec["coat"], bottom)
        m += frustum((0, 0, H + 0.52), (-0.04 - sway, 0, bottom), 0.2, 0.31 if standing else 0.38,
                     coat, su=0.7 if standing else 0.95, gap=(0.0, 0.8), caps=False)
        m += frustum((0, 0, H + 0.58), (0, 0, H + 0.36), 0.12, 0.27, coat, su=0.82, caps=False)
        m += frustum((0, 0, H + 0.5), (0, 0, H + 0.6), 0.1, 0.085, coat, caps=False)
    elif spec["style"] == "poncho":
        m += frustum((0, 0, H + 0.6), (0, 0, H + 0.12), 0.09, 0.42, _poncho_fn(spec["poncho"], H),
                     su=0.92, caps=False)
    sleeve = spec["coat"] if spec["style"] == "duster" else spec["shirt"]
    if spec["style"] == "poncho":
        sleeve = spec["poncho"][0]

    # neck, scarf, head
    m += frustum((0, 0, H + 0.5), (0, 0, H + 0.63), 0.05, 0.05, spec["skin"])
    if spec.get("scarf"):
        m += frustum((0, 0, H + 0.5), (0, 0, H + 0.6), 0.1, 0.075, spec["scarf"])
        m += frustum((0.06, -0.02, H + 0.5), (0.1, -0.03, H + 0.36), 0.05, 0.025, spec["scarf"])
    hc = np.array([0.01, 0, H + 0.72])
    m += ellipsoid(hc, (0.095, 0.085, 0.11), _head_fn(spec, hc))
    m += ellipsoid(hc + [0.09, 0, -0.005], (0.025, 0.02, 0.03), spec["skin"])  # nose
    if spec.get("mustache"):
        m += ellipsoid(hc + [0.085, 0, -0.045], (0.02, 0.06, 0.015), spec["hair"])
    if spec.get("cigar"):
        m += beam(hc + [0.08, 0.02, -0.06], hc + [0.16, 0.035, -0.075], 0.011, (196, 180, 150))
        m += ellipsoid(hc + [0.165, 0.036, -0.076], (0.014, 0.014, 0.014), (255, 120, 40))
    hat = _hat(spec, H + 0.79)

    # arms + weapon
    Zs = H + 0.48
    sL = np.array([0, 0.21, Zs])
    sR = np.array([0, -0.21, Zs])
    finger = None
    if pose == "dead":
        eR, hR = sR + [0.05, -0.25, 0.1], sR + [0.1, -0.5, 0.25]
        eL, hL = sL + [0.05, 0.25, 0.05], sL + [0.12, 0.48, 0.15]
        gun = None
    elif pose == "point":
        # "There he is!": off arm thrust out at the stranger, gun hand lowered.
        if phase < 0.5:
            eL, hL = np.array([0.14, 0.24, Zs - 0.14]), np.array([0.32, 0.16, Zs - 0.06])
        else:
            eL, hL = np.array([0.26, 0.14, Zs + 0.03]), np.array([0.54, 0.05, Zs + 0.1])
            finger = (hL + [0.03, 0, 0], hL + [0.12, -0.01, 0.01])
        if weapon == "colt":
            eR, hR = np.array([0.02, -0.26, Zs - 0.28]), np.array([0.1, -0.24, Zs - 0.5])
            gun = ("colt", hR + [-0.02, 0, 0.05], hR + [0.22, 0, -0.08])
        else:
            eR, hR = np.array([-0.05, -0.28, Zs - 0.28]), np.array([0.02, -0.22, H + 0.05])
            gun = (weapon, np.array([-0.2, -0.22, H + 0.25]), np.array([0.65, -0.24, H - 0.25]))
    elif pose == "cower":
        # Hands clamped on the hat, gun forgotten.
        eL, hL = np.array([0.16, 0.3, H + 0.66]), np.array([0.05, 0.09, H + 0.86])
        eR, hR = np.array([0.16, -0.3, H + 0.66]), np.array([0.05, -0.09, H + 0.86])
        if weapon == "colt":
            gun = ("colt", hR + [0.0, -0.02, -0.02], hR + [-0.12, -0.04, 0.2])
        else:
            gun = (weapon, np.array([0.35, -0.45, 0.03]), np.array([0.35 + 0.85, -0.25, 0.03]))
    elif pose in ("hurt", "fall"):
        # Hit: clutching the wound, gun arm sagging.
        eL, hL = np.array([0.1, 0.25, Zs - 0.25]), np.array([0.14, 0.05, Zs - 0.22])
        if weapon == "colt":
            eR, hR = np.array([0.03, -0.26, Zs - 0.28]), np.array([0.12, -0.25, Zs - 0.5])
            gun = ("colt", hR + [-0.02, 0, 0.05], hR + [0.22, 0, -0.1])
        else:
            eR, hR = np.array([-0.05, -0.28, Zs - 0.28]), np.array([0.02, -0.23, H + 0.05])
            gun = (weapon, np.array([-0.2, -0.24, H + 0.22]), np.array([0.6, -0.26, H - 0.3]))
    elif pose == "flinch":
        # Startled by a near miss: arms up to shield the face.
        eL, hL = np.array([0.12, 0.32, Zs - 0.05]), np.array([0.2, 0.1, Zs + 0.2])
        eR, hR = np.array([0.1, -0.32, Zs - 0.08]), np.array([0.2, -0.08, Zs + 0.14])
        if weapon == "colt":
            gun = ("colt", hR + [0.0, 0, -0.03], hR + [0.06, 0, 0.24])
        else:
            gun = (weapon, np.array([0.05, -0.3, Zs - 0.35]), np.array([0.3, 0.4, Zs + 0.4]))
    elif weapon == "colt":
        eR = np.array([0.27, -0.14, Zs - 0.03])
        hR = np.array([0.5, -0.07, Zs - 0.05])
        sw = 0.06 * math.sin(phase) if walk else 0.0
        eL = np.array([-0.02 + sw, 0.25, Zs - 0.28])
        hL = np.array([0.03 + sw * 2, 0.23, Zs - 0.52])
        gun = ("colt", hR + [-0.03, 0, -0.06], hR + [0.27, 0, 0.0])
    elif weapon == "coach":
        # Coach gun carried low at the hip.
        eR, hR = np.array([-0.08, -0.29, Zs - 0.28]), np.array([0.04, -0.17, H + 0.13])
        eL, hL = np.array([0.16, 0.12, Zs - 0.3]), np.array([0.4, -0.07, H + 0.21])
        gun = ("coach", np.array([-0.16, -0.18, H + 0.08]), np.array([0.78, -0.05, H + 0.25]))
    else:
        # Rifle shouldered.
        eR = np.array([-0.02, -0.27, Zs - 0.2])
        hR = np.array([0.12, -0.1, Zs - 0.1])
        eL = np.array([0.25, 0.14, Zs - 0.2])
        hL = np.array([0.42, -0.03, Zs - 0.12])
        gun = (weapon, np.array([-0.1, -0.12, Zs - 0.04]), np.array([1.0, -0.04, Zs - 0.15]))
    for s, e, h in ((sL, eL, hL), (sR, eR, hR)):
        m += frustum(s, e, 0.058, 0.05, sleeve)
        m += frustum(e, h, 0.05, 0.042, sleeve)
        m += ellipsoid(h, (0.045, 0.04, 0.045), spec["skin"])
    m += ellipsoid((0, 0.17, Zs - 0.02), (0.08, 0.07, 0.07), sleeve)
    m += ellipsoid((0, -0.17, Zs - 0.02), (0.08, 0.07, 0.07), sleeve)
    if gun and pose == "fire":
        kick = 0.1 if weapon == "coach" else 0.07
        gun = (gun[0], gun[1], gun[2] + [0, 0, kick])
    if gun:
        m += _weapon(*gun)
    if finger:
        m += beam(finger[0], finger[1], 0.014, spec["skin"])

    if pose == "dead":
        m.transform(rot_y(-math.pi / 2))
        m.translate((0, 0, -m.P[:, 2].min() + 0.0))
        m.translate((0.75, 0, 0))
        hat.transform(rot_y(-0.3)).translate((-1.45 + 0.75, 0.25, -(H + 0.79)))
        m += hat
        gk = "colt" if weapon == "colt" else weapon
        g0 = np.array([0.3, -0.62, 0.03])
        glen = 0.3 if gk == "colt" else 0.95
        m += _weapon(gk, g0, g0 + [glen * 0.8, -glen * 0.4, 0.0])
    else:
        m += hat
        if pose == "flinch":
            m.transform(rot_y(-0.16))
        elif pose == "cower":
            m.transform(rot_y(0.38), pivot=(0, 0, 0.5))
            m.translate((0, 0, -0.02 * phase))
        elif pose == "hurt":
            m.transform(rot_y(-0.12 - 0.14 * phase))
        elif pose == "fire":
            m.transform(rot_y(-0.05))
        elif pose == "fall":
            m.transform(rot_y(-0.95))
            m.translate((0.1, 0, -min(0.0, m.P[:, 2].min())))
    return m


def yaw_for_dir(d):
    """World yaw that appears as screen direction d*45 deg (0 = right, 2 = down)."""
    a = d * math.pi / 4
    dx, dy = math.cos(a), math.sin(a)
    X = (dx / PX + dy / PY) / 2
    Y = (dy / PY - dx / PX) / 2
    return math.atan2(Y, X)


def blood_pool(seed):
    rng = np.random.default_rng(seed)
    pts, cols = [], []
    for _ in range(4):
        cx, cy = rng.normal(0.1, 0.25), rng.normal(0, 0.2)
        r = rng.uniform(0.15, 0.32)
        g = np.mgrid[-r:r:0.01, -r:r:0.01].reshape(2, -1).T
        g = g[(g ** 2).sum(1) < r * r]
        pts.append(np.column_stack([g[:, 0] + cx, g[:, 1] + cy, np.zeros(len(g))]))
    P = np.concatenate(pts)
    C = np.tile([104.0, 18, 16], (len(P), 1))
    C[hash01(P[:, 0] * 50, P[:, 1] * 50) > 0.8] = (130, 26, 22)
    return Cloud(P, np.tile([0, 0, 1.0], (len(P), 1)), C)


def sheet(name, weapon):
    spec = SPECS[name]
    W, H = CELL
    out = np.zeros((H * 8, W * len(COLS), 4), np.uint8)
    for d in range(8):
        yaw = yaw_for_dir(d)
        for ci, col in enumerate(COLS):
            if col == "idle":
                m = build(spec, weapon, "idle")
            elif col.startswith("walk"):
                m = build(spec, weapon, "walk", int(col[-1]) * math.pi / 2)
            elif col == "crouch":
                m = build(spec, weapon, "crouch")
            elif col.startswith("cwalk"):
                m = build(spec, weapon, "cwalk", int(col[-1]) * math.pi)
            elif col.rstrip("01") in ("point", "cower", "hurt"):
                m = build(spec, weapon, col.rstrip("01"), float(col[-1]))
            elif col in ("flinch", "fire", "fall"):
                m = build(spec, weapon, col)
            else:
                m = build(spec, weapon, "dead")
            ground = None
            if col == "dead":
                ground = blood_pool(d)
                ground.transform(rot_z(yaw))
            m.transform(rot_z(yaw))
            img, _ = render(m, size=CELL, anchor=ANCHOR, ground=ground)
            out[d * H:(d + 1) * H, ci * W:(ci + 1) * W] = img
    return out


def portrait():
    spec = SPECS["hero"]
    m = build(spec, "colt", "idle")
    m.transform(rot_y(-0.5), pivot=(0, 0, 1.6))
    m.transform(rot_z(yaw_for_dir(2) - 0.3))
    img, anc = render(m, size=(80, 80), anchor=(40, 276), scale=8.4, shadow=False, edges=False)  # UI: fixed 2x
    return img
