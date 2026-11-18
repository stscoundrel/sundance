"""Compares the freshly baked assets with what's committed, by what they draw and sound
like, not their bytes: another machine's PNG encoder can pack the same pixels differently,
and that's no change to the game. Called by tools/check_bake.sh after a bake; exits 1 if
any sprite or sound differs, or any other baked file differs at all."""
import io
import subprocess
import sys

import numpy as np
import soundfile
from PIL import Image


def committed(path):
    return subprocess.run(["git", "show", "HEAD:" + path], capture_output=True, check=True).stdout


def decoded(path, data):
    if path.endswith(".png"):
        return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"))
    if path.endswith(".wav"):
        return soundfile.read(io.BytesIO(data), dtype="int32")[0]
    return None


def main():
    status = subprocess.run(["git", "status", "--porcelain", "--", "assets"],
                            capture_output=True, text=True, check=True).stdout.splitlines()
    differ = []
    for line in status:
        code, path = line[:2], line[3:]
        if code.strip() != "M":
            differ.append(f"{path} ({'new' if code == '??' else 'gone'})")
            continue
        old, new = committed(path), open(path, "rb").read()
        a, b = decoded(path, old), decoded(path, new)
        if a is None:
            differ.append(path)
        elif a.shape != b.shape:
            differ.append(f"{path} (size {a.shape} -> {b.shape})")
        elif not np.array_equal(a, b):
            d = np.abs(a.astype(np.int64) - b.astype(np.int64))
            differ.append(f"{path} ({np.count_nonzero(d)} values differ, by up to {d.max()})")
    same = len(status) - len(differ)
    if same:
        print(f"{same} files re-encoded with the same pixels or samples (not a change)")
    if differ:
        print("The bake came out different from what's committed:")
        for d in differ[:40]:
            print("   ", d)
        print(f"{len(differ)} files in all")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
