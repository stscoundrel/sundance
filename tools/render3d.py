"""Tiny point-splat renderer: builds models from primitives in metres and renders
them in 2:1 isometric pixel art with quantised lighting, cast shadows and outlines.

World axes: X and Y on the ground (grid gx/gy), Z up. One grid tile = 1.25 m.
"""
import math
import numpy as np

TILE_M = 1.25
PX = 16.0 / TILE_M      # screen x per metre of (X - Y)
PY = 8.0 / TILE_M       # screen y per metre of (X + Y)
PZ = 15.7               # screen y per metre of height
SP = 0.022              # default sampling spacing (m) at 1 texel per world pixel
PIX = 3                 # texels per world pixel: sprites carry 3x detail

_sun = np.array([-0.55, 0.2, 0.95])
SUN = _sun / np.linalg.norm(_sun)
VIEW = np.array([0.612, 0.612, 0.5])
LEVELS = np.array([0.52, 0.68, 0.84, 1.0, 1.12])
SHADOW_TINT = np.array([44.0, 30.0, 52.0])
OUTLINE = (26, 17, 13)


def _col(color, P, N):
    if callable(color):
        return np.asarray(color(P, N), float).reshape(len(P), 3)
    return np.tile(np.array(color, float), (len(P), 1))


def _norm(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    n[n == 0] = 1
    return v / n


class Cloud:
    def __init__(self, P=None, N=None, C=None):
        self.P = np.zeros((0, 3)) if P is None else P
        self.N = np.zeros((0, 3)) if N is None else N
        self.C = np.zeros((0, 3)) if C is None else C

    def add(self, other):
        self.P = np.concatenate([self.P, other.P])
        self.N = np.concatenate([self.N, other.N])
        self.C = np.concatenate([self.C, other.C])
        return self

    def __iadd__(self, other):
        return self.add(other)

    def copy(self):
        return Cloud(self.P.copy(), self.N.copy(), self.C.copy())

    def transform(self, R, t=(0, 0, 0), pivot=(0, 0, 0)):
        pivot = np.array(pivot, float)
        self.P = (self.P - pivot) @ R.T + pivot + np.array(t, float)
        self.N = self.N @ R.T
        return self

    def translate(self, t):
        self.P = self.P + np.array(t, float)
        return self


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def make(P, N, color):
    P = np.asarray(P, float).reshape(-1, 3)
    N = _norm(np.asarray(N, float).reshape(-1, 3))
    return Cloud(P, N, _col(color, P, N))


# ---------------------------------------------------------------- primitives

def ellipsoid(c, r, color, sp=SP, zmin=None):
    sp /= PIX
    rx, ry, rz = r
    nphi = max(6, int(math.pi * max(r) / sp))
    nth = max(10, int(2 * math.pi * max(rx, ry) / sp))
    phi = (np.arange(nphi) + 0.5) / nphi * math.pi
    th = np.arange(nth) / nth * 2 * math.pi
    PH, TH = np.meshgrid(phi, th, indexing="ij")
    x, y, z = np.cos(TH) * np.sin(PH), np.sin(TH) * np.sin(PH), np.cos(PH)
    P = np.stack([x * rx, y * ry, z * rz], -1).reshape(-1, 3) + np.array(c, float)
    N = np.stack([x / rx, y / ry, z / rz], -1).reshape(-1, 3)
    if zmin is not None:
        keep = P[:, 2] >= zmin
        P, N = P[keep], N[keep]
    return make(P, N, color)


def frustum(p0, p1, r0, r1, color, su=1.0, sw=1.0, caps=True, gap=None, sp=SP):
    """Cone frustum from p0 to p1. su/sw scale the cross-section along the local
    u/w axes (u = model X for vertical frustums). gap=(angle, half_width) leaves a
    slit (e.g. the open front of a duster)."""
    sp /= PIX
    p0 = np.array(p0, float)
    p1 = np.array(p1, float)
    axis = p1 - p0
    L = np.linalg.norm(axis)
    a = axis / L
    if abs(a[2]) > 0.9:
        u = np.array([1.0, 0, 0]) - a * a[0]
    else:
        u = np.cross(a, [0, 0, 1.0])
    u /= np.linalg.norm(u)
    w = np.cross(a, u)
    rmax = max(r0, r1) * max(su, sw)
    nt = max(2, int(L / sp) + 1)
    nth = max(10, int(2 * math.pi * rmax / sp))
    T = np.linspace(0, 1, nt)
    th = np.arange(nth) / nth * 2 * math.pi
    if gap is not None:
        d = np.angle(np.exp(1j * (th - gap[0])))
        th = th[np.abs(d) > gap[1]]
    TT, TH = np.meshgrid(T, th, indexing="ij")
    R = r0 + (r1 - r0) * TT
    cu, sw_ = np.cos(TH), np.sin(TH)
    P = (p0 + a * (L * TT)[..., None]
         + (R * cu * su)[..., None] * u + (R * sw_ * sw)[..., None] * w)
    nr = (cu / su)[..., None] * u + (sw_ / sw)[..., None] * w
    nr = _norm(nr.reshape(-1, 3))
    N = nr + a * ((r0 - r1) / L)
    out = make(P.reshape(-1, 3), N, color)
    if caps:
        for pc, rc, nd in ((p0, r0, -a), (p1, r1, a)):
            if rc <= 0.004:
                continue
            nrho = max(2, int(rc / sp))
            pts = []
            for i in range(nrho + 1):
                rho = rc * i / nrho
                k = max(1, int(2 * math.pi * rho * max(su, sw) / sp))
                ang = np.arange(k) / k * 2 * math.pi
                pts.append(pc + (rho * np.cos(ang) * su)[:, None] * u
                           + (rho * np.sin(ang) * sw)[:, None] * w)
            pts = np.concatenate(pts)
            out += make(pts, np.tile(nd, (len(pts), 1)), color)
    return out


def quad(p, e1, e2, color, sp=SP, normal=None):
    sp /= PIX
    p, e1, e2 = (np.array(v, float) for v in (p, e1, e2))
    n1 = max(2, int(np.linalg.norm(e1) / sp) + 1)
    n2 = max(2, int(np.linalg.norm(e2) / sp) + 1)
    s = np.linspace(0, 1, n1)
    t = np.linspace(0, 1, n2)
    S, T = np.meshgrid(s, t, indexing="ij")
    P = p + S[..., None] * e1 + T[..., None] * e2
    n = np.cross(e1, e2) if normal is None else np.array(normal, float)
    return make(P.reshape(-1, 3), np.tile(n, (n1 * n2, 1)), color)


def tri(p0, p1, p2, color, sp=SP):
    sp /= PIX
    p0, p1, p2 = (np.array(v, float) for v in (p0, p1, p2))
    e1, e2 = p1 - p0, p2 - p0
    n = max(2, int(max(np.linalg.norm(e1), np.linalg.norm(e2)) / sp) + 1)
    s = np.linspace(0, 1, n)
    S, T = np.meshgrid(s, s, indexing="ij")
    keep = (S + T) <= 1.0
    P = p0 + S[keep][:, None] * e1 + T[keep][:, None] * e2
    nn = np.cross(e1, e2)
    return make(P, np.tile(nn, (len(P), 1)), color)


def box(c0, c1, color, sp=SP, skip=()):
    """Axis-aligned box. skip may contain '-x','+x','-y','+y','-z','+z'."""
    x0, y0, z0 = c0
    x1, y1, z1 = c1
    dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    out = Cloud()
    faces = {
        "-z": ((x0, y0, z0), (dx, 0, 0), (0, dy, 0), (0, 0, -1)),
        "+z": ((x0, y0, z1), (dx, 0, 0), (0, dy, 0), (0, 0, 1)),
        "-x": ((x0, y0, z0), (0, dy, 0), (0, 0, dz), (-1, 0, 0)),
        "+x": ((x1, y0, z0), (0, dy, 0), (0, 0, dz), (1, 0, 0)),
        "-y": ((x0, y0, z0), (dx, 0, 0), (0, 0, dz), (0, -1, 0)),
        "+y": ((x0, y1, z0), (dx, 0, 0), (0, 0, dz), (0, 1, 0)),
    }
    for k, (p, e1, e2, n) in faces.items():
        if k in skip:
            continue
        out += quad(p, e1, e2, color, sp, normal=n)
    return out


def disc(c, r_out, color, r_in=0.0, curl=0.0, front_curl=0.3, sp=SP, underside=None):
    """Horizontal disc / annulus (hat brims). curl raises the rim, more at the sides."""
    sp /= PIX
    c = np.array(c, float)
    pts = []
    nr = max(2, int((r_out - r_in) / sp) + 1)
    for i in range(nr + 1):
        rho = r_in + (r_out - r_in) * i / nr
        k = max(6, int(2 * math.pi * rho / sp))
        ang = np.arange(k) / k * 2 * math.pi
        side = front_curl + (1 - front_curl) * np.abs(np.sin(ang))
        f = ((rho - r_in) / max(r_out - r_in, 1e-6)) ** 2
        z = c[2] + curl * f * side
        pts.append(np.stack([c[0] + rho * np.cos(ang), c[1] + rho * np.sin(ang), z], -1))
    P = np.concatenate(pts)
    rel = P - c
    N = np.stack([-rel[:, 0] * curl * 3, -rel[:, 1] * curl * 3, np.ones(len(P))], -1)
    out = make(P, N, color)
    under = make(P - [0, 0, 0.01], -N, underside if underside is not None else color)
    return out.add(under)


def beam(p0, p1, r, color, sp=SP):
    return frustum(p0, p1, r, r, color, sp=sp)


# ---------------------------------------------------------------- rendering

def project(P):
    sx = (P[:, 0] - P[:, 1]) * PX
    sy = (P[:, 0] + P[:, 1]) * PY - P[:, 2] * PZ
    return sx, sy


def shade(cloud):
    N = _norm(cloud.N)
    facing = N @ VIEW
    d = N @ SUN
    d = np.where(facing < -0.05, -0.4, d)
    lvl = 0.6 + 0.55 * np.clip(d, 0, 1)
    idx = np.abs(lvl[:, None] - LEVELS[None, :]).argmin(1)
    f = LEVELS[idx]
    col = cloud.C * f[:, None]
    dark = f < 0.75
    col[dark] = col[dark] * 0.82 + SHADOW_TINT * 0.18
    return np.clip(col, 0, 255)


def render(cloud, size=None, anchor=None, shadow=True, outline=True, edges=True,
           scale=PIX, ground=None, shadow_alpha=96, pad=6, shadow_extra=None):
    """Render to an RGBA array. Returns (img, anchor) where anchor is the pixel of
    the model origin. ground: Cloud drawn first at ground level (pools, decals)."""
    P = cloud.P
    sx, sy = project(P)
    sx, sy = sx * scale, sy * scale
    depth = P @ VIEW
    col = shade(cloud)

    shp = None
    if shadow:
        SP_ = P if shadow_extra is None else np.concatenate([P, shadow_extra.P])
        G = SP_ - SUN[None, :] * (SP_[:, 2:3] / SUN[2])
        gsx, gsy = project(G)
        shp = (gsx * scale, gsy * scale)

    if size is None:
        xs = [sx]
        ys = [sy]
        if shp is not None:
            xs.append(shp[0])
            ys.append(shp[1])
        if ground is not None:
            gx_, gy_ = project(ground.P)
            xs.append(gx_ * scale)
            ys.append(gy_ * scale)
        minx = math.floor(min(a.min() for a in xs)) - pad
        miny = math.floor(min(a.min() for a in ys)) - pad
        maxx = math.ceil(max(a.max() for a in xs)) + pad
        maxy = math.ceil(max(a.max() for a in ys)) + pad
        W, H = maxx - minx + 1, maxy - miny + 1
        anchor = (-minx, -miny)
    else:
        W, H = size
    ax, ay = anchor

    img = np.zeros((H, W, 4), np.uint8)
    D = np.full((H, W), -1e9)
    mask = np.zeros((H, W), bool)

    if shp is not None:
        px = np.floor(shp[0] + ax).astype(int)
        py = np.floor(shp[1] + ay).astype(int)
        ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
        smask = np.zeros((H, W), bool)
        smask[py[ok], px[ok]] = True
        img[smask] = (18, 10, 8, shadow_alpha)

    if ground is not None:
        gsx, gsy = project(ground.P)
        px = np.floor(gsx * scale + ax).astype(int)
        py = np.floor(gsy * scale + ay).astype(int)
        ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
        img[py[ok], px[ok], :3] = ground.C[ok].astype(np.uint8)
        img[py[ok], px[ok], 3] = 235

    px = np.floor(sx + ax).astype(int)
    py = np.floor(sy + ay).astype(int)
    ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
    px, py, dep, cc = px[ok], py[ok], depth[ok], col[ok]
    lin = py * W + px
    order = np.argsort(-dep, kind="stable")
    u, first = np.unique(lin[order], return_index=True)
    sel = order[first]
    flat = img.reshape(-1, 4)
    flat[u, :3] = cc[sel].astype(np.uint8)
    flat[u, 3] = 255
    D.reshape(-1)[u] = dep[sel]
    mask.reshape(-1)[u] = True

    if edges:
        dark = np.zeros((H, W), bool)
        for dy_, dx_ in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nb = np.roll(np.roll(D, dy_, 0), dx_, 1)
            nbm = np.roll(np.roll(mask, dy_, 0), dx_, 1)
            dark |= mask & nbm & (nb - D > 0.15)
        rgb = img[..., :3].astype(float)
        rgb[dark] *= 0.68
        img[..., :3] = rgb.astype(np.uint8)

    if outline:
        dil = mask.copy()
        dil[1:, :] |= mask[:-1, :]
        dil[:-1, :] |= mask[1:, :]
        dil[:, 1:] |= mask[:, :-1]
        dil[:, :-1] |= mask[:, 1:]
        ring = dil & ~mask
        img[ring] = (*OUTLINE, 255)
    return img, anchor


def noise2(h, w, scale, seed):
    """Smooth value noise in [0,1] of shape (h,w), feature size `scale` px."""
    rng = np.random.default_rng(seed)
    gh, gw = int(h / scale) + 3, int(w / scale) + 3
    g = rng.random((gh, gw))
    y = np.arange(h) / scale
    x = np.arange(w) / scale
    y0 = np.floor(y).astype(int)
    x0 = np.floor(x).astype(int)
    fy = y - y0
    fx = x - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return (top + (bot - top) * fy[:, None]).astype(np.float32)


def hash01(*vals):
    v = np.zeros_like(np.asarray(vals[0], float))
    for i, x in enumerate(vals):
        v = v + np.asarray(x, float) * (12.9898 + 31.7 * i)
    return np.abs(np.sin(v) * 43758.5453) % 1.0
