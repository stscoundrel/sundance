#!/usr/bin/env python3
"""Music for Sundance, written as notes and played on instruments made of sums
of sines and shaped noise, the same way the guns and the bells are made.

    tools/.venv/bin/python tools/music.py [out.wav]     # the sketch
    tools/.venv/bin/python tools/music.py silencio      # Silencio's layers, to build/music/
    tools/.venv/bin/python tools/gen_assets.py music     # every level's score, into the game

Silencio's score is three layers the game blends (see silencio() below and
scripts/music.gd). The first piece is a sketch to judge the sound by, not yet in the game. It goes
from a snowbound hush (piano, strings, a voice humming far off) through a bell,
a jaw harp and a whistled call, into a gallop: the theme whistled, then twanged
on a low guitar with the gang shouting back, then sung high over a trumpet, and
home to the piano.
"""
import os
import sys
import time
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(1966)


def hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


def secs(s):
    return int(round(s * SR))


# --- shaping, all zero-phase by FFT ---------------------------------------

def fft_filter(x, resp):
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * resp(f), n=n, axis=-1)


def lp(f, fc, order=1.0):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(f, fc, order=1.0):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bump(f, fc, db, width=1.0):
    x = np.log2(np.maximum(f, 1e-3) / fc) / width
    return 1.0 + (10 ** (db / 20.0) - 1.0) * np.exp(-x * x)


def noise(n, resp=None):
    w = rng.standard_normal(n)
    if resp is not None:
        w = fft_filter(w, resp)
    return w / (w.std() + 1e-12)


def wander(n, rate, depth):
    """A slow random drift, a new value every 1/rate seconds, smoothly joined."""
    k = max(2, int(n / SR * rate) + 2)
    pts = rng.standard_normal(k)
    x = np.linspace(0, k - 1, n)
    i = np.floor(x).astype(int)
    i1 = np.minimum(i + 1, k - 1)
    w = (1 - np.cos(np.pi * (x - i))) / 2
    return depth * (pts[i] * (1 - w) + pts[i1] * w)


# --- a sung or blown line: pitch, vibrato and breath over a run of notes ---

def line(notes, attack=0.03, release=0.1, glide=0.04, vib_rate=5.5,
         vib_depth=0.25, vib_delay=0.3, drift=0.04, scoop=0.0, scoop_time=0.05,
         artic=0.02, fall=0.0, punch=0.0):
    """notes: (start s, length s, midi, velocity). One voice, legato where the
    notes touch. Returns the start time and the phase, frequency and loudness."""
    notes = sorted(notes)
    start = notes[0][0]
    end = max(t + d for t, d, _, _ in notes) + release * 5 + 0.05
    n = secs(end - start)
    t = np.arange(n) / SR
    pitch = np.full(n, float(notes[0][2]))
    bend = np.zeros(n)
    vib = np.zeros(n)
    amp = np.zeros(n)
    for t0, d, m, v in notes:
        i0 = secs(t0 - start)
        k = t[: n - i0]
        pitch[i0:] = m
        if scoop:
            bend[i0:] += -scoop * np.exp(-k / scoop_time)
        if fall:
            seg = np.clip(k / d, 0, 1.5) ** 2 * fall
            bend[i0:] += np.where(k < d + release * 3, seg, 0)
        e = np.minimum(1.0, k / attack)
        if punch:
            e *= 1.0 + punch * np.exp(-k / 0.07) * (k > attack)
        r0 = max(d - artic, d * 0.7)
        e *= np.where(k > r0, np.exp(-(k - r0) / release), 1.0)
        amp[i0:] = np.maximum(amp[i0:], e * v)
        vd = np.clip((k - vib_delay) / 0.4, 0, 1) * vib_depth
        vib[i0:] = np.where(k < d + release * 2, vd, 0)
    if glide > 0:
        w = max(1, secs(glide))
        c = np.cumsum(np.concatenate([[0], np.pad(pitch, (w // 2, w - w // 2 - 1), mode="edge")]))
        pitch = (c[w:] - c[:-w]) / w
    rate = vib_rate * (1 + wander(n, 0.5, 0.04))
    midi = pitch + bend + vib * np.sin(2 * np.pi * np.cumsum(rate) / SR + rng.uniform(0, 6.3))
    midi += wander(n, 4.0, drift)
    f = hz(midi)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return start, phase, f, amp


# --- instruments -----------------------------------------------------------

def pluck(m, dur, vel=1.0, pickup=0.12, tau=2.0, bright=1.0, B=1.2e-4,
          maxf=9000.0, damp=0.05, click=0.3, vib=0.0, vib_delay=0.25):
    """A plucked string. pickup near 0 is the bridge: thin and twangy."""
    f = float(hz(m))
    n = secs(dur + damp * 6 + 0.01)
    t = np.arange(n) / SR
    if vib:
        depth = np.clip((t - vib_delay) / 0.3, 0, 1) * vib
        ratio = 2 ** (depth * np.sin(2 * np.pi * 5.6 * t) / 12)
        base = 2 * np.pi * f * np.cumsum(ratio) / SR
    else:
        base = 2 * np.pi * f * t
    out = np.zeros(n)
    tot = 0.0
    for k in range(1, 90):
        stretch = k * np.sqrt(1 + B * k * k)
        if stretch * f > maxf:
            break
        a = abs(np.sin(np.pi * k * pickup)) / k ** (1.15 - 0.35 * bright)
        tk = tau / (1.0 + 0.35 * (k - 1) * np.sqrt(f / 196.0))
        out += a * np.exp(-t / tk) * np.sin(stretch * base + rng.uniform(0, 0.5))
        tot += a
    out /= tot
    out *= np.where(t > dur, np.exp(-(t - dur) / damp), 1.0) * np.minimum(1.0, t / 0.0015)
    if click:
        out += click * 0.08 * noise(n, lambda fr: hp(fr, 2000) * lp(fr, 8000)) * np.exp(-t / 0.004)
    return out * vel


def piano(m, dur, vel=0.6):
    f = float(hz(m))
    ring = min(7.0, 2.0 + 4.0 * (261.0 / f) ** 0.5)
    n = secs(dur + 0.8)
    t = np.arange(n) / SR
    B = 3e-4 * (f / 261.0) ** 0.5
    out = np.zeros(n)
    tot = 0.0
    for k in range(1, 40):
        stretch = k * np.sqrt(1 + B * k * k)
        if stretch * f > 6500:
            break
        a = abs(np.sin(np.pi * k / 7.3)) / k ** (1.7 - 0.9 * vel)
        tl = ring / (1 + 0.3 * (k - 1))
        ts = 0.3 / (1 + 0.2 * (k - 1))
        e = 0.45 * np.exp(-t / ts) + 0.55 * np.exp(-t / tl)
        for cents in (-0.7, 0.8):
            fk = stretch * f * 2 ** (cents / 1200)
            out += 0.5 * a * e * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.3))
        tot += a
    out /= tot
    out *= np.where(t > dur, np.exp(-(t - dur) / 0.12), 1.0) * np.minimum(1.0, t / 0.002)
    out += 0.03 * noise(n, lambda fr: lp(fr, 1500)) * np.exp(-t / 0.006)
    return out * vel


def whistle(notes):
    start, ph, f, a = line(notes, attack=0.035, release=0.07, glide=0.05, vib_rate=5.2,
                           vib_depth=0.3, vib_delay=0.25, drift=0.05, scoop=0.35,
                           scoop_time=0.04)
    n = len(a)
    breath = noise(n, lambda fr: lp(fr, 120, 2))
    s = np.sin(ph) * (1 + 0.04 * breath) + 0.015 * np.sin(2 * ph)
    s += 0.12 * breath * np.sin(ph + 0.3)     # the hiss that rides on the note
    s += 0.006 * noise(n, lambda fr: hp(fr, 3000) * lp(fr, 9000))
    return start, s * a


VOWELS = {
    "a_sop": ((800, 1150, 2900, 3900), (110, 130, 170, 220)),
    "u_sop": ((350, 700, 2700, 3800), (80, 90, 170, 220)),
    "a_male": ((700, 1150, 2500, 3300), (90, 120, 160, 250)),
    "o_male": ((480, 820, 2800, 3500), (80, 100, 160, 220)),
}


def formant_gain(f, F, BW):
    g = np.ones_like(f)
    for Fi, Bi in zip(F, BW):
        g = g * (Fi * Fi) / np.sqrt((Fi * Fi - f * f) ** 2 + (f * Bi) ** 2)
    return g


def sing(notes, vowel, tilt=1.3, maxf=6000.0, breath=0.02, **kw):
    """A wordless voice. A soprano lifts her first formant to her note, as
    singers do up high, so the top notes ring rather than thin out."""
    start, ph, f, a = line(notes, **kw)
    F, BW = VOWELS[vowel]
    F1 = np.maximum(F[0], f * 1.08)
    Fs = (F1,) + tuple(F[1:])
    out = np.zeros(len(a))
    fmin = float(f.min())
    for k in range(1, 200):
        if k * fmin > maxf:
            break
        fk = k * f
        g = formant_gain(fk, Fs, BW) / k ** tilt * (fk < maxf)
        out += g * np.sin(k * ph)
    out /= np.abs(out).max() + 1e-9
    out += breath * noise(len(a), lambda fr: hp(fr, 1500) * lp(fr, 6000))
    return start, out * a


def choir(notes, vowel, voices=3, spread=12.0, **kw):
    start, total = None, None
    for v in range(voices):
        det = (v - (voices - 1) / 2) * spread / 100.0
        nv = [(t + rng.uniform(0, 0.03), d, m + det, vel) for t, d, m, vel in notes]
        s, sig = sing(nv, vowel, vib_rate=5.0 + 0.5 * v, **kw)
        if total is None:
            start, total = s, sig
        else:
            off = secs(s - start)
            if off < 0:
                total = np.concatenate([np.zeros(-off), total])
                start, off = s, 0
            if off + len(sig) > len(total):
                total = np.concatenate([total, np.zeros(off + len(sig) - len(total))])
            total[off:off + len(sig)] += sig
    return start, total / voices


def shout(m=55, voices=7):
    """The gang, all at once: 'Hah!'"""
    n = secs(0.7)
    out = np.zeros(n)
    F, BW = VOWELS["a_male"]
    for v in range(voices):
        d = rng.uniform(0, 0.03)
        pitch = m + rng.uniform(-1.0, 1.0) - (12 if v % 3 == 0 else 0)
        _, sig = sing([(0.04, 0.2, pitch, 1.0)], "a_male", tilt=0.9, attack=0.012,
                      release=0.05, glide=0, vib_depth=0, drift=0.2, fall=-3.0,
                      breath=0.05)
        o = secs(d)
        L = min(len(sig), n - o)
        out[o:o + L] += sig[:L]
        h = secs(0.06)
        asp = fft_filter(rng.standard_normal(h), lambda fr: formant_gain(fr, F, BW) * hp(fr, 300))
        asp /= asp.std() + 1e-9
        out[o:o + h] += 0.15 * asp * np.sin(np.linspace(0, np.pi, h))
    return out / voices


def trumpet(notes, vel=1.0):
    start, ph, f, a = line(notes, attack=0.045, release=0.1, glide=0.03, vib_rate=5.5,
                           vib_depth=0.16, vib_delay=0.45, drift=0.03, scoop=0.6,
                           scoop_time=0.045, artic=0.04, punch=0.25)
    e = a / (a.max() + 1e-9)
    out = np.zeros(len(a))
    fm = float(f.mean())
    for k in range(1, 30):
        if k * fm > 9000:
            break
        fk = k * f
        g = e ** (1 + 0.45 * (k - 1)) * k ** -0.1 * lp(fk, 3500) * bump(fk, 1300, 6, 0.8)
        out += g * np.sin(k * ph)
    out /= np.abs(out).max() + 1e-9
    return start, out * vel


def jaw_harp(m, dur, sweep, vel=1.0):
    """The reed twangs on one note; the mouth moves a resonance over its
    harmonics, which is the whole tune of it: boing."""
    f = float(hz(m))
    n = secs(dur + 0.35)
    t = np.arange(n) / SR
    f0, f1, tt = sweep
    Fc = f1 + (f0 - f1) * np.exp(-t / tt)
    out = np.zeros(n)
    for k in range(1, 80):
        fk = k * f
        if fk > 5000:
            break
        res = 1.0 / (1.0 + ((fk - Fc) / 90.0) ** 2)
        g = k ** -0.6 * (0.06 + res + 0.15 / (1 + ((fk - 2600) / 300.0) ** 2))
        out += g * np.sin(2 * np.pi * fk * t)
    out /= np.abs(out).max() + 1e-9
    e = np.exp(-t / 0.3) * np.minimum(1.0, t / 0.002)
    e *= np.where(t > dur, np.exp(-(t - dur) / 0.05), 1.0)
    return out * e * vel


def bell(m, length=7.0, vel=1.0):
    """A church bell; m is its strike note, the hum an octave under it."""
    base = float(hz(m)) / 2.0
    ratios = [0.5, 1.0, 1.2, 1.5, 2.0, 2.5, 2.67, 3.0, 4.0, 5.33, 6.4, 8.0]
    amps = [0.5, 0.45, 0.55, 0.2, 1.0, 0.3, 0.35, 0.2, 0.25, 0.12, 0.08, 0.05]
    taus = [1.0, 0.7, 0.55, 0.4, 0.45, 0.25, 0.25, 0.18, 0.14, 0.09, 0.07, 0.05]
    n = secs(length)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, tau in zip(ratios, amps, taus):
        fr = base * r * (1 + rng.uniform(-0.003, 0.003))
        for split in (-0.35, 0.35):
            out += 0.5 * a * np.exp(-t / (tau * length * 0.5)) * np.sin(2 * np.pi * (fr + split * r) * t + rng.uniform(0, 6.3))
    out /= sum(amps)
    out += 0.15 * noise(n, lambda fr: hp(fr, 1500)) * np.exp(-t / 0.008)
    return out * vel * np.minimum(1.0, t / 0.001)


def timp(m, vel=1.0, length=1.6):
    f = float(hz(m))
    n = secs(length)
    t = np.arange(n) / SR
    glide = 1 + 0.04 * np.exp(-t / 0.03)
    ph = 2 * np.pi * f * np.cumsum(glide) / SR
    out = np.zeros(n)
    for r, a, tau in zip([1, 1.5, 1.99, 2.44, 2.98], [1, .5, .3, .2, .1], [.9, .5, .35, .25, .18]):
        out += a * np.exp(-t / (tau * length / 1.6)) * np.sin(r * ph)
    out /= 2.1
    out += 0.35 * noise(n, lambda fr: lp(fr, 600, 2)) * np.exp(-t / 0.02)
    return out * vel * np.minimum(1.0, t / 0.001)


def snare(vel=1.0):
    n = secs(0.35)
    t = np.arange(n) / SR
    tone = (0.6 * np.sin(2 * np.pi * 185 * t) + 0.3 * np.sin(2 * np.pi * 330 * t)) * np.exp(-t / 0.035)
    nz = noise(n, lambda f: hp(f, 900, 2) * lp(f, 9000) * bump(f, 4000, 4))
    nz *= np.exp(-t / (0.05 + 0.07 * vel)) * np.minimum(1.0, t / 0.0008)
    return (0.6 * tone + 0.45 * nz) * vel


def whip():
    n = secs(0.45)
    t = np.arange(n) / SR
    tc = 0.14
    swish = noise(n, lambda f: hp(f, 1500) * lp(f, 7000)) * np.clip(t / tc, 0, 1) ** 3 * (t < tc) * 0.25
    crack = noise(n, lambda f: hp(f, 700)) * np.where(t >= tc, np.exp(-(t - tc) / 0.007), 0)
    return swish + crack


def strings(m, dur, vel=1.0, attack=0.5, release=0.9, voices=3):
    f = float(hz(m))
    n = secs(dur + release * 5)
    t = np.arange(n) / SR
    L = 4096
    x = np.arange(L) / L
    table = np.zeros(L)
    for k in range(1, int(5000 / f) + 1):
        table += np.sin(2 * np.pi * k * x) / k * lp(k * f, 2200, 1.5)
    table /= np.abs(table).max()
    out = np.zeros(n)
    for v in range(voices):
        det = (v - (voices - 1) / 2) * 7.0
        vib = 0.07 * np.sin(2 * np.pi * (4.8 + 0.4 * v) * t + rng.uniform(0, 6.3)) + wander(n, 1.0, 0.03)
        fv = f * 2 ** ((det / 100 + vib) / 12)
        ph = np.cumsum(fv) / SR + rng.uniform(0, 1)
        out += table[((ph % 1.0) * L).astype(int)]
    out /= voices
    e = np.where(t < attack, (1 - np.cos(np.pi * t / attack)) / 2, 1.0)
    e *= np.where(t > dur, np.exp(-(t - dur) / release), 1.0)
    return out * e * vel


def wind(n):
    base = noise(n, lambda f: bump(f, 500, 8, 1.2) * lp(f, 1500, 2) * hp(f, 120))
    swell = np.clip(0.6 + 0.5 * wander(n, 0.3, 1.0), 0.1, 1.5)
    nb = noise(n, lambda f: lp(f, 40, 2))
    fc = 620 + 220 * wander(n, 0.15, 1.0)
    howl = nb * np.sin(2 * np.pi * np.cumsum(fc) / SR)
    return base * swell + 0.5 * howl * swell ** 2


# --- the mix ---------------------------------------------------------------

class Mix:
    # reverb send per bus
    SENDS = {"close": 0.12, "mid": 0.3, "guitar": 0.3, "far": 0.65, "air": 0.4}

    def __init__(self, seconds):
        self.n = secs(seconds)
        self.bus = {b: np.zeros((2, self.n)) for b in self.SENDS}

    def put(self, sig, t, bus="mid", pan=0.0, gain=1.0):
        i = secs(t)
        if sig.ndim == 1:
            th = (pan + 1) * np.pi / 4
            sig = np.vstack([sig * np.cos(th), sig * np.sin(th)]) * np.sqrt(2)
        if i < 0:
            sig, i = sig[:, -i:], 0
        L = min(sig.shape[1], self.n - i)
        if L > 0:
            self.bus[bus][:, i:i + L] += gain * sig[:, :L]


def hall_ir(rt=2.6, length=3.4, pre=0.025):
    n = secs(length)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2):
        dark = noise(n, lambda f: lp(f, 2800) * hp(f, 120))
        bright = rng.standard_normal(n)
        ir = dark * np.exp(-6.9 * t / rt) + 0.5 * bright * np.exp(-6.9 * t / (rt * 0.2))
        ir *= np.clip((t - pre) / 0.01, 0, 1)
        chans.append(ir)
    ir = np.array(chans)
    return ir / np.sqrt((ir ** 2).sum(axis=1, keepdims=True))


def convolve(x, ir):
    m = len(x) + ir.shape[-1]
    nfft = 1 << (m - 1).bit_length()
    X = np.fft.rfft(x, nfft)
    return np.fft.irfft(X * np.fft.rfft(ir, nfft, axis=-1), nfft, axis=-1)[:, :len(x)]


def delay(x, s):
    d = secs(s)
    y = np.zeros_like(x)
    y[:, d:] = x[:, :-d]
    return y


def guitar_fx(x):
    """The twang: a hot amp, a bright middle, and the echo off the canyon."""
    p = np.abs(x).max() + 1e-9
    y = np.tanh(2.2 * x / p) / np.tanh(2.2) * p
    y = fft_filter(y, lambda f: hp(f, 90) * bump(f, 1600, 5) * lp(f, 6500))
    echo = fft_filter(delay(y, 0.19) * 0.38 + delay(y, 0.38) * 0.16, lambda f: lp(f, 3000))
    return y + echo


def render(mix):
    """The buses through their effects and the hall, not yet levelled."""
    dry = np.zeros((2, mix.n))
    send = np.zeros(mix.n)
    for b, s in Mix.SENDS.items():
        x = mix.bus[b]
        if b == "guitar":
            x = guitar_fx(x)
        mix.bus[b] = x
        dry += x
        send += s * (x[0] + x[1]) / 2
    out = dry + convolve(send, hall_ir())
    return fft_filter(out, lambda f: hp(f, 28, 2))


def master(mix):
    out = render(mix)
    out *= 0.9 / np.percentile(np.abs(out), 99.97)
    out = np.tanh(out)
    return out * (0.94 / np.abs(out).max())


def write_ogg(path, x, quality=0.3):
    """Ogg Vorbis, about 185 kbps at 0.3 (libsndfile's compression level: 0 is
    the best). Written in blocks: libsndfile falls over given minutes at once."""
    import soundfile as sf
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    y = np.clip(x.T, -1, 1).astype(np.float32)
    with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=quality) as f:
        for i in range(0, len(y), 8192):
            f.write(y[i:i + 8192])


def write_wav(path, x):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    pcm = (np.clip(x.T, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- the score -------------------------------------------------------------

CHORDS = {"Dm": (2, 5, 9), "Gm": (7, 10, 2), "A": (9, 1, 4), "F": (5, 9, 0),
          "C": (0, 4, 7), "Eb": (3, 7, 10), "Bb": (10, 2, 5),
          "Am": (9, 0, 4), "G": (7, 11, 2), "E": (4, 8, 11),
          "Em": (4, 7, 11), "D": (2, 6, 9), "B": (11, 3, 6), "Cm": (0, 3, 7)}


def tones(ch, lo, hi):
    return [m for m in range(lo, hi + 1) if m % 12 in CHORDS[ch]]


def bass_note(ch):
    return 33 + (CHORDS[ch][0] - 9) % 12


class Clock:
    def __init__(self, t0, bpm):
        self.t0, self.beat = t0, 60.0 / bpm

    def at(self, bar, beat=0.0):
        return self.t0 + (bar * 4 + beat) * self.beat

    def dur(self, beats):
        return beats * self.beat

    def end(self, bars):
        return self.at(bars)


class Clock8(Clock):
    """Twelve-eight: four lilting beats of three to the bar. Positions count eighths."""

    def __init__(self, t0, beat_bpm):
        self.t0, self.beat = t0, 60.0 / beat_bpm / 3

    def at(self, bar, eighth=0.0):
        return self.t0 + (bar * 12 + eighth) * self.beat


# The tune: (bar, eighth, eighths, midi). Long notes and wide leaps over the walk down.
WALK = ["Dm", "Dm", "C", "Bb", "A", "A"]
MELODY = [
    (0, 0, 9, 81), (0, 9, 1, 82), (0, 10, 1, 81), (0, 11, 1, 79),
    (1, 0, 3, 81), (1, 3, 6, 86), (1, 9, 2, 84), (1, 11, 1, 82),
    (2, 0, 6, 84), (2, 6, 3, 79), (2, 9, 2, 81), (2, 11, 1, 79),
    (3, 0, 9, 77), (3, 9, 1, 79), (3, 10, 1, 77), (3, 11, 1, 76),
    (4, 0, 3, 76), (4, 3, 3, 81), (4, 6, 3, 85), (4, 9, 1, 86), (4, 10, 2, 85),
    (5, 0, 12, 81),
]
# The trumpet's long answer under the sung tune.
COUNTER = [(0, 0, 12, 74), (1, 0, 6, 77), (1, 6, 6, 76), (2, 0, 12, 76),
           (3, 0, 12, 74), (4, 0, 6, 73), (4, 6, 6, 76), (5, 0, 12, 76)]


def notes_of(c, part, shift=0, vel=1.0):
    return [(c.at(b, bt), c.dur(d), m + shift, vel) for b, bt, d, m in part]


def pedal(mix, c, chords, level=1.0):
    """The low string tolling the root on one, and softer on the third beat."""
    for bar, ch in enumerate(chords):
        r = bass_note(ch)
        mix.put(pluck(r, c.dur(11.5), 1.0, pickup=0.09, tau=3.0, bright=1.2, maxf=7000, vib=0.2),
                c.at(bar), "guitar", -0.3, 0.4 * level)
        mix.put(pluck(r, c.dur(5.5), 1.0, pickup=0.22, tau=2.0, bright=0.4, maxf=2500, damp=0.08),
                c.at(bar), "close", 0.0, 0.5 * level)
        mix.put(pluck(r, c.dur(5.5), 0.6, pickup=0.22, tau=2.0, bright=0.4, maxf=2500, damp=0.08),
                c.at(bar, 6), "close", 0.0, 0.5 * level)


def arpeggio(mix, c, chords, level=1.0):
    """A picked guitar rocking up and down the chord in eighths."""
    for bar, ch in enumerate(chords):
        low = bass_note(ch) + 12
        third = tones(ch, low + 13, low + 24)[0]
        pat = [low, low + 7, low + 12, third, low + 12, low + 7]
        for j in range(12):
            v = 0.9 if j % 3 == 0 else 0.6
            mix.put(pluck(pat[j % 6], c.dur(2.5), v, pickup=0.2, tau=1.4, bright=0.6, maxf=6000,
                          damp=0.08, click=0.15), c.at(bar, j) + rng.normal(0, 0.004), "mid", 0.35, 0.13 * level)


def rasgueado(mix, c, ch, t, level=1.0):
    """A flamenco roll of the fingers across the strings: four quick strokes."""
    strum = [bass_note(ch) + 12] + tones(ch, 53, 66)
    for stroke in range(4):
        order = strum if stroke % 2 == 0 else strum[::-1]
        for j, m in enumerate(order):
            mix.put(pluck(m, 0.5 if stroke == 3 else 0.1, 0.5 + 0.15 * stroke, pickup=0.25, tau=1.0,
                          bright=0.7, maxf=6000, damp=0.04, click=0.25),
                    t + stroke * 0.03 + j * 0.006 - 0.09, "mid", 0.45, 0.07 * level)


def timp_roll(mix, c, bar, eighth, eighths, m):
    k = int(eighths * 4)
    for j in range(k):
        mix.put(timp(m, 0.1 + 0.5 * j / max(1, k - 1), 1.0), c.at(bar, eighth + j / 4), "close", -0.1, 0.4)


def snare_roll8(mix, c, bar, eighth, eighths, v0=0.15, v1=0.9, level=1.0):
    k = int(eighths * 4)
    for j in range(k):
        v = v0 + (v1 - v0) * j / max(1, k - 1)
        mix.put(snare(v), c.at(bar, eighth + j / 4), "close", 0.15, 0.3 * level)


def snare_roll(mix, c, bar, beat, beats, v0=0.15, v1=0.9, level=1.0):
    k = int(beats * 8)
    for j in range(k):
        v = v0 + (v1 - v0) * j / max(1, k - 1)
        mix.put(snare(v), c.at(bar, beat + j / 8), "close", 0.15, 0.3 * level)


def compose():
    total = 108.0
    mix = Mix(total)
    marks = {}

    # The wind under all of it, loud in the hush, gone in the gallop, back at the end.
    w = wind(mix.n)
    key = [(0, .0), (1.5, 1), (20, 1), (24, .35), (31, .12), (90, .12), (94, .8), (total, .8)]
    tt = np.arange(mix.n) / SR
    w *= np.interp(tt, [k[0] for k in key], [k[1] for k in key])
    mix.put(w, 0.0, "air", 0.0, 0.05)

    # A: the hush. Piano arpeggios, strings, and the theme hummed slowly far off.
    a = Clock(1.0, 66)
    marks["hush"] = a.t0
    chords_a = ["Dm", "Bb", "Gm", "A", "Dm", "A"]
    pads = {"Dm": [50, 53, 57, 62], "Bb": [46, 53, 58, 62], "Gm": [43, 50, 55, 58], "A": [45, 52, 57, 61]}
    for bar, ch in enumerate(chords_a):
        for m in pads[ch]:
            mix.put(strings(m, a.dur(4), 0.9, attack=1.2, release=1.4), a.at(bar), "far", rng.uniform(-.4, .4), 0.07)
        low = min(tones(ch, 38, 49))
        arp = [low, low + 7, low + 12] + tones(ch, low + 13, low + 30)[:3]
        arp = arp + arp[-2:0:-1]
        for j in range(8):
            m = arp[j % len(arp)]
            v = 0.45 + 0.15 * (j == 0) + rng.uniform(-.05, .05)
            mix.put(piano(m, a.dur(1.6), v), a.at(bar, j * 0.5) + rng.normal(0, 0.006), "far", -0.2 + 0.05 * j, 0.32)
    hum = [(1, 0, 2, 74), (1, 2, 2, 69), (2, 0, 2, 67), (2, 2, 1, 65), (2, 3, 1, 64),
           (3, 0, 1.5, 65), (3, 1.5, .5, 67), (3, 2, 2, 69), (4, 0, 4, 69)]
    s, sig = sing(notes_of(a, hum, vel=0.8), "u_sop", tilt=1.6, attack=0.25, release=0.4,
                  glide=0.09, vib_rate=5.0, vib_depth=0.22, vib_delay=0.4, drift=0.05)
    mix.put(sig, s, "far", 0.15, 0.22)

    # B: a bell, the jaw harp starts, a whistled call from the hills.
    b = Clock(a.end(6), 120)
    marks["call"] = b.t0
    mix.put(bell(62, 8.0), b.at(0), "far", -0.3, 0.45)
    mix.put(bell(62, 7.0, 0.7), b.at(2), "far", -0.3, 0.45)
    mix.put(pluck(38, b.dur(7), 1.0, pickup=0.09, tau=3.0, bright=1.2, maxf=7000, vib=0.25), b.at(0), "guitar", -0.3, 0.45)
    mix.put(pluck(38, b.dur(6), 0.9, pickup=0.09, tau=3.0, bright=1.2, maxf=7000, vib=0.25), b.at(2), "guitar", -0.3, 0.45)
    call = [(0, 0, 3, 81), (0, 3, 5, 86), (2, 0, 1, 84), (2, 1, 1, 82), (2, 2, 5.5, 81)]
    s, sig = whistle(notes_of(b, call))
    mix.put(sig, s, "mid", 0.25, 0.28)
    for bar in range(4):
        mix.put(timp(38, 0.5), b.at(bar), "close", -0.1, 0.4)
    for j in range(16):
        mix.put(timp(33, 0.1 + 0.5 * j / 15, 1.0), b.at(3, j * 0.25), "close", -0.1, 0.45)
    snare_roll(mix, b, 3, 2, 2, 0.1, 0.8)

    # From here the piece is in twelve-eight over a low D: four lilting beats
    # to the bar, the chords walking down D minor, C, B flat, A and no backbeat
    # anywhere. The drums only roll and swell into the downbeats.
    c1 = Clock8(b.end(4), 72)
    sweeps = [(350, 1500, 0.08), (1400, 500, 0.1), (400, 1200, 0.06)]
    harp_pat = [0, 2, 3, 5, 6, 8, 9, 11]
    for bar in range(4):            # the call's three-three-two, in sixteenths
        for j, step in enumerate([0, 3, 6, 8, 11, 14]):
            mix.put(jaw_harp(50, b.dur(0.6), sweeps[j % 3], 1.0 if j % 3 == 0 else 0.75),
                    b.at(bar, step * 0.25), "mid", -0.45, 0.18)
    for bar in range(6):            # and on into the lilt
        for j, step in enumerate(harp_pat):
            mix.put(jaw_harp(50, c1.dur(1.5), sweeps[j % 3], 1.0 if step % 3 == 0 else 0.6),
                    c1.at(bar, step), "mid", -0.45, 0.16)

    # C1: the tune whistled over the jaw harp, a picked guitar and the low pedal.
    marks["whistled"] = c1.t0
    pedal(mix, c1, WALK, 0.8)
    arpeggio(mix, c1, WALK, 0.7)
    for bar in (0, 3):
        mix.put(bell(62, 7.0, 0.7), c1.at(bar), "far", -0.3, 0.4)
    s, sig = whistle(notes_of(c1, MELODY))
    mix.put(sig, s, "mid", 0.2, 0.34)
    snare_roll8(mix, c1, 5, 9, 3, 0.1, 0.7)

    # C2: the tune twanged low, the gang shouting into the long notes.
    c2 = Clock8(c1.end(6), 72)
    marks["twanged"] = c2.t0
    pedal(mix, c2, WALK, 1.0)
    arpeggio(mix, c2, WALK, 1.0)
    for bar, ch in enumerate(WALK):
        r = bass_note(ch)
        mix.put(timp(r if r >= 36 else r + 12, 0.9), c2.at(bar), "close", -0.1, 0.5)
        if bar % 2 == 1:
            timp_roll(mix, c2, bar, 9, 3, r if r >= 36 else r + 12)
    for bar, eighth, dd, m in MELODY:
        long = dd >= 6
        mix.put(pluck(m - 24, c2.dur(dd) * 0.95, 1.0, pickup=0.09, tau=2.8 if long else 1.6, bright=1.3,
                      maxf=7000, damp=0.04, vib=0.3 if long else 0.0), c2.at(bar, eighth), "guitar", -0.15, 0.7)
    for bar, eighth in ((0, 6), (3, 6), (5, 6), (5, 9)):
        mix.put(shout(55 + (2 if eighth == 9 else 0)), c2.at(bar, eighth) - 0.03, "mid", rng.uniform(-.2, .2), 0.4)
    snare_roll8(mix, c2, 5, 9, 3, 0.15, 1.0)

    # D: sung high over everything, the trumpet answering, strings and a male choir.
    d = Clock8(c2.end(6), 72)
    marks["sung"] = d.t0
    pedal(mix, d, WALK, 1.0)
    arpeggio(mix, d, WALK, 0.9)
    mix.put(whip(), d.at(0) - 0.14, "mid", 0.5, 0.3)
    for bar, ch in enumerate(WALK):
        r = bass_note(ch)
        tm = r if r >= 36 else r + 12
        mix.put(timp(tm, 1.0), d.at(bar), "close", -0.1, 0.55)
        mix.put(timp(tm, 0.6), d.at(bar, 6), "close", -0.1, 0.45)
        rasgueado(mix, d, ch, d.at(bar), 1.0)
        if bar % 3 == 0:
            mix.put(bell(62, 6.0, 0.8), d.at(bar), "far", -0.4, 0.35)
        for m in tones(ch, 50, 69):
            mix.put(strings(m, d.dur(12), 0.8, attack=0.3, release=0.6, voices=2),
                    d.at(bar), "far", rng.uniform(-.5, .5), 0.045)
        for m in tones(ch, 48, 62):
            cs, csig = choir([(d.at(bar), d.dur(11.5), m, 0.8)], "a_male", voices=3, attack=0.2,
                             release=0.3, glide=0, vib_depth=0.15, drift=0.05)
            mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.06)
        if bar % 2 == 1:
            snare_roll8(mix, d, bar, 9, 3, 0.1, 0.6 if bar < 5 else 1.0)
    s, sig = sing(notes_of(d, MELODY, 0, 0.95), "a_sop", tilt=1.2, attack=0.07, release=0.14,
                  glide=0.07, vib_rate=5.8, vib_depth=0.35, vib_delay=0.18, drift=0.04, scoop=0.25)
    mix.put(sig, s, "far", 0.1, 0.55)
    s, sig = trumpet(notes_of(d, COUNTER, 0, 0.9))
    mix.put(sig, s, "mid", -0.3, 0.2)

    # E: one hit, all together, and the piano alone again in the wind.
    e = Clock(d.end(6), 120)
    marks["end"] = e.t0
    mix.put(shout(57), e.at(0) - 0.03, "mid", 0.0, 0.5)
    mix.put(timp(38, 1.0, 3.0), e.at(0), "close", -0.1, 0.7)
    mix.put(bell(62, 9.0), e.at(0), "far", -0.3, 0.5)
    mix.put(pluck(38, 3.0, 1.0, pickup=0.09, tau=3.0, bright=1.2, maxf=7000, vib=0.3), e.at(0), "guitar", -0.2, 0.5)
    mix.put(pluck(26, 2.5, 1.0, pickup=0.22, tau=2.0, bright=0.4, maxf=2500), e.at(0), "close", 0.0, 0.6)
    for j, m in enumerate([50] + tones("Dm", 53, 66)):
        mix.put(pluck(m, 2.5, 0.9, pickup=0.25, tau=1.5, bright=0.6), e.at(0) + j * 0.012, "mid", 0.4, 0.1)
    for m in [50, 53, 57, 62, 65]:
        mix.put(strings(m, 2.5, 0.8, attack=0.05, release=1.2), e.at(0), "far", rng.uniform(-.5, .5), 0.06)
    p = Clock(e.at(0) + 4.0, 66)
    reprise = [(0, 0, 1, 74), (0, 1, 1, 69), (0, 2, .5, 70), (0, 2.5, .5, 69), (0, 3, 1, 67),
               (1, 0, 1, 65), (1, 1, 1, 64), (1, 2, 4, 62)]
    for bar, beat, dd, m in reprise:
        mix.put(piano(m, p.dur(dd + 0.6), 0.5), p.at(bar, beat), "far", 0.1, 0.34)
    for beat, dd, ms in ((0, 4, [50, 57]), (4, 2, [43, 50]), (6, 6, [38, 50, 57])):
        for m in ms:
            mix.put(piano(m, p.dur(dd), 0.4), p.at(0, beat), "far", -0.2, 0.3)
    mix.put(bell(62, 9.0, 0.5), p.at(1, 2), "far", -0.5, 0.25)
    return mix, marks


# --- Silencio: the snowbound town's score, in three layers -----------------
#
# One piece of 32 bars at 66, played round and round under the whole level. The
# snow layer always plays: piano and strings, a voice humming once a time
# round. Unease (a gang on edge, a search, the gold gone) adds low plucked
# strings, a timpani heartbeat and a thin high note. The fight adds timpani
# driving in eighths, the strings sawing under it and the voice crying the tune
# high. The three share every bar and chord, so the game can bring each up or
# down at any moment and they still fit.

SILENCIO_BPM = 66
SILENCIO_CHORDS = [
    "Dm", "Bb", "Gm", "A", "Dm", "Bb", "Gm", "A",
    "F", "C", "Dm", "A", "Bb", "F", "Gm", "A",
    "Dm", "Bb", "Gm", "A", "Dm", "Bb", "Gm", "A",
    "Dm", "Gm", "Bb", "A", "Dm", "Bb", "A", "A",
]
# The tune of the third phrase (and the voice's lament): (bar, beat, beats, midi).
SILENCIO_TUNE = [(1, 0, 2, 86), (1, 2, 2, 81), (2, 0, 2, 79), (2, 2, 1, 77), (2, 3, 1, 76),
                 (3, 0, 1.5, 77), (3, 1.5, .5, 79), (3, 2, 2, 81), (4, 0, 4, 81),
                 (5, 0, 2, 86), (5, 2, 2, 82), (6, 0, 2, 79), (6, 2, 1, 81), (6, 3, 1, 82), (7, 0, 4, 81)]
# The hum in the second phrase, over F, C, Dm, A, Bb, F, Gm, A.
SILENCIO_HUM = [(0, 0, 2, 69), (0, 2, 2, 72), (1, 0, 3, 67), (1, 3, 1, 64), (2, 0, 2, 65), (2, 2, 1, 69),
                (2, 3, 1, 74), (3, 0, 4, 73), (4, 0, 2, 74), (4, 2, 2, 70), (5, 0, 2, 69), (5, 2, 2, 65),
                (6, 0, 1.5, 67), (6, 1.5, .5, 69), (6, 2, 2, 70), (7, 0, 4, 69)]


def voicing(ch):
    r = next(m for m in range(43, 55) if m % 12 == CHORDS[ch][0])
    return [r] + tones(ch, r + 1, r + 14)[:3]


def low_root(ch):
    return next(m for m in range(38, 50) if m % 12 == CHORDS[ch][0])


def shifted(part, bars, shift=0):
    return [(b + bars, bt, d, m + shift) for b, bt, d, m in part]


def silencio_snow(c, mix):
    for bar, ch in enumerate(SILENCIO_CHORDS):
        for m in voicing(ch):
            mix.put(strings(m, c.dur(4), 0.9, attack=1.2, release=1.4), c.at(bar), "far", rng.uniform(-.4, .4), 0.07)
        phrase = bar // 8
        low = low_root(ch)
        arp = [low, low + 7, low + 12] + tones(ch, low + 13, low + 30)[:3]
        arp = arp + arp[-2:0:-1]
        if phrase in (0, 2):        # eighths rocking up and back
            for j in range(8):
                v = 0.45 + 0.15 * (j == 0) + rng.uniform(-.05, .05)
                mix.put(piano(arp[j % len(arp)], c.dur(1.6), v), c.at(bar, j * 0.5) + rng.normal(0, 0.006),
                        "far", -0.2 + 0.05 * j, 0.3 if phrase == 0 else 0.24)
        elif phrase == 1:           # quarters, slower to the ear, under the hum
            for j in range(4):
                mix.put(piano(arp[j], c.dur(2.2), 0.4 + rng.uniform(-.04, .04)), c.at(bar, j) + rng.normal(0, 0.006),
                        "far", -0.15 + 0.1 * j, 0.28)
        else:                       # a chord and a single high note: nearly nothing
            for m in [low] + tones(ch, low + 7, low + 16)[:2]:
                mix.put(piano(m, c.dur(3.8), 0.38), c.at(bar) + rng.normal(0, 0.008), "far", -0.2, 0.26)
            top = tones(ch, 74, 86)[rng.integers(0, 2)]
            mix.put(piano(top, c.dur(2), 0.32), c.at(bar, 2) + rng.normal(0, 0.01), "far", 0.25, 0.26)
    s, sig = sing(notes_of(c, shifted(SILENCIO_HUM, 8), vel=0.8), "u_sop", tilt=1.6, attack=0.25, release=0.4,
                  glide=0.09, vib_rate=5.0, vib_depth=0.22, vib_delay=0.4, drift=0.05)
    mix.put(sig, s, "far", 0.15, 0.2)
    for b, bt, d, m in shifted(SILENCIO_TUNE, 16):      # the tune on the piano's top, a music box in the snow
        mix.put(piano(m, c.dur(d + 0.5), 0.42), c.at(b, bt), "far", 0.2, 0.3)


def silencio_unease(c, mix):
    for bar, ch in enumerate(SILENCIO_CHORDS):
        r = low_root(ch)
        for m in (r - 12, r - 5):
            mix.put(strings(m, c.dur(4), 0.9, attack=1.6, release=1.0, voices=2), c.at(bar), "far", rng.uniform(-.3, .3), 0.08)
        for j, m in enumerate((r - 12, r - 5, r, r - 5)):   # pizzicato walking in quarters
            mix.put(pluck(m, 0.22, 0.9 if j == 0 else 0.7, pickup=0.3, tau=0.6, bright=0.3, maxf=2500, damp=0.05, click=0.05),
                    c.at(bar, j) + rng.normal(0, 0.004), "close", 0.1, 0.28)
        tm = r - 12 if r - 12 >= 36 else r
        mix.put(timp(tm, 0.35, 1.2), c.at(bar), "close", -0.1, 0.4)        # lub
        mix.put(timp(tm, 0.22, 1.0), c.at(bar, 0.4), "close", -0.1, 0.4)   # dub
        if bar % 4 == 0:
            high = 81 if ch != "C" else 79
            mix.put(strings(high, c.dur(12), 0.6, attack=3.0, release=2.0, voices=2), c.at(bar), "far", 0.4, 0.022)
            mix.put(pluck(r - 12, c.dur(6), 0.7, pickup=0.09, tau=3.0, bright=1.0, maxf=6000, vib=0.2),
                    c.at(bar), "guitar", -0.35, 0.22)


def silencio_fight(c, mix):
    accents = [1, .4, .55, .4, .8, .4, .55, .65]
    for bar, ch in enumerate(SILENCIO_CHORDS):
        r = low_root(ch)
        tm = r - 12 if r - 12 >= 36 else r
        phrase, inbar = bar // 8, bar % 8
        for j, v in enumerate(accents):
            mix.put(timp(tm, v * 0.8, 1.0), c.at(bar, j * 0.5) + rng.normal(0, 0.003), "close", -0.1, 0.4)
            m = (r - 12, r, r - 12, r - 5)[j % 4]
            mix.put(strings(m, 0.17, 0.9 if j % 2 == 0 else 0.7, attack=0.015, release=0.09, voices=2),
                    c.at(bar, j * 0.5), "mid", 0.2, 0.09)
        if inbar == 7:
            snare_roll(mix, c, bar, 2, 2, 0.1, 0.8, 0.8)
        if inbar == 0:
            mix.put(bell(57, 7.0, 0.7), c.at(bar), "far", -0.4, 0.3)
        if phrase in (1, 3):
            for m in tones(ch, 48, 62):
                cs, csig = choir([(c.at(bar), c.dur(3.8), m, 0.8)], "a_male", voices=3, attack=0.3,
                                 release=0.4, glide=0, vib_depth=0.15, drift=0.05)
                mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.05)
    for phrase in (0, 2):
        s, sig = sing(notes_of(c, shifted(SILENCIO_TUNE, phrase * 8), 0, 0.9), "a_sop", tilt=1.2, attack=0.08,
                      release=0.16, glide=0.08, vib_rate=5.8, vib_depth=0.35, vib_delay=0.2, drift=0.04, scoop=0.25)
        mix.put(sig, s, "far", 0.1, 0.42)


def layered(c, bars, parts):
    """Each part rendered as a layer of the loop's exact length. Each is rendered
    with a tail and the tail folded back onto its start, so the loop's seam rings
    on like any other bar line. parts: (name, fn(clock, mix), seed)."""
    global rng
    loop = c.end(bars) - c.t0
    out = {}
    for name, part, seed in parts:
        rng = np.random.default_rng(seed)
        mix = Mix(loop + 6.0)
        part(c, mix)
        x = render(mix)
        n = secs(loop)
        x[:, :x.shape[1] - n] += x[:, n:]
        out[name] = x[:, :n]
    # One gain for all of them, so they sit together as written.
    peak = np.abs(sum(out.values())).max()
    for k in out:
        out[k] *= 0.9 / peak
    return out


def silencio():
    return layered(Clock(0.0, SILENCIO_BPM), len(SILENCIO_CHORDS),
                   (("snow", silencio_snow, 11), ("unease", silencio_unease, 12), ("fight", silencio_fight, 13)))


# --- Cruz Verde: the fort asleep, then the battle --------------------------
#
# Twelve-eight at a dotted crotchet of 80, A minor walking down to E (the
# Spanish way down), 32 bars round. The fort layer is the ground both halves
# stand on: a picked guitar and the low string tolling. Tension plays while the
# fort's asleep and the stranger's creeping in: a tick like a clock, the jaw
# harp now and then, a whistle from the walls, a high string held. When the
# shooting starts it gives way to the battle: the bass galloping in threes,
# military drumming with no backbeat, rasgueados on the strong beats, two
# trumpets in thirds as the revolution's bands play them, the chapel bell, the
# men's choir and the gang shouting.

CRUZ_BEAT = 80
CRUZ_CHORDS = [
    "Am", "G", "F", "E", "Am", "G", "F", "E",
    "Dm", "Am", "Dm", "E", "F", "G", "Am", "E",
    "Am", "G", "F", "E", "Am", "G", "F", "E",
    "F", "G", "Am", "Am", "Dm", "E", "Am", "E",
]
# The battle tune, for the trumpets: (bar, eighth, eighths, midi), per eight bars.
CRUZ_TUNE = [
    (0, 0, 3, 76), (0, 3, 3, 81), (0, 6, 3, 84), (0, 9, 2, 83), (0, 11, 1, 81),
    (1, 0, 6, 83), (1, 6, 3, 79), (1, 9, 2, 81), (1, 11, 1, 83),
    (2, 0, 3, 84), (2, 3, 3, 81), (2, 6, 3, 77), (2, 9, 2, 81), (2, 11, 1, 84),
    (3, 0, 9, 83), (3, 9, 1, 80), (3, 10, 1, 81), (3, 11, 1, 83),
    (4, 0, 3, 84), (4, 3, 3, 83), (4, 6, 3, 81), (4, 9, 3, 76),
    (5, 0, 3, 86), (5, 3, 3, 84), (5, 6, 3, 83), (5, 9, 3, 79),
    (6, 0, 3, 81), (6, 3, 3, 84), (6, 6, 3, 81), (6, 9, 3, 77),
    (7, 0, 10, 76),
]
CRUZ_CALLS = [   # the second phrase: calls answered by the choir
    (0, 0, 3, 74), (0, 3, 3, 77), (0, 6, 6, 81),
    (1, 0, 3, 76), (1, 3, 3, 81), (1, 6, 6, 84),
    (2, 0, 6, 86), (2, 6, 6, 81),
    (3, 0, 6, 80), (3, 6, 6, 83),
    (4, 0, 3, 81), (4, 3, 3, 84), (4, 6, 6, 84),
    (5, 0, 3, 83), (5, 3, 3, 86), (5, 6, 6, 79),
    (6, 0, 3, 84), (6, 3, 3, 83), (6, 6, 6, 81),
    (7, 0, 6, 80), (7, 6, 6, 83),
]
CRUZ_LAST = [    # the fourth: F G Am Am Dm E Am E, a gap for the shouting
    (0, 0, 6, 81), (0, 6, 6, 84), (1, 0, 6, 83), (1, 6, 6, 86), (2, 0, 10, 84),
    (4, 0, 3, 74), (4, 3, 3, 77), (4, 6, 3, 81), (4, 9, 3, 86), (5, 0, 9, 83), (5, 9, 3, 80),
    (6, 0, 10, 81),
]
# The whistle from the walls, over the first eight bars.
CRUZ_WHISTLE = [
    (0, 0, 9, 81), (0, 9, 1, 83), (0, 10, 1, 81), (0, 11, 1, 79),
    (1, 0, 3, 83), (1, 3, 6, 86), (1, 9, 2, 84), (1, 11, 1, 83),
    (2, 0, 6, 84), (2, 6, 6, 81),
    (3, 0, 12, 83),
    (4, 0, 6, 88), (4, 6, 3, 86), (4, 9, 3, 84),
    (5, 0, 6, 83), (5, 6, 6, 79),
    (6, 0, 3, 81), (6, 3, 3, 84), (6, 6, 3, 83), (6, 9, 3, 81),
    (7, 0, 6, 80), (7, 6, 6, 83),
]


def third_below(m, ch, scale=None):
    """The second trumpet's note: a chord tone under the tune, else a third under
    it in the key (A minor, with G sharp over E, unless told another scale)."""
    under = [t for t in tones(ch, m - 5, m - 3)]
    if under:
        return under[-1]
    if scale is None:
        scale = (9, 11, 0, 2, 4, 5, 8 if ch == "E" else 7)
    below = [x for x in range(m - 4, m - 2) if x % 12 in scale]
    return below[0] if below else m - 3


def tick(vel=1.0):
    """A dry wooden tick, like a clock in an empty room."""
    n = secs(0.12)
    t = np.arange(n) / SR
    nz = noise(n, lambda f: hp(f, 1800, 2) * lp(f, 7000) * bump(f, 3200, 6, 0.5))
    tone = np.sin(2 * np.pi * 1250 * t) * np.exp(-t / 0.012)
    return (0.5 * nz * np.exp(-t / 0.006) + 0.5 * tone) * vel


def cruz_ground(c, mix):
    """The picked guitar and the low string tolling: under the battle only, so the
    sleeping fort keeps its silences."""
    pedal(mix, c, CRUZ_CHORDS, 0.55)
    arpeggio(mix, c, CRUZ_CHORDS, 0.55)


# The sleeping fort: a sound, then nothing, then another. Each a moment at
# (bar, eighth); the gaps between them, two to six seconds of only the wind and
# the hall dying away, are the point. Some stop dead; a roll swells into no hit.
CRUZ_QUIET = [
    (0, 0, "twang", 33), (2, 0, "harp", 0), (2, 3, "harp", 1), (3, 6, "ticks", 3),
    (4, 0, "whistle", (0, 2)), (6, 3, "harmonic", 88), (8, 0, "bell", 69),
    (10, 0, "drone", 45), (12, 0, "ping", 76), (13, 0, "harp", 2), (13, 3, "harp", 0), (13, 6, "harp", 1),
    (16, 0, "twang", 33), (16, 0, "bell", 69), (18, 0, "whistle", (2, 4)), (18, 0, "ticks", 8),
    (21, 0, "roll", 45), (24, 0, "tremolo", 88), (27, 0, "ticks", 4),
    (28, 0, "twang", 40), (29, 6, "harp", 2), (30, 0, "whistle", (7, 8)),
]


def cruz_tension(c, mix):
    sweeps = [(350, 1500, 0.08), (1400, 500, 0.1), (400, 1200, 0.06)]
    for bar, e, what, arg in CRUZ_QUIET:
        t = c.at(bar, e)
        if what == "twang":     # a low string, plucked once and left to ring out
            mix.put(pluck(arg, c.dur(10), 1.0, pickup=0.09, tau=3.0, bright=1.1, maxf=6000, vib=0.25),
                    t, "guitar", -0.3, 0.3)
        elif what == "harp":
            mix.put(jaw_harp(45, c.dur(2), sweeps[arg], 0.9), t, "mid", -0.45, 0.12)
        elif what == "ticks":   # a clock in an empty room, a few strokes and stopped
            for j in range(arg):
                mix.put(tick(0.7 if j == 0 else 0.5), c.at(bar, e + j * 3), "mid", 0.5, 0.08)
        elif what == "whistle":
            lo, hi = arg
            part = [n for n in CRUZ_WHISTLE if lo <= n[0] < hi]
            s0, sig = whistle(notes_of(c, shifted(part, bar - lo)))
            mix.put(sig, s0, "mid", 0.25, 0.2)
        elif what == "harmonic":
            mix.put(strings(arg, c.dur(9), 0.6, attack=2.5, release=1.5, voices=2), t, "far", 0.4, 0.025)
        elif what == "bell":
            mix.put(bell(arg, 8.0, 0.7), t, "far", -0.4, 0.2)
        elif what == "drone":   # low strings swelling for two bars, then cut off dead
            for m in (arg - 12, arg - 5):
                mix.put(strings(m, c.dur(24), 0.9, attack=c.dur(22), release=0.04, voices=3), t, "mid", 0.0, 0.07)
            mix.put(timp(arg - 12 if arg - 12 >= 36 else arg, 0.4, 1.6), t, "close", -0.1, 0.4)
        elif what == "ping":    # one high note on the guitar, alone
            mix.put(pluck(arg, c.dur(6), 0.8, pickup=0.15, tau=2.5, bright=0.9), t, "mid", 0.35, 0.16)
        elif what == "roll":    # a timpani swelling for a bar... into nothing
            k = 48
            for j in range(k):
                mix.put(timp(arg - 12 if arg - 12 >= 36 else arg, 0.05 + 0.6 * (j / k) ** 2, 0.5),
                        c.at(bar, e + j / 4), "close", -0.1, 0.42)
        elif what == "tremolo":  # a high string trembling, held three bars, cut
            n = strings(arg, c.dur(34), 0.7, attack=c.dur(20), release=0.05, voices=3)
            tt = np.arange(len(n)) / SR
            mix.put(n * (0.7 + 0.3 * np.sin(2 * np.pi * 11 * tt)), t, "far", 0.4, 0.03)


def cruz_battle(c, mix):
    cruz_ground(c, mix)
    snare_vel = [.8, .2, .25, .4, .2, .25, .6, .2, .25, .4, .3, .5]
    for bar, ch in enumerate(CRUZ_CHORDS):
        phrase, inbar = bar // 8, bar % 8
        r = bass_note(ch)
        tm = r if r >= 36 else r + 12
        for e in range(12):
            v = (1.0, 0.55, 0.75)[e % 3]
            t = c.at(bar, e) + rng.normal(0, 0.003)
            mix.put(pluck(r, c.dur(1) * 0.85, v, pickup=0.22, tau=1.0, bright=0.45, maxf=2500, damp=0.03, click=0.1),
                    t, "close", 0.0, 0.5)
            mix.put(strings(r + 12, 0.12, v, attack=0.01, release=0.07, voices=2), t, "mid", -0.15, 0.07)
            mix.put(snare(snare_vel[e]), t, "close", 0.15, 0.24)
            if snare_vel[e] >= 0.6:
                mix.put(snare(0.2), t - 0.018, "close", 0.15, 0.24)   # the flam
        mix.put(timp(tm, 1.0), c.at(bar), "close", -0.1, 0.55)
        mix.put(timp(tm, 0.7), c.at(bar, 6), "close", -0.1, 0.5)
        for e in (0, 6):
            rasgueado(mix, c, ch, c.at(bar, e), 1.0)
        if inbar == 0:
            mix.put(bell(69, 6.0, 0.9), c.at(bar), "far", -0.4, 0.35)
            mix.put(bell(69, 5.0, 0.6), c.at(bar, 6), "far", -0.4, 0.3)
        if inbar == 7:
            snare_roll8(mix, c, bar, 6, 6, 0.2, 1.0)
        if phrase in (1, 3):
            for m in tones(ch, 48, 62):
                cs, csig = choir([(c.at(bar), c.dur(11.5), m, 0.8)], "a_male", voices=3, attack=0.15,
                                 release=0.3, glide=0, vib_depth=0.15, drift=0.05)
                mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.05)
    for bar, e in ((7, 3), (7, 6), (11, 6), (15, 3), (15, 6), (19, 6), (23, 3), (23, 6),
                   (27, 0), (27, 6), (31, 0), (31, 3), (31, 6)):
        mix.put(shout(55 + rng.integers(0, 3)), c.at(bar, e) - 0.03, "mid", rng.uniform(-.3, .3), 0.38)
    lines = shifted(CRUZ_TUNE, 0) + shifted(CRUZ_CALLS, 8) + shifted(CRUZ_TUNE, 16) + shifted(CRUZ_LAST, 24)
    lead = [(b, e, d, m) for b, e, d, m in lines]
    second = [(b, e, d, third_below(m, CRUZ_CHORDS[b])) for b, e, d, m in lines]
    for part, pan, gain in ((lead, -0.25, 0.22), (second, 0.25, 0.16)):
        s, sig = trumpet(notes_of(c, part, 0, 0.95))
        mix.put(sig, s, "mid", pan, gain)


def cruz_verde():
    return layered(Clock8(0.0, CRUZ_BEAT), len(CRUZ_CHORDS),
                   (("tension", cruz_tension, 22), ("battle", cruz_battle, 23)))


# --- Paso Esperanza: waiting for the army, then the fight for the train --------
#
# Not layers but a run of pieces, one after the other (scripts/music.gd plays
# them through an AudioStreamInteractive), all at 132 in E minor. The build plays
# once from the start: a low string pulsing like a slow train, a heartbeat, a
# high string; at ten seconds (when word comes that they're on the road) a bugle
# far off, the federales' own, answered from another side, then both again, nearer
# each time, over a quiet snare and the choir, everything swelling onto B. The hold goes on swelling, round
# and round, till the first soldier walks onto the map, whenever that is. Then the
# call: the bugle up close over a roll, and the action crashes in: strings
# chugging in sixteenths like the engine, the march's drums (no backbeat),
# trumpets in thirds, the twang, whips and an anvil, the choir and the soprano,
# the gang shouting. Two minutes round, and round again till it's over. Won, the
# trumpets close it on E major and a bell.

TRAIN_BPM = 132
TRAIN_A = ["Em", "Em", "D", "D", "C", "C", "B", "B"]
TRAIN_B = ["Am", "Em", "Am", "B", "C", "D", "Em", "B"]
TRAIN_C = ["Em", "F", "Em", "F", "C", "D", "B", "B"]
TRAIN_FORM = "AABCABCA"
TRAIN_CHORDS = sum(({"A": TRAIN_A, "B": TRAIN_B, "C": TRAIN_C}[k] for k in TRAIN_FORM), [])
E_MINOR = (4, 6, 7, 9, 11, 0, 2)
TRAIN_TUNE = [   # (bar, beat, beats, midi): the A phrase
    (0, 0, 1.5, 83), (0, 1.5, .5, 79), (0, 2, 1, 76), (0, 3, 1, 79),
    (1, 0, 2, 83), (1, 2, 1, 84), (1, 3, 1, 83),
    (2, 0, 1.5, 81), (2, 1.5, .5, 78), (2, 2, 1, 74), (2, 3, 1, 78),
    (3, 0, 3, 81),
    (4, 0, 1.5, 79), (4, 1.5, .5, 76), (4, 2, 1, 72), (4, 3, 1, 76),
    (5, 0, 2, 79), (5, 2, 1, 81), (5, 3, 1, 79),
    (6, 0, 1.5, 78), (6, 1.5, .5, 75), (6, 2, 1, 71), (6, 3, 1, 75),
    (7, 0, 3, 78),
]
TRAIN_TURN = [(7, 0, 1, 83), (7, 1, 1, 81), (7, 2, 1, 79), (7, 3, 1, 78)]   # the A phrase's second ending
TRAIN_CALLS = [  # the B phrase
    (0, 0, .5, 76), (0, .5, .5, 81), (0, 1, 3, 84), (1, 0, 4, 83),
    (2, 0, .5, 76), (2, .5, .5, 81), (2, 1, 2, 84), (2, 3, 1, 88),
    (3, 0, 2, 87), (3, 2, 2, 83), (4, 0, 2, 88), (4, 2, 2, 84),
    (5, 0, 2, 86), (5, 2, 2, 81), (6, 0, 1, 83), (6, 1, 1, 79), (6, 2, 2, 76), (7, 0, 4, 78),
]
TRAIN_SONG = [   # the C phrase, for the soprano
    (0, 0, 4, 83), (1, 0, 4, 84), (2, 0, 2, 83), (2, 2, 2, 79), (3, 0, 4, 81),
    (4, 0, 2, 79), (4, 2, 2, 76), (5, 0, 2, 78), (5, 2, 2, 81), (6, 0, 4, 83), (7, 0, 4, 78),
]
# The bugle's call, on the open notes of a bugle in B: three quick, then up.
BUGLE = [(0, 1 / 3, 71), (1 / 3, 1 / 3, 71), (2 / 3, 1 / 3, 71), (1, 1, 78), (2, .5, 75), (2.5, .5, 78), (3, 2.5, 83)]


def anvil(vel=1.0):
    n = secs(1.2)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, tau in ((1, 1, .9), (2.76, .6, .5), (5.4, .35, .3), (8.93, .2, .18)):
        out += a * np.exp(-t / tau) * np.sin(2 * np.pi * 1100 * r * t + rng.uniform(0, 6.3))
    out /= 2.15
    out += 0.4 * noise(n, lambda f: hp(f, 2000)) * np.exp(-t / 0.004)
    return out * vel


# Another bugle answering from another side: down from the top.
BUGLE_ANSWER = [(0, .5, 78), (.5, .5, 78), (1, 1, 83), (2, .5, 78), (2.5, .5, 75), (3, 2, 71)]


def bugle(c, at, far=False, call=BUGLE, near=None):
    """The army's call. A bugle has no valves: no vibrato to speak of, bright.
    near (0 far off .. 1 at hand) darkens it with the distance; far is near 0."""
    notes = [(c.at(0, at + b), c.dur(d) * 0.95, m, 1.0) for b, d, m in call]
    start, ph, f, a = line(notes, attack=0.03, release=0.08, glide=0.01, vib_depth=0.04, drift=0.02,
                           scoop=0.4, scoop_time=0.03, artic=0.05, punch=0.35)
    e = a / (a.max() + 1e-9)
    out = np.zeros(len(a))
    for k in range(1, 24):
        if k * float(f.mean()) > 9000:
            break
        out += e ** (1 + 0.3 * (k - 1)) * k ** -0.05 * lp(k * f, 4500) * bump(k * f, 1500, 7, 0.7) * np.sin(k * ph)
    out /= np.abs(out).max() + 1e-9
    if near is None and far:
        near = 0.0
    if near is not None and near < 1.0:
        cut = 2200 * (3.0 ** near)
        out = fft_filter(out, lambda fr: lp(fr, cut, 2) * hp(fr, 300 * (1 - near) + 60))
    return start, out


def train_build(c, mix):
    roots = ["Em"] * 6 + ["C", "C", "D", "D", "B", "B"]
    for bar, ch in enumerate(roots):
        r = low_root(ch)
        grow = bar / 11
        for e in range(8):   # the pulse, a slow train
            mix.put(pluck(r, c.dur(0.4), (0.9 if e % 2 == 0 else 0.6), pickup=0.2, tau=0.8, bright=0.5,
                          maxf=3000, damp=0.03, click=0.1), c.at(bar, e * 0.5), "close", 0.0, 0.18 + 0.3 * grow)
        if bar < 9:
            mix.put(timp(r if r >= 36 else r + 12, 0.35 + 0.2 * grow, 1.2), c.at(bar), "close", -0.1, 0.4)
            mix.put(timp(r if r >= 36 else r + 12, 0.22 + 0.1 * grow, 1.0), c.at(bar, 0.4), "close", -0.1, 0.4)
        if bar >= 7:
            for j in range(16):
                mix.put(snare(0.08 + 0.3 * grow + (0.15 if j % 4 == 0 else 0)), c.at(bar, j / 4), "close", 0.15, 0.25)
        if bar >= 9:
            for j in range(8):
                mix.put(timp(r if r >= 36 else r + 12, 0.3 + 0.5 * grow, 0.8), c.at(bar, j / 2), "close", -0.1, 0.4)
            for m in tones(ch, 47, 62):
                cs, csig = choir([(c.at(bar), c.dur(3.9), m, 0.5 + 0.4 * grow)], "a_male", voices=3, attack=0.6,
                                 release=0.3, glide=0, vib_depth=0.15, drift=0.05)
                mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.05)
        if bar >= 10:
            mix.put(strings(83, c.dur(4), 0.8, attack=1.0, release=0.2, voices=3), c.at(bar), "far", 0.4, 0.04)
    mix.put(strings(88, c.dur(16), 0.6, attack=4.0, release=1.5, voices=2), c.at(1), "far", 0.4, 0.02)
    # Word of them on the road: a bugle far off, answered from another side, then
    # both again, nearer each time; the last of them up close is the call itself.
    for beat, call, pan, near, gain in ((5 * 4 + 2, BUGLE, 0.5, 0.0, 0.14), (7 * 4, BUGLE_ANSWER, -0.6, 0.15, 0.13),
                                        (8 * 4 + 2, BUGLE, 0.45, 0.35, 0.17), (9 * 4 + 2, BUGLE_ANSWER, -0.5, 0.5, 0.18),
                                        (10 * 4 + 1, BUGLE, 0.4, 0.65, 0.2)):
        s0, sig = bugle(c, beat, call=call, near=near)
        mix.put(sig, s0, "far", pan, gain)
    snare_roll(mix, c, 11, 0, 4, 0.3, 0.9, 0.9)
    for j in range(16):
        mix.put(timp(35, 0.4 + 0.5 * j / 15, 0.8), c.at(11, j / 4), "close", -0.1, 0.4)


def _swelling(c, mix, bars, level=1.0):
    """B held: a timpani and a snare rolling, the low pulse, strings and choir held."""
    for bar in range(bars):
        for j in range(16):
            mix.put(timp(35, (0.45 + 0.1 * (j % 4 == 0)) * level, 0.7), c.at(bar, j / 4), "close", -0.1, 0.25)
            mix.put(snare((0.25 + 0.1 * (j % 4 == 0)) * level), c.at(bar, j / 4), "close", 0.15, 0.15)
        for e in range(8):
            mix.put(pluck(35, c.dur(0.4), 0.9 if e % 2 == 0 else 0.65, pickup=0.2, tau=0.8, bright=0.5, maxf=3000,
                          damp=0.03, click=0.1), c.at(bar, e * 0.5), "close", 0.0, 0.3 * level)
    for m in (47, 54, 59, 63):
        mix.put(strings(m, c.dur(4 * bars), 0.9, attack=0.05, release=0.05, voices=3), c.at(0), "mid", rng.uniform(-.4, .4), 0.035)
    for m in (47, 54, 59):
        cs, csig = choir([(c.at(0), c.dur(4 * bars), m, 0.85)], "a_male", voices=3, attack=0.1, release=0.1,
                         glide=0, vib_depth=0.15, drift=0.05)
        mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.03)
    mix.put(strings(83, c.dur(4 * bars), 0.8, attack=0.05, release=0.05, voices=3), c.at(0), "far", 0.4, 0.025)


def train_hold(c, mix):
    _swelling(c, mix, 4)


def train_call(c, mix):
    _swelling(c, mix, 2, 0.9)
    snare_roll(mix, c, 1, 2, 2, 0.4, 1.0)
    s0, sig = bugle(c, 0)
    mix.put(sig, s0, "mid", -0.2, 0.32)


def train_action(c, mix):
    snare_vel = [.8, .2, .3, .2, .5, .2, .3, .4, .8, .2, .3, .2, .5, .3, .6, .4]
    for bar, ch in enumerate(TRAIN_CHORDS):
        sec, inbar = TRAIN_FORM[bar // 8], bar % 8
        r = low_root(ch)
        tm = r if r >= 36 else r + 12
        for j in range(16):   # the engine: strings chugging in sixteenths
            m = (r + 12, r + 24, r + 19, r + 24)[j % 4]
            t = c.at(bar, j / 4) + rng.normal(0, 0.002)
            mix.put(strings(m, 0.09, 1.0 if j % 4 == 0 else 0.7, attack=0.008, release=0.05, voices=2), t, "mid", 0.25, 0.05)
            mix.put(snare(snare_vel[j]), t, "close", 0.15, 0.22)
            if j % 2 == 0:
                mix.put(pluck(r, c.dur(0.45), 1.0 if j % 8 == 0 else 0.65, pickup=0.22, tau=1.0, bright=0.45,
                              maxf=2500, damp=0.03, click=0.1), t, "close", 0.0, 0.45)
        mix.put(timp(tm, 1.0), c.at(bar), "close", -0.1, 0.55)
        mix.put(timp(tm, 0.75), c.at(bar, 2), "close", -0.1, 0.5)
        if inbar == 0:
            mix.put(whip(), c.at(bar) - 0.14, "mid", 0.5, 0.28)
        if sec == "C":
            mix.put(anvil(0.7), c.at(bar, 3), "mid", 0.45, 0.12)
            mix.put(anvil(0.5), c.at(bar, 3.5), "mid", 0.45, 0.12)
        if sec in "BC":
            for m in tones(ch, 48, 62):
                cs, csig = choir([(c.at(bar), c.dur(3.9), m, 0.8)], "a_male", voices=3, attack=0.12,
                                 release=0.25, glide=0, vib_depth=0.15, drift=0.05)
                mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.045)
        if inbar == 7 and bar == len(TRAIN_CHORDS) - 1:
            snare_roll(mix, c, bar, 2, 2, 0.3, 1.0)
    trumpet_lines = []
    for i, sec in enumerate(TRAIN_FORM):
        b0 = i * 8
        if sec == "A":
            tune = TRAIN_TUNE if i % 2 == 0 else [n for n in TRAIN_TUNE if n[0] < 7] + TRAIN_TURN
            trumpet_lines += shifted(tune, b0)
            for b in (3, 7):   # the twang in the gaps
                ch = TRAIN_CHORDS[b0 + b]
                riff = [low_root(ch) + 12 + x for x in (0, 7, 12, 7)] if i % 2 else [low_root(ch) + 12 + x for x in (12, 7, 3 if "m" in ch else 4, 0)]
                for j, m in enumerate(riff):
                    mix.put(pluck(m, c.dur(0.5), 1.0, pickup=0.09, tau=1.6, bright=1.3, maxf=7000),
                            c.at(b0 + b, 2 + j * 0.5), "guitar", -0.3, 0.4)
            mix.put(shout(55 + rng.integers(0, 3)), c.at(b0 + 7, 3) - 0.03, "mid", rng.uniform(-.3, .3), 0.38)
        elif sec == "B":
            trumpet_lines += shifted(TRAIN_CALLS, b0)
            for b in (3, 7):
                mix.put(shout(55 + rng.integers(0, 3)), c.at(b0 + b, 3) - 0.03, "mid", rng.uniform(-.3, .3), 0.38)
        else:
            s0, sig = sing(notes_of(c, shifted(TRAIN_SONG, b0), 0, 0.9), "a_sop", tilt=1.2, attack=0.08,
                           release=0.14, glide=0.06, vib_rate=5.8, vib_depth=0.35, vib_delay=0.15, drift=0.04, scoop=0.25)
            mix.put(sig, s0, "far", 0.1, 0.4)
            for b in range(8):   # the twang doubling the engine, low
                ch = TRAIN_CHORDS[b0 + b]
                for j in range(8):
                    mix.put(pluck(low_root(ch) + 12, c.dur(0.4), 0.9 if j % 2 == 0 else 0.6, pickup=0.09, tau=1.2,
                                  bright=1.2, maxf=7000, damp=0.03), c.at(b0 + b, j / 2), "guitar", -0.35, 0.14)
    lead = trumpet_lines
    second = [(b, e, d, third_below(m, TRAIN_CHORDS[b], E_MINOR if TRAIN_CHORDS[b] != "B" else (4, 6, 7, 9, 11, 0, 3)))
              for b, e, d, m in trumpet_lines]
    for part, pan, gain in ((lead, -0.25, 0.22), (second, 0.25, 0.16)):
        s0, sig = trumpet(notes_of(c, part, 0, 0.95))
        mix.put(sig, s0, "mid", pan, gain)


def train_won(c, mix):
    close = [(0, 0, 2, 83), (0, 2, 2, 79), (1, 0, 2, 84), (1, 2, 2, 79), (2, 0, 2, 78), (2, 2, 2, 75), (3, 0, 8, 80)]
    chords = ["Em", "C", "B", "E", "E", "E"]
    second = [(b, e, d, third_below(m, chords[b], (4, 6, 8, 9, 11, 1, 3) if chords[b] == "E" else E_MINOR))
              for b, e, d, m in close]
    for part, pan, gain in ((close, -0.25, 0.24), (second, 0.25, 0.18)):
        s0, sig = trumpet(notes_of(c, part, 0, 0.95))
        mix.put(sig, s0, "mid", pan, gain)
    for bar, ch in enumerate(chords[:4]):
        r = low_root(ch)
        mix.put(timp(r if r >= 36 else r + 12, 0.9 if bar == 3 else 0.6, 3.0 if bar == 3 else 1.4), c.at(bar), "close", -0.1, 0.5)
        mix.put(pluck(r, c.dur(4 if bar < 3 else 10), 0.9, pickup=0.22, tau=2.0, bright=0.45, maxf=2500), c.at(bar), "close", 0.0, 0.45)
        for m in tones(ch, 52, 68):
            mix.put(strings(m, c.dur(4 if bar < 3 else 9), 0.8, attack=0.2, release=1.6, voices=2), c.at(bar), "far",
                    rng.uniform(-.5, .5), 0.05)
    mix.put(bell(64, 9.0, 0.8), c.at(3), "far", -0.4, 0.35)
    snare_roll(mix, c, 2, 2, 2, 0.2, 0.8)


def train():
    """The pieces in the order they play: (name, audio, loops)."""
    global rng
    c = Clock(0.0, TRAIN_BPM)
    out = []
    for name, part, bars, loops, seed in (("build", train_build, 12, False, 31), ("hold", train_hold, 4, True, 32),
                                          ("call", train_call, 2, False, 33), ("action", train_action, 64, True, 34),
                                          ("won", train_won, 7, False, 35)):
        rng = np.random.default_rng(seed)
        n = secs(c.end(bars))
        mix = Mix(c.end(bars) + 6.0)
        part(c, mix)
        x = render(mix)
        if loops:
            x[:, :x.shape[1] - n] += x[:, n:]
            x = x[:, :n]
        else:
            x = x[:, :n] if name != "won" else x   # (a piece that hands over stops on its bar line; the end rings out)
        beats = bars * 4 if loops or name != "won" else int(x.shape[1] / SR * TRAIN_BPM / 60)   # (the win rings out past its bars)
        out.append((name, x, loops, beats))
    peak = max(np.abs(x).max() for _, x, _, _ in out)
    return [(name, x * 0.9 / peak, loops, beats) for name, x, loops, beats in out]


# --- San Miguel: the first town, and the theme ----------------------------
#
# The game's own tune, the one to remember: four bars that climb a fourth and
# a fifth to a held note, then the same a step down, twice, and home. G minor,
# twelve-eight at a dotted crotchet of 76, 32 bars (A B A B, 101 s round). Two
# layers, as at Cruz Verde, but here the tension never stops: the town's held
# by a gang and a man hangs at noon. It plays all the while there's no fight:
# the picked guitar and the low string tolling, a clock ticking every beat, the
# jaw harp, the bell at each phrase, a high string, the timpani swelling into
# the next, and over it the theme whistled; the second time round, twanged low.
# The fight is Cruz Verde's band (they liked it there) with the theme on the
# trumpets, in thirds: the same tune, now in the open.

SM_BEAT = 76
SM_A = ["Gm", "Gm", "F", "F", "Eb", "D", "Gm", "D"]
SM_B = ["Cm", "Gm", "Cm", "D", "Eb", "F", "D", "Gm"]
SM_CHORDS = SM_A + SM_B + SM_A + SM_B
SM_THEME_A = [   # (bar, eighth, eighths, midi)
    (0, 0, 3, 74), (0, 3, 3, 79), (0, 6, 5, 82), (0, 11, 1, 81),
    (1, 0, 9, 79), (1, 9, 3, 74),
    (2, 0, 3, 72), (2, 3, 3, 77), (2, 6, 5, 81), (2, 11, 1, 79),
    (3, 0, 9, 77), (3, 9, 3, 72),
    (4, 0, 3, 70), (4, 3, 3, 75), (4, 6, 3, 79), (4, 9, 3, 82),
    (5, 0, 6, 81), (5, 6, 3, 78), (5, 9, 3, 74),
    (6, 0, 3, 79), (6, 3, 3, 82), (6, 6, 6, 86),
    (7, 0, 12, 78),
]
SM_THEME_B = [
    (0, 0, 6, 87), (0, 6, 3, 86), (0, 9, 3, 84),
    (1, 0, 6, 82), (1, 6, 6, 79),
    (2, 0, 3, 84), (2, 3, 3, 87), (2, 6, 3, 86), (2, 9, 3, 84),
    (3, 0, 12, 81),
    (4, 0, 6, 82), (4, 6, 6, 79),
    (5, 0, 6, 81), (5, 6, 6, 84),
    (6, 0, 3, 82), (6, 3, 3, 81), (6, 6, 3, 79), (6, 9, 3, 78),
    (7, 0, 12, 79),
]
G_MINOR = (7, 9, 10, 0, 2, 3, 5)


def sm_scale(ch):
    return (7, 9, 10, 0, 2, 3, 6) if ch == "D" else G_MINOR


def sm_tension(c, mix):
    pedal(mix, c, SM_CHORDS, 0.4)
    arpeggio(mix, c, SM_CHORDS, 0.4)
    sweeps = [(350, 1500, 0.08), (1400, 500, 0.1), (400, 1200, 0.06)]
    for bar, ch in enumerate(SM_CHORDS):
        phrase, inbar = bar // 8, bar % 8
        for beat in range(4):   # the clock: noon's coming
            mix.put(tick(0.7 if beat == 0 else 0.45), c.at(bar, beat * 3), "mid", 0.5, 0.05)
        if bar % 2 == 0:
            for j, e in enumerate((0, 6)):
                mix.put(jaw_harp(43, c.dur(1.5), sweeps[(bar + j) % 3], 0.8), c.at(bar, e), "mid", -0.45, 0.06)
        if inbar == 0:
            mix.put(bell(67, 7.0, 0.6), c.at(bar), "far", -0.4, 0.13)
        if phrase % 2 == 1 and inbar % 4 == 0:
            mix.put(strings(86, c.dur(46), 0.6, attack=4.0, release=2.0, voices=2), c.at(bar), "far", 0.4, 0.018)
        if inbar == 7:
            timp_roll(mix, c, bar, 6, 6, 43)
    for phrase, part in enumerate((SM_THEME_A, SM_THEME_B, SM_THEME_A, SM_THEME_B)):
        if phrase == 2:   # the second time round, twanged low on the guitar
            for b, e, d, m in shifted(part, 16):
                long = d >= 6
                mix.put(pluck(m - 12, c.dur(d) * 0.95, 1.0, pickup=0.09, tau=2.8 if long else 1.6, bright=1.3,
                              maxf=7000, damp=0.04, vib=0.3 if long else 0.0), c.at(b, e), "guitar", -0.15, 0.32)
        else:
            s0, sig = whistle(notes_of(c, shifted(part, phrase * 8)))
            mix.put(sig, s0, "mid", 0.2, 0.17)


def sm_battle(c, mix):
    pedal(mix, c, SM_CHORDS, 0.55)
    arpeggio(mix, c, SM_CHORDS, 0.55)
    snare_vel = [.8, .2, .25, .4, .2, .25, .6, .2, .25, .4, .3, .5]
    for bar, ch in enumerate(SM_CHORDS):
        phrase, inbar = bar // 8, bar % 8
        r = bass_note(ch)
        tm = r if r >= 36 else r + 12
        for e in range(12):
            v = (1.0, 0.55, 0.75)[e % 3]
            t = c.at(bar, e) + rng.normal(0, 0.003)
            mix.put(pluck(r, c.dur(1) * 0.85, v, pickup=0.22, tau=1.0, bright=0.45, maxf=2500, damp=0.03, click=0.1),
                    t, "close", 0.0, 0.5)
            mix.put(strings(r + 12, 0.12, v, attack=0.01, release=0.07, voices=2), t, "mid", -0.15, 0.07)
            mix.put(snare(snare_vel[e]), t, "close", 0.15, 0.24)
            if snare_vel[e] >= 0.6:
                mix.put(snare(0.2), t - 0.018, "close", 0.15, 0.24)   # the flam
        mix.put(timp(tm, 1.0), c.at(bar), "close", -0.1, 0.55)
        mix.put(timp(tm, 0.7), c.at(bar, 6), "close", -0.1, 0.5)
        for e in (0, 6):
            rasgueado(mix, c, ch, c.at(bar, e), 1.0)
        if inbar == 0:
            mix.put(whip(), c.at(bar) - 0.14, "mid", 0.5, 0.28)
            mix.put(bell(67, 6.0, 0.9), c.at(bar), "far", -0.4, 0.32)
        if inbar == 7:
            snare_roll8(mix, c, bar, 6, 6, 0.2, 1.0)
        if phrase % 2 == 1:
            for m in tones(ch, 48, 62):
                cs, csig = choir([(c.at(bar), c.dur(11.5), m, 0.8)], "a_male", voices=3, attack=0.15,
                                 release=0.3, glide=0, vib_depth=0.15, drift=0.05)
                mix.put(csig, cs, "far", rng.uniform(-.6, .6), 0.05)
    for bar, e in ((7, 3), (7, 6), (15, 6), (15, 9), (23, 3), (23, 6), (31, 0), (31, 6)):
        mix.put(shout(55 + rng.integers(0, 3)), c.at(bar, e) - 0.03, "mid", rng.uniform(-.3, .3), 0.38)
    lines = shifted(SM_THEME_A, 0) + shifted(SM_THEME_B, 8) + shifted(SM_THEME_A, 16) + shifted(SM_THEME_B, 24)
    second = [(b, e, d, third_below(m, SM_CHORDS[b], sm_scale(SM_CHORDS[b]))) for b, e, d, m in lines]
    for part, pan, gain in ((lines, -0.25, 0.22), (second, 0.25, 0.16)):
        s0, sig = trumpet(notes_of(c, part, 0, 0.95))
        mix.put(sig, s0, "mid", pan, gain)
    for b, e, d, m in shifted(SM_THEME_A, 16):   # the twang doubling the trumpets, an octave down, the third phrase
        mix.put(pluck(m - 12, c.dur(d) * 0.95, 1.0, pickup=0.09, tau=2.4 if d >= 6 else 1.4, bright=1.3,
                      maxf=7000, damp=0.04, vib=0.3 if d >= 6 else 0.0), c.at(b, e), "guitar", -0.4, 0.3)


def san_miguel():
    return layered(Clock8(0.0, SM_BEAT), len(SM_CHORDS),
                   (("tension", sm_tension, 41), ("battle", sm_battle, 42)))


# Each level's score: its layers, and the part each plays (see scripts/music.gd).
SCORES = {
    "silencio": (silencio, {"snow": "always", "unease": "unease", "fight": "fight"}),
    "cruz_verde": (cruz_verde, {"tension": "calm", "battle": "fight"}),
    "train": (train, None),   # pieces played in turn, not layers
    "san_miguel": (san_miguel, {"tension": "calm", "battle": "fight"}),
}


def bake(meta, assets):
    """Called by gen_assets.py: writes each level's layers and lists them in meta.
    SUNDANCE_MUSIC=cruz_verde bakes only that one (each takes minutes)."""
    meta.setdefault("music", {})
    only = [k for k in os.environ.get("SUNDANCE_MUSIC", "").split(",") if k]
    for name, (fn, roles) in SCORES.items():
        if only and name not in only:
            continue
        if roles is None:
            pieces = []
            for k, x, loops, beats in fn():
                rel = "music/%s_%s.ogg" % (name, k)
                write_ogg(os.path.join(assets, rel), x)
                pieces.append({"name": k, "path": "res://assets/" + rel, "loops": loops, "beats": beats})
                print("    %s %s: %.1f s, %.1f dB rms" % (name, k, x.shape[1] / SR, 20 * np.log10(np.sqrt((x ** 2).mean()))))
            meta["music"][name] = {"bpm": TRAIN_BPM, "pieces": pieces}
            continue
        layers = fn()
        out = []
        for k, x in layers.items():
            rel = "music/%s_%s.ogg" % (name, k)
            write_ogg(os.path.join(assets, rel), x)
            out.append({"name": k, "role": roles[k], "path": "res://assets/" + rel})
            print("    %s %s: %.1f dB rms" % (name, k, 20 * np.log10(np.sqrt((x ** 2).mean()))))
        meta["music"][name] = {"layers": out}


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "train":
        # a listen through: the build, the hold twice round, the call, the action, the win
        if len(sys.argv) > 2 and sys.argv[2] == "build":   # the build alone, quick, into the hold and the call
            global rng
            c = Clock(0.0, TRAIN_BPM)
            run = []
            for part, bars, seed in ((train_build, 12, 31), (train_hold, 2, 32), (train_call, 2, 33)):
                rng = np.random.default_rng(seed)
                mix = Mix(c.end(bars) + 1.0)
                part(c, mix)
                run.append(render(mix)[:, :secs(c.end(bars))])
            x = np.concatenate(run, axis=1)
            os.makedirs("build/music", exist_ok=True)
            write_wav("build/music/train_build.wav", x * 0.9 / np.abs(x).max())
            return
        pieces = {k: x for k, x, _, _ in train()}
        run = [pieces["build"], pieces["hold"], pieces["hold"][:, :secs(2 * 4 * 60 / TRAIN_BPM)], pieces["call"],
               pieces["action"], pieces["won"]]
        os.makedirs("build/music", exist_ok=True)
        write_wav("build/music/train_preview.wav", np.clip(np.concatenate(run, axis=1), -1, 1))
        return
    if len(sys.argv) > 1 and sys.argv[1] in SCORES:
        name = sys.argv[1]
        layers = SCORES[name][0]()
        os.makedirs("build/music", exist_ok=True)
        for k, x in layers.items():
            write_wav("build/music/%s_%s.wav" % (name, k), x)
        write_wav("build/music/%s_all.wav" % name, np.clip(sum(layers.values()), -1, 1))
        return
    out = sys.argv[1] if len(sys.argv) > 1 else "build/music/sundance_theme.wav"
    t0 = time.time()
    mix, marks = compose()
    x = master(mix)
    write_wav(out, x)
    print(f"wrote {out} ({x.shape[1] / SR:.1f} s) in {time.time() - t0:.0f} s")
    # How loud each bus sits in each section, to keep the lead on top.
    names = list(marks) + ["_"]
    times = list(marks.values()) + [x.shape[1] / SR]
    for i, name in enumerate(names[:-1]):
        a, b = secs(times[i]), secs(times[i + 1])
        row = "  ".join(f"{bus}:{20 * np.log10(np.sqrt((mix.bus[bus][:, a:b] ** 2).mean()) + 1e-9):6.1f}" for bus in mix.bus)
        print(f"{name:9s} {times[i]:5.1f}s  {row}")


if __name__ == "__main__":
    main()
