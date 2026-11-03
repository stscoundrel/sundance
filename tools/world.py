"""Buildings and props for the town, built from primitives in metres.
Every model has its origin at the footprint's minimum corner."""
import math
import numpy as np
from render3d import (Cloud, make, box, quad, tri, frustum, ellipsoid, beam, hash01, TILE_M,
                      rot_x, rot_y, rot_z)

T = TILE_M
BSP = 0.04  # building sample spacing

FONT = {
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"], "N": ["#.#", "###", "###", "###", "#.#"],
    "O": ["###", "#.#", "#.#", "#.#", "###"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], " ": ["...", "...", "...", "...", "..."],
    "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "M": ["#.#", "###", "###", "#.#", "#.#"], "P": ["##.", "#.#", "##.", "#..", "#.."],
    "W": ["#.#", "#.#", "###", "###", "#.#"], "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
}


# ---------------------------------------------------------------- materials

def face_uv(P, N):
    """Horizontal coordinate along a vertical face and a face id."""
    ax = np.abs(N[:, 0]) > np.abs(N[:, 1])
    u = np.where(ax, P[:, 1], P[:, 0])
    fid = np.where(ax, np.sign(N[:, 0]) * 2, np.sign(N[:, 1]) * 3)
    return u, fid


def planks(base, board=0.22, vertical=False, seed=0, mud=0.35):
    base = np.array(base, float)

    def f(P, N):
        u, fid = face_uv(P, N)
        coord = u if vertical else P[:, 2]
        row = np.floor(coord / board)
        tone = 0.86 + 0.26 * hash01(row, fid + seed)
        if not vertical:
            tone *= 0.95 + 0.1 * hash01(np.floor(u / 1.7 + row * 0.37), row)
        c = base * tone[:, None]
        gapm = (coord % board) < 0.035
        c[gapm] *= 0.62
        streak = hash01(np.floor(u * 9), row) > 0.93
        c[streak] *= 0.85
        low = P[:, 2] < mud * (0.7 + 0.6 * hash01(np.floor(u * 6)))
        c[low] = c[low] * 0.6 + np.array([84, 60, 42]) * 0.4
        return c
    return f


def adobe(base, seed=0):
    base = np.array(base, float)
    brick = np.array([168, 106, 76], float)

    def f(P, N):
        u, fid = face_uv(P, N)
        horiz = np.abs(N[:, 2]) > 0.5
        uu = np.where(horiz, P[:, 0] + P[:, 1] * 0.7, u)
        vv = np.where(horiz, P[:, 1], P[:, 2])
        n1 = hash01(np.floor(uu * 2.2), np.floor(vv * 2.2), fid + seed)
        n2 = hash01(np.floor(uu * 9), np.floor(vv * 9), fid)
        c = base * (0.9 + 0.08 * n1 + 0.06 * n2)[:, None]
        patch = (hash01(np.floor(uu * 0.9 + 3), np.floor(vv * 1.4), fid + seed + 5) > 0.82) & ~horiz
        row = np.floor(vv / 0.14)
        mortar = ((vv % 0.14) < 0.03) | (((uu + row * 0.15) % 0.3) < 0.03)
        pc = brick * (0.9 + 0.2 * hash01(row, np.floor(uu / 0.3)))[:, None]
        c[patch] = np.where(mortar[patch][:, None], base * 0.75, pc[patch])
        crack = (hash01(np.floor(uu * 30), np.floor(vv * 4), fid) > 0.985)
        c[crack] *= 0.6
        low = (P[:, 2] < 0.35 + 0.15 * n1) & ~horiz
        c[low] = c[low] * 0.7 + np.array([120, 88, 60]) * 0.3
        return c
    return f


def bricks(base, mortar_col=(186, 160, 128)):
    base = np.array(base, float)

    def f(P, N):
        u, fid = face_uv(P, N)
        row = np.floor(P[:, 2] / 0.13)
        col = np.floor((u + row * 0.16) / 0.32)
        c = base * (0.86 + 0.24 * hash01(row, col, fid))[:, None]
        mort = ((P[:, 2] % 0.13) < 0.025) | (((u + row * 0.16) % 0.32) < 0.03)
        c[mort] = mortar_col
        return c
    return f


def roofing(base, along_y=True, row=0.28):
    base = np.array(base, float)

    def f(P, N):
        r = np.floor((P[:, 0] if along_y else P[:, 1]) / row)
        k = np.floor((P[:, 1] if along_y else P[:, 0]) / 0.4 + r * 0.5)
        c = base * (0.82 + 0.3 * hash01(r, k))[:, None]
        edge = ((P[:, 0] if along_y else P[:, 1]) % row) < 0.05
        c[edge] *= 0.7
        return c
    return f


def solid(col):
    return lambda P, N: np.tile(np.array(col, float), (len(P), 1))


# Doorways at street level, recorded as buildings are modelled so townsfolk know
# where they can run indoors: (face, centre along the face in metres, W, D).
DOORS = []
# Glazed windows, for shutters and broken glass: (face, (u0, u1), (z0, z1), W, D).
WINDOWS = []
GLAZED = []
# Lanterns hung under a porch awning: (x, y, z of the beam), metres from the origin.
LANTERNS = []
# Painted boards hung on chains under an awning: (x, y, z of the chains' tops, text).
SIGNS = []
SIGN_SWING = (-0.5, -0.33, -0.17, 0.0, 0.17, 0.33, 0.5)   # radians about the beam, a frame each
# Laundry pegged out on a washing line: (x, y, z of the line there, kind, seed).
WASHING = []


# Shutter frames, open to closed: each leaf's swing from flat against the wall (pi)
# to shut across the window (0).
SHUTTER_SWING = (math.pi * 0.97, math.pi * 0.6, math.pi * 0.27, 0.0)
SHUTTER_PAINT = {"adobe": [(64, 128, 138), (58, 88, 140), (86, 124, 80), (150, 64, 48)],
                 "wood": [(118, 98, 76), (96, 108, 90), (128, 72, 58), (150, 140, 120)]}


def broken_glass(window, seed):
    """A shot-out pane: a dark hole where the glass was, jagged shards left in the
    frame, catching the light. Laid just proud of the window."""
    face, (u0, u1), (z0, z1), W, D = window
    rng = np.random.default_rng(seed)
    fr = 0.07
    cu, cz = rng.uniform(u0 + 0.3, u1 - 0.3), rng.uniform(z0 + 0.3, z1 - 0.3)   # where it went in

    def fn(P, N):
        u = P[:, 0] if face == "+y" else P[:, 1]
        z = P[:, 2]
        ang = np.arctan2(z - cz, u - cu)
        # the hole's ragged edge: a radius that jumps about with the angle
        edge = 0.18 + 0.5 * hash01(np.floor((ang + math.pi) / (2 * math.pi) * 9) + seed)
        r = np.hypot(u - cu, z - cz)
        c = np.tile([16.0, 14, 16], (len(P), 1))            # the dark room beyond
        shard = r > edge * (u1 - u0)
        c[shard] = (70, 78, 92)
        glint = shard & (((u - z * 0.7) * 9) % 1.0 < 0.18)
        c[glint] = (150, 162, 176)
        crack = shard & (np.abs(np.sin(ang * 5 + seed)) < 0.06)
        c[crack] = (196, 204, 214)
        return c
    if face == "+y":
        return quad((u0 + fr, D + 0.012, z0 + fr), (u1 - u0 - 2 * fr, 0, 0), (0, 0, z1 - z0 - 2 * fr), fn,
                    normal=(0, 1, 0))
    return quad((W + 0.012, u0 + fr, z0 + fr), (0, u1 - u0 - 2 * fr, 0), (0, 0, z1 - z0 - 2 * fr), fn,
                normal=(1, 0, 0))


def lantern(at, broken=False):
    """A tin-and-glass lantern on a short chain from the awning beam; shot, the
    glass is gone and it hangs askew from one link."""
    x, y, top = at
    out = Cloud()
    z = top - 0.45
    tilt = np.array([0.12, 0.05, 0]) if broken else np.zeros(3)
    out += beam((x, y, top), (x, y, z + 0.32) + tilt * 0.5, 0.012, (50, 46, 44))     # the chain
    c = np.array([x, y, z]) + tilt
    out += frustum(c + [0, 0, 0.26], c + [0, 0, 0.34], 0.07, 0.03, (44, 40, 38))   # the cap
    out += frustum(c + [0, 0, -0.02], c + [0, 0, 0.03], 0.075, 0.075, (44, 40, 38))  # the base
    for a in np.linspace(0, 2 * math.pi, 4, endpoint=False):   # the tin cage
        out += beam(c + [0.07 * math.cos(a), 0.07 * math.sin(a), 0.02],
                    c + [0.065 * math.cos(a), 0.065 * math.sin(a), 0.27], 0.01, (44, 40, 38))
    if not broken:
        out += frustum(c + [0, 0, 0.03], c + [0, 0, 0.26], 0.06, 0.06, (255, 226, 150))   # glass, lit within
    else:
        out += frustum(c + [0, 0, 0.03], c + [0, 0, 0.09], 0.062, 0.062, (120, 130, 140))  # a jagged rim
    return out


def _board_paint(x0, x1, z0, z1, text, board=(70, 50, 36), ink=(228, 208, 162)):
    """A painted board: a darker frame round the edge and the words in the middle,
    on the faces front and back."""
    def f(P, N):
        u, z = P[:, 0], P[:, 2]
        c = np.tile(np.array(board, float), (len(P), 1)) * (0.92 + 0.12 * hash01(np.floor(z * 12)))[:, None]
        edge = (u < x0 + 0.05) | (u > x1 - 0.05) | (z < z0 + 0.05) | (z > z1 - 0.05)
        c[edge] *= 0.72
        n = len(text)
        unit = min((x1 - x0 - 0.16) / (4 * n - 1), (z1 - z0 - 0.14) / 5)
        start = (x0 + x1) / 2 - unit * (4 * n - 1) / 2
        top = (z0 + z1) / 2 + unit * 2.5
        gx = np.floor((u - start) / unit).astype(int)
        gy = np.floor((top - z) / unit).astype(int)
        li, lx = gx // 4, gx % 4
        ink_m = np.zeros(len(P), bool)
        for i, ch in enumerate(text):
            g = FONT.get(ch, FONT[" "])
            for r in range(5):
                for k in range(3):
                    if g[r][k] == "#":
                        ink_m |= (li == i) & (lx == k) & (gy == r)
        c[ink_m & ~edge & (np.abs(N[:, 1]) > 0.5)] = ink
        return c
    return f


def hanging_sign(at, swing=0.0, askew=False):
    """A painted board on two chains from the awning. A round sets it swinging about
    the chains' tops; enough of them part a chain and it hangs down from one corner."""
    x, y, top, text = at
    w, h, drop = 1.0, 0.42, 0.2
    x0, x1, z1 = x - w / 2, x + w / 2, top - drop
    out = Cloud()
    board = box((x0, y - 0.025, z1 - h), (x1, y + 0.025, z1), _board_paint(x0, x1, z1 - h, z1, text), 0.02)
    chain = (52, 48, 44)
    if askew:   # the right chain shot through: down from the left corner, nearly on end
        board.transform(rot_y_(1.15), pivot=(x0 + 0.06, y, z1))
        out += board
        out += _sign_bracket(x0, x1, y, top)
        out += beam((x0 + 0.06, y, top), (x0 + 0.06, y, z1), 0.01, chain)
        out += beam((x1 - 0.06, y, top), (x1 - 0.06, y, top - 0.08), 0.01, chain)   # the broken end
        return out
    out += board
    for cx in (x0 + 0.06, x1 - 0.06):
        out += beam((cx, y, top), (cx, y, z1), 0.01, chain)
    out.transform(rot_x(swing), pivot=(x, y, top))
    out += _sign_bracket(x0, x1, y, top)
    return out


def _sign_bracket(x0, x1, y, top):
    """The iron arm it hangs from, out from under the awning's edge."""
    out = Cloud()
    iron = (46, 42, 40)
    out += beam((x0 - 0.04, y, top), (x1 + 0.04, y, top), 0.014, iron)
    for xx in (x0 - 0.04, x1 + 0.04):
        out += beam((xx, y, top), (xx, y - 0.3, top + 0.28), 0.012, iron)
    return out


def rot_y_(a):
    c, s_ = math.cos(a), math.sin(a)
    return np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])


# Washing: (kind, width, height, colour). Pegged out across a yard or an alley.
GARMENTS = {
    "sheet": (1.0, 1.1, (232, 228, 214)),
    "shirt": (0.5, 0.62, (126, 146, 172)),
    "longjohns": (0.46, 1.0, (176, 58, 48)),
    "towel": (0.42, 0.5, (226, 220, 200)),
    "skirt": (0.6, 0.8, (96, 70, 92)),
}
LAUNDRY_LOOKS = ((0.12, False), (0.55, False), (-0.35, False), (0.12, True), (0.55, True), (-0.35, True))


def garment(peg, flap=0.0, holed=False, down=False):
    """A piece of washing pegged to the line at `peg`, the wind (or a round) lifting
    its hem by `flap`. Holed: shot through. Down: torn off the line, in the dirt."""
    x, y, z, kind, seed = peg
    w, h, col = GARMENTS[kind]
    rng = np.random.default_rng(seed)
    sp = 0.02 / 3
    u, v = np.meshgrid(np.arange(-w / 2, w / 2, sp), np.arange(0.0, h, sp), indexing="ij")
    u, v = u.ravel(), v.ravel()
    keep = np.ones(len(u), bool)
    if kind == "longjohns":   # two legs below the seat
        keep &= ~((v > h * 0.45) & (np.abs(u) < 0.035))
    if kind == "shirt":       # narrower at the hem than across the shoulders, sleeves hanging
        keep &= ~((v > 0.18) & (np.abs(u) > 0.17))
    if kind == "skirt":
        keep &= np.abs(u) < w / 2 * (0.55 + 0.45 * v / h)
    if holed:
        for _ in range(3):
            cu, cv, r = rng.uniform(-w / 3, w / 3), rng.uniform(h * 0.2, h * 0.85), rng.uniform(0.035, 0.06)
            keep &= np.hypot(u - cu, v - cv) > r
    u, v = u[keep], v[keep]
    base = np.array(col, float)
    C = np.tile(base, (len(u), 1)) * (0.9 + 0.12 * hash01(np.floor(u * 30), np.floor(v * 30)))[:, None]
    if kind == "towel":   # a stripe across
        C[(v > h * 0.7) & (v < h * 0.8)] = (170, 60, 50)
    if kind == "shirt":   # the sleeves, a shade darker in the fold
        C[np.abs(u) > 0.17] *= 0.88
    if down:
        # in a heap in the dirt below the line, crumpled
        P = np.stack([x + u * 0.85 + 0.05 * np.sin(v * 9), y + 0.25 + v * 0.45,
                      0.02 + 0.05 * hash01(np.floor(u * 8), np.floor(v * 8))], -1)
        return make(P, np.tile([0, 0, 1.0], (len(P), 1)), lambda P_, N_: C)
    t = v / h
    bend = flap * 0.45 * t ** 1.6 + 0.03 * flap * np.sin(u * 9 + seed)
    P = np.stack([x + u, y + bend, z - v * np.cos(flap * 0.5 * t)], -1)
    out = make(P, np.tile([0, 1.0, 0], (len(P), 1)), lambda P_, N_: C)
    out += make(P - [0, 0.006, 0], np.tile([0, -1.0, 0], (len(P), 1)), lambda P_, N_: C * 0.8)
    for px in (x - w / 2 + 0.04, x + w / 2 - 0.04):   # the pegs
        out += box((px - 0.012, y - 0.015, z - 0.06), (px + 0.012, y + 0.015, z + 0.03), solid((150, 120, 84)), 0.01)
    return out


def washline(L, kinds, seed):
    """Two T-posts and a sagging line between them along x, with the washing out:
    `kinds` pegged along it in turn. Its pegs go in WASHING."""
    m = Cloud()
    wood = (110, 84, 60)
    y = 0.15
    for px in (0.1, L - 0.1):
        m += box((px - 0.05, y - 0.05, 0), (px + 0.05, y + 0.05, 2.15), solid(wood), 0.02)
        m += box((px - 0.04, y - 0.25, 2.05), (px + 0.04, y + 0.25, 2.12), solid(wood), 0.02)
    sag = lambda xx: 2.08 - 0.16 * math.sin(math.pi * (xx - 0.1) / (L - 0.2))
    xs = np.linspace(0.1, L - 0.1, 24)
    for a, b in zip(xs[:-1], xs[1:]):
        m += beam((a, y, sag(a)), (b, y, sag(b)), 0.008, (196, 186, 160))
    gap = (L - 0.4) / len(kinds)
    for i, k in enumerate(kinds):
        cx = 0.2 + gap * (i + 0.5)
        WASHING.append((cx, y, sag(cx), k, seed + i))
    return m


def shutter(window, swing, col):
    """A window's pair of plank shutters, each leaf hinged at its side of the frame
    and swung `swing` radians from shut (0) toward flat against the wall (pi)."""
    face, (u0, u1), (z0, z1), W, D = window
    if face == "+y":
        at = lambda u, n, z: np.array([u, D + n, z])
    else:
        at = lambda u, n, z: np.array([W + n, u, z])
    out = Cloud()
    hw = (u1 - u0) / 2 + 0.04
    base = np.array(col, float)
    for hinge, side in ((u0 - 0.04, 1.0), (u1 + 0.04, -1.0)):
        du, dn = side * math.cos(swing), math.sin(swing) + 0.002
        h = at(hinge, 0.05, z0 - 0.04)
        along = at(hinge + du, 0.05 + dn, z0 - 0.04) - h
        up = np.array([0, 0, z1 - z0 + 0.08])
        normal = at(-dn * side, du * side, 0) - at(0, 0, 0)

        def planks(P, N, h=h, along=along):
            t = (P - h) @ along / hw
            c = np.tile(base, (len(P), 1)) * (0.82 + 0.28 * hash01(np.floor(t * 4.0)))[:, None]
            c[((P[:, 2] - z0) % 0.6) < 0.08] *= 0.8   # battens
            return c
        for off in (0.0, 0.035):
            out += quad(h + normal * off, along * hw, up, planks, normal=normal if off else -normal)
    return out


def decorate(fn, W, D, openings):
    """Paint windows, doors and signs onto faces. openings: dicts with face ('+x','+y'),
    u=(u0,u1), z=(z0,z1), kind and optional text/color."""
    planes = {"+x": (0, W, 1), "-x": (0, 0, 1), "+y": (1, D, 0), "-y": (1, 0, 0)}
    for o in openings:
        if o["kind"] in ("door", "batwing", "arch", "dark") and o["z"][0] < 0.5:
            DOORS.append((o["face"], (o["u"][0] + o["u"][1]) / 2, W, D))
        if o["kind"] == "win" or (o["kind"] == "dark" and o["z"][0] >= 0.5):
            WINDOWS.append((o["face"], tuple(o["u"]), tuple(o["z"]), W, D))
            GLAZED.append(o["kind"] == "win")   # (an adobe's openings have no glass to break)

    def f(P, N):
        c = fn(P, N)
        for o in openings:
            axis, val, uax = planes[o["face"]]
            sgn = 1 if o["face"][0] == "+" else -1
            on = (N[:, axis] * sgn > 0.5) & (np.abs(P[:, axis] - val) < 0.06)
            u = P[:, uax]
            z = P[:, 2]
            u0, u1 = o["u"]
            z0, z1 = o["z"]
            m = on & (u >= u0) & (u <= u1) & (z >= z0) & (z <= z1)
            if not m.any():
                continue
            k = o["kind"]
            uu, zz = u[m], z[m]
            fr = 0.07
            inner = (uu > u0 + fr) & (uu < u1 - fr) & (zz > z0 + fr) & (zz < z1 - fr)
            frame_c = np.array(o.get("frame", (196, 176, 140)), float)
            cc = np.tile(frame_c, (len(uu), 1))
            if k in ("win", "barred"):
                glass = np.tile([36.0, 40, 50], (len(uu), 1))
                glint = ((uu - u0) - (zz - z0) * 0.6) % 0.9 < 0.08
                glass[glint] = (110, 120, 130)
                mull = (np.abs(uu - (u0 + u1) / 2) < 0.035) | (np.abs(zz - (z0 + z1) / 2) < 0.035)
                glass[mull] = frame_c * 0.8
                if k == "barred":
                    bars = ((uu - u0) % 0.16) < 0.04
                    glass[bars] = (40, 40, 44)
                cc[inner] = glass[inner]
            elif k in ("door", "batwing", "arch", "dark"):
                wood = np.array(o.get("color", (74, 48, 32)), float)
                d = np.tile(wood, (len(uu), 1)) * (0.85 + 0.25 * hash01(np.floor((uu - u0) / 0.14)))[:, None]
                if k == "batwing":
                    d[:] = (20, 14, 12)
                    bw = (zz > z0 + 0.45) & (zz < z0 + 1.55) & (np.abs(uu - (u0 + u1) / 2) > 0.04)
                    d[bw] = (128, 92, 58)
                    slats = bw & (((zz - z0) % 0.14) < 0.04)
                    d[slats] = (96, 66, 40)
                if k == "dark":
                    d[:] = (24, 18, 16)
                cc[inner] = d[inner]
                if k == "arch":
                    r = (u1 - u0) / 2
                    cu = (u0 + u1) / 2
                    top = z1 - r
                    out_arch = (zz > top) & (((uu - cu) ** 2 + (zz - top) ** 2) > r * r)
                    keep = ~out_arch
                    cc = np.where(keep[:, None], np.tile(wood, (len(uu), 1)) * 0.9, c[m])
                    cc[keep & ~inner] = wood * 0.6
            elif k == "sign":
                board = np.array(o.get("color", (60, 44, 34)), float)
                cc = np.tile(board, (len(uu), 1))
                cc[~inner] = frame_c * 0.7
                text = o["text"]
                n = len(text)
                unit = min((u1 - u0 - 0.3) / (4 * n - 1), (z1 - z0 - 0.2) / 5)
                start = (u0 + u1) / 2 - unit * (4 * n - 1) / 2
                top = (z0 + z1) / 2 + unit * 2.5
                gx = np.floor((uu - start) / unit).astype(int)
                gy = np.floor((top - zz) / unit).astype(int)
                li, lx = gx // 4, gx % 4
                ink = np.zeros(len(uu), bool)
                for i, ch in enumerate(text):
                    g = FONT.get(ch, FONT[" "])
                    sel = (li == i) & (lx < 3) & (gy >= 0) & (gy < 5)
                    idx = np.where(sel)[0]
                    for j in idx:
                        if g[gy[j]][lx[j]] == "#":
                            ink[j] = True
                cc[ink] = o.get("ink", (232, 214, 170))
            c[m] = cc
        return c
    return f


# ---------------------------------------------------------------- pieces

def gable_roof(W, D, z, rise, color, along_y=True, overhang=0.25):
    out = Cloud()
    o = overhang
    if along_y:  # ridge runs along Y
        out += quad((-o, -o, z - o * rise / (W / 2)), (W / 2 + o, 0, rise + o * rise / (W / 2)),
                    (0, D + 2 * o, 0), color, BSP)
        out += quad((W / 2, -o, z + rise), (W / 2 + o, 0, -rise - o * rise / (W / 2)),
                    (0, D + 2 * o, 0), color, BSP)
    else:
        out += quad((-o, -o, z - o * rise / (D / 2)), (0, D / 2 + o, rise + o * rise / (D / 2)),
                    (W + 2 * o, 0, 0), color, BSP)
        out += quad((-o, D / 2, z + rise), (0, D / 2 + o, -rise - o * rise / (D / 2)),
                    (W + 2 * o, 0, 0), color, BSP)
    out.N = np.where(out.N[:, 2:3] < 0, -out.N, out.N)
    return out


def gable_ends(W, D, z, rise, fn, along_y=True):
    out = Cloud()
    if along_y:
        for y, n in ((0, -1), (D, 1)):
            t = tri((0, y, z), (W, y, z), (W / 2, y, z + rise), fn, BSP)
            t.N[:] = (0, n, 0)
            out += t
    else:
        for x, n in ((0, -1), (W, 1)):
            t = tri((x, 0, z), (x, D, z), (x, D / 2, z + rise), fn, BSP)
            t.N[:] = (n, 0, 0)
            out += t
    return out


def boardwalk(W, D, depth=1.2, awning=3.0, posts=4, wood=(132, 98, 66), hang=None):
    LANTERNS.append((W / 2 - 1.15, D + depth + 0.12, awning - 0.25))   # by the door, on a hook out front
    if hang:   # a board on chains the other side of the door, out from the awning's edge
        SIGNS.append((W / 2 + 1.3, D + depth + 0.16, awning - 0.3, hang))
    out = Cloud()
    out += box((0, D, 0), (W, D + depth, 0.15), planks(wood, board=0.18, vertical=True, mud=0), BSP)
    for x in np.linspace(0.1, W - 0.22, posts):
        out += box((x, D + depth - 0.16, 0.15), (x + 0.12, D + depth - 0.04, awning),
                   solid((112, 80, 54)), 0.02)
    out += quad((0, D, awning + 0.1), (W, 0, 0), (0, depth + 0.1, -0.35),
                roofing((116, 88, 66), along_y=False, row=0.2), BSP)
    return out


def false_front(W, D, z0, z1, step, fn):
    out = box((0, D - 0.15, z0), (W, D, z1), fn, BSP)
    if step:
        out += box((W * 0.28, D - 0.15, z1), (W * 0.72, D, z1 + step), fn, BSP)
    out += box((-0.05, D - 0.2, z1), (W + 0.05, D + 0.05, z1 + 0.08), solid((96, 70, 48)), 0.03)
    return out


def wheel(center, r, color=(96, 66, 42), axis="y", spokes=12):
    cx, cy, cz = center
    g = np.mgrid[-r:r:0.009, -r:r:0.009].reshape(2, -1).T
    rr = np.hypot(g[:, 0], g[:, 1])
    ang = np.arctan2(g[:, 1], g[:, 0])
    rim = (rr < r) & (rr > r - 0.07)
    hub = rr < 0.09
    sp = (np.abs(((ang + math.pi / spokes) % (2 * math.pi / spokes)) - math.pi / spokes) * rr < 0.025) & (rr < r)
    keep = rim | hub | sp
    g, rim = g[keep], rim[keep]
    if axis == "y":
        P = np.column_stack([cx + g[:, 0], np.full(len(g), cy), cz + g[:, 1]])
        N = np.tile([0, 1.0, 0], (len(g), 1))
    else:
        P = np.column_stack([np.full(len(g), cx), cy + g[:, 0], cz + g[:, 1]])
        N = np.tile([1.0, 0, 0], (len(g), 1))
    C = np.tile(np.array(color, float), (len(g), 1))
    C[rim] = (60, 50, 44)
    return Cloud(P, N, C)


# ---------------------------------------------------------------- buildings

def saloon():
    W, D, Hh = 7 * T, 6 * T, 5.6
    wall = planks((152, 106, 70))
    ops = [
        dict(face="+y", u=(W / 2 - 0.75, W / 2 + 0.75), z=(0.15, 2.5), kind="batwing"),
        dict(face="+y", u=(1.0, 2.6), z=(0.9, 2.3), kind="win"),
        dict(face="+y", u=(W - 2.6, W - 1.0), z=(0.9, 2.3), kind="win"),
        dict(face="+y", u=(0.9, 1.9), z=(3.5, 4.9), kind="win"),
        dict(face="+y", u=(W / 2 - 0.5, W / 2 + 0.5), z=(3.5, 4.9), kind="win"),
        dict(face="+y", u=(W - 1.9, W - 0.9), z=(3.5, 4.9), kind="win"),
        dict(face="+y", u=(0.7, W - 0.7), z=(5.75, 6.85), kind="sign", text="SALOON",
             color=(140, 36, 28)),
        dict(face="+x", u=(1.4, 2.6), z=(1.0, 2.3), kind="win"),
        dict(face="+x", u=(4.6, 5.8), z=(1.0, 2.3), kind="win"),
        dict(face="+x", u=(1.4, 2.6), z=(3.5, 4.8), kind="win"),
        dict(face="+x", u=(4.6, 5.8), z=(3.5, 4.8), kind="win"),
    ]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z",))
    m += gable_roof(W, D, Hh, 1.3, roofing((96, 72, 60)))
    m += gable_ends(W, D, Hh, 1.3, wall)
    m += false_front(W, D, Hh, 7.0, 0.6, fn)
    m += box((0, D, 2.9), (W, D + 0.04, 3.05), solid((90, 64, 44)), 0.03)
    # balcony rail on the upper floor
    m += boardwalk(W, D, awning=3.1, posts=5, hang="WHISKY")
    return m


def store():
    W, D, Hh = 5 * T, 5 * T, 3.8
    wall = planks((150, 140, 122), seed=3)
    ops = [
        dict(face="+y", u=(W / 2 - 0.55, W / 2 + 0.55), z=(0.15, 2.3), kind="door"),
        dict(face="+y", u=(0.6, 2.2), z=(0.7, 2.4), kind="win"),
        dict(face="+y", u=(W - 2.2, W - 0.6), z=(0.7, 2.4), kind="win"),
        dict(face="+y", u=(0.5, W - 0.5), z=(3.95, 4.95), kind="sign", text="STORE",
             color=(58, 70, 56)),
        dict(face="+x", u=(1.2, 2.4), z=(1.0, 2.3), kind="win"),
        dict(face="+x", u=(3.6, 4.8), z=(1.0, 2.3), kind="win"),
    ]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z",))
    m += gable_roof(W, D, Hh, 1.0, roofing((104, 92, 80)))
    m += gable_ends(W, D, Hh, 1.0, wall)
    m += false_front(W, D, Hh, 5.1, 0.0, fn)
    m += boardwalk(W, D, awning=2.8, posts=3, hang="TOBACCO")
    return m


def sheriff():
    W, D, Hh = 5 * T, 5 * T, 3.6
    wall = planks((118, 84, 60), seed=7)
    ops = [
        dict(face="+y", u=(W / 2 - 0.5, W / 2 + 0.5), z=(0.15, 2.3), kind="door", color=(50, 34, 26)),
        dict(face="+y", u=(0.7, 1.9), z=(0.9, 2.2), kind="barred"),
        dict(face="+y", u=(W - 1.9, W - 0.7), z=(0.9, 2.2), kind="barred"),
        dict(face="+y", u=(0.4, W - 0.4), z=(3.8, 4.75), kind="sign", text="SHERIFF",
             color=(40, 34, 30), ink=(214, 180, 90)),
        dict(face="+x", u=(1.5, 2.4), z=(1.2, 2.2), kind="barred"),
        dict(face="+x", u=(3.8, 4.7), z=(1.2, 2.2), kind="barred"),
    ]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z",))
    m += gable_roof(W, D, Hh, 0.9, roofing((86, 70, 62)))
    m += gable_ends(W, D, Hh, 0.9, wall)
    m += false_front(W, D, Hh, 4.9, 0.4, fn)
    m += boardwalk(W, D, awning=2.8, posts=3, hang="WANTED")
    return m


def bank():
    W, D, Hh = 6 * T, 6 * T, 4.8
    wall = bricks((150, 84, 62))
    ops = [
        dict(face="+y", u=(W / 2 - 0.6, W / 2 + 0.6), z=(0.15, 2.6), kind="door", color=(56, 38, 28),
             frame=(206, 192, 164)),
        dict(face="+y", u=(0.8, 2.0), z=(1.0, 2.6), kind="barred", frame=(206, 192, 164)),
        dict(face="+y", u=(W - 2.0, W - 0.8), z=(1.0, 2.6), kind="barred", frame=(206, 192, 164)),
        dict(face="+y", u=(1.2, W - 1.2), z=(3.3, 4.4), kind="sign", text="BANK",
             color=(36, 46, 40), ink=(220, 190, 100)),
        dict(face="+x", u=(1.5, 2.7), z=(1.0, 2.6), kind="barred", frame=(206, 192, 164)),
        dict(face="+x", u=(4.8, 6.0), z=(1.0, 2.6), kind="barred", frame=(206, 192, 164)),
    ]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP)
    m += box((-0.08, -0.08, Hh), (W + 0.08, D + 0.08, Hh + 0.35), solid((200, 182, 150)), 0.03,
             skip=("-z",))
    m += box((0.3, 0.3, Hh + 0.35), (W - 0.3, D - 0.3, Hh + 0.36), solid((96, 82, 70)), BSP)
    m += box((-0.05, -0.05, 0), (W + 0.05, D + 0.05, 0.4), solid((176, 160, 136)), 0.03, skip=("-z", "+z"))
    m += boardwalk(W, D, awning=3.0, posts=4, wood=(120, 110, 96), hang="LOANS")
    return m


def adobe_house(w, h, base, height, seed):
    W, D = w * T, h * T
    wall = adobe(base, seed)
    ops = [
        dict(face="+x", u=(D / 2 - 0.55, D / 2 + 0.55), z=(0, 2.1), kind="arch", color=(84, 54, 36)),
        dict(face="+x", u=(0.6, 1.3), z=(1.2, 1.9), kind="dark"),
        dict(face="+y", u=(1.0, 1.8), z=(1.2, 1.9), kind="dark"),
        dict(face="+y", u=(W - 1.8, W - 1.0), z=(1.2, 1.9), kind="dark"),
    ]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, height), fn, BSP, skip=("-z", "+z"))
    m += box((0, 0, height), (W, D, height + 0.01), adobe(tuple(c * 0.85 for c in base), seed + 1), BSP,
             skip=("-z", "-x", "-y", "+x", "+y"))
    for (a, b) in (((0, 0), (W, 0.2)), ((0, D - 0.2), (W, D)), ((0, 0), (0.2, D)), ((W - 0.2, 0), (W, D))):
        m += box((a[0], a[1], height), (b[0], b[1], height + 0.35), wall, 0.03, skip=("-z",))
    # vigas
    for y in np.arange(0.5, D - 0.3, 0.75):
        m += beam((W - 0.05, y, height - 0.3), (W + 0.32, y, height - 0.32), 0.07, (110, 78, 50))
    for x in np.arange(0.5, W - 0.3, 0.75):
        m += beam((x, D - 0.05, height - 0.3), (x, D + 0.32, height - 0.32), 0.07, (110, 78, 50))
    # chili ristra next to the door
    for i in range(7):
        m += ellipsoid((W + 0.08, D / 2 + 0.85, 1.9 - i * 0.12), (0.05, 0.06, 0.07), (170, 30, 22))
    return m


def church():
    W, D, Hh = 6 * T, 7 * T, 5.0
    white = adobe((224, 210, 184), 11)
    ops = [
        dict(face="+x", u=(4.6, 5.8), z=(0, 2.6), kind="arch", color=(78, 50, 32)),
        dict(face="+x", u=(3.2, 3.7), z=(2.4, 3.8), kind="arch", color=(30, 24, 22)),
        dict(face="+x", u=(7.0, 7.5), z=(2.4, 3.8), kind="arch", color=(30, 24, 22)),
    ]
    fn = decorate(white, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z",))

    def rosette(P, N):
        c = fn(P, N)
        on = (N[:, 1] > 0.5) & (np.abs(P[:, 1] - D) < 0.06)
        d = np.hypot(P[:, 0] - W / 2, P[:, 2] - 3.8)
        c[on & (d < 0.55)] = (90, 60, 40)
        c[on & (d < 0.45)] = (40, 30, 30)
        return c
    m.C = rosette(m.P, m.N)
    # stepped parapet on the back (visible) facade
    m += box((W / 2 - 1.4, D - 0.25, Hh), (W / 2 + 1.4, D, Hh + 0.7), white, BSP)
    m += box((W / 2 - 0.7, D - 0.25, Hh + 0.7), (W / 2 + 0.7, D, Hh + 1.2), white, BSP)
    m += box((W / 2 - 0.05, D - 0.18, Hh + 1.2), (W / 2 + 0.05, D - 0.08, Hh + 1.9), solid((80, 60, 44)), 0.02)
    m += box((W / 2 - 0.3, D - 0.18, Hh + 1.6), (W / 2 + 0.3, D - 0.08, Hh + 1.7), solid((80, 60, 44)), 0.02)
    # bell tower on the street corner
    x0, x1, y0, y1 = W - 2.6, W, 0, 2.6
    m += box((x0, y0, 0), (x1, y1, 6.6), white, BSP)
    for px_, py_ in ((x0, y0), (x1 - 0.35, y0), (x0, y1 - 0.35), (x1 - 0.35, y1 - 0.35)):
        m += box((px_, py_, 6.6), (px_ + 0.35, py_ + 0.35, 8.3), white, 0.03)
    m += box((x0 - 0.1, y0 - 0.1, 8.3), (x1 + 0.1, y1 + 0.1, 8.75), white, BSP)
    m += ellipsoid(((x0 + x1) / 2, (y0 + y1) / 2, 7.35), (0.48, 0.48, 0.55), (150, 112, 52), zmin=6.95)
    m += beam(((x0 + x1) / 2, (y0 + y1) / 2, 7.9), ((x0 + x1) / 2, (y0 + y1) / 2, 8.3), 0.04, (60, 50, 40))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    m += box((cx - 0.06, cy - 0.06, 8.75), (cx + 0.06, cy + 0.06, 9.9), solid((70, 52, 38)), 0.02)
    m += box((cx - 0.06, cy - 0.38, 9.4), (cx + 0.06, cy + 0.38, 9.52), solid((70, 52, 38)), 0.02)
    return m


def stable():
    W, D, Hh = 6 * T, 5 * T, 3.4
    wall = planks((130, 64, 46), board=0.24, vertical=True, seed=13)

    def doors(P, N):
        c = wall(P, N)
        on = (N[:, 1] > 0.5) & (np.abs(P[:, 1] - D) < 0.06)
        u, z = P[:, 0], P[:, 2]
        d = on & (u > 2.5) & (u < 5.0) & (z < 2.9)
        c[d] = c[d] * 0.85
        tu = (u - 2.5) / 2.5
        tz = z / 2.9
        brace = d & ((np.abs(tu - tz) < 0.04) | (np.abs(tu - (1 - tz)) < 0.04) |
                     (u < 2.6) | (u > 4.9) | (z > 2.8) | (np.abs(u - 3.75) < 0.05))
        c[brace] = (206, 194, 170)
        loft = (N[:, 0] > 0.5) & (np.abs(P[:, 0] - W) < 0.06) & (np.abs(P[:, 1] - D / 2) < 0.55) & \
               (z > 3.6) & (z < 4.5)
        c[loft] = (30, 22, 18)
        return c
    DOORS.append(("+y", 3.75, W, D))
    m = box((0, 0, 0), (W, D, Hh), doors, BSP, skip=("-z",))
    m += gable_roof(W, D, Hh, 1.8, roofing((98, 76, 62), along_y=False), along_y=False)
    m += gable_ends(W, D, Hh, 1.8, doors, along_y=False)
    return m


def water_tower():
    S = 2 * T
    m = Cloud()
    wood = (118, 86, 58)
    legs = [(0.3, 0.3), (S - 0.3, 0.3), (0.3, S - 0.3), (S - 0.3, S - 0.3)]
    for x, y in legs:
        m += box((x - 0.1, y - 0.1, 0), (x + 0.1, y + 0.1, 3.5), solid(wood), 0.025)
    for (a, b) in ((0, 1), (0, 2), (1, 3), (2, 3)):
        (xa, ya), (xb, yb) = legs[a], legs[b]
        m += beam((xa, ya, 0.4), (xb, yb, 3.2), 0.04, (100, 72, 48))
        m += beam((xb, yb, 0.4), (xa, ya, 3.2), 0.04, (100, 72, 48))
    m += box((0, 0, 3.5), (S, S, 3.65), planks(wood, board=0.2, vertical=True, mud=0), 0.03)

    def staves(P, N):
        ang = np.arctan2(P[:, 1] - S / 2, P[:, 0] - S / 2)
        st = np.floor(ang / (2 * math.pi) * 40)
        c = np.tile([122.0, 90, 62], (len(P), 1)) * (0.85 + 0.25 * hash01(st))[:, None]
        hoop = (np.abs(P[:, 2] - 3.95) < 0.05) | (np.abs(P[:, 2] - 4.6) < 0.05) | (np.abs(P[:, 2] - 5.2) < 0.05)
        c[hoop] = (56, 50, 48)
        return c
    m += frustum((S / 2, S / 2, 3.65), (S / 2, S / 2, 5.35), 1.15, 1.12, staves, sp=0.035)
    m += frustum((S / 2, S / 2, 5.35), (S / 2, S / 2, 6.1), 1.3, 0.05, roofing((92, 74, 62)), sp=0.035)
    m += beam((S / 2 + 1.0, S / 2 + 0.3, 3.9), (S / 2 + 1.6, S / 2 + 0.5, 3.1), 0.06, (60, 56, 52))
    return m


def gallows():
    S = 3 * T
    m = Cloud()
    m += box((0, 0, 0), (S, S, 1.5), planks((120, 92, 64), board=0.2, seed=5), BSP)

    def trap(P, N):
        c = planks((120, 92, 64), board=0.2, vertical=True, mud=0)(P, N)
        t = (np.abs(P[:, 0] - S / 2) < 0.5) & (np.abs(P[:, 1] - S / 2) < 0.5)
        c[t] = c[t] * 0.7
        return c
    m += box((0, 0, 1.5), (S, S, 1.52), trap, BSP, skip=("-z", "-x", "-y", "+x", "+y"))
    for i in range(4):
        m += box((S + i * 0.3, 0.9, 0), (S + (i + 1) * 0.3, 2.0, 1.5 - i * 0.37), solid((112, 84, 58)), 0.03)
    m += box((0.4, S / 2 - 0.1, 1.5), (0.6, S / 2 + 0.1, 4.6), solid((96, 70, 48)), 0.025)
    m += box((0.4, S / 2 - 0.1, 4.4), (S / 2 + 0.2, S / 2 + 0.1, 4.6), solid((96, 70, 48)), 0.025)
    m += beam((0.5, S / 2, 3.8), (1.1, S / 2, 4.4), 0.05, (96, 70, 48))
    m += beam((S / 2, S / 2, 4.4), (S / 2, S / 2, 3.35), 0.018, (170, 150, 110))
    m += frustum((S / 2, S / 2, 3.35), (S / 2, S / 2, 3.05), 0.11, 0.11, (170, 150, 110), caps=False)
    return m


# ---------------------------------------------------------------- props

def crate():
    s = 1.0

    def fn(P, N):
        c = planks((168, 128, 82), board=0.2, mud=0)(P, N)
        u, fid = face_uv(P, N)
        horiz = np.abs(N[:, 2]) > 0.5
        a = np.where(horiz, P[:, 0], u)
        b = np.where(horiz, P[:, 1], P[:, 2])
        e = (a < 0.08) | (a > s - 0.08) | (b < 0.08) | (b > 0.95 - 0.08)
        c[e] = (110, 80, 52)
        return c
    return box((0, 0, 0), (s, s, 0.95), fn)


def barrel():
    r = 0.34
    c0 = (r, r)

    def fn(P, N):
        ang = np.arctan2(P[:, 1] - r, P[:, 0] - r)
        st = np.floor(ang / (2 * math.pi) * 16)
        c = np.tile([138.0, 96, 62], (len(P), 1)) * (0.85 + 0.25 * hash01(st))[:, None]
        hoop = (np.abs(P[:, 2] - 0.12) < 0.035) | (np.abs(P[:, 2] - 0.82) < 0.035) | \
               (np.abs(P[:, 2] - 0.5) < 0.03)
        c[hoop] = (60, 54, 50)
        return c
    m = frustum((*c0, 0), (*c0, 0.47), 0.29, 0.34, fn)
    m += frustum((*c0, 0.47), (*c0, 0.94), 0.34, 0.29, fn)
    return m


def wagon():
    L, Wd = 3.0, 1.5
    m = Cloud()
    wood = planks((128, 96, 64), board=0.18, mud=0.0)
    m += box((0.25, 0.2, 0.6), (L - 0.25, Wd - 0.2, 0.78), wood)
    m += box((0.25, 0.2, 0.78), (L - 0.25, 0.28, 1.15), wood)
    m += box((0.25, Wd - 0.28, 0.78), (L - 0.25, Wd - 0.2, 1.15), wood)
    m += box((0.25, 0.28, 0.78), (0.33, Wd - 0.28, 1.15), wood)
    m += box((L - 0.33, 0.28, 0.78), (L - 0.25, Wd - 0.28, 1.15), wood)
    m += box((0.6, 0.4, 0.78), (1.4, 1.0, 1.1), solid((176, 150, 104)))     # sacks
    m += box((1.5, 0.35, 0.78), (2.3, 1.1, 1.3), crate_fn((160, 120, 80)))
    for x in (0.75, L - 0.75):
        for y in (0.12, Wd - 0.12):
            m += wheel((x, y, 0.52), 0.52)
    m += beam((L - 0.2, Wd / 2, 0.55), (L + 0.9, Wd / 2, 0.25), 0.05, (110, 82, 56))
    return m


def crate_fn(col):
    return planks(col, board=0.2, mud=0)


def trough():
    L, Wd, H = 1.9, 0.7, 0.6
    wood = planks((116, 88, 60), board=0.15, mud=0)
    m = box((0, 0, 0), (L, Wd, H), wood, skip=("+z",))
    m += box((0.08, 0.08, H - 0.12), (L - 0.08, Wd - 0.08, H - 0.11), solid((84, 100, 96)),
             skip=("-z", "-x", "+x", "-y", "+y"))
    for x in (0.0, L - 0.06):
        m += box((x, 0, H - 0.04), (x + 0.06, Wd, H), wood, 0.02)
    m += box((0, 0, H - 0.04), (L, 0.06, H), wood, 0.02)
    m += box((0, Wd - 0.06, H - 0.04), (L, Wd, H), wood, 0.02)
    return m


def coffin():
    L, Wd = 2.0, 0.7
    wood = planks((80, 54, 38), board=0.12, vertical=True, mud=0)
    m = box((0, 0.05, 0), (L, Wd - 0.05, 0.42), wood)
    m += box((0.05, 0.1, 0.42), (L - 0.05, Wd - 0.1, 0.46), solid((98, 68, 46)))
    m += box((0.35, Wd / 2 - 0.03, 0.46), (0.95, Wd / 2 + 0.03, 0.47), solid((150, 130, 96)))
    m += box((0.55, Wd / 2 - 0.2, 0.46), (0.61, Wd / 2 + 0.2, 0.47), solid((150, 130, 96)))
    return m


def olla():
    """A big clay water jar (an olla) by an adobe door, a painted band round it."""
    def clay(P, N):
        c = np.tile([176.0, 98, 62], (len(P), 1))
        band = np.abs(P[:, 2] - 0.4) < 0.04
        c[band] = (92, 48, 34)
        dots = (np.abs(P[:, 2] - 0.3) < 0.025) & ((np.arctan2(P[:, 1] - 0.25, P[:, 0] - 0.25) * 4) % 1.0 < 0.4)
        c[dots] = (230, 200, 160)
        return c
    m = ellipsoid((0.25, 0.25, 0.28), (0.22, 0.22, 0.26), clay)
    m += frustum((0.25, 0.25, 0.48), (0.25, 0.25, 0.6), 0.1, 0.12, clay, caps=False)
    return m


def olla_broken():
    """Shards round a dark wet patch where the jar stood."""
    rng = np.random.default_rng(7)
    m = Cloud()
    m += box((0.08, 0.08, 0.0), (0.42, 0.42, 0.005), solid((112, 84, 64)), skip=("-z", "-x", "-y", "+x", "+y"))
    m += frustum((0.25, 0.25, 0.0), (0.25, 0.25, 0.12), 0.2, 0.19, solid((170, 94, 60)), caps=False)  # the bottom
    for _ in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.18, 0.4)
        c = np.array([0.25 + r * math.cos(a), 0.25 + r * math.sin(a), 0.03])
        d = np.array([math.cos(a + 1.4), math.sin(a + 1.4), rng.uniform(0.2, 0.8)]) * rng.uniform(0.05, 0.1)
        m += beam(c - d, c + d, 0.03, (176, 98, 62) if rng.random() < 0.7 else (92, 48, 34))
    return m


def chair(over=False):
    """A plain wooden porch chair; knocked over, it lies on its back."""
    wood = (120, 84, 54)
    m = Cloud()
    m += box((0.04, 0.04, 0.42), (0.46, 0.46, 0.47), planks(wood, board=0.12, mud=0), 0.02)
    for x in (0.06, 0.4):
        for y in (0.06, 0.4):
            m += box((x, y, 0), (x + 0.05, y + 0.05, 0.42), solid(wood), 0.02)
    for x in (0.06, 0.4):
        m += box((x, 0.04, 0.47), (x + 0.05, 0.09, 1.0), solid(wood), 0.02)
    for z in (0.7, 0.9):
        m += box((0.06, 0.04, z), (0.45, 0.08, z + 0.06), solid((134, 96, 62)), 0.02)
    if over:
        m.transform(rot_x(math.pi / 2))   # tipped back onto its backrest, legs out
        m.translate((0, 1.0, 0.0))
    return m


def table(bottles=True):
    """A small saloon table, a bottle or two and a couple of glasses on it."""
    wood = (110, 76, 50)
    m = Cloud()
    m += box((0, 0, 0.72), (0.7, 0.7, 0.77), planks(wood, board=0.14, mud=0), 0.02)
    m += box((0.3, 0.3, 0), (0.4, 0.4, 0.72), solid((90, 62, 42)), 0.02)
    m += box((0.18, 0.18, 0), (0.52, 0.52, 0.04), solid((90, 62, 42)), 0.02)
    if bottles:
        for (x, y, col, h) in ((0.22, 0.3, (60, 96, 50), 0.28), (0.45, 0.22, (110, 66, 30), 0.3),
                               (0.4, 0.5, (60, 96, 50), 0.26)):
            m += frustum((x, y, 0.77), (x, y, 0.77 + h * 0.65), 0.04, 0.04, solid(col))
            m += frustum((x, y, 0.77 + h * 0.65), (x, y, 0.77 + h), 0.03, 0.014, solid(col))
        for (x, y) in ((0.55, 0.45), (0.18, 0.52)):
            m += frustum((x, y, 0.77), (x, y, 0.84), 0.025, 0.03, solid((196, 204, 200)), caps=False)
    else:
        rng = np.random.default_rng(3)
        for _ in range(10):   # broken glass and spilt whisky on the top
            x, y = rng.uniform(0.1, 0.6, 2)
            m += box((x, y, 0.77), (x + 0.03, y + 0.02, 0.785), solid((170, 190, 180)), 0.01)
        m += box((0.2, 0.25, 0.77), (0.5, 0.5, 0.775), solid((92, 64, 40)), 0.02,
                 skip=("-z", "-x", "-y", "+x", "+y"))
    return m


def upturned(faces):
    """A long cantina table thrown over on its side for a barricade: the top stood
    up as a shield towards `faces` ("n", "s", "e" or "w"), the legs sticking out
    behind it. A table is 1.2 tiles long; the legs reach back 0.6."""
    L, W, top = 1.2 * T, 0.6 * T, 0.06
    wood = planks((116, 80, 52), board=0.14, mud=0)
    m = box((0, 0, 0.02), (L, top, W), wood, 0.02)                               # the top, on edge
    m += box((0.04, top, 0.04), (L - 0.04, top + 0.06, 0.1), solid((92, 64, 42)), 0.02)   # apron
    m += box((0.04, top, W - 0.1), (L - 0.04, top + 0.06, W - 0.04), solid((92, 64, 42)), 0.02)
    for x in (0.08, L - 0.16):
        for z in (0.08, W - 0.16):
            m += box((x, top, z), (x + 0.08, W, z + 0.08), solid((96, 66, 44)), 0.02)   # legs, out back
    # turned to face its way: as built it faces -y (north on the grid)
    D = W
    R = {"n": np.eye(3), "s": np.diag([1.0, -1.0, 1.0]),
         "w": np.array([[0, 1.0, 0], [1.0, 0, 0], [0, 0, 1.0]]),
         "e": np.array([[0, -1.0, 0], [1.0, 0, 0], [0, 0, 1.0]])}[faces]
    m.transform(R)
    lo = m.P.min(0)
    m.translate((-lo[0], -lo[1], 0))
    return m


def crate_stack():
    """The fort's stores: two crates side by side, a third on top, a sack against them."""
    m = crate()
    m += crate().translate((1.0, 0, 0))
    top = crate()
    top.transform(rot_z(0.12), pivot=(0.5, 0.5, 0))
    m += top.translate((0.45, 0.02, 0.95))
    m += ellipsoid((1.55, 0.95, 0.25), (0.32, 0.18, 0.26), solid((176, 150, 104)))
    return m


def keg():
    """A powder keg: small and squat, its staves stained near black, bright copper
    hoops (no iron to strike a spark) and a white band painted round its middle so
    nobody mistakes it for a water barrel. A wooden bung in the top."""
    r = 0.27
    c0 = (r + 0.02, r + 0.02)

    def fn(P, N):
        ang = np.arctan2(P[:, 1] - c0[1], P[:, 0] - c0[0])
        st = np.floor(ang / (2 * math.pi) * 14)
        c = np.tile([62.0, 44, 32], (len(P), 1)) * (0.85 + 0.3 * hash01(st))[:, None]
        z = P[:, 2]
        band = np.abs(z - 0.34) < 0.07
        c[band] = (226, 220, 200)
        hoop = (np.abs(z - 0.08) < 0.03) | (np.abs(z - 0.6) < 0.03)
        c[hoop] = (196, 112, 60)
        return c
    m = frustum((*c0, 0), (*c0, 0.34), 0.23, 0.27, fn)
    m += frustum((*c0, 0.34), (*c0, 0.68), 0.27, 0.23, fn)
    m += frustum((c0[0] + 0.08, c0[1], 0.68), (c0[0] + 0.08, c0[1], 0.72), 0.04, 0.04, solid((150, 110, 70)))
    return m


def dyn_crate():
    """A crate of dynamite, the lid prised half off: the red sticks packed in rows
    inside, in sawdust, a red band painted round the boards."""
    L, Wd, H = 1.0, 0.7, 0.5
    wood = planks((176, 140, 92), board=0.12, mud=0)

    def fn(P, N):
        c = wood(P, N)
        band = (np.abs(P[:, 2] - 0.28) < 0.07) & (np.abs(N[:, 2]) < 0.5)
        c[band] = (176, 40, 30)
        return c
    m = box((0, 0, 0), (L, Wd, H), fn, skip=("+z",))
    m += box((0.04, 0.04, H - 0.08), (L - 0.04, Wd - 0.04, H - 0.07), solid((196, 168, 112)),
             skip=("-z", "-x", "+x", "-y", "+y"))                                     # sawdust
    for i in range(7):   # the sticks, lying lengthwise in a row
        y = 0.1 + i * 0.08
        m += beam((0.08, y, H - 0.05), (L - 0.12, y, H - 0.05), 0.032, (184, 36, 28))
    lid = box((0, 0, 0), (L, Wd * 0.55, 0.04), planks((168, 132, 86), board=0.12, mud=0))
    lid.transform(rot_x(-0.35))
    m += lid.translate((0.0, Wd * 0.48, H + 0.02))
    return m


def coop():
    """A little plank hen house on short legs, a ramp up to its hatch."""
    wood = planks((150, 118, 82), board=0.14, mud=0)
    m = Cloud()
    for x in (0.08, 0.9):
        for y in (0.08, 0.62):
            m += box((x, y, 0), (x + 0.06, y + 0.06, 0.25), solid((96, 70, 48)), 0.02)
    m += box((0.05, 0.05, 0.25), (1.0, 0.72, 0.85), wood)
    m += quad((0.0, 0.0, 0.92), (1.05, 0, 0), (0, 0.77, -0.14), roofing((104, 82, 62), along_y=False, row=0.16))
    m += box((0.55, 0.719, 0.3), (0.78, 0.722, 0.55), solid((26, 20, 18)))          # the hatch
    m += quad((0.56, 0.72, 0.3), (0.2, 0, 0), (0, 0.42, -0.3), planks((128, 96, 64), board=0.06, mud=0))  # ramp
    for i in range(3):   # straw at the hatch
        m += beam((0.6 + i * 0.05, 0.75, 0.31), (0.65 + i * 0.05, 0.8, 0.3), 0.008, (214, 190, 120))
    return m


def coop_broken():
    """Shot through: holes in the boards, the hatch hanging off, feathers about."""
    rng = np.random.default_rng(13)
    m = damaged(coop(), 53)
    for _ in range(14):
        x, y = rng.uniform(-0.2, 1.3), rng.uniform(-0.1, 1.2)
        m += ellipsoid((x, y, 0.01), (0.025, 0.012, 0.006), (236, 230, 220) if rng.random() < 0.7 else (150, 92, 50))
    return m


def hen(color, pose="stand", phase=0.0):
    """A hen (facing +x), about knee high: plump body, tail up, red comb. Poses:
    stand / peck (head down) / flap (wings up, legs pumping), phase 0..1."""
    m = Cloud()
    body, dark = np.array(color, float), np.array(color, float) * 0.72
    up = 0.04 if pose == "flap" else 0.0
    m += ellipsoid((0.0, 0, 0.24 + up), (0.15, 0.1, 0.11), tuple(body))
    m += ellipsoid((-0.13, 0, 0.32 + up), (0.06, 0.05, 0.1), tuple(dark))          # tail
    head = np.array([0.2, 0, 0.1]) if pose == "peck" else np.array([0.12, 0, 0.4 + up])
    m += ellipsoid((0.08, 0, 0.3 + up) if pose != "peck" else (0.14, 0, 0.2), (0.05, 0.045, 0.07), tuple(body))
    m += ellipsoid(tuple(head), (0.05, 0.045, 0.05), tuple(body))
    m += ellipsoid(tuple(head + [0.0, 0, 0.05]), (0.035, 0.012, 0.025), (200, 30, 26))   # comb
    m += ellipsoid(tuple(head + [0.035, 0, -0.04]), (0.015, 0.01, 0.02), (200, 30, 26))  # wattle
    m += beam(head + [0.04, 0, 0], head + [0.085, 0, -0.01], 0.012, (230, 180, 60))   # beak
    if pose == "flap":
        lift = 0.1 + 0.08 * math.sin(phase * 2 * math.pi)
        for s in (1, -1):
            m += ellipsoid((-0.02, s * 0.15, 0.32 + lift), (0.1, 0.07, 0.02), tuple(dark))
    else:
        for s in (1, -1):
            m += ellipsoid((-0.02, s * 0.09, 0.25), (0.1, 0.02, 0.06), tuple(dark))
    stride = 0.06 * math.sin(phase * 2 * math.pi) if pose in ("flap", "walk") else 0.0
    for s, k in ((1, 1), (-1, -1)):
        m += beam((0.0, s * 0.04, 0.16), (stride * k, s * 0.04, 0.0), 0.012, (220, 170, 60))
    return m


def hen_crate():
    """A slatted crate of hens for market, heads poking out."""
    m = Cloud()
    wood = (176, 140, 96)
    m += box((0, 0, 0), (0.7, 0.5, 0.04), solid(wood), 0.02)
    for y in (0.0, 0.23, 0.46):   # an open-slatted lid
        m += box((0, y, 0.42), (0.7, y + 0.04, 0.46), solid(wood), 0.015)
    for x in np.linspace(0.0, 0.66, 7):
        for y in (0.0, 0.46):
            m += box((x, y, 0.04), (x + 0.035, y + 0.04, 0.42), solid(wood), 0.015)
    for y in np.linspace(0.0, 0.46, 5):
        for x in (0.0, 0.66):
            m += box((x, y, 0.04), (x + 0.04, y + 0.035, 0.42), solid(wood), 0.015)
    for (x, y, c) in ((0.2, 0.25, (236, 230, 218)), (0.48, 0.2, (150, 86, 44)), (0.42, 0.36, (236, 230, 218))):
        h = hen(c)
        h.P = h.P * 0.8 + [x, y, 0.04]
        m += h
    return m


# Small things gunfire breaks that are no cover at all (bullets pass through):
# each a list of looks, whole first; each hit moves it one look on.
FRAGILE = {
    "olla": lambda: [olla(), olla_broken()],
    "coop": lambda: [coop(), coop_broken()],
    "hencrate": lambda: [hen_crate(), wrecked(hen_crate(), "hencrate", 47)],
    "chair": lambda: [chair(), chair(over=True), wrecked(chair(), "chair", 41)],
    "table": lambda: [table(), table(bottles=False), wrecked(table(bottles=False), "table", 43)],
}


# ---------------------------------------------------------------- broken props

# Props that shooting wears down: each gets a damaged and a wrecked look.
BREAKABLE = ("crate", "barrel", "coffin", "trough", "wagon", "crate_stack", "wagon_over", "nest_x", "nest_y",
             "upturned_n", "upturned_s", "upturned_e", "upturned_w", "keg", "dyn_crate")
RAW_WOOD = np.array([214, 178, 128], float)   # fresh splinters


def damaged(m, seed):
    """Shot up: holes torn through the boards, raw wood round them, a few splinters
    sticking out."""
    rng = np.random.default_rng(seed)
    P = m.P
    lo, hi = P.min(0), P.max(0)
    size = hi - lo
    keep = np.ones(len(P), bool)
    raw = np.zeros(len(P), bool)
    out = Cloud()
    for _ in range(int(4 + 3 * max(1.0, size[0] * size[1]))):
        c = P[rng.integers(len(P))]
        r = rng.uniform(0.05, 0.11) * max(1.0, min(size[0], size[1]) * 1.2)
        d = np.linalg.norm(P - c, axis=1)
        keep &= d > r
        raw |= (d > r) & (d < r * 1.7)
        for _ in range(2):   # splinters
            a = rng.uniform(0, 2 * math.pi)
            tip = c + np.array([math.cos(a), math.sin(a), rng.uniform(0.0, 0.5)]) * rng.uniform(0.08, 0.16)
            out += beam(c, tip, 0.012, tuple(RAW_WOOD))
    C = m.C.copy()
    C[raw] = C[raw] * 0.4 + RAW_WOOD * 0.6
    out += Cloud(P[keep], m.N[keep], C[keep], m.S[keep])
    return out


def wrecked(m, kind, seed):
    """Shot to pieces: a low heap of broken boards where it stood, in its own wood."""
    rng = np.random.default_rng(seed)
    lo, hi = m.P.min(0), m.P.max(0)
    col = np.array({"trough": (116, 88, 60)}.get(kind, np.median(m.C, axis=0)), float)   # (not the water)
    out = Cloud()
    area = (hi[0] - lo[0]) * (hi[1] - lo[1])
    for _ in range(int(6 + 9 * area)):
        a = rng.uniform(0, math.pi)
        L = rng.uniform(0.25, 0.7)
        c = np.array([rng.uniform(lo[0], hi[0]), rng.uniform(lo[1], hi[1]), rng.uniform(0.02, 0.16)])
        d = np.array([math.cos(a), math.sin(a), rng.uniform(-0.25, 0.25)]) * L / 2
        shade = tuple(np.clip(col * rng.uniform(0.75, 1.15), 0, 255))
        out += beam(c - d, c + d, rng.uniform(0.025, 0.04), shade)
        if rng.random() < 0.4:
            out += beam(c + d * 0.6, c + d * 0.6 + np.array([0, 0, 0.06]), 0.012, tuple(RAW_WOOD))
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    if kind == "barrel":
        for k in range(2):   # the hoops, fallen loose
            ring = Cloud()
            for i in range(24):
                t0, t1 = i / 24 * 2 * math.pi, (i + 1) / 24 * 2 * math.pi
                p0 = (cx + 0.3 * math.cos(t0) + k * 0.12, cy + 0.26 * math.sin(t0), 0.03 + k * 0.03)
                p1 = (cx + 0.3 * math.cos(t1) + k * 0.12, cy + 0.26 * math.sin(t1), 0.03 + k * 0.03)
                ring += beam(p0, p1, 0.015, (60, 54, 50))
            out += ring
    elif kind == "wagon":
        out += wheel((lo[0] + 0.7, hi[1] + 0.05, 0.5), 0.52)             # one still standing
        flat = wheel((0, 0, 0), 0.52)
        flat.transform(np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float))   # one lying flat
        flat.translate((hi[0] - 0.8, cy, 0.06))
        out += flat
    return out


def prop_states(kind):
    """The three looks of a breakable prop: whole, shot up, wrecked."""
    m = BUILDINGS[kind][0]()
    seed = sum(map(ord, kind))
    return [m, damaged(m, seed), wrecked(m, kind, seed + 1)]


def hitch():
    m = Cloud()
    wood = (110, 80, 54)
    for x in (0.1, 1.9):
        m += box((x - 0.06, 0.06, 0), (x + 0.06, 0.18, 1.0), solid(wood), 0.02)
    m += beam((0.0, 0.12, 0.95), (2.0, 0.12, 0.95), 0.05, wood)
    return m


def cactus():
    def fn(P, N):
        ang = np.arctan2(N[:, 1], N[:, 0])
        rib = (np.floor(ang / (2 * math.pi) * 14) % 2) == 0
        c = np.tile([92.0, 122, 70], (len(P), 1))
        c[rib] = (74, 100, 58)
        return c
    c = 0.375
    m = frustum((c, c, 0), (c, c, 2.3), 0.19, 0.16, fn)
    m += ellipsoid((c, c, 2.3), (0.16, 0.16, 0.12), fn)
    m += frustum((c, c, 1.0), (c, c + 0.45, 1.05), 0.1, 0.1, fn)
    m += frustum((c, c + 0.45, 1.0), (c, c + 0.45, 1.8), 0.11, 0.09, fn)
    m += ellipsoid((c, c + 0.45, 1.8), (0.09, 0.09, 0.07), fn)
    m += frustum((c, c, 1.3), (c + 0.35, c - 0.1, 1.33), 0.09, 0.09, fn)
    m += frustum((c + 0.35, c - 0.1, 1.3), (c + 0.35, c - 0.1, 1.85), 0.09, 0.08, fn)
    m += ellipsoid((c + 0.35, c - 0.1, 1.85), (0.08, 0.08, 0.06), fn)
    return m


def cross():
    wood = solid((142, 126, 106))
    m = box((0.22, 0.08, 0), (0.32, 0.18, 1.15), wood, 0.02)
    m += box((0.02, 0.08, 0.75), (0.52, 0.18, 0.85), wood, 0.02)
    return m


def mound():
    """A fresh grave: a long heap of turned earth, darker than the dust round it."""
    def earth(P, N):
        c = np.tile(np.array([92.0, 64, 42]), (len(P), 1))
        clod = hash01(np.floor(P[:, 0] * 14), np.floor(P[:, 1] * 14)) > 0.8
        c[clod] = (70, 48, 32)
        return c
    m = ellipsoid((0.5, 0.28, 0.0), (0.5, 0.26, 0.16), earth)
    for x, y in ((0.12, 0.08), (0.86, 0.5), (0.95, 0.12)):
        m += ellipsoid((x, y, 0.02), (0.06, 0.05, 0.04), solid((84, 58, 38)))
    return m


def open_grave(coffin_beside=True):
    """A grave being dug: the spoil heaped up at the back, the coffin waiting before it, and the dark hole in front where it can be seen into; or (coffin_beside
    False) the coffin down in the hole, its lid showing, for the earth to go back over."""
    def earth(P, N):
        c = np.tile(np.array([96.0, 68, 44]), (len(P), 1))
        clod = hash01(np.floor(P[:, 0] * 14), np.floor(P[:, 1] * 14)) > 0.78
        c[clod] = (72, 50, 34)
        return c
    m = ellipsoid((1.1, 0.24, 0.0), (0.95, 0.22, 0.3), earth)                        # the spoil
    m += box((0.18, 1.15, 0.0), (2.02, 1.95, 0.012), solid((84, 58, 38)), skip=("-z",))  # the rim
    m += box((0.3, 1.27, 0.012), (1.9, 1.83, 0.016), solid((30, 21, 16)), skip=("-z",))  # the hole
    if coffin_beside:   # the same coffin as stands about San Miguel's streets, a cross on its lid
        c = coffin()
        c.translate((0.1, 0.4, 0))
        m += c
    else:
        m += box((0.42, 1.36, 0.016), (1.78, 1.74, 0.02), solid((120, 90, 60)), skip=("-z",))  # the lid, below
    return m


def tumbleweed(frame, seed=4):
    rng = np.random.default_rng(seed)
    m = Cloud()
    for _ in range(150):
        a = rng.normal(size=3)
        a /= np.linalg.norm(a)
        b = rng.normal(size=3)
        b /= np.linalg.norm(b)
        r1, r2 = rng.uniform(0.15, 0.36), rng.uniform(0.15, 0.36)
        col = (172, 142, 92) if rng.random() < 0.6 else (138, 108, 68)
        m += beam(a * r1, b * r2, 0.012, col, sp=0.02)
    m.transform(rot_x(frame * math.pi / 8))
    m.translate((0.4, 0.4, 0.38))
    return m


def frontier(w, h, wall_h, front_h, wall, sign, sign_col, ink=(232, 214, 170), floors=1,
             roof_col=(100, 84, 72), step=0.0, extras=None, hang=None):
    """A generic false-front building facing +y: plank or brick walls, windows per
    floor, a sign on the false front, boardwalk and awning."""
    W, D = w * T, h * T
    ops = [dict(face="+y", u=(W / 2 - 0.55, W / 2 + 0.55), z=(0.15, 2.3), kind="door")]
    n = max(1, int(W // 2.2))
    for f in range(floors):
        z0 = 0.9 + f * 2.6
        for i in range(n):
            cx = (i + 0.5) * W / n
            if f == 0 and abs(cx - W / 2) < 1.0:
                continue
            ops.append(dict(face="+y", u=(cx - 0.55, cx + 0.55), z=(z0, z0 + 1.3), kind="win"))
        for i in range(max(1, int(D // 2.4))):
            cy = (i + 0.5) * D / max(1, int(D // 2.4))
            ops.append(dict(face="+x", u=(cy - 0.5, cy + 0.5), z=(z0 + 0.1, z0 + 1.2), kind="win"))
    ops.append(dict(face="+y", u=(0.4, W - 0.4), z=(wall_h + 0.15, front_h - 0.15), kind="sign",
                    text=sign, color=sign_col, ink=ink))
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, wall_h), fn, BSP, skip=("-z",))
    m += gable_roof(W, D, wall_h, 1.0, roofing(roof_col))
    m += gable_ends(W, D, wall_h, 1.0, wall)
    m += false_front(W, D, wall_h, front_h, step, fn)
    m += boardwalk(W, D, awning=2.8, posts=max(2, int(W // 2.4) + 1), hang=hang)
    if extras:
        m += extras(W, D)
    return m


def _barber_pole(W, D):
    def stripes(P, N):
        c = np.tile([226.0, 220, 210], (len(P), 1))
        red = ((P[:, 2] * 6 + np.arctan2(P[:, 1] - (D + 0.1), P[:, 0] - (W * 0.3)) / math.pi) % 1.0) < 0.5
        c[red] = (170, 36, 30)
        return c
    return frustum((W * 0.3, D + 0.1, 1.2), (W * 0.3, D + 0.1, 2.4), 0.08, 0.08, stripes)


def _gun_sign(W, D):
    """The gunsmith's trade sign: a rifle twice the size of life, carved and painted,
    mounted on the false front just above the awning."""
    import chars   # the rifle itself is the one the characters carry
    butt = np.array([W / 2 - 1.1, D + 0.06, 3.36])
    sign = chars.weapon_model("rifle", butt, (1.0, 0, 0.0))
    sign.P = (sign.P - butt) * 2.0 + butt
    return sign


def cantina():
    """An adobe cantina with its name painted on the wall."""
    W, D = 6 * T, 5 * T
    m = adobe_house(6, 5, (214, 176, 132), 3.4, 41)
    ops = [dict(face="+y", u=(1.0, W - 1.0), z=(2.2, 3.0), kind="sign", text="CANTINA",
                color=(176, 60, 40), ink=(236, 216, 160), frame=(176, 60, 40))]
    fn = decorate(adobe((214, 176, 132), 41), W, D, ops)
    m += box((0, D, 0), (W, D + 0.02, 3.4), fn, BSP, skip=("-z", "+z", "-x", "+x", "-y"))
    return m


# ---------------------------------------------------------------- Cruz Verde

# A revolutionary garrison's walled town: a thick adobe perimeter with gates and
# breaches, a chapel with a bell wall, barracks, the general's house; a village of
# jacales outside, and a great cemetery beside it.
FORT_ADOBE = (206, 172, 128)


def fort_wall(L, along_x=True, seed=51, height=3.4):
    """A length of the fort's wall, `L` tiles along x (or y) and a tile thick:
    crenellated, with drain spouts, too tall to see over."""
    W, D = (L * T, T) if along_x else (T, L * T)
    wall = adobe(FORT_ADOBE, seed)
    m = box((0, 0, 0), (W, D, height), wall, BSP, skip=("-z",))
    run = W if along_x else D
    for i in range(int(run / 0.9)):
        a = i * 0.9 + 0.2
        lo, hi = (a, 0.0), (a + 0.5, D)
        if not along_x:
            lo, hi = (0.0, a), (W, a + 0.5)
        m += box((lo[0], lo[1], height), (hi[0], hi[1], height + 0.45), wall, 0.03, skip=("-z",))
    for i in range(1, int(run / 2.5)):   # canales: wooden spouts out through the parapet
        a = i * 2.5
        if along_x:
            m += beam((a, D - 0.1, height - 0.2), (a, D + 0.35, height - 0.25), 0.06, (110, 78, 50))
        else:
            m += beam((W - 0.1, a, height - 0.2), (W + 0.35, a, height - 0.25), 0.06, (110, 78, 50))
    return m


def fort_gate(along_x=True):
    """A gateway: two thick piers and the beam across them, the great doors swung
    wide back against the wall."""
    W, D = (5 * T, T) if along_x else (T, 5 * T)
    wall = adobe(FORT_ADOBE, 53)
    m = Cloud()
    pier = 1.0 * T
    span = 5 * T
    for a in (0.0, span - pier):
        lo, hi = ((a, 0, 0), (a + pier, D, 4.2)) if along_x else ((0, a, 0), (W, a + pier, 4.2))
        m += box(lo, hi, wall, BSP, skip=("-z",))
    wood = planks((110, 76, 50), board=0.22, vertical=True, seed=5)
    if along_x:
        m += box((pier, 0.1, 3.4), (span - pier, D - 0.1, 3.75), solid((100, 70, 46)), 0.03)
        for x0, x1 in ((pier, pier + 0.12), (span - pier - 0.12, span - pier)):   # the doors, folded back
            m += box((x0, D, 0.0), (x1, D + 1.4, 3.2), wood, 0.03)
    else:
        m += box((0.1, pier, 3.4), (W - 0.1, span - pier, 3.75), solid((100, 70, 46)), 0.03)
        for y0, y1 in ((pier, pier + 0.12), (span - pier - 0.12, span - pier)):
            m += box((W, y0, 0.0), (W + 1.4, y1, 3.2), wood, 0.03)
    return m


def bastion():
    """A squat corner tower, taller than the walls, a dark loophole on each face."""
    W = 2 * T
    wall = adobe(tuple(c * 0.96 for c in FORT_ADOBE), 57)
    ops = [dict(face="+x", u=(W / 2 - 0.12, W / 2 + 0.12), z=(2.6, 3.3), kind="dark"),
           dict(face="+y", u=(W / 2 - 0.12, W / 2 + 0.12), z=(2.6, 3.3), kind="dark")]
    fn = decorate(wall, W, W, ops)
    m = box((0, 0, 0), (W, W, 4.6), fn, BSP, skip=("-z",))
    for i in range(4):
        a = i * 0.65 + 0.12
        for lo, hi in (((a, 0), (a + 0.4, 0.3)), ((a, W - 0.3), (a + 0.4, W)), ((0, a), (0.3, a + 0.4)),
                       ((W - 0.3, a), (W, a + 0.4))):
            m += box((lo[0], lo[1], 4.6), (hi[0], hi[1], 5.05), wall, 0.03, skip=("-z",))
    return m


def rubble():
    """Where the wall's been knocked through: a heap of broken adobe blocks."""
    rng = np.random.default_rng(61)
    m = Cloud()
    wall = adobe(FORT_ADOBE, 63)
    for i in range(34):
        x, y = rng.uniform(0.0, 1.7), rng.uniform(0.0, 0.95)
        z = rng.uniform(0.0, 0.75) * max(0.0, 1.0 - abs(x - 0.9) / 1.0) * max(0.0, 1.0 - abs(y - 0.5) / 0.7)
        w, d, h = rng.uniform(0.25, 0.5), rng.uniform(0.2, 0.4), rng.uniform(0.15, 0.3)
        m += box((x, y, z), (x + w, y + d, z + h), wall, 0.03)
    return m


def chapel():
    """A whitewashed chapel, its bell wall (espadaña) over the door with two bells."""
    W, D, Hh = 5 * T, 6 * T, 4.2
    white = adobe((226, 214, 190), 71)
    ops = [dict(face="+y", u=(W / 2 - 0.6, W / 2 + 0.6), z=(0, 2.6), kind="arch", color=(84, 54, 36)),
           dict(face="+x", u=(2.0, 2.5), z=(2.2, 3.3), kind="arch", color=(30, 24, 22)),
           dict(face="+x", u=(5.0, 5.5), z=(2.2, 3.3), kind="arch", color=(30, 24, 22))]
    fn = decorate(white, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z",))
    # the espadana: a wall rising over the front, two openings with their bells
    y0, y1 = D - 0.35, D
    def bellwall(P, N):
        c = white(P, N)
        for cx, cz in ((W / 2 - 0.7, Hh + 1.2), (W / 2 + 0.7, Hh + 1.2)):
            hole = (np.abs(P[:, 0] - cx) < 0.32) & (P[:, 2] > cz - 0.45) & \
                   ((P[:, 2] < cz + 0.1) | (np.hypot(P[:, 0] - cx, P[:, 2] - cz - 0.1) < 0.32))
            c[hole] = (40, 32, 28)
        return c
    m += box((W / 2 - 1.5, y0, Hh), (W / 2 + 1.5, y1, Hh + 1.9), bellwall, BSP)
    m += box((W / 2 - 0.4, y0, Hh + 1.9), (W / 2 + 0.4, y1, Hh + 2.4), white, BSP)
    for cx in (W / 2 - 0.7, W / 2 + 0.7):
        m += ellipsoid((cx, (y0 + y1) / 2, Hh + 1.05), (0.22, 0.22, 0.26), (150, 112, 52), zmin=Hh + 0.85)
    m += box((W / 2 - 0.04, y1 - 0.25, Hh + 2.4), (W / 2 + 0.04, y1 - 0.12, Hh + 3.0), solid((70, 52, 38)), 0.02)
    m += box((W / 2 - 0.22, y1 - 0.25, Hh + 2.75), (W / 2 + 0.22, y1 - 0.12, Hh + 2.84), solid((70, 52, 38)), 0.02)
    return m


def barracks():
    """The garrison's quarters: a long low adobe with a portal of rough posts along
    the front, CUARTEL painted over the doors."""
    W, D, Hh = 10 * T, 4 * T, 3.2
    wall = adobe((196, 160, 118), 73)
    ops = [dict(face="+y", u=(x - 0.5, x + 0.5), z=(0, 2.2), kind="arch", color=(70, 46, 32)) for x in (2.5, 6.25, 10.0)]
    ops += [dict(face="+y", u=(x - 0.35, x + 0.35), z=(1.2, 1.9), kind="dark") for x in (4.4, 8.1)]

    ops += [dict(face="+x", u=(D / 2 - 0.35, D / 2 + 0.35), z=(1.2, 1.9), kind="dark")]
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z", "+z"))
    m += box((0, 0, Hh), (W, D, Hh + 0.01), adobe((170, 136, 100), 74), BSP, skip=("-z", "-x", "-y", "+x", "+y"))
    for (a, b) in (((0, 0), (W, 0.2)), ((0, D - 0.2), (W, D)), ((0, 0), (0.2, D)), ((W - 0.2, 0), (W, D))):
        m += box((a[0], a[1], Hh), (b[0], b[1], Hh + 0.35), wall, 0.03, skip=("-z",))
    # a raised parapet over the middle, CUARTEL painted on it above the portal's shade
    front = decorate(wall, W, D, [dict(face="+y", u=(W / 2 - 3.0, W / 2 + 3.0), z=(Hh + 0.05, Hh + 0.85), kind="sign",
                                       text="CUARTEL", color=(190, 158, 116), ink=(120, 40, 30), frame=(190, 158, 116))])
    m += box((W / 2 - 3.2, D - 0.25, Hh), (W / 2 + 3.2, D, Hh + 0.95), front, BSP, skip=("-z",))
    # the portal: posts, a beam, a shade of poles and brush
    for x in np.linspace(0.2, W - 0.35, 6):
        m += box((x, D + 1.0, 0), (x + 0.15, D + 1.15, 2.7), solid((112, 80, 54)), 0.02)
    m += box((0, D + 1.0, 2.7), (W, D + 1.15, 2.85), solid((100, 72, 48)), 0.03)
    m += quad((0, D, 2.95), (W, 0, 0), (0, 1.25, -0.15), roofing((150, 120, 80), along_y=False, row=0.12), BSP)
    return m


def casa_grande():
    """The general's house: two storeys of ochre adobe, a wooden balcony over the
    great door, barred windows."""
    W, D, Hh = 8 * T, 6 * T, 6.0
    wall = adobe((200, 150, 98), 77)
    ops = [dict(face="+y", u=(W / 2 - 0.8, W / 2 + 0.8), z=(0, 2.8), kind="arch", color=(78, 44, 28))]
    for z0 in (1.0, 3.9):
        for x in (1.6, W - 1.6) + ((W / 2,) if z0 > 2 else ()):
            ops.append(dict(face="+y", u=(x - 0.45, x + 0.45), z=(z0, z0 + 1.3), kind="barred"))
        for y in (2.0, D - 2.0):
            ops.append(dict(face="+x", u=(y - 0.45, y + 0.45), z=(z0, z0 + 1.3), kind="barred"))
    fn = decorate(wall, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z", "+z"))
    m += box((0, 0, Hh), (W, D, Hh + 0.01), adobe((176, 128, 84), 78), BSP, skip=("-z", "-x", "-y", "+x", "+y"))
    for (a, b) in (((0, 0), (W, 0.25)), ((0, D - 0.25), (W, D)), ((0, 0), (0.25, D)), ((W - 0.25, 0), (W, D))):
        m += box((a[0], a[1], Hh), (b[0], b[1], Hh + 0.5), wall, 0.03, skip=("-z",))
    # the balcony
    x0, x1 = W / 2 - 1.6, W / 2 + 1.6
    m += box((x0, D, 3.6), (x1, D + 1.0, 3.75), solid((104, 70, 44)), 0.03)
    for x in np.linspace(x0, x1, 12):
        m += beam((x, D + 0.95, 3.75), (x, D + 0.95, 4.6), 0.02, (80, 54, 34))
    m += box((x0, D + 0.9, 4.6), (x1, D + 1.0, 4.68), solid((90, 60, 38)), 0.02)
    for x in (x0 + 0.2, x1 - 0.2):
        m += beam((x, D, 3.2), (x, D + 0.9, 3.6), 0.05, (90, 60, 38))   # corbels
    return m


def jacal(seed=81):
    """A villager's hut: daubed wattle walls under a steep thatch, a blanket for a door."""
    W, D, Hh = 3 * T, 3 * T, 2.3
    rng = np.random.default_rng(seed)
    mud = adobe((176, 140, 102), seed)
    ops = [dict(face="+y", u=(W / 2 - 0.45, W / 2 + 0.45), z=(0, 1.8), kind="door", color=(150, 50, 40)),
           dict(face="+x", u=(D / 2 - 0.3, D / 2 + 0.3), z=(1.0, 1.5), kind="dark")]
    fn = decorate(mud, W, D, ops)
    m = box((0, 0, 0), (W, D, Hh), fn, BSP, skip=("-z", "+z"))
    def thatch(P, N):
        c = np.tile([176.0, 150, 98], (len(P), 1)) * (0.8 + 0.3 * hash01(np.floor(P[:, 0] * 20 + P[:, 1] * 3)))[:, None]
        return c
    o = 0.35
    apex = (W / 2, D / 2, Hh + 1.6)
    for a, b in (((-o, -o), (W + o, -o)), ((W + o, -o), (W + o, D + o)), ((W + o, D + o), (-o, D + o)),
                 ((-o, D + o), (-o, -o))):
        m += tri((a[0], a[1], Hh - 0.15), (b[0], b[1], Hh - 0.15), apex, thatch)
    if rng.random() < 0.6:   # a bench by the door
        m += box((W - 1.1, D + 0.1, 0.0), (W - 0.2, D + 0.4, 0.45), solid((120, 90, 60)), 0.02)
    return m


def well():
    """The plaza well: a stone ring, a timber frame, a rope and bucket."""
    stone = lambda P, N: np.tile([150.0, 140, 124], (len(P), 1)) * (0.8 + 0.3 * hash01(np.floor(P[:, 2] * 8),
                                  np.floor(np.arctan2(P[:, 1] - 0.75, P[:, 0] - 0.75) * 4)))[:, None]
    m = frustum((0.75, 0.75, 0), (0.75, 0.75, 0.8), 0.7, 0.66, stone)
    m += ellipsoid((0.75, 0.75, 0.79), (0.55, 0.55, 0.02), (20, 24, 28))
    for x in (0.12, 1.38):
        m += box((x - 0.06, 0.69, 0.6), (x + 0.06, 0.81, 2.1), solid((104, 74, 50)), 0.02)
    m += beam((0.06, 0.75, 2.0), (1.44, 0.75, 2.0), 0.06, (96, 68, 46))
    m += beam((0.75, 0.75, 2.0), (0.75, 0.75, 1.35), 0.01, (190, 176, 140))
    m += frustum((0.75, 0.75, 1.1), (0.75, 0.75, 1.35), 0.12, 0.14, solid((110, 80, 54)))
    return m


def sandbags(along_x=True):
    """A breastwork of sandbags, three courses high: good low cover."""
    m = Cloud()
    L = 2.0 * T
    for row in range(3):
        n = 5 - (row == 2)
        for i in range(n):
            a = (i + 0.5 + 0.5 * (row % 2)) * (L / 5.2)
            c = (a, 0.36, 0.13 + row * 0.22) if along_x else (0.36, a, 0.13 + row * 0.22)
            r = (0.27, 0.2, 0.12) if along_x else (0.2, 0.27, 0.12)
            m += ellipsoid(c, r, solid((172 - row * 6, 150 - row * 6, 104)))
    return m


def cannon():
    """An old bronze field gun on its wooden carriage: a relic, but good cover."""
    m = Cloud()
    wood = solid((100, 70, 46))
    m += box((0.3, 0.32, 0.45), (2.2, 0.88, 0.62), wood, 0.03)
    m += box((2.0, 0.42, 0.0), (2.4, 0.78, 0.5), wood, 0.03)   # the trail on the ground
    m += wheel((0.9, 0.2, 0.62), 0.6, axis="y")
    m += wheel((0.9, 1.0, 0.62), 0.6, axis="y")
    m += frustum((0.0, 0.6, 0.85), (1.9, 0.6, 0.78), 0.12, 0.19, solid((150, 110, 50)))
    m += ellipsoid((1.95, 0.6, 0.78), (0.14, 0.19, 0.19), (150, 110, 50))
    return m


def flagpole():
    """The garrison's flag, the tricolour, on a tall pole."""
    m = box((0.1, 0.1, 0), (0.2, 0.2, 7.0), solid((90, 70, 52)), 0.02)
    for i, col in enumerate(((40, 120, 70), (232, 226, 210), (190, 40, 36))):
        m += quad((0.2 + i * 0.5, 0.15, 6.0), (0.5, 0.05 * (i + 1), 0.0), (0, 0, 0.9), col, normal=(0, 1, 0))
    return m


def pole():
    """A rough post driven into the plaza by the well, for tying a man to: grey,
    split old wood, and a few turns of rope round it at his wrists' height."""
    wood = lambda P, N: np.tile([112.0, 92, 70], (len(P), 1)) * (0.78 + 0.3 * hash01(np.floor(P[:, 2] * 14), np.floor(P[:, 0] * 40)))[:, None]
    m = frustum((0.15, 0.15, 0), (0.15, 0.15, 2.2), 0.09, 0.075, wood)
    for z in (0.95, 1.02, 1.09):
        m += frustum((0.15, 0.15, z), (0.15, 0.15, z + 0.04), 0.1, 0.1, (176, 156, 112), caps=False)
    return m


def headstone(seed=0):
    """A stone at a grave's head, worn and leaning a little: low cover."""
    rng = np.random.default_rng(91 + seed)
    stone = lambda P, N: np.tile([150.0, 144, 132], (len(P), 1)) * (0.8 + 0.25 * hash01(np.floor(P[:, 2] * 10), seed))[:, None]
    m = box((0.05, 0.05, 0), (0.55, 0.22, 0.55), stone, 0.02)
    m += ellipsoid((0.3, 0.135, 0.55), (0.25, 0.085, 0.14), stone, zmin=0.55)
    m.transform(rot_x(rng.uniform(-0.12, 0.12)), pivot=(0.3, 0.13, 0))
    return m


def stone_circle():
    """The cemetery's heart: a ring of flat paving stones round bare ground, the
    crosses all about it."""
    rng = np.random.default_rng(97)
    m = Cloud()
    c = 3.0 * T
    for k in range(64):
        a = k / 64 * 2 * math.pi + rng.uniform(-0.02, 0.02)
        r = 3.3 + rng.uniform(-0.1, 0.1)
        x, y = c + r * math.cos(a), c + r * math.sin(a)
        m += box((x - 0.18, y - 0.18, 0.0), (x + 0.18, y + 0.18, 0.05), solid((168 - k % 3 * 8, 160 - k % 3 * 8, 146)), 0.03)
    return m


def agave(seed=0):
    """A spiky rosette of agave leaves."""
    rng = np.random.default_rng(101 + seed)
    m = Cloud()
    for i in range(14):
        a = i / 14 * 2 * math.pi + rng.uniform(-0.2, 0.2)
        L = rng.uniform(0.45, 0.7)
        up = rng.uniform(0.4, 1.0)
        m += beam((0.3, 0.3, 0.05), (0.3 + L * math.cos(a) * 0.8, 0.3 + L * math.sin(a) * 0.8, 0.05 + L * up), 0.035,
                  (96, 124, 104) if i % 2 else (84, 112, 94))
    return m


# ---------------------------------------------------------------- the train

# A freight held up on the line by the revolution: a 4-4-0 on its side where they
# tore the rails up under her, the tender off the track behind, the cars standing
# with their doors open and the cargo going out of them. Cars are built along y,
# the way the line runs; the long ones are baked in chunks (CHUNKED, below).
IRON = (66, 76, 82)          # the boiler's Russia iron
BRASS = (196, 156, 64)
LOCO_RED = (142, 46, 34)
SOOT = (40, 38, 38)
STEEL = (88, 84, 80)


def _no_ground(m):
    """Drop whatever's sunk below the dirt (a wreck lies half dug in)."""
    keep = m.P[:, 2] >= 0.0
    return Cloud(m.P[keep], m.N[keep], m.C[keep], m.S[keep])


def _iron_wheel(c, r, axis="x"):
    """A cast-iron car wheel: solid but for a few spokes, a bright tread."""
    w = wheel(c, r, STEEL, axis=axis, spokes=10)
    w += wheel(c, r * 0.55, (70, 66, 62), axis=axis, spokes=20)
    return w


def _trucks(W, D, ends=(1.15, None), r=0.42):
    """The underframe of a car `W` x `D` metres: sills, couplers and a two-axle truck
    under each end."""
    m = Cloud()
    m += box((0.1, 0.0, 0.85), (W - 0.1, D, 1.1), solid((52, 46, 42)), BSP)
    for y in (-0.25, D):
        m += box((W / 2 - 0.12, y, 0.8), (W / 2 + 0.12, y + 0.25, 1.0), solid(SOOT), 0.03)   # couplers
    for yc in (ends[0], D - ends[0] if ends[1] is None else ends[1]):
        for x in (W / 2 - 0.85, W / 2 + 0.7):
            m += box((x, yc - 1.05, 0.3), (x + 0.15, yc + 1.05, 0.62), solid((48, 44, 42)), 0.03)   # side frames
        for dy in (-0.72, 0.72):
            for x in (W / 2 - 0.72, W / 2 + 0.72):
                m += _iron_wheel((x, yc + dy, r), r)
    return m


def boxcar(col=(134, 58, 40), seed=3):
    """A wooden boxcar, its sliding doors run open on both sides and cargo crates
    stacked inside: rifles for the revolution."""
    W, D = 2.4 * T, 6 * T
    z0, z1 = 1.15, 3.35
    m = _trucks(W, D)
    DOORS.extend([("-x", D / 2, W, D), ("+x", D / 2, W, D)])   # (the way in, up off the dirt, for whoever's unloading)
    wood = planks(col, board=0.16, vertical=True, seed=seed, mud=0.0)
    dw = 1.7
    d0, d1, zd = D / 2 - dw / 2, D / 2 + dw / 2, z0 + 2.0
    for x0, x1 in ((0.0, 0.08), (W - 0.08, W)):
        m += box((x0, 0, z0), (x1, d0, z1), wood, BSP)
        m += box((x0, d1, z0), (x1, D, z1), wood, BSP)
        m += box((x0, d0, zd), (x1, d1, z1), wood, BSP)
    for y0, y1 in ((0.0, 0.08), (D - 0.08, D)):
        m += box((0, y0, z0), (W, y1, z1), wood, BSP)
    trim = solid(tuple(c * 0.62 for c in col))
    for x0, x1 in ((-0.04, 0.0), (W, W + 0.04)):   # corner posts and the sill's edge
        for y in (0.0, D - 0.12):
            m += box((x0, y, z0), (x1, y + 0.12, z1), trim, 0.02)
        m += box((x0, 0, z0), (x1, D, z0 + 0.1), trim, 0.02)
    m += box((0.08, 0.08, z0 - 0.04), (W - 0.08, D - 0.08, z0), solid((66, 52, 40)), BSP, skip=("-z",))
    m += box((-0.1, -0.1, z1), (W + 0.1, D + 0.1, z1 + 0.08), solid((74, 66, 62)), BSP)       # roof
    m += box((W / 2 - 0.25, 0, z1 + 0.08), (W / 2 + 0.25, D, z1 + 0.12), planks((112, 88, 62), mud=0), 0.03)
    m += wheel((W / 2, -0.12, z1 - 0.1), 0.24, SOOT, axis="y", spokes=4)   # the brake wheel
    leaf = planks(tuple(c * 0.92 for c in col), board=0.16, vertical=True, seed=seed + 1, mud=0.0)
    m += box((W + 0.04, d1, z0 - 0.04), (W + 0.11, d1 + dw, zd + 0.06), leaf, BSP)    # doors run back
    m += box((-0.11, d0 - dw, z0 - 0.04), (-0.04, d0, zd + 0.06), leaf, BSP)
    for x in (W + 0.12, -0.12):
        m += beam((x, d0 - dw, zd + 0.1), (x, d1 + dw, zd + 0.1), 0.025, SOOT)
    # inside, in the light from the door: cases of rifles and ammunition, piled high
    dark = 0.55
    for i, (x0, y0, h) in enumerate(((0.3, d0 + 0.1, 1.3), (1.5, d0 - 0.2, 0.9), (0.4, d0 + 0.85, 0.85),
                                     (1.6, d0 + 0.75, 1.5), (0.9, d0 - 0.9, 1.6), (1.2, d1 + 0.1, 1.2))):
        c = tuple(v * dark for v in ((176, 140, 96) if i % 2 else (150, 118, 80)))
        m += box((x0, y0, z0), (x0 + 1.15, y0 + 0.6, z0 + h), planks(c, board=0.2, mud=0), BSP)
    return m


def boxcar_burnt():
    """The guards' car, where they made their stand: burnt out to the floor, the
    charred ribs standing, still smoking."""
    W, D = 2.4 * T, 6 * T
    z0 = 1.15
    rng = np.random.default_rng(61)
    m = _trucks(W, D)
    char = lambda P, N: np.tile([46.0, 38, 34], (len(P), 1)) * (0.7 + 0.5 * hash01(np.floor(P[:, 0] * 9), np.floor(P[:, 1] * 9)))[:, None]
    m += box((0.0, 0.0, z0 - 0.06), (W, D, z0), char, BSP)
    for side in (0.0, W - 0.1):
        for i, y in enumerate(np.linspace(0.05, D - 0.15, 9)):
            h = rng.uniform(0.4, 2.2) if i not in (0, 8) else 2.2
            m += box((side, y, z0), (side + 0.1, y + 0.1, z0 + h), char, 0.02)
        for y in np.linspace(0.3, D - 0.6, 5):   # what's left of the boards, low down
            m += box((side + 0.02, y, z0), (side + 0.08, y + rng.uniform(0.4, 0.9), z0 + rng.uniform(0.2, 0.7)), char, 0.03)
    for y in (0.0, D - 0.1):
        m += box((0, y, z0), (W, y + 0.1, z0 + 1.1), char, 0.03)
        m += box((0.1, y, z0 + 1.1), (W * 0.45, y + 0.1, z0 + 2.2), char, 0.03)
    # the roof's iron sheets, fallen in across the floor, and ash
    for i in range(4):
        y = 0.6 + i * 1.7
        m += quad((0.2, y, z0 + 0.05 + i % 2 * 0.25), (W - 0.4, 0, 0.0), (0.1, 1.2, 0.2), solid((90, 76, 66)), BSP)
    ash = lambda P, N: np.tile([92.0, 88, 84], (len(P), 1)) * (0.75 + 0.35 * hash01(np.floor(P[:, 0] * 14), np.floor(P[:, 1] * 14)))[:, None]
    m += ellipsoid((W / 2, D * 0.35, z0), (0.9, 1.1, 0.12), ash, zmin=z0)
    m += ellipsoid((W / 2 + 0.3, D * 0.75, z0), (0.7, 0.8, 0.1), ash, zmin=z0)
    return m


def flatcar():
    """A flatcar: cases lashed down under a canvas, the canvas half thrown back where
    they've started on it."""
    W, D = 2.4 * T, 4.5 * T
    z0 = 1.15
    m = _trucks(W, D, ends=(1.05, None))
    m += box((0, 0, z0 - 0.12), (W, D, z0), planks((116, 90, 64), board=0.18, mud=0), BSP)
    for i, (y0, n) in enumerate(((0.3, 3), (2.6, 2))):
        for k in range(n):
            for j in range(2):
                x0 = 0.25 + j * 1.3
                m += box((x0, y0 + k * 0.7, z0), (x0 + 1.15, y0 + k * 0.7 + 0.55, z0 + 0.42), planks((172, 138, 94), board=0.2, mud=0), BSP)
                if i == 0:
                    m += box((x0 + 0.1, y0 + k * 0.7, z0 + 0.42), (x0 + 1.05, y0 + k * 0.7 + 0.5, z0 + 0.8), planks((160, 128, 86), board=0.2, mud=0), BSP)
    canvas = lambda P, N: np.tile([178.0, 162, 124], (len(P), 1)) * (0.88 + 0.16 * hash01(np.floor(P[:, 0] * 6), np.floor(P[:, 1] * 6)))[:, None]
    m += box((0.15, 0.2, z0 + 0.8), (W - 0.15, 2.5, z0 + 0.86), canvas, BSP)                  # over the first lot
    m += box((0.15, 0.2, z0 + 0.1), (0.21, 2.5, z0 + 0.86), canvas, BSP)
    m += box((W - 0.21, 0.2, z0 + 0.1), (W - 0.15, 2.5, z0 + 0.86), canvas, BSP)
    m += ellipsoid((W / 2, 4.6, z0 + 0.1), (1.3, 0.45, 0.18), canvas, zmin=z0)                  # thrown back
    for y in (0.6, 1.4, 2.2):
        m += beam((0.1, y, z0 + 0.1), (0.1, y, z0 + 0.88), 0.02, (150, 130, 90))
        m += beam((0.1, y, z0 + 0.88), (W - 0.1, y, z0 + 0.88), 0.02, (150, 130, 90))
    return m


def locomotive():
    """The engine: an American 4-4-0, red wheels and cab, a brass dome and a
    diamond stack, built upright along y, her pilot at +y."""
    L, W = 9.5, 2.6
    cx = W / 2
    m = Cloud()
    m += box((cx - 0.45, 0.4, 0.75), (cx + 0.45, L - 0.7, 1.1), solid(SOOT), BSP)
    boiler = lambda P, N: np.tile(np.array(IRON, float), (len(P), 1)) * (0.92 + 0.12 * hash01(np.floor(P[:, 1] * 3)))[:, None]
    m += frustum((cx, 2.4, 2.15), (cx, 7.9, 2.15), 0.72, 0.72, boiler)
    for y in (3.4, 4.9, 6.4, 7.8):
        m += frustum((cx, y, 2.15), (cx, y + 0.07, 2.15), 0.745, 0.745, BRASS, caps=False)
    m += frustum((cx, 7.9, 2.15), (cx, 8.9, 2.15), 0.78, 0.78, SOOT)
    m += box((cx - 0.6, 7.9, 1.2), (cx + 0.6, 8.9, 1.6), solid(SOOT), BSP)            # the saddle
    m += frustum((cx, 8.4, 2.85), (cx, 8.4, 3.5), 0.17, 0.22, SOOT)                   # the diamond stack
    m += frustum((cx, 8.4, 3.5), (cx, 8.4, 3.95), 0.22, 0.62, SOOT)
    m += frustum((cx, 8.4, 3.95), (cx, 8.4, 4.3), 0.62, 0.3, SOOT)
    m += box((cx - 0.3, 8.75, 2.95), (cx + 0.3, 9.25, 3.5), solid(SOOT), 0.03)         # the oil headlamp
    m += box((cx - 0.32, 8.73, 3.5), (cx + 0.32, 9.27, 3.56), solid(BRASS), 0.03)
    m += ellipsoid((cx, 9.27, 3.22), (0.2, 0.03, 0.2), (230, 214, 150))
    m += frustum((cx, 5.6, 2.8), (cx, 5.6, 3.3), 0.34, 0.3, BRASS)                      # steam dome
    m += ellipsoid((cx, 5.6, 3.3), (0.3, 0.3, 0.12), BRASS)
    m += frustum((cx, 4.2, 2.8), (cx, 4.2, 3.15), 0.28, 0.25, boiler)                   # sand dome
    m += ellipsoid((cx, 4.2, 3.15), (0.25, 0.25, 0.1), boiler)
    m += frustum((cx, 6.9, 2.85), (cx, 6.9, 3.1), 0.14, 0.2, BRASS)                     # bell
    for x0, x1 in ((-0.12, 0.35), (W - 0.35, W + 0.12)):                                 # running boards
        m += box((x0, 2.4, 1.55), (x1, 8.0, 1.62), planks((100, 76, 54), mud=0), 0.03)
    # the cab: red-brown boards, dark windows, a black roof
    cab = decorate(planks((126, 58, 38), board=0.12, vertical=True, mud=0), W, 2.4,
                   [dict(face="+x", u=(0.5, 1.4), z=(2.4, 3.1), kind="dark"), dict(face="+y", u=(0.3, 0.8), z=(2.4, 3.1), kind="dark")])
    m += box((-0.05, 0.1, 1.3), (W + 0.05, 2.4, 3.5), cab, BSP)
    m += box((-0.25, 0.0, 3.5), (W + 0.25, 2.6, 3.62), solid(SOOT), BSP)
    # the drivers, coupled by their side rods; a four-wheel truck under the front
    for x in (0.05, W - 0.05):
        for y in (1.6, 3.5):
            m += wheel((x, y, 0.82), 0.82, LOCO_RED, axis="x", spokes=14)
            m += box((x - 0.04, y - 0.12, 0.7), (x + 0.04, y + 0.12, 0.94), solid((176, 172, 160)), 0.02)   # counterweight crank
        m += beam((x + (0.08 if x > 1 else -0.08), 1.6, 0.62), (x + (0.08 if x > 1 else -0.08), 3.5, 0.62), 0.05, (176, 172, 160))
        for y in (6.6, 7.6):
            m += wheel((x + (-0.25 if x > 1 else 0.25), y, 0.42), 0.42, LOCO_RED, axis="x", spokes=10)
        m += frustum((x, 6.5, 1.15), (x, 7.7, 1.15), 0.28, 0.28, SOOT)                  # cylinders
        m += beam((x + (0.1 if x > 1 else -0.1), 6.5, 1.15), (x + (0.1 if x > 1 else -0.1), 3.5, 0.95), 0.045, (176, 172, 160))
    # the pilot: the cowcatcher's bars, fanning down to the rail
    for i in range(7):
        x = 0.25 + i * (W - 0.5) / 6
        m += beam((x, L - 0.75, 1.05), (cx + (x - cx) * 0.55, L, 0.12), 0.035, LOCO_RED)
    m += box((0.1, L - 0.85, 0.95), (W - 0.1, L - 0.7, 1.15), solid(LOCO_RED), 0.03)
    return m


def loco_wreck():
    """The engine on her side where she went off the torn-up rails: rolled over to
    the west, her wheels in the air towards the fight, a furrow of dirt along her
    boiler. She stops anything, and no one sees over her."""
    n = len(WINDOWS)
    m = locomotive()
    del WINDOWS[n:], GLAZED[n:]   # (her cab windows are only paint: no shutters to them)
    m.transform(rot_y(-math.pi / 2))            # her top goes over to the west
    m.translate((4.3, 0.0, 0.05))
    dirt = lambda P, N: np.tile([160.0, 120, 82], (len(P), 1)) * (0.85 + 0.25 * hash01(np.floor(P[:, 1] * 4), np.floor(P[:, 0] * 4)))[:, None]
    for y, r in ((2.6, 0.9), (4.6, 1.0), (6.6, 0.9)):
        m += ellipsoid((0.1, y, 0.0), (0.5, r * 1.3, 0.25), dirt, zmin=0.0)
    return _no_ground(m)


def tender():
    """The tender, dragged off the rails by the engine going over: leaning, one
    truck in the dirt, coal spilled."""
    W, D = 2.6, 5.0
    m = _trucks(W, D, ends=(1.1, None), r=0.42)
    m += box((0, 0, 1.15), (W, D, 2.6), solid(tuple(np.array(IRON) * 0.8)), BSP)
    m += box((W, 0.6, 1.75), (W + 0.02, D - 0.6, 1.85), solid(BRASS), 0.02)
    for x0, x1 in ((-0.03, 0.0), (W, W + 0.03)):
        m += box((x0, 0, 2.5), (x1, D, 2.6), solid(BRASS), 0.02)
    coal = lambda P, N: np.tile([30.0, 30, 34], (len(P), 1)) * (0.7 + 0.6 * hash01(np.floor(P[:, 0] * 12), np.floor(P[:, 1] * 12), np.floor(P[:, 2] * 12)))[:, None]
    m += ellipsoid((W / 2, 3.4, 2.6), (1.1, 1.4, 0.45), coal, zmin=2.6)
    m.transform(rot_y(-0.14), pivot=(0, 0, 0))   # leaning over after the engine
    m.translate((0.45, 0.0, -0.12))
    return _no_ground(m)


def coal_heap():
    """Coal spilled off the tender when she went over."""
    coal = lambda P, N: np.tile([32.0, 32, 36], (len(P), 1)) * (0.7 + 0.6 * hash01(np.floor(P[:, 0] * 12), np.floor(P[:, 1] * 12), np.floor(P[:, 2] * 12)))[:, None]
    m = ellipsoid((0.75, 0.6, 0.0), (0.7, 0.55, 0.28), coal, zmin=0.0)
    m += ellipsoid((1.1, 0.9, 0.0), (0.4, 0.35, 0.15), coal, zmin=0.0)
    return m


def wheelset():
    """A pair of wheels on their axle, torn off a truck and lying in the dirt."""
    m = Cloud()
    for y in (0.15, 1.6):
        w = _iron_wheel((0, 0, 0), 0.42, axis="y")
        w.transform(rot_x(0.35))
        w.translate((0.55, y, 0.42))
        m += w
    m += beam((0.55, 0.15, 0.42), (0.55, 1.6, 0.42), 0.06, STEEL)
    return _no_ground(m)


def rail_bent():
    """Two lengths of rail the revolution levered up and twisted, a few ties still
    spiked to them."""
    m = Cloud()
    rail = (138, 132, 124)
    for x, bend in ((0.3, 0.5), (1.0, -0.4)):
        pts = [(x + bend * math.sin(t * math.pi) ** 2, t * 3.8, 0.08 + 0.5 * math.sin(t * math.pi * 0.8)) for t in np.linspace(0, 1, 9)]
        for a, b in zip(pts, pts[1:]):
            m += beam(a, b, 0.06, rail)
    for y, a in ((0.4, 0.3), (1.5, -0.2), (2.9, 0.5)):
        t = box((-0.6, -0.11, 0), (0.6, 0.11, 0.15), planks((80, 60, 46), board=0.3, mud=0), 0.03)
        t.transform(rot_z(a))
        t.translate((0.75, y, 0.0))
        m += t
    return m


def tie():
    """A loose railroad tie."""
    t = box((-0.6, -0.11, 0), (0.6, 0.11, 0.15), planks((84, 62, 46), board=0.3, mud=0), 0.03)
    t.transform(rot_z(0.4))
    t.translate((0.6, 0.4, 0))
    return t


def ties(along_x=True):
    """Ties from the torn-up track, stacked crib-fashion into a breastwork: the
    rudest of defences, but heavy timber."""
    m = Cloud()
    L = 2.0 * T
    for row in range(5):
        for i in range(3):
            a = 0.12 + i * 0.25
            lo, hi = ((0.0 + row % 2 * 0.06, a, row * 0.15), (L - 0.06 + row % 2 * 0.06, a + 0.2, row * 0.15 + 0.15))
            if not along_x:
                lo, hi = ((a, lo[0], lo[2]), (a + 0.2, hi[0], hi[2]))
            m += box(lo, hi, planks((84 - row * 3, 62 - row * 2, 46), board=0.4, mud=0, seed=row + i), 0.03)
    return m


def rifle_crate(open_=False):
    """A case of rifles, rope handles at the ends; open, the lid off and the rifles
    showing in their racks."""
    pine = planks((182, 148, 102), board=0.14, mud=0)
    m = box((0, 0, 0), (1.25, 0.5, 0.36 if open_ else 0.4), pine, 0.03, skip=("+z",) if open_ else ())
    if open_:
        for i in range(5):
            y = 0.08 + i * 0.085
            m += beam((0.1, y, 0.3), (1.15, y, 0.3), 0.025, (86, 60, 40))     # stocks
            m += beam((0.5, y, 0.31), (1.15, y, 0.31), 0.012, (64, 64, 66))    # barrels
        lid = box((0, 0, 0), (1.25, 0.5, 0.04), pine, 0.03)
        lid.transform(rot_x(-1.2))
        lid.translate((0.0, 0.48, 0.02))
        m += lid
    else:
        m += box((0.1, 0.0, 0.18), (1.15, 0.01, 0.24), solid((60, 50, 40)), 0.02)   # the stencil band
    for x in (-0.03, 1.25):
        m += beam((x, 0.15, 0.25), (x, 0.35, 0.25), 0.02, (190, 170, 120))
    return m


def rifle_crates():
    """Cases waiting by a door to be carried off: four, two and two, one across the
    top."""
    m = Cloud()
    for x, y, z, a in ((0, 0, 0, 0), (0, 0.52, 0, 0), (0, 0, 0.4, 0), (0, 0.52, 0.4, 0)):
        m += rifle_crate().translate((x, y, z))
    top = rifle_crate()
    top.transform(rot_z(0.15))
    top.translate((0.05, 0.25, 0.8))
    m += top
    return m


def ammo_box():
    """A small heavy box of cartridges, painted army green."""
    m = box((0, 0, 0), (0.55, 0.38, 0.3), planks((92, 100, 70), board=0.12, mud=0), 0.03)
    m += box((0.2, 0.15, 0.3), (0.35, 0.23, 0.33), solid((50, 50, 46)), 0.02)
    return m


TELEGRAPH_SPAN = 7 * T   # poles seven tiles apart: each carries its own half of the wire either side


def telegraph(cut=None):
    """A telegraph pole beside the line, its wire running on to the next. The
    revolution cut it before they stopped the train: `cut` is the side (-1 north, +1
    south) where the wire's down, hanging from the arm."""
    m = Cloud()
    wood = (110, 88, 66)
    m += frustum((0.15, 0.15, 0), (0.15, 0.15, 6.0), 0.1, 0.08, wood)
    m += box((-0.55, 0.1, 5.6), (0.85, 0.2, 5.7), solid(wood), 0.02)
    half = TELEGRAPH_SPAN / 2
    for x in (-0.45, 0.75):
        m += frustum((x, 0.15, 5.7), (x, 0.15, 5.82), 0.04, 0.03, (120, 170, 150))
        for side in (-1, 1):
            if side == cut:
                pts = [(x, 0.15, 5.78), (x + 0.1, 0.15 + side * 0.4, 4.2), (x + 0.3, 0.15 + side * 0.6, 1.8), (x + 0.6, 0.15 + side * 0.4, 0.02)]
            else:
                pts = [(x, 0.15 + side * half * t, 5.78 - 0.35 * (1 - (1 - t) ** 2)) for t in np.linspace(0, 1, 7)]
            for a, b in zip(pts, pts[1:]):
                m += beam(a, b, 0.012, (40, 40, 42))
    return m


def telegraph_down():
    """A telegraph pole cut down across the dirt, its arm snapped, a hank of the
    wire left lying by it."""
    wood = (110, 88, 66)
    m = frustum((0.5, 0.1, 0.12), (0.5, 4.8, 0.1), 0.1, 0.08, wood)
    arm = box((-0.7, -0.05, 0), (0.7, 0.05, 0.1), solid(wood), 0.02)
    arm.transform(rot_z(0.5))
    arm.translate((0.45, 4.4, 0.18))
    m += arm
    for i in range(14):   # the wire, in loose coils
        a0, a1 = i * 0.9, (i + 1) * 0.9
        c = (0.2 + 0.05 * i, 2.0)
        m += beam((c[0] + 0.35 * math.cos(a0), c[1] + 0.3 * math.sin(a0), 0.02),
                  (c[0] + 0.35 * math.cos(a1), c[1] + 0.3 * math.sin(a1), 0.02), 0.012, (40, 40, 42))
    return m


def rock(seed=0, s=1.0):
    """A boulder out in the scrub: stone to hide behind."""
    rng = np.random.default_rng(131 + seed)
    stone = lambda P, N: np.tile([156.0, 132, 106], (len(P), 1)) * (0.78 + 0.3 * hash01(np.floor(P[:, 0] * 6), np.floor(P[:, 2] * 6), seed))[:, None]
    m = Cloud()
    for i in range(4):
        c = (0.6 * s + rng.uniform(-0.25, 0.25) * s, 0.5 * s + rng.uniform(-0.15, 0.15) * s, 0.0)
        r = (rng.uniform(0.35, 0.55) * s, rng.uniform(0.3, 0.45) * s, rng.uniform(0.35, 0.7) * s)
        m += ellipsoid(c, r, stone, zmin=0.0)
    return m


def mule(x, y, col):
    """A mule in harness, facing -x."""
    m = Cloud()
    dark = tuple(c * 0.7 for c in col)
    m += ellipsoid((x, y, 1.05), (0.62, 0.22, 0.27), col)
    m += beam((x - 0.48, y, 1.15), (x - 0.82, y, 1.5), 0.14, col)
    m += ellipsoid((x - 0.98, y, 1.42), (0.24, 0.1, 0.12), col)
    m += ellipsoid((x - 1.16, y, 1.36), (0.08, 0.085, 0.085), dark)
    for s in (-1, 1):
        m += beam((x - 0.86, y + s * 0.05, 1.55), (x - 0.78, y + s * 0.1, 1.86), 0.035, col)   # the ears
        for dx in (-0.45, 0.45):
            m += beam((x + dx, y + s * 0.12, 0.95), (x + dx, y + s * 0.12, 0.0), 0.05, dark)
    m += beam((x + 0.6, y, 1.15), (x + 0.75, y, 0.62), 0.03, dark)                        # tail
    m += ellipsoid((x - 0.52, y, 1.22), (0.09, 0.2, 0.26), (46, 34, 26))                  # collar
    m += beam((x - 0.5, y, 1.0), (x + 0.4, y, 1.0), 0.025, (46, 34, 26))                   # traces
    return m


def carreta():
    """The revolution's freight wagon, high-sided, two mules in harness facing out
    of the fight (-x), the first cases of rifles already aboard."""
    m = Cloud()
    L, Wd, x0 = 3.4, 1.6, 2.5
    wood = planks((120, 92, 64), board=0.18, mud=0.2)
    m += box((x0, 0.15, 0.7), (x0 + L, Wd - 0.15, 0.85), wood, BSP)
    for y0, y1 in ((0.15, 0.22), (Wd - 0.22, Wd - 0.15)):
        m += box((x0, y0, 0.85), (x0 + L, y1, 1.45), wood, BSP)
    for x in (x0, x0 + L - 0.07):
        m += box((x, 0.22, 0.85), (x + 0.07, Wd - 0.22, 1.45), wood, BSP)
    for i in range(3):
        m += rifle_crate().translate((x0 + 0.3 + i * 0.05, 0.3 + (i % 2) * 0.5, 0.85 + (i // 2) * 0.4))
    m += wheel((x0 + 0.7, 0.08, 0.5), 0.5)
    m += wheel((x0 + 0.7, Wd - 0.08, 0.5), 0.5)
    m += wheel((x0 + L - 0.65, 0.08, 0.62), 0.62)
    m += wheel((x0 + L - 0.65, Wd - 0.08, 0.62), 0.62)
    m += beam((x0 + 0.1, Wd / 2, 0.55), (x0 - 1.0, Wd / 2, 0.85), 0.05, (110, 82, 56))    # the tongue
    m += mule(1.3, Wd / 2 - 0.38, (118, 92, 70))
    m += mule(1.38, Wd / 2 + 0.38, (96, 84, 76))
    m.translate((0.3, 0, 0))
    return m


def wagon_over():
    """A wagon turned over in the ambush, on its side, its underside and wheels to
    the east: a big piece of cover. Its load is spilled about it: a crate, sacks."""
    m = wagon()
    m.transform(rot_x(math.pi / 2))   # her top goes over to the north (-y), wheels to the camera
    m.translate((0.0, 1.55, 0.0))
    m += box((0.6, 1.6, 0.0), (1.4, 2.4, 0.75), crate_fn((160, 120, 80)), 0.03)
    m += sacks(1.9, 1.7, n=3)
    return _no_ground(m)


def sacks(x0=0.0, y0=0.0, n=5):
    """Sacks of beans and flour heaped up: soft, but they stop a round."""
    rng = np.random.default_rng(71 + n)
    burlap = lambda c: (lambda P, N: np.tile(np.array(c, float), (len(P), 1)) * (0.9 + 0.14 * hash01(np.floor(P[:, 0] * 30), np.floor(P[:, 2] * 30)))[:, None])
    m = Cloud()
    for i in range(n):
        row = 1 if i >= 3 else 0
        x = x0 + 0.42 + (i % 3) * 0.5 + row * 0.25
        y = y0 + 0.38 + rng.uniform(-0.04, 0.06)
        col = (170, 138, 94) if rng.random() < 0.6 else (206, 196, 172)
        m += box((x - 0.25, y - 0.2, 0.02 + row * 0.24), (x + 0.25, y + 0.2, 0.22 + row * 0.24), burlap(col), 0.02)
        m += ellipsoid((x, y, 0.2 + row * 0.24), (0.24, 0.19, 0.06), burlap(col))
        m += ellipsoid((x + 0.26, y, 0.12 + row * 0.24), (0.05, 0.06, 0.05), burlap(tuple(c * 0.85 for c in col)))   # the tied neck
    return m


def handcar():
    """The section gang's handcar, knocked off the line and over on its side, the
    pump handle sticking out."""
    m = Cloud()
    wood = planks((120, 92, 64), board=0.16, mud=0)
    m += box((0, 0, 0.5), (1.6, 2.2, 0.62), wood, 0.03)
    for y in (0.4, 1.8):
        for x in (0.15, 1.45):
            m += _iron_wheel((x, y, 0.3), 0.3)
    m += box((0.7, 0.95, 0.62), (0.9, 1.25, 1.3), solid(SOOT), 0.03)
    m += beam((0.8, 0.2, 1.35), (0.8, 2.0, 1.35), 0.04, SOOT)
    m.transform(rot_y(-(math.pi / 2 - 0.15)))   # over on her side, the deck to the west
    m.translate((1.4, 0.0, 0.0))
    return _no_ground(m)


def _loose_rifle(m, at, a, tilt=0.0):
    """A rifle lying in the dirt: stock and barrel, along angle `a`."""
    d = np.array([math.cos(a), math.sin(a), tilt])
    at = np.array(at, float)
    m += beam(at, at + d * 0.42, 0.035, (96, 64, 40))                  # the stock
    m += beam(at + d * 0.42, at + d * 1.05, 0.016, (62, 62, 66))       # the barrel
    m += beam(at + d * 0.5, at + d * 0.7, 0.024, (110, 76, 48))        # the forestock


def rifle_pile():
    """Rifles heaped on the ground where the cases broke open, and the guards' own
    thrown on top, for the carriers to take an armful at a time."""
    rng = np.random.default_rng(141)
    m = Cloud()
    for i in range(9):
        layer = i // 4
        _loose_rifle(m, (0.1 + rng.uniform(0, 0.2), 0.12 + rng.uniform(0, 0.55), 0.04 + layer * 0.05),
                     rng.uniform(-0.35, 0.35), rng.uniform(-0.03, 0.06))
    return m


def flag_down():
    """The federal colours down in the dirt: the staff across the ground, the
    tricolour crumpled beside it, the eagle showing in the white."""
    m = Cloud()
    m += beam((0.05, 0.15, 0.04), (1.7, 0.3, 0.04), 0.02, (120, 92, 60))
    m += ellipsoid((1.72, 0.3, 0.05), (0.03, 0.03, 0.03), (205, 165, 70))
    cols = ((46, 112, 66), (232, 228, 214), (188, 40, 36))
    for i, col in enumerate(cols):
        x0 = 1.15 - i * 0.3
        m += quad((x0 - 0.3, 0.32, 0.02), (0.3, 0.0, 0.0), (0.04, 0.6, 0.0), solid(col), 0.02, normal=(0, 0, 1))
        m += ellipsoid((x0 - 0.15, 0.6, 0.03), (0.13, 0.12, 0.04), col, zmin=0.0)   # a fold
    m += ellipsoid((0.7, 0.58, 0.06), (0.06, 0.07, 0.03), (120, 86, 52))            # the eagle
    return m


def _m1895(m, base, a, tilt=0.0):
    """The Colt-Browning's gun, from the spade grip at `base` along angle `a`: square
    receiver, heavy barrel, the gas lever swung under the muzzle, the belt out of the
    feed on its left."""
    d = np.array([math.cos(a) * math.cos(tilt), math.sin(a) * math.cos(tilt), math.sin(tilt)])
    side = np.array([-math.sin(a), math.cos(a), 0.0])
    b = np.array(base, float)
    m += beam(b - side * 0.06, b + side * 0.06, 0.02, (60, 58, 56))                      # the spade grip
    m += beam(b, b + d * 0.1, 0.02, (60, 58, 56))
    for k in np.linspace(0.1, 0.42, 6):
        m += box(tuple(b + d * k - 0.075), tuple(b + d * k + 0.075), (66, 66, 70), 0.02)    # receiver
    m += beam(b + d * 0.42, b + d * 1.15, 0.04, (82, 84, 92))                             # barrel
    m += beam(b + d * 0.95 - [0, 0, 0.06], b + d * 0.7 - [0, 0, 0.14], 0.02, (60, 58, 56))  # gas lever
    for i in range(7):   # the belt hanging out of the feed
        p_ = b + d * 0.25 + side * (0.1 + i * 0.03) - [0, 0, 0.04 * i]
        m += box(tuple(p_ - 0.02), tuple(p_ + 0.02), (205, 165, 70), 0.01)


def mgun(a):
    """The gun on its low tripod, turned to screen angle `a` (radians, about the
    tripod head at the origin): the stranger works it crouched behind."""
    m = Cloud()
    head = np.array([0.0, 0.0, 0.62])
    for la in (a + math.pi, a + math.pi * 0.35, a - math.pi * 0.35):   # two legs forward, the trail back
        m += beam(head, head + np.array([math.cos(la) * 0.55, math.sin(la) * 0.55, -0.62]), 0.025, (78, 70, 60))
    m += ellipsoid(tuple(head), (0.06, 0.06, 0.05), (60, 58, 56))
    back = head + np.array([math.cos(a), math.sin(a), 0.0]) * -0.38 + [0, 0, 0.06]
    _m1895(m, back, a, 0.03)
    return m


def mgun_pile():
    """Machine guns off the train, the tripods left behind, laid on a tarp with
    their belts for the carriers."""
    m = Cloud()
    m += quad((0, 0, 0.01), (1.4, 0, 0), (0, 0.9, 0), solid((150, 136, 104)), 0.03, normal=(0, 0, 1))
    _m1895(m, (0.15, 0.25, 0.08), 0.1)
    _m1895(m, (0.2, 0.6, 0.08), -0.05)
    return m


def nest(along_x=True):
    """The gun's own sandbags, heaped tight round it, low enough to fire over: they
    wear away as the army closes in."""
    m = Cloud()
    L = 1.6 * T
    for row in range(3):
        n = 4 - (row == 2)
        for i in range(n):
            a = (i + 0.5 + 0.5 * (row % 2)) * (L / 4.2)
            c = (a, 0.36, 0.13 + row * 0.2) if along_x else (0.36, a, 0.13 + row * 0.2)
            r = (0.27, 0.2, 0.11) if along_x else (0.2, 0.27, 0.11)
            m += ellipsoid(c, r, solid((166 - row * 6, 146 - row * 6, 102)))
    return m


# Long things baked in pieces along their length, each its own sprite sorted at its
# own middle, so a man beside one end of a boxcar is drawn in front of it, not
# behind (one sprite sorts at the middle of the whole car). Name -> (axis, pieces);
# the maps place "<name>_<i>", one after another.
CHUNKED = {"boxcar_a": (1, 3), "boxcar_b": (1, 3), "boxcar_burnt": (1, 3), "flatcar": (1, 2),
           "loco_wreck": (1, 3), "tender": (1, 2), "carreta": (0, 2)}


BUILDINGS = {
    # name: (builder, footprint (tiles), collision type, fade, colliders (tiles, relative))
    "saloon": (saloon, (7, 6), "wall", True, None),
    "store": (store, (5, 5), "wall", True, None),
    "sheriff": (sheriff, (5, 5), "wall", True, None),
    "bank": (bank, (6, 6), "wall", True, None),
    "adobe_a": (lambda: adobe_house(5, 4, (208, 178, 140), 3.0, 21), (5, 4), "wall", True, None),
    "adobe_b": (lambda: adobe_house(4, 4, (214, 168, 136), 3.4, 31), (4, 4), "wall", True, None),
    "church": (church, (6, 7), "wall", True, None),
    "stable": (stable, (6, 5), "wall", True, None),
    "water_tower": (water_tower, (2, 2), "wall", True,
                    [[0.16, 0.16, 0.4, 0.4], [1.6, 0.16, 1.84, 0.4], [0.16, 1.6, 0.4, 1.84],
                     [1.6, 1.6, 1.84, 1.84]]),
    "gallows": (gallows, (3, 3), "cover", True, None),
    "hotel": (lambda: frontier(7, 6, 5.4, 7.0, planks((150, 156, 134), seed=17), "HOTEL", (60, 50, 44),
                               floors=2, step=0.5, hang="ROOMS"), (7, 6), "wall", True, None),
    "barber": (lambda: frontier(4, 4, 3.4, 4.6, planks((190, 182, 160), seed=19), "BARBER", (40, 60, 90),
                                extras=_barber_pole, hang="BATHS"), (4, 4), "wall", True, None),
    "undertaker": (lambda: frontier(4, 5, 3.6, 4.8, planks((70, 62, 58), seed=23), "UNDERTAKER", (24, 22, 22),
                                    ink=(210, 200, 180), hang="COFFINS"), (4, 5), "wall", True, None),
    "assay": (lambda: frontier(5, 4, 3.6, 4.8, bricks((168, 150, 120), (210, 196, 170)), "ASSAY", (80, 60, 40), hang="GOLD"),
              (5, 4), "wall", True, None),
    "feed": (lambda: frontier(5, 5, 4.0, 5.4, planks((140, 96, 60), seed=29), "FEED", (230, 210, 160),
                              ink=(120, 40, 30), step=0.4, hang="HAY"), (5, 5), "wall", True, None),
    "gunsmith": (lambda: frontier(3, 4, 3.4, 4.6, planks((112, 72, 54), seed=37), "GUNSMITH", (34, 30, 28),
                                  ink=(214, 180, 96), extras=_gun_sign), (3, 4), "wall", True, None),
    "cantina": (cantina, (6, 5), "wall", True, None),
    "crate": (crate, (0.8, 0.8), "cover", False, None),
    "barrel": (barrel, (0.55, 0.55), "cover", False, None),
    "wagon": (wagon, (2.4, 1.2), "cover", False, [[0.2, 0.15, 2.2, 1.05]]),
    "trough": (trough, (1.52, 0.56), "cover", False, None),
    "coffin": (coffin, (1.6, 0.56), "cover", False, None),
    "hitch": (hitch, (1.6, 0.2), "none", False, None),
    "cactus": (cactus, (0.6, 0.6), "post", False, [[0.15, 0.15, 0.45, 0.45]]),
    "cross": (cross, (0.42, 0.2), "none", False, None),
    # Cruz Verde
    "wall_x8": (lambda: fort_wall(8, True, 51), (8, 1), "wall", True, None),
    "wall_x4": (lambda: fort_wall(4, True, 52), (4, 1), "wall", True, None),
    "wall_y8": (lambda: fort_wall(8, False, 54), (1, 8), "wall", True, None),
    "wall_y4": (lambda: fort_wall(4, False, 55), (1, 4), "wall", True, None),
    "gate_x": (lambda: fort_gate(True), (5, 1), "wall", True, [[0, 0, 1, 1], [4, 0, 5, 1]]),
    "gate_y": (lambda: fort_gate(False), (1, 5), "wall", True, [[0, 0, 1, 1], [0, 4, 1, 5]]),
    "bastion": (bastion, (2, 2), "wall", True, None),
    "rubble": (rubble, (1.6, 1.0), "cover", False, None),
    "chapel": (chapel, (5, 6), "wall", True, None),
    "barracks": (barracks, (10, 4), "wall", True, None),
    "casa_grande": (casa_grande, (8, 6), "wall", True, None),
    "jacal": (lambda: jacal(81), (3, 3), "wall", True, None),
    "jacal_b": (lambda: jacal(83), (3, 3), "wall", True, None),
    "well": (well, (1.2, 1.2), "cover", False, [[0.15, 0.15, 1.05, 1.05]]),
    "sandbags_x": (lambda: sandbags(True), (2.0, 0.6), "cover", False, None),
    # the explosives: shot, a keg fizzes a second and goes up; a crate of dynamite
    # burns a while first, then makes the biggest bang there is
    "keg": (keg, (0.45, 0.45), "cover", False, None),
    "dyn_crate": (dyn_crate, (0.8, 0.56), "cover", False, None),
    "crate_stack": (crate_stack, (1.6, 0.8), "cover", False, [[0, 0, 1.6, 0.8]]),
    # tables thrown over for a barricade, named for the way the top faces: only the
    # top stops anything, the legs behind it don't
    "upturned_n": (lambda: upturned("n"), (1.2, 0.6), "cover", False, [[0, 0, 1.2, 0.12]]),
    "upturned_s": (lambda: upturned("s"), (1.2, 0.6), "cover", False, [[0, 0.48, 1.2, 0.6]]),
    "upturned_w": (lambda: upturned("w"), (0.6, 1.2), "cover", False, [[0, 0, 0.12, 1.2]]),
    "upturned_e": (lambda: upturned("e"), (0.6, 1.2), "cover", False, [[0.48, 0, 0.6, 1.2]]),
    "sandbags_y": (lambda: sandbags(False), (0.6, 2.0), "cover", False, None),
    "cannon": (cannon, (2.0, 1.0), "cover", False, None),
    "flagpole": (flagpole, (0.3, 0.3), "post", False, None),
    "pole": (pole, (0.3, 0.3), "none", False, None),
    "headstone": (lambda: headstone(0), (0.5, 0.25), "cover", False, None),
    "headstone_b": (lambda: headstone(1), (0.5, 0.25), "cover", False, None),
    "stone_circle": (stone_circle, (6, 6), "none", False, None),
    "agave": (lambda: agave(0), (0.6, 0.6), "none", False, None),
    "mound": (mound, (1.0, 0.56), "none", False, None),
    "open_grave": (lambda: open_grave(True), (2.2, 2.0), "none", False, None),
    "open_grave_in": (lambda: open_grave(False), (2.2, 2.0), "none", False, None),
    "olla": (olla, (0.4, 0.4), "none", False, None),
    "chair": (chair, (0.4, 0.4), "none", False, None),
    "table": (table, (0.56, 0.56), "none", False, None),
    "coop": (coop, (0.84, 0.6), "none", False, None),
    "hencrate": (hen_crate, (0.56, 0.4), "none", False, None),
    "washline": (lambda: washline(4.5, ("sheet", "shirt", "longjohns", "towel"), 3), (3.6, 0.24), "none", False, None),
    "washline_b": (lambda: washline(4.5, ("skirt", "sheet", "shirt"), 11), (3.6, 0.24), "none", False, None),
    "washline_alley": (lambda: washline(2.4, ("sheet", "longjohns"), 17), (1.92, 0.24), "none", False, None),
    # the train
    "boxcar_a": (lambda: boxcar((134, 58, 40), 3), (2.4, 6), "wall", True, None),
    "boxcar_b": (lambda: boxcar((150, 108, 62), 7), (2.4, 6), "wall", True, None),
    "boxcar_burnt": (boxcar_burnt, (2.4, 6), "cover", False, None),
    "flatcar": (flatcar, (2.4, 4.5), "cover", False, None),
    "loco_wreck": (loco_wreck, (3.5, 7.5), "wall", True, None),
    "tender": (tender, (2.4, 4.0), "wall", True, None),
    "coal": (coal_heap, (1.2, 1.0), "none", False, None),
    "wheelset": (wheelset, (1.0, 1.4), "cover", False, None),
    "rail_bent": (rail_bent, (1.2, 3.0), "none", False, None),
    "tie": (tie, (1.0, 0.7), "none", False, None),
    "ties_x": (lambda: ties(True), (2.0, 0.65), "cover", False, None),
    "ties_y": (lambda: ties(False), (0.65, 2.0), "cover", False, None),
    "rifle_crate": (rifle_crate, (1.0, 0.4), "cover", False, None),
    "rifle_crate_open": (lambda: rifle_crate(True), (1.0, 0.4), "cover", False, [[0, 0, 1.0, 0.4]]),
    "rifle_crates": (rifle_crates, (1.0, 0.85), "cover", False, None),
    "ammo_box": (ammo_box, (0.45, 0.3), "cover", False, None),
    "telegraph": (telegraph, (0.3, 0.3), "post", False, None),
    "telegraph_cut_n": (lambda: telegraph(-1), (0.3, 0.3), "post", False, None),
    "telegraph_cut_s": (lambda: telegraph(1), (0.3, 0.3), "post", False, None),
    "telegraph_down": (telegraph_down, (1.0, 4.0), "none", False, None),
    "rock": (lambda: rock(0), (1.0, 0.8), "cover", False, None),
    "rock_b": (lambda: rock(1, 0.7), (0.7, 0.6), "cover", False, None),
    "rock_c": (lambda: rock(2, 1.6), (1.6, 1.3), "cover", False, None),
    "wagon_over": (wagon_over, (2.6, 2.0), "cover", False, [[0.1, 0.0, 2.5, 1.2]]),
    "sacks": (sacks, (1.2, 0.6), "cover", False, None),
    "handcar": (handcar, (1.2, 1.8), "cover", False, None),
    "rifle_pile": (rifle_pile, (1.0, 0.7), "none", False, None),
    "flag_down": (flag_down, (1.4, 0.8), "none", False, None),
    "mgun_pile": (mgun_pile, (1.2, 0.8), "none", False, None),
    "nest_x": (lambda: nest(True), (1.6, 0.6), "cover", False, None),
    "nest_y": (lambda: nest(False), (0.6, 1.6), "cover", False, None),
    "carreta": (carreta, (5.0, 1.3), "cover", False, None),
}


def _chunk_entries():
    """Each piece of a CHUNKED model is a building of its own: its slice of the
    footprint and the colliders, the parent's sprite cut along the same lines."""
    for name, (axis, n) in CHUNKED.items():
        fn, fp, collide, fade, colliders = BUILDINGS[name]
        step = fp[axis] / n
        for i in range(n):
            lo, hi = i * step, (i + 1) * step
            cfp = list(fp)
            cfp[axis] = step
            cols = []
            for r in colliders or [[0, 0, fp[0], fp[1]]]:
                a, b = max(r[axis], lo), min(r[axis + 2], hi)
                if b > a:
                    rr = list(r)
                    rr[axis], rr[axis + 2] = a - lo, b - lo
                    cols.append(rr)
            BUILDINGS[f"{name}_{i}"] = (None, tuple(cfp), collide, fade, cols)


_chunk_entries()
