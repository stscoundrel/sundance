"""Buildings and props for the town, built from primitives in metres.
Every model has its origin at the footprint's minimum corner."""
import math
import numpy as np
from render3d import (Cloud, make, box, quad, tri, frustum, ellipsoid, beam, hash01, TILE_M,
                      rot_x)

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
BREAKABLE = ("crate", "barrel", "coffin", "trough", "wagon")
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
    "mound": (mound, (1.0, 0.56), "none", False, None),
    "olla": (olla, (0.4, 0.4), "none", False, None),
    "chair": (chair, (0.4, 0.4), "none", False, None),
    "table": (table, (0.56, 0.56), "none", False, None),
    "coop": (coop, (0.84, 0.6), "none", False, None),
    "hencrate": (hen_crate, (0.56, 0.4), "none", False, None),
    "washline": (lambda: washline(4.5, ("sheet", "shirt", "longjohns", "towel"), 3), (3.6, 0.24), "none", False, None),
    "washline_b": (lambda: washline(4.5, ("skirt", "sheet", "shirt"), 11), (3.6, 0.24), "none", False, None),
    "washline_alley": (lambda: washline(2.4, ("sheet", "longjohns"), 17), (1.92, 0.24), "none", False, None),
}
