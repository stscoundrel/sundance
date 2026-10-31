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


def decorate(fn, W, D, openings):
    """Paint windows, doors and signs onto faces. openings: dicts with face ('+x','+y'),
    u=(u0,u1), z=(z0,z1), kind and optional text/color."""
    planes = {"+x": (0, W, 1), "-x": (0, 0, 1), "+y": (1, D, 0), "-y": (1, 0, 0)}
    for o in openings:
        if o["kind"] in ("door", "batwing", "arch", "dark") and o["z"][0] < 0.5:
            DOORS.append((o["face"], (o["u"][0] + o["u"][1]) / 2, W, D))

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


def boardwalk(W, D, depth=1.2, awning=3.0, posts=4, wood=(132, 98, 66)):
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
    m += boardwalk(W, D, awning=3.1, posts=5)
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
    m += boardwalk(W, D, awning=2.8, posts=3)
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
    m += boardwalk(W, D, awning=2.8, posts=3)
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
    m += boardwalk(W, D, awning=3.0, posts=4, wood=(120, 110, 96))
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
             roof_col=(100, 84, 72), step=0.0, extras=None):
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
    m += boardwalk(W, D, awning=2.8, posts=max(2, int(W // 2.4) + 1))
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
                               floors=2, step=0.5), (7, 6), "wall", True, None),
    "barber": (lambda: frontier(4, 4, 3.4, 4.6, planks((190, 182, 160), seed=19), "BARBER", (40, 60, 90),
                                extras=_barber_pole), (4, 4), "wall", True, None),
    "undertaker": (lambda: frontier(4, 5, 3.6, 4.8, planks((70, 62, 58), seed=23), "UNDERTAKER", (24, 22, 22),
                                    ink=(210, 200, 180)), (4, 5), "wall", True, None),
    "assay": (lambda: frontier(5, 4, 3.6, 4.8, bricks((168, 150, 120), (210, 196, 170)), "ASSAY", (80, 60, 40)),
              (5, 4), "wall", True, None),
    "feed": (lambda: frontier(5, 5, 4.0, 5.4, planks((140, 96, 60), seed=29), "FEED", (230, 210, 160),
                              ink=(120, 40, 30), step=0.4), (5, 5), "wall", True, None),
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
}
