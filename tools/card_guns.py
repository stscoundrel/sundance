"""The loadout card's guns: each gun the stranger can choose, modelled finer and at its
true proportions for the picture on its card. In play the same guns are a few pixels
in a man's hands and drawn oversized to read at a glance (chars.weapon_model); here,
baked at the card's own pixels, there is room for the fluted cylinder, the lever, the
bands and the grain of the stock.

Every gun is laid out on its own axes: x from the butt to the muzzle (its length about
GUN_LEN), y up from the bore, z towards its right side. The card shows its left side.
"""
import math
import numpy as np
from render3d import Cloud, frustum, ellipsoid, quad

STEEL = (70, 72, 78)
BLUED = (66, 72, 92)
BRIGHT = (172, 176, 184)       # armory bright: the musket's barrel and bands
BRASS = (205, 165, 70)
GILT = (232, 186, 72)          # the Winchester's and the Henry's gunmetal brass
IVORY = (214, 198, 164)
WALNUT = (122, 76, 44)
DARK = (92, 58, 36)            # the escopeta's old stock
END_GRAIN = (168, 120, 78)     # where a saw went through the wood
BORE = (20, 16, 14)


def case_hardened(P, N):
    """Colour-case hardening: the frame's mottle of straw, blue and plum, in patches."""
    k = (np.sin(P[:, 0] * 260 + P[:, 2] * 410) + np.sin(P[:, 1] * 330 - P[:, 2] * 190)
         + np.sin((P[:, 0] + P[:, 1]) * 610 + P[:, 2] * 150)) / 3
    straw, blue, plum = np.array([176, 150, 106.0]), np.array([104, 118, 150.0]), np.array([146, 112, 134.0])
    t = np.clip(k * 0.5 + 0.5, 0, 1)[:, None]
    return np.where(t < 0.5, straw * (1 - 2 * t) + blue * 2 * t, blue * (2 - 2 * t) + plum * (2 * t - 1))


class Gun:
    """A gun built on its own axes (see the module's note)."""

    def __init__(self, butt, a, side, up):
        self.o, self.a, self.s, self.u = butt, a, side, up
        self.out = Cloud()

    def p(self, x, y, z=0.0):
        return self.o + self.a * x + self.u * y + self.s * z

    def wood(self, base):
        """Walnut with its grain running along the gun, wavering."""
        base = np.array(base, float)
        a, u = self.a, self.u

        def f(P, N):
            s, q = P @ a, P @ u
            k = 0.93 + 0.09 * np.sin(s * 150 + 2.4 * np.sin(s * 21 + q * 170))
            return base * k[:, None]
        return f

    def rod(self, p0, p1, r, color, r1=None):
        self.out += frustum(self.p(*p0), self.p(*p1), r, r if r1 is None else r1, color)

    def line(self, pts, r, color):
        for q0, q1 in zip(pts, pts[1:]):
            self.rod(q0, q1, r, color)

    def ball(self, c, r, color):
        self.out += ellipsoid(self.p(*c), (r, r, r), color)

    def box(self, x0, y0, z0, x1, y1, z1, color):
        """A box squared to the gun, not to the world."""
        a, u, s = self.a, self.u, self.s
        ex, ey, ez = a * (x1 - x0), u * (y1 - y0), s * (z1 - z0)
        o, f = self.p(x0, y0, z0), self.p(x1, y1, z1)
        for q, e1, e2, n in ((o, ex, ey, -s), (f, -ex, -ey, s), (o, ex, ez, -u), (f, -ex, -ez, u),
                             (o, ey, ez, -a), (f, -ey, -ez, a)):
            self.out += quad(q, e1, e2, color, normal=n)

    def octagon(self, x0, x1, y, r, color):
        """An octagonal barrel, its flats catching the light each their own way."""
        for k in range(8):
            t0, t1, tn = (k - 0.5) * math.pi / 4, (k + 0.5) * math.pi / 4, k * math.pi / 4
            c0 = self.p(x0, y + r * math.cos(t0), r * math.sin(t0))
            c1 = self.p(x0, y + r * math.cos(t1), r * math.sin(t1))
            self.out += quad(c0, self.a * (x1 - x0), c1 - c0, color,
                             normal=self.u * math.cos(tn) + self.s * math.sin(tn))
        self.rod((x0, y), (x0 + 0.001, y), r * 0.92, color)
        self.rod((x1 - 0.001, y), (x1, y), r * 0.92, color)

    def bore(self, x, y, r, z=0.0):
        """The dark of the muzzle."""
        self.rod((x, y, z), (x + 0.0006, y, z), r, BORE)

    def slab(self, x0, x1, top, bottom, half, color):
        """Wood between two edges: top and bottom are (x, y) polylines, half its
        thickness each side (a number, or (x, half) pairs to taper it)."""
        tx, ty = np.array(top, float).T
        bx, by = np.array(bottom, float).T
        n = max(8, int((x1 - x0) / 0.0035))
        for x in np.linspace(x0, x1, n):
            yt, yb = np.interp(x, tx, ty), np.interp(x, bx, by)
            h = half if np.isscalar(half) else np.interp(x, *np.array(half, float).T)
            self.rod((x, yt), (x, yb), h, color)

    def guard(self, x0, x1, y, depth, r, color):
        """A trigger guard: a loop hung under the frame from x0 back to x1."""
        pts = []
        for i in range(13):
            t = i / 12 * math.pi
            pts.append((x0 + (x1 - x0) * (1 - math.cos(t)) / 2 - 0.004 * math.sin(t) ** 2, y - depth * math.sin(t)))
        self.line(pts, r, color)

    def trigger(self, x, y, length, color=STEEL):
        self.line([(x, y), (x - 0.002, y - length * 0.6), (x - 0.006, y - length)], 0.0022, color)

    def hammer(self, x, y, h, back, color, z=0.0, r=0.004):
        """A hammer rising from the frame at x, its spur reaching back."""
        self.line([(x, y, z), (x - 0.002, y + h * 0.7, z), (x - back, y + h, z)], r, color)

    def screw(self, x, y, z, color=(44, 44, 50)):
        self.ball((x, y, z), 0.0024, color)

    def sight(self, x, y, h, color=STEEL):
        self.box(x - 0.004, y, -0.0012, x + 0.002, y + h, 0.0012, color)


# ------------------------------------------------------------------- revolvers

def _plow_grip(g, bx, by, fx, fy, panel, strap):
    """The plow-handle grip: straps front and back, the panel between, flaring back at the butt."""
    back = [(bx - 0.03 * t - 0.015 * t ** 3, by - 0.106 * t) for t in np.linspace(0, 1, 24)]
    front = [(fx - 0.012 * t - 0.006 * t * t, fy - 0.064 * t) for t in np.linspace(0, 1, 24)]
    for (x0, y0), (x1, y1) in zip(back, front):
        g.rod((x0 + (x1 - x0) * 0.1, y0 + (y1 - y0) * 0.1), (x0 + (x1 - x0) * 0.9, y0 + (y1 - y0) * 0.9), 0.0135, panel)
    g.line(back, 0.0042, strap)
    g.line(front, 0.0036, strap)
    g.rod(back[-1], front[-1], 0.006, strap)                                     # the butt
    g.screw(bx - 0.022, by - 0.066, -0.0138, (150, 120, 70))


def _cylinder(g, x0, x1, y, r, color, flutes=True):
    g.rod((x0, y), (x1, y), r, color)
    if flutes:
        for i in range(6):
            ang = (i + 0.5) / 6 * 2 * math.pi
            c, s = math.cos(ang), math.sin(ang)
            g.rod((x0 + 0.006, y + 0.95 * r * c, 0.95 * r * s), (x1 - 0.008, y + 0.95 * r * c, 0.95 * r * s),
                  0.0035, (40, 42, 54))
    else:   # the chambers' nipples at the back, behind their shields
        for i in range(6):
            ang = i / 6 * 2 * math.pi
            g.rod((x0 - 0.003, y + 0.6 * r * math.cos(ang), 0.6 * r * math.sin(ang)), (x0, y + 0.6 * r * math.cos(ang),
                  0.6 * r * math.sin(ang)), 0.0025, STEEL)


def _saa(g, muzzle, grip):
    """The Colt Single Action Army: the frame, cylinder and grip, a barrel to `muzzle`."""
    g.rod((0.145, 0), (muzzle, 0), 0.0078, BLUED)
    g.sight(muzzle - 0.006, 0.0068, 0.0058, BLUED)
    g.bore(muzzle, 0, 0.0045)
    g.rod((0.15, -0.0125), (0.26, -0.0125), 0.0052, BLUED)                     # ejector housing
    g.ball((0.257, -0.0125, -0.006), 0.004, STEEL)                             # the rod's crescent head
    g.rod((0.14, -0.013), (0.152, -0.013), 0.0045, STEEL)                      # base pin
    _cylinder(g, 0.098, 0.142, -0.013, 0.0205, BLUED)
    g.box(0.062, -0.042, -0.0165, 0.098, 0.009, 0.0165, case_hardened)          # recoil shield
    g.box(0.098, 0.006, -0.009, 0.146, 0.012, 0.009, case_hardened)             # top strap
    g.box(0.098, -0.042, -0.012, 0.146, -0.033, 0.012, case_hardened)
    g.box(0.142, -0.022, -0.011, 0.152, 0.009, 0.011, case_hardened)
    for x, y in ((0.072, -0.012), (0.088, -0.03), (0.148, -0.03)):
        g.screw(x, y, -0.0168)
    g.hammer(0.066, 0.004, 0.026, 0.02, case_hardened)
    g.guard(0.062, 0.098, -0.042, 0.024, 0.0028, BLUED)
    g.trigger(0.082, -0.042, 0.014, case_hardened)
    _plow_grip(g, 0.06, -0.004, 0.064, -0.046, grip, BLUED)


def colt(g):
    """The stranger's Colt, ivory-gripped, with the seven-and-a-half-inch barrel."""
    _saa(g, 0.33, IVORY)


def buntline(g):
    """The Colt again, walnut-gripped, and the twelve-inch barrel running on and on."""
    _saa(g, 0.47, g.wood(WALNUT))


def schofield(g):
    """Smith & Wesson Schofield: all blued, the barrel's strap running back over the
    cylinder to the latch in front of the hammer, the hinge low at the front of the frame,
    the hump at the top of the backstrap."""
    g.rod((0.148, 0), (0.32, 0), 0.0076, BLUED)
    g.box(0.148, 0.004, -0.0028, 0.32, 0.0098, 0.0028, BLUED)                  # the rib along the top
    g.ball((0.314, 0.012, 0), 0.0035, BLUED)                                   # half-moon front sight
    g.bore(0.32, 0, 0.0045)
    g.rod((0.148, -0.0115), (0.24, -0.0115), 0.0058, BLUED)                    # extractor shroud
    _cylinder(g, 0.1, 0.144, -0.013, 0.0205, BLUED)
    g.box(0.064, -0.042, -0.0165, 0.1, 0.004, 0.0165, BLUED)
    g.box(0.096, 0.004, -0.008, 0.152, 0.011, 0.008, BLUED)                    # the barrel's strap
    g.box(0.086, 0.004, -0.007, 0.1, 0.019, 0.007, STEEL)                      # the stirrup latch
    g.box(0.1, -0.042, -0.012, 0.152, -0.033, 0.012, BLUED)
    g.box(0.144, -0.04, -0.011, 0.156, -0.004, 0.011, BLUED)
    g.ball((0.152, -0.036, -0.012), 0.004, STEEL)                              # the hinge
    for x, y in ((0.075, -0.014), (0.09, -0.032)):
        g.screw(x, y, -0.0168)
    g.hammer(0.068, 0.004, 0.024, 0.018, BLUED)
    g.guard(0.064, 0.1, -0.042, 0.026, 0.003, BLUED)
    g.trigger(0.084, -0.042, 0.015, BLUED)
    _plow_grip(g, 0.06, -0.006, 0.066, -0.046, g.wood((110, 72, 44)), BLUED)
    g.ball((0.058, 0.0, 0), 0.0085, BLUED)                                     # the hump


def navy(g):
    """Colt Navy 1851: an open top over the plain cylinder, the frame and trigger guard
    in brass, the octagon barrel on its lug with the loading lever folded under it."""
    g.octagon(0.15, 0.34, 0, 0.0085, BLUED)
    g.ball((0.334, 0.009, 0), 0.0028, BRASS)                                   # brass bead
    g.bore(0.34, 0, 0.0048)
    g.box(0.145, -0.032, -0.0095, 0.18, -0.004, 0.0095, BLUED)                 # the barrel lug
    g.box(0.155, -0.022, -0.0105, 0.162, -0.012, 0.0105, STEEL)                # the wedge through it
    g.line([(0.17, -0.034), (0.2, -0.016), (0.29, -0.014)], 0.0038, case_hardened)   # loading lever
    g.ball((0.29, -0.014, 0), 0.004, STEEL)                                    # its catch
    _cylinder(g, 0.1, 0.145, -0.013, 0.0205, (78, 84, 104), flutes=False)
    g.rod((0.103, -0.013 + 0.0206), (0.142, -0.013 + 0.0206), 0.0012, (110, 118, 140))   # roll-engraving's glint
    g.box(0.064, -0.042, -0.0165, 0.1, -0.002, 0.0165, BRASS)                  # the frame, open above
    g.box(0.1, -0.042, -0.012, 0.15, -0.033, 0.012, BRASS)
    for x, y in ((0.076, -0.014), (0.09, -0.032)):
        g.screw(x, y, -0.0168)
    g.hammer(0.068, 0.0, 0.03, 0.02, case_hardened)
    g.guard(0.064, 0.1, -0.042, 0.024, 0.003, BRASS)
    g.trigger(0.084, -0.042, 0.014)
    _plow_grip(g, 0.062, -0.006, 0.066, -0.046, g.wood(WALNUT), BRASS)


def pistola(g):
    """A percussion horse pistol: the bird's-head grip with its brass cap, the stock run
    up a round barrel to a brass band, the hammer on the lock, the swivel ramrod."""
    w = g.wood(WALNUT)
    # the grip, curving down and back, and the fore-stock along under the barrel
    g.slab(0.02, 0.17, [(0.02, -0.096), (0.06, -0.078), (0.1, -0.03), (0.17, -0.002)],
           [(0.02, -0.118), (0.06, -0.126), (0.1, -0.094), (0.13, -0.044), (0.17, -0.026)], 0.014, w)
    g.slab(0.16, 0.38, [(0.16, -0.002), (0.38, -0.002)], [(0.16, -0.026), (0.38, -0.02)],
           [(0.16, 0.014), (0.38, 0.011)], w)
    g.line([(0.016, -0.094), (0.016, -0.112), (0.03, -0.126), (0.06, -0.13)], 0.008, BRASS)   # butt cap
    g.rod((0.12, 0), (0.46, 0), 0.0092, (150, 152, 160), 0.0082)
    g.bore(0.46, 0, 0.006)
    g.rod((0.322, -0.006), (0.336, -0.006), 0.0145, BRASS)                     # the band
    g.box(0.1, -0.024, -0.0145, 0.15, -0.008, -0.011, BRASS)                   # side plate, the lock's on his right
    g.screw(0.11, -0.016, -0.015)
    g.screw(0.14, -0.016, -0.015)
    g.box(0.124, 0.002, -0.004, 0.134, 0.012, 0.004, STEEL)                    # the bolster and nipple
    g.line([(0.098, -0.004, 0.006), (0.1, 0.018, 0.006), (0.112, 0.03, 0.006), (0.128, 0.022, 0.006),
            (0.13, 0.014, 0.006)], 0.0042, case_hardened)                       # the hammer, down on the nipple
    g.guard(0.09, 0.15, -0.024, 0.028, 0.003, BRASS)
    g.trigger(0.118, -0.024, 0.016)
    g.rod((0.17, -0.02), (0.45, -0.016), 0.0032, STEEL)                        # the ramrod
    g.ball((0.45, -0.016, 0), 0.0045, STEEL)



def derringer(g):
    """Remington double derringer: the two barrels stacked one over the other with the
    rib down their side, hinged at the top to flip up, the spur trigger with no guard,
    one hammer for both, and the bird's-head grip in pearl."""
    for y in (0.0, -0.019):
        g.rod((0.07, y), (0.2, y), 0.0094, BLUED)
        g.bore(0.2, y, 0.0052)
    g.box(0.07, -0.012, -0.0105, 0.2, -0.007, -0.0094, BLUED)                  # the rib between, each side
    g.box(0.07, -0.012, 0.0094, 0.2, -0.007, 0.0105, BLUED)
    g.box(0.07, 0.008, -0.002, 0.2, 0.012, 0.002, BLUED)                       # the top rib
    g.ball((0.07, 0.012, -0.004), 0.0036, STEEL)                               # the hinge
    g.box(0.03, -0.034, -0.011, 0.072, 0.006, 0.011, BLUED)                    # the frame
    g.box(0.038, -0.026, -0.0118, 0.06, -0.016, -0.011, STEEL)                 # the locking lever
    g.screw(0.05, -0.006, -0.0116)
    g.hammer(0.034, 0.0, 0.022, 0.016, BLUED)
    g.line([(0.05, -0.034), (0.048, -0.042), (0.044, -0.048)], 0.0026, STEEL)   # the spur trigger
    pearl = (226, 220, 206)
    g.slab(-0.024, 0.036, [(-0.024, -0.034), (-0.01, -0.012), (0.036, -0.004)],
           [(-0.024, -0.07), (-0.014, -0.086), (0.002, -0.09), (0.014, -0.074), (0.026, -0.05), (0.036, -0.036)],
           0.0115, pearl)
    g.line([(0.02, -0.005), (-0.01, -0.012), (-0.022, -0.03), (-0.026, -0.06), (-0.016, -0.084),
            (0.002, -0.091)], 0.0034, BLUED)                                     # the backstrap, round the bird's head
    g.screw(0.004, -0.046, -0.012)


def howdah(g):
    """A howdah pistol: a double shotgun's action shrunk to a hand, two fat .577 barrels
    side by side, the hammers on their locks, two triggers, and a walnut grip curved
    down to a steel butt cap with its lanyard ring."""
    w = g.wood(WALNUT)
    g.slab(0.0, 0.11, [(0.0, -0.062), (0.05, -0.03), (0.11, -0.008)],
           [(0.0, -0.11), (0.03, -0.12), (0.06, -0.09), (0.09, -0.056), (0.11, -0.046)], 0.015, w)
    g.line([(-0.002, -0.06), (-0.004, -0.09), (0.004, -0.114), (0.03, -0.122)], 0.0055, STEEL)   # butt cap
    g.rod((0.008, -0.118, 0), (0.008, -0.13, 0), 0.006, STEEL)                 # the lanyard ring
    _double(g, 0.15, 0.44, 0.08)


# ------------------------------------------------------------------- shotguns

def _butt(g, x1, comb, wrist, toe, color, plate=None, crescent=False):
    """A buttstock from the butt plate at x=0 to the frame at x1: comb is the heel's
    height, toe the toe's, wrist the (top, bottom) at the hand."""
    top = [(0.0, comb), (x1 - 0.06, wrist[0]), (x1, wrist[0] + 0.004)]
    bottom = [(0.0, toe), (x1 - 0.1, wrist[1] - 0.004), (x1 - 0.06, wrist[1]), (x1, wrist[1] + 0.002)]
    g.slab(0.004, x1, top, bottom, [(0.0, 0.021), (x1 - 0.08, 0.015), (x1, 0.014)], color)
    if plate is not None:
        if crescent:   # the crescent butt plate's horns
            pts = [(0.012 * ((y - (comb + toe) / 2) / ((comb - toe) / 2)) ** 2 - 0.004, y)
                   for y in np.linspace(comb, toe, 12)]
        else:
            pts = [(0.0, comb), (0.0, toe)]
        g.line(pts, 0.006, plate)


def _double(g, x_frame, x_muzzle, fore_end):
    """The side-by-side's action and barrels: the case-hardened locks and two hammers,
    the barrels side by side with the rib between, a splinter fore-end under them."""
    for z in (0.0102, -0.0102):
        g.rod((x_frame + 0.04, 0, z), (x_muzzle, 0, z), 0.0102, BLUED, 0.0095)
        g.bore(x_muzzle, 0, 0.0072, z)
    g.box(x_frame + 0.04, 0.006, -0.004, x_muzzle, 0.012, 0.004, BLUED)        # the rib
    g.ball((x_muzzle - 0.006, 0.0135, 0), 0.0028, BRASS)                       # bead
    g.box(x_frame, -0.045, -0.018, x_frame + 0.045, 0.004, 0.018, case_hardened)
    g.box(x_frame - 0.06, -0.034, -0.0195, x_frame + 0.004, -0.008, -0.016, case_hardened)   # the lock plate
    g.screw(x_frame - 0.03, -0.022, -0.0198)
    for z in (0.012, -0.012):
        g.hammer(x_frame - 0.012, -0.012, 0.03, 0.02, case_hardened, z=z, r=0.0042)
    g.ball((x_frame + 0.044, -0.01, -0.012), 0.004, STEEL)                     # the hinge pin's head
    g.box(x_frame + 0.004, 0.004, -0.004, x_frame + 0.02, 0.012, 0.004, STEEL)   # the top lever
    g.slab(x_frame + 0.045, x_frame + 0.045 + fore_end, [(x_frame, -0.006), (x_frame + 0.3, -0.006)],
           [(x_frame, -0.04), (x_frame + 0.045 + fore_end, -0.028)], 0.016, g.wood(WALNUT))
    g.guard(x_frame - 0.05, x_frame + 0.01, -0.045, 0.026, 0.003, STEEL)
    g.trigger(x_frame - 0.02, -0.045, 0.016)
    g.trigger(x_frame - 0.008, -0.045, 0.016)


def coach(g):
    """A double-barrelled coach gun: the straight walnut stock, the two hammers."""
    _butt(g, 0.31, -0.012, (-0.024, -0.058), -0.13, g.wood(WALNUT), STEEL)
    _double(g, 0.31, 0.97, 0.2)


def sawnoff(g):
    """The double gun cut down: the stock sawn off behind the hand, the barrels stubby."""
    w = g.wood(WALNUT)
    g.slab(0.13, 0.27, [(0.13, -0.034), (0.27, -0.016)], [(0.13, -0.106), (0.2, -0.074), (0.27, -0.054)], 0.015, w)
    g.slab(0.126, 0.132, [(0.12, -0.034), (0.14, -0.034)], [(0.12, -0.106), (0.14, -0.106)], 0.015, END_GRAIN)
    _double(g, 0.27, 0.6, 0.14)


def champion(g):
    """Johnson & Bye Champion: plain walnut, one long barrel on a case-hardened frame, the
    side lever that snaps it open, one hammer."""
    _butt(g, 0.32, -0.012, (-0.024, -0.058), -0.13, g.wood(WALNUT), STEEL)
    g.rod((0.36, 0), (1.15, 0), 0.0112, BLUED, 0.0098)
    g.bore(1.15, 0, 0.0075)
    g.ball((1.144, 0.013, 0), 0.0028, BRASS)
    g.box(0.32, -0.045, -0.016, 0.365, 0.006, 0.016, case_hardened)
    g.line([(0.35, -0.02, -0.018), (0.33, -0.036, -0.018), (0.29, -0.042, -0.018)], 0.0032, case_hardened)   # snap lever
    g.ball((0.35, -0.02, -0.018), 0.004, STEEL)
    g.hammer(0.322, -0.002, 0.026, 0.02, case_hardened, r=0.0045)
    g.slab(0.365, 0.56, [(0.36, -0.009), (0.56, -0.009)], [(0.36, -0.03), (0.56, -0.02)], 0.013, g.wood(WALNUT))
    g.guard(0.27, 0.33, -0.045, 0.026, 0.003, STEEL)
    g.trigger(0.305, -0.045, 0.016)


def colt55(g):
    """Colt 1855 revolving shotgun: a walnut butt to the open-top frame and side hammer,
    the fat five-shot cylinder, the long round barrel on its lug with the loading lever
    folded under it, a short fore-end, the brass trigger guard."""
    w = g.wood(WALNUT)
    _butt(g, 0.27, -0.012, (-0.024, -0.058), -0.13, w, BRASS)
    g.box(0.27, -0.046, -0.015, 0.31, 0.004, 0.015, BLUED)                     # frame
    g.box(0.31, -0.046, -0.012, 0.44, -0.034, 0.012, BLUED)                    # under the cylinder
    _cylinder(g, 0.312, 0.43, -0.004, 0.03, (78, 84, 104), flutes=False)
    g.box(0.43, -0.03, -0.011, 0.47, 0.0, 0.011, BLUED)                        # the barrel lug
    g.rod((0.43, 0.006), (1.05, 0.006), 0.0108, BLUED, 0.0098)
    g.bore(1.05, 0.006, 0.0074)
    g.ball((1.044, 0.019, 0), 0.0028, BRASS)
    g.line([(0.45, -0.03), (0.52, -0.016), (0.72, -0.012)], 0.0038, case_hardened)   # loading lever
    g.ball((0.72, -0.012, 0), 0.004, STEEL)
    g.slab(0.47, 0.64, [(0.47, -0.006), (0.64, -0.006)], [(0.47, -0.03), (0.64, -0.024)], 0.013, w)
    g.hammer(0.29, 0.002, 0.026, 0.02, case_hardened)
    g.guard(0.25, 0.31, -0.046, 0.024, 0.003, BRASS)
    g.trigger(0.285, -0.046, 0.016)


def spencer82(g):
    """Spencer 1882 slide-action: a deep blued frame with the port on top the empties fly
    out of, one long barrel, the tube under it and on the tube the ribbed wooden slide."""
    _butt(g, 0.31, -0.014, (-0.026, -0.064), -0.135, g.wood(WALNUT), STEEL)
    g.box(0.31, -0.06, -0.017, 0.44, 0.012, 0.017, BLUED)
    g.box(0.34, 0.006, -0.0172, 0.4, 0.0125, -0.006, (24, 22, 26))            # the ejection port
    for x in (0.33, 0.42):
        g.screw(x, -0.03, -0.0175)
    g.rod((0.44, 0), (1.02, 0), 0.0105, BLUED, 0.0098)
    g.bore(1.02, 0, 0.0072)
    g.ball((1.014, 0.0125, 0), 0.0028, BRASS)
    g.rod((0.44, -0.021), (0.86, -0.021), 0.0078, BLUED)                       # magazine tube
    g.rod((0.86, -0.021), (0.872, -0.021), 0.0085, STEEL)                      # its cap
    w = g.wood(WALNUT)
    g.rod((0.5, -0.021), (0.7, -0.021), 0.0155, w)                             # the slide
    for x in np.arange(0.512, 0.7, 0.012):
        g.rod((x, -0.021), (x + 0.0035, -0.021), 0.0159, (70, 42, 26))        # its ribs
    g.guard(0.29, 0.35, -0.06, 0.024, 0.003, BLUED)
    g.trigger(0.33, -0.06, 0.014)


def escopeta(g):
    """The escopeta: an old miquelet-lock fowling piece, a dark slender stock run far up
    the long barrel, brass butt plate and bands, the cock and frizzen up on the lock."""
    w = g.wood(DARK)
    g.slab(0.004, 0.26, [(0.0, -0.016), (0.2, -0.026), (0.26, -0.012)],
           [(0.0, -0.118), (0.16, -0.06), (0.26, -0.03)], [(0.0, 0.019), (0.2, 0.013), (0.26, 0.013)], w)
    g.line([(0.0, -0.016), (0.0, -0.118)], 0.006, BRASS)
    g.slab(0.25, 0.98, [(0.25, -0.004), (0.98, -0.004)], [(0.25, -0.03), (0.98, -0.018)],
           [(0.25, 0.014), (0.98, 0.011)], w)
    g.octagon(0.22, 0.42, 0, 0.0108, (84, 84, 92))                             # the breech, octagonal
    g.rod((0.42, 0), (1.3, 0), 0.0095, (84, 84, 92), 0.0085)
    g.bore(1.3, 0, 0.006)
    for x in (0.62, 0.84, 0.97):
        g.rod((x, -0.007), (x + 0.012, -0.007), 0.0155, BRASS)
    g.box(0.2, -0.026, -0.0145, 0.29, -0.008, -0.011, BRASS)                   # side plate
    # the miquelet lock stands up on his right: the cock gripping its flint, the frizzen ahead
    g.line([(0.224, -0.004, 0.012), (0.226, 0.02, 0.012), (0.236, 0.034, 0.012)], 0.0045, STEEL)
    g.box(0.232, 0.03, 0.008, 0.248, 0.038, 0.016, (60, 60, 64))               # the flint in its jaws
    g.line([(0.268, 0.004, 0.012), (0.264, 0.036, 0.012)], 0.0048, STEEL)      # the frizzen
    g.guard(0.2, 0.27, -0.03, 0.026, 0.003, BRASS)
    g.trigger(0.236, -0.03, 0.016)
    g.rod((0.3, -0.024), (1.28, -0.02), 0.0035, (176, 132, 88))                # a wooden ramrod


# ------------------------------------------------------------------- rifles

def _lever(g, x0, y, color=BLUED):
    """The lever: a loop for the fingers behind the trigger."""
    g.line([(x0 + 0.1, y), (x0 + 0.08, y - 0.016), (x0 + 0.04, y - 0.018), (x0 + 0.012, y - 0.022),
            (x0 - 0.004, y - 0.04), (x0 + 0.01, y - 0.058), (x0 + 0.04, y - 0.056), (x0 + 0.04, y - 0.022)],
           0.0036, color)


def _winchester_action(g, x0, x1):
    """The brass frame of the Henry and the Winchester, the hammer, the lever."""
    g.box(x0, -0.058, -0.0165, x1, 0.008, 0.0165, GILT)
    g.rod((x0, 0.0035), (x1, 0.0035), 0.016, GILT)                            # the round of its top
    for x, y in ((x0 + 0.03, -0.022), (x0 + 0.1, -0.02), (x0 + 0.06, -0.044)):
        g.screw(x, y, -0.0168, (110, 90, 46))
    g.hammer(x0 + 0.006, 0.012, 0.024, 0.016, case_hardened, r=0.0042)
    g.trigger(x0 + 0.03, -0.058, 0.014)
    _lever(g, x0, -0.058)


def rifle(g):
    """Winchester 1866, the Yellow Boy: the brass frame, the crescent butt plate, the
    octagon barrel and the magazine under it, the walnut fore-end with its cap."""
    _butt(g, 0.29, -0.01, (-0.022, -0.056), -0.125, g.wood(WALNUT), GILT, crescent=True)
    _winchester_action(g, 0.29, 0.44)
    g.octagon(0.44, 1.1, 0, 0.0088, BLUED)
    g.bore(1.1, 0, 0.0052)
    g.sight(1.09, 0.008, 0.006)
    g.box(0.54, 0.007, -0.004, 0.58, 0.014, 0.004, BLUED)                     # the rear sight's ladder
    g.rod((0.44, -0.019), (1.07, -0.019), 0.0068, BLUED)
    g.rod((1.07, -0.019), (1.08, -0.019), 0.0072, STEEL)
    g.slab(0.44, 0.72, [(0.44, -0.004), (0.72, -0.004)], [(0.44, -0.034), (0.72, -0.03)], 0.015, g.wood(WALNUT))
    g.rod((0.715, -0.016), (0.735, -0.016), 0.0165, BLUED)                     # fore-end cap


def henry(g):
    """Henry 1860: the brass frame like the Winchester's but no fore-end: the octagon barrel
    and the magazine under it are one slotted piece, the follower's brass tab in the slot,
    the sleeve at the muzzle."""
    _butt(g, 0.29, -0.01, (-0.022, -0.056), -0.125, g.wood((128, 80, 46)), GILT, crescent=True)
    _winchester_action(g, 0.29, 0.44)
    g.octagon(0.44, 1.12, 0, 0.0092, BLUED)
    g.bore(1.12, 0, 0.0052)
    g.sight(1.11, 0.0085, 0.006)
    g.box(0.54, 0.0075, -0.004, 0.58, 0.015, 0.004, BLUED)
    g.rod((0.44, -0.019), (1.08, -0.019), 0.0094, BLUED)                       # the magazine
    g.box(0.47, -0.0215, -0.0101, 1.04, -0.0165, -0.0085, (24, 22, 26))         # its slot
    g.box(0.6, -0.023, -0.012, 0.612, -0.015, -0.007, BRASS)                   # the follower's tab
    g.rod((1.05, -0.019), (1.1, -0.019), 0.0102, STEEL)                        # the sleeve
    g.ball((0.86, -0.04, -0.004), 0.0045, STEEL)                               # sling swivel


def spencer(g):
    """Spencer carbine: walnut butt with the magazine tube's brass cap at its heel, a dark
    case-hardened receiver, the lever that is its trigger guard, a short fore-end, one
    band, and the saddle-ring bar along its left."""
    w = g.wood((104, 64, 40))
    _butt(g, 0.3, -0.012, (-0.024, -0.058), -0.122, w, STEEL)
    g.ball((0.0, -0.034, 0), 0.0085, BRASS)                                    # the tube's cap
    g.box(0.3, -0.06, -0.017, 0.43, 0.006, 0.017, case_hardened)
    g.rod((0.3, 0.0), (0.43, 0.0), 0.016, case_hardened)
    for x, y in ((0.32, -0.03), (0.4, -0.03)):
        g.screw(x, y, -0.0175)
    g.hammer(0.318, 0.004, 0.026, 0.018, case_hardened, z=0.008, r=0.0045)    # the side hammer, on his right
    g.rod((0.24, -0.03, -0.019), (0.36, -0.03, -0.019), 0.0028, STEEL)         # saddle-ring bar
    ring = [(0.3 + 0.012 * math.cos(t), -0.03 - 0.012 - 0.012 * math.sin(t), -0.021) for t in np.linspace(0, 2 * math.pi, 18)]
    g.line(ring, 0.0018, STEEL)
    g.line([(0.43, -0.06), (0.4, -0.068), (0.36, -0.074), (0.33, -0.09), (0.3, -0.086), (0.31, -0.07),
            (0.34, -0.064), (0.3, -0.06)], 0.0036, case_hardened)               # the lever
    g.trigger(0.36, -0.06, 0.012)
    g.rod((0.43, 0), (1.0, 0), 0.0098, BLUED, 0.009)
    g.bore(1.0, 0, 0.0055)
    g.sight(0.99, 0.009, 0.006)
    g.box(0.45, 0.009, -0.005, 0.5, 0.017, 0.005, BLUED)                       # the rear sight
    g.slab(0.43, 0.68, [(0.43, -0.004), (0.68, -0.004)], [(0.43, -0.03), (0.68, -0.024)], 0.014, w)
    g.rod((0.645, -0.008), (0.66, -0.008), 0.0175, STEEL)                      # the band


def _full_stock(g, x0, x1, top, bottom, color):
    g.slab(x0, x1, [(x0, top), (x1, top)], [(x0, bottom), (x1, bottom + 0.008)], [(x0, 0.015), (x1, 0.011)], color)


def springfield(g):
    """Springfield 1861 rifle-musket: a long full stock nearly to the muzzle, three bands
    and the barrel in armory bright, the ramrod under it, the lock's hammer up."""
    w = g.wood(WALNUT)
    _butt(g, 0.3, -0.012, (-0.024, -0.056), -0.124, w, BRIGHT)
    _full_stock(g, 0.3, 1.32, -0.004, -0.032, w)
    g.rod((0.24, 0), (1.45, 0), 0.0115, BRIGHT, 0.0085)
    g.bore(1.45, 0, 0.0058)
    g.sight(1.38, 0.0085, 0.006)
    g.box(0.34, 0.008, -0.005, 0.37, 0.017, 0.005, BRIGHT)                     # rear sight
    for x in (0.86, 1.08, 1.29):
        g.rod((x, -0.009), (x + 0.016, -0.009), 0.0175, BRIGHT)
    g.rod((0.4, -0.026), (1.44, -0.021), 0.0034, BRIGHT)                       # ramrod
    g.ball((1.44, -0.021, 0), 0.0048, BRIGHT)                                  # its trumpet head
    g.box(0.22, -0.026, -0.0155, 0.32, -0.01, -0.0115, BRIGHT)                 # side plate
    g.screw(0.24, -0.018, -0.016)
    g.screw(0.3, -0.018, -0.016)
    g.box(0.268, 0.002, 0.004, 0.282, 0.013, 0.012, BRIGHT)                    # the bolster
    g.line([(0.25, -0.006, 0.01), (0.252, 0.02, 0.01), (0.264, 0.03, 0.01), (0.276, 0.024, 0.01),
            (0.276, 0.016, 0.01)], 0.0046, BRIGHT)                              # the hammer, on his right
    g.guard(0.22, 0.3, -0.032, 0.026, 0.003, BRIGHT)
    g.trigger(0.26, -0.032, 0.016)
    g.ball((0.31, -0.045, 0), 0.004, BRIGHT)                                   # sling swivels
    g.ball((1.08, -0.032, 0), 0.004, BRIGHT)


def _rolling_block(g, x0):
    """The Rolling Block's case-hardened action: the big hammer and, ahead of it, the
    breech block with the thumb-spur that rolls it back."""
    g.box(x0, -0.05, -0.016, x0 + 0.075, 0.006, 0.016, case_hardened)
    for x, y in ((x0 + 0.02, -0.018), (x0 + 0.05, -0.018)):
        g.screw(x, y, -0.0168)
    g.hammer(x0 + 0.02, 0.006, 0.03, 0.022, case_hardened, r=0.005)
    g.line([(x0 + 0.05, 0.004), (x0 + 0.052, 0.018), (x0 + 0.046, 0.024)], 0.004, case_hardened)   # block spur
    g.guard(x0 - 0.03, x0 + 0.04, -0.05, 0.024, 0.003, STEEL)
    g.trigger(x0 + 0.004, -0.05, 0.014)


def remington(g):
    """The Remington Rolling Block as the army has it: the full stock, the action, a long
    barrel in a fore-end banded nearly to the muzzle, the ramrod under it."""
    w = g.wood(WALNUT)
    _butt(g, 0.29, -0.012, (-0.024, -0.056), -0.124, w, STEEL)
    _rolling_block(g, 0.29)
    _full_stock(g, 0.365, 1.16, -0.004, -0.032, w)
    g.rod((0.365, 0), (1.3, 0), 0.0105, BLUED, 0.0088)
    g.bore(1.3, 0, 0.0055)
    g.sight(1.29, 0.0085, 0.006)
    g.box(0.42, 0.009, -0.005, 0.47, 0.018, 0.005, BLUED)
    for x in (0.86, 1.13):
        g.rod((x, -0.009), (x + 0.016, -0.009), 0.0172, STEEL)
    g.rod((0.4, -0.026), (1.29, -0.021), 0.0034, STEEL)
    g.ball((1.29, -0.021, 0), 0.0045, STEEL)



def sharps(g):
    """Sharps 1874, the buffalo gun: a heavy octagon barrel, the case-hardened frame
    with its side hammer and the lever under it that drops the block, a short
    fore-end with its pewter cap, the tall tang sight folded up behind the hammer."""
    w = g.wood(WALNUT)
    _butt(g, 0.3, -0.01, (-0.022, -0.056), -0.12, w, STEEL, crescent=True)
    g.box(0.3, -0.046, -0.017, 0.4, 0.008, 0.017, case_hardened)               # the frame
    for x, y in ((0.32, -0.02), (0.36, -0.03)):
        g.screw(x, y, -0.0178)
    g.hammer(0.33, 0.004, 0.03, 0.024, case_hardened, r=0.0052)
    g.box(0.268, 0.006, -0.0015, 0.276, 0.04, 0.0015, STEEL)                   # tang sight, up
    g.box(0.264, 0.034, -0.0035, 0.28, 0.04, 0.0035, STEEL)
    g.line([(0.4, -0.046), (0.39, -0.07), (0.35, -0.078), (0.31, -0.07), (0.3, -0.05)],
           0.0035, case_hardened)                                               # the lever, its loop for the hand
    g.trigger(0.36, -0.046, 0.014)
    g.slab(0.4, 0.66, [(0.4, -0.006), (0.66, -0.006)], [(0.4, -0.034), (0.66, -0.028)],
           [(0.4, 0.015), (0.66, 0.012)], w)                                    # fore-end
    g.rod((0.655, -0.017), (0.672, -0.017), 0.0145, (150, 150, 156))           # its pewter cap
    g.octagon(0.4, 1.32, 0, 0.0125, BLUED)
    g.bore(1.32, 0, 0.0062)
    g.sight(1.3, 0.012, 0.007)
    g.box(0.52, 0.012, -0.005, 0.57, 0.021, 0.005, BLUED)                      # rear sight on the barrel

def rollingblock(g):
    """A Rolling Block carbine cut down: the stock sawn to a pistol grip, the action, a
    short round barrel and a stub of fore-end."""
    w = g.wood(WALNUT)
    g.slab(0.12, 0.27, [(0.12, -0.034), (0.27, -0.016)], [(0.12, -0.104), (0.2, -0.074), (0.27, -0.054)], 0.015, w)
    g.slab(0.116, 0.122, [(0.11, -0.034), (0.13, -0.034)], [(0.11, -0.104), (0.13, -0.104)], 0.015, END_GRAIN)
    _rolling_block(g, 0.27)
    g.rod((0.345, 0), (0.72, 0), 0.0105, BLUED, 0.0095)
    g.bore(0.72, 0, 0.0055)
    g.sight(0.71, 0.009, 0.006)
    g.slab(0.345, 0.52, [(0.345, -0.004), (0.52, -0.004)], [(0.345, -0.03), (0.52, -0.024)], 0.014, w)


DETAILED = {k: f for k, f in globals().items() if k in (
    "colt", "buntline", "schofield", "navy", "howdah", "derringer", "pistola", "coach", "sawnoff", "champion", "spencer82", "escopeta", "colt55",
    "rifle", "henry", "spencer", "springfield", "remington", "sharps", "rollingblock")}


def model(kind, butt, a, side, up):
    """The card's model of `kind`, laid from `butt` along a, or None if it hasn't one."""
    if kind not in DETAILED:
        return None
    g = Gun(butt, a, side, up)
    DETAILED[kind](g)
    return g.out
