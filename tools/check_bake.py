"""Compares baked assets by what they draw and sound like, not their bytes: another
encoder can pack the same pixels differently, and that's no change to the game. Called
by tools/check_bake.sh after a bake; exits 1 if any sprite or sound differs, or any
other baked file differs at all.
    check_bake.py                 # this checkout's fresh bake against what's committed
    check_bake.py BASE HERE       # two checkouts' fresh bakes against each other (each
                                  # wrote its files after its own assets/.bake_stamp)
The second is the one CI runs: a bake on another machine can round a pixel or two
differently from the one the assets were baked on, so the fair question for a pull
request is whether its bake differs from the base's on the same runner."""
import io
import os
import subprocess
import sys

import numpy as np
import soundfile
from PIL import Image


def decoded(path, data):
    if path.endswith(".png"):
        return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"))
    if path.endswith(".wav"):
        return soundfile.read(io.BytesIO(data), dtype="int32")[0]
    return None


def compare(path, old, new):
    """None if the two are the same to the eye and ear, else what's different."""
    if old == new:
        return None
    a, b = decoded(path, old), decoded(path, new)
    if a is None:
        return path
    if a.shape != b.shape:
        return f"{path} (size {a.shape} -> {b.shape})"
    if np.array_equal(a, b):
        return None
    d = np.abs(a.astype(np.int64) - b.astype(np.int64))
    return f"{path} ({np.count_nonzero(d)} values differ, by up to {d.max()})"


def against_committed():
    status = subprocess.run(["git", "status", "--porcelain", "--", "assets"],
                            capture_output=True, text=True, check=True).stdout.splitlines()
    differ = []
    for line in status:
        code, path = line[:2], line[3:]
        if code.strip() != "M":
            differ.append(f"{path} ({'new' if code == '??' else 'gone'})")
            continue
        old = subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, check=True).stdout
        d = compare(path, old, open(path, "rb").read())
        if d:
            differ.append(d)
    return len(status), differ


def baked(root):
    """The files under root's assets/ that its bake wrote (newer than its stamp)."""
    stamp = os.path.getmtime(os.path.join(root, "assets", ".bake_stamp"))
    out = set()
    for d, _, files in os.walk(os.path.join(root, "assets")):
        for f in files:
            p = os.path.join(d, f)
            if f != ".bake_stamp" and os.path.getmtime(p) >= stamp:
                out.add(os.path.relpath(p, root))
    return out


def between(base, here):
    a, b = baked(base), baked(here)
    differ = [f"{p} (only the {'base' if p in a else 'pull request'} bakes it)" for p in sorted(a ^ b)]
    for p in sorted(a & b):
        d = compare(p, open(os.path.join(base, p), "rb").read(), open(os.path.join(here, p), "rb").read())
        if d:
            differ.append(d)
    return len(a | b), differ


def main():
    if len(sys.argv) == 3:
        n, differ = between(sys.argv[1], sys.argv[2])
        what = "the base's bake"
    else:
        n, differ = against_committed()
        what = "what's committed"
    if n - len(differ):
        print(f"{n - len(differ)} files the same to the eye and ear")
    if differ:
        print(f"The bake came out different from {what}:")
        for d in differ[:40]:
            print("   ", d)
        print(f"{len(differ)} files in all")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
