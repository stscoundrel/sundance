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
from render3d import render, noise2, PIX  # noqa: E402

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
    sheets = [("hero_colt", "hero", "colt"), ("hero_coach", "hero", "coach"),
              ("hero_rifle", "hero", "rifle"), ("pistolero", "pistolero", "colt"),
              ("rifleman", "rifleman", "rifle"), ("redscarf", "redscarf", "coach"),
              ("jefe", "jefe", "coach")]
    meta["chars"] = {}
    for key, spec, weapon in sheets:
        print("  character", key)
        path = save(chars.sheet(spec, weapon), f"sprites/chars/{key}.png")
        meta["chars"][key] = {"file": path, "cell": list(chars.CELL), "anchor": list(chars.ANCHOR),
                              "cols": len(chars.COLS), "rows": 8, "anims": chars.anims()}


def gen_world(meta):
    meta["objects"] = {}
    for name, (fn, fp, collide, fade, colliders) in world.BUILDINGS.items():
        print("  object", name)
        img, anchor = render(fn(), edges=True)
        path = save(img, f"sprites/world/{name}.png")
        meta["objects"][name] = {"file": path, "anchor": list(anchor), "footprint": list(fp),
                                 "collide": collide, "fade": fade,
                                 "colliders": colliders or [[0, 0, fp[0], fp[1]]]}
    frames = []
    for f in range(4):
        img, anchor = render(world.tumbleweed(f), size=(24 * PIX, 24 * PIX), anchor=(12 * PIX, 18 * PIX))
        frames.append(img)
    path = save(np.concatenate(frames, 1), "sprites/world/tumbleweed.png")
    meta["tumbleweed"] = {"file": path, "cell": [24 * PIX, 24 * PIX], "anchor": [12 * PIX, 18 * PIX], "frames": 4}


def gen_ground(meta, level):
    N = level["size"]
    M = 8
    span = N + 2 * M
    K = PIX
    W, H = span * 32 * K, span * 16 * K
    ox, oy = span * 16, 2 * M * 8          # world position of the image's top-left corner (negated)
    py, px = np.mgrid[0:H, 0:W].astype(np.float32)
    sx, sy = (px + 0.5) / K - ox, (py + 0.5) / K - oy
    del px, py
    gx = (sx / 16 + sy / 8) / 2
    gy = (sy / 8 - sx / 16) / 2
    rng = np.random.default_rng(7)

    n_big = noise2(H, W, 90 * K, 1)
    n_mid = noise2(H, W, 24 * K, 2)
    n_small = noise2(H, W, 6 * K, 3)
    fine = rng.random((H, W))
    tone = 0.25 * n_big + 0.15 + 0.3 * n_mid + 0.15 * n_small + 0.1 * fine

    sand = np.array([[166, 124, 84], [182, 140, 96], [196, 156, 108], [210, 172, 122]], float)
    q = np.clip((tone - 0.25) / 0.5 * 4, 0, 3.99).astype(int)
    img = sand[q]

    inside = (gx >= 0) & (gx < N) & (gy >= 0) & (gy < N)

    # boot hill: reddish dirt
    bx0, by0, bx1, by1 = level["boothill"]
    bh = (gx > bx0) & (gx < bx1) & (gy > by0) & (gy < by1)
    img[bh] = img[bh] * 0.9 + np.array([170, 100, 70]) * 0.1

    # streets
    road = np.zeros((H, W), bool)
    rut = np.zeros((H, W), bool)
    edge_n = (n_mid - 0.5) * 0.9 + (n_small - 0.5) * 0.4
    for x0, y0, x1, y1 in level["streets"]:
        d = np.maximum.reduce([x0 - gx, gx - x1, y0 - gy, gy - y1])
        road |= d < edge_n * 0.8
        horiz = (x1 - x0) > (y1 - y0)
        inrect = (gx > x0) & (gx < x1) & (gy > y0) & (gy < y1)
        if horiz:
            c = (y0 + y1) / 2
            for off in (-0.85, 0.85, -2.1, 2.1):
                rut |= inrect & (np.abs(gy - c - off - (n_mid - 0.5) * 0.3) < 0.07)
        else:
            c = (x0 + x1) / 2
            for off in (-0.85, 0.85):
                rut |= inrect & (np.abs(gx - c - off - (n_mid - 0.5) * 0.3) < 0.07)
    dirt = np.array([[132, 96, 66], [146, 108, 74], [158, 118, 82], [170, 130, 90]], float)
    rq = np.clip((0.6 * n_small + 0.4 * fine - 0.2) / 0.6 * 4, 0, 3.99).astype(int)
    img[road] = dirt[rq[road]]
    img[rut & road] = img[rut & road] * 0.8

    # hoof prints and horse dung
    hp = road & (fine > 0.985)
    img[hp] *= 0.75

    # mud patches (Corbucci)
    mud = np.array([[74, 52, 38], [88, 62, 44], [102, 74, 52]], float)
    for cx, cy, r in level["mud"]:
        d = np.hypot(gx - cx, (gy - cy) * 1.0) / r + (n_small - 0.5) * 0.5 + (n_mid - 0.5) * 0.4
        core = d < 1.0
        mq = np.clip((n_small * 0.7 + fine * 0.3) * 3, 0, 2.99).astype(int)
        img[core] = mud[mq[core]]
        rim = (d >= 1.0) & (d < 1.18)
        img[rim] = img[rim] * 0.82
        puddle = d < 0.3 - (n_small - 0.5) * 0.4
        img[puddle] = np.array([104, 104, 94]) * (0.9 + 0.15 * n_small[puddle])[:, None]
        glint = puddle & (fine > 0.93)
        img[glint] = (150, 150, 136)

    # pebbles and dry grass
    peb = (fine > 0.992) & ~road
    img[peb] = img[peb] * 0.7
    peb2 = (fine < 0.006)
    img[peb2] = np.minimum(img[peb2] * 1.18, 255)
    tuft_seed = (rng.random((H, W)) > 1 - 0.0015 / (K * K)) & ~road
    tuft_seed &= ~inside | (n_big > 0.55)
    ys, xs = np.nonzero(tuft_seed)
    for y, x in zip(ys, xs):
        for k in range(rng.integers(4, 10)):
            dx = int(rng.integers(-2 * K, 2 * K + 1))
            hgt = int(rng.integers(1, 3 * K + 1))
            col = (134, 128, 66) if rng.random() < 0.5 else (110, 104, 56)
            for j in range(hgt):
                yy, xx = y - j, x + dx + (j * np.sign(dx) if hgt > 2 else 0)
                if 0 <= yy < H and 0 <= xx < W:
                    img[yy, xx] = col

    # outside the town limits the land fades into haze
    dist = np.maximum.reduce([-gx, gx - N, -gy, gy - N, np.zeros_like(gx)])
    fade = np.clip(dist / M, 0, 1)
    img = img * (1 - 0.35 * fade[..., None]) + np.array([150, 112, 80]) * 0.35 * fade[..., None]
    border = inside & ((np.minimum.reduce([gx, N - gx, gy, N - gy])) < 0.06)
    img[border] = img[border] * 0.9

    path = save(np.clip(img, 0, 255).astype(np.uint8), "sprites/ground.png")
    meta["ground"] = {"file": path, "origin": [-ox, -oy]}
    meta["tex_scale"] = 1.0 / K


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


def gen_ui(meta):
    meta["ui"] = {}
    # portrait
    p = chars.portrait()
    meta["ui"]["portrait"] = save(p, "sprites/ui/portrait.png")

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


def write(name, x, meta, peak=0.9):
    x = np.asarray(x, float)
    m = np.abs(x).max()
    if m > 0:
        x = x / m * peak
    path = os.path.join(ASSETS, "sfx", name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
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
    """A steel-on-steel click: noise strike exciting inharmonic modes. weight > 1 is
    heavier: lower, longer, more body."""
    ratios = [1.0, 1.47, 2.09, 2.76, 3.51, 4.62]
    freqs = [base / weight * r for r in ratios]
    decays = [0.012 * weight / (1 + 0.35 * i) for i in range(len(ratios))]
    amps = [1.0, 0.7, 0.55, 0.4, 0.3, 0.2]
    x = modal(rng, freqs, decays, amps, dur)
    t = t_of(dur)
    x += highpass(rng.normal(0, 1, len(t)), 2000) * np.exp(-t / 0.0015) * 1.3
    if weight > 1.2:
        x += lowpass(rng.normal(0, 1, len(t)), 500) * np.exp(-t / (0.01 * weight)) * 1.5
    return x


def room(x, rng, tau=0.07, wet=0.3):
    w = convolve(x, canyon_ir(rng, tau)) * wet
    w[:len(x)] += x
    return w


def gunshot(rng, power, crack_tau, body_fc, thump_f, ring_f, tau, echoes):
    """Spaghetti-western gunshot: whip crack, powder boom, a hint of metallic ring,
    then a long, dark canyon tail with slap-back echoes."""
    t = t_of(0.5)
    n = rng.normal(0, 1, len(t))
    crack = highpass(n, 2500) * np.exp(-t / crack_tau) * 2.5
    f = 5200 * np.exp(-t / 0.012) + 700
    whip = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.03) * 0.5
    body = lowpass(n, body_fc) * np.exp(-t / (0.05 * power)) * 3.0
    th = thump_f * (1 + 2.0 * np.exp(-t / 0.015))
    thump = np.sin(2 * np.pi * np.cumsum(th) / SR) * np.exp(-t / (0.09 * power)) * 1.6
    ring = modal(rng, [ring_f, ring_f * 1.53, ring_f * 2.2], [0.12, 0.08, 0.05], [0.3, 0.2, 0.1], 0.5)
    dry = crack + whip + body + thump + ring * 0.6
    dry[:int(SR * 0.002)] *= np.linspace(0, 1, int(SR * 0.002))
    wet = convolve(dry, canyon_ir(rng, tau, echoes))
    out = wet * 0.8
    out[:len(dry)] += dry
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
    # Three takes of each gun so repeated shots don't sound identical.
    for i in range(3):
        sfx = "" if i == 0 else "_%d" % (i + 1)
        jit = rng.uniform(0.9, 1.1)
        write("colt" + sfx, gunshot(rng, 1.0, 0.003, 1300, 75, 1150, 0.9 * jit,
                                    [(0.24 * jit, 0.35, 1400), (0.55 * jit, 0.2, 900)]), meta)
        write("coach" + sfx, gunshot(rng, 2.0, 0.005, 700, 52, 820, 1.2 * jit,
                                     [(0.28 * jit, 0.4, 1000), (0.62 * jit, 0.25, 700)]), meta, 0.95)
        write("rifle" + sfx, gunshot(rng, 1.2, 0.002, 1700, 88, 1400, 1.1 * jit,
                                     [(0.31 * jit, 0.4, 1600), (0.74 * jit, 0.22, 1000)]), meta)

    t = t_of(0.7)
    f = 3600 * np.exp(-t / 0.45) + 900
    vib = 1 + 0.025 * np.sin(2 * np.pi * 38 * t)
    ric = np.sin(2 * np.pi * np.cumsum(f * vib) / SR)
    ric += 0.4 * np.sin(2 * np.pi * np.cumsum(f * 1.51 * vib) / SR)
    ric *= np.minimum(1, t / 0.004) * np.exp(-t / 0.25)
    ric += highpass(rng.normal(0, 1, len(t)), 2500) * np.exp(-t / 0.006)
    write("ricochet", room(ric, rng, 0.4, 0.5), meta, 0.5)

    # Colt SAA: thumbing the hammer gives the four famous clicks ("C-O-L-T").
    cock = place(0.16, [(0.0, metal(rng, 3300) * 0.5), (0.028, metal(rng, 3000) * 0.55),
                        (0.055, metal(rng, 3400) * 0.6), (0.088, metal(rng, 2500, 1.3) * 1.0)])
    write("cock", room(cock, rng), meta, 0.5)
    # Winchester lever: action thrown open, then snapped shut, with wood under it.
    lever = place(0.32, [(0.0, metal(rng, 1500, 1.6)), (0.01, bandpass(rng.normal(0, 1, int(SR * 0.07)), 1500, 4500) * np.linspace(0.5, 0, int(SR * 0.07))),
                         (0.15, metal(rng, 1300, 2.0) * 1.3), (0.15, modal(rng, [240, 410], [0.03, 0.02], [0.8, 0.4], 0.1))])
    write("lever", room(lever, rng), meta, 0.6)
    # A cartridge pushed past the loading gate.
    push = bandpass(rng.normal(0, 1, int(SR * 0.05)), 2500, 6000) * np.linspace(0.3, 0.8, int(SR * 0.05))
    write("shell_in", room(place(0.12, [(0, push), (0.05, metal(rng, 3900, 0.8) * 0.8)]), rng), meta, 0.45)
    # Ejector rod, then the brass case tinkling onto the boards.
    parts = [(0.0, metal(rng, 2200) * 0.6)]
    for st, a in ((0.11, 1.0), (0.19, 0.55), (0.24, 0.3), (0.27, 0.15)):
        parts.append((st, modal(rng, [4300, 6900, 9200], [0.05, 0.03, 0.02], [a, a * 0.5, a * 0.3], 0.15)))
    write("eject", room(place(0.45, parts), rng), meta, 0.35)
    # Coach gun: breaking it open and snapping it shut.
    write("break_open", room(place(0.2, [(0, metal(rng, 900, 2.2)), (0.04, metal(rng, 2000, 1.2) * 0.5)]), rng),
          meta, 0.6)
    write("close", room(place(0.2, [(0, metal(rng, 800, 2.6) * 1.4), (0.015, modal(rng, [160, 330], [0.04, 0.02], [1, 0.5], 0.15))]), rng),
          meta, 0.7)
    write("dry", room(metal(rng, 1900, 1.5), rng), meta, 0.4)
    t = t_of(0.15)
    thud = lowpass(rng.normal(0, 1, len(t)), 450) * np.exp(-t / 0.025) * 2
    thud += np.sin(2 * np.pi * (110 + 80 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.05)
    write("hit", room(thud, rng, 0.1, 0.2), meta, 0.8)
    write("pickup", room(place(0.3, [(0, modal(rng, [3800, 6100], [0.05, 0.03], [1, 0.5], 0.1)),
                                     (0.07, modal(rng, [4200, 6600], [0.05, 0.03], [0.8, 0.4], 0.1))]), rng), meta, 0.4)
    write("step", steps_crunch(rng), meta, 0.25)

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
    steps = {"chars": gen_characters, "world": gen_world, "fx": gen_fx, "ui": gen_ui, "sfx": gen_sfx}
    for key, fn in steps.items():
        if not only or key in only:
            fn(meta)
    if not only or "ground" in only:
        print("  ground")
        gen_ground(meta, level)
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
    print("Done.")


if __name__ == "__main__":
    main()
