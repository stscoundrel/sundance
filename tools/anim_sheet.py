"""A contact sheet of baked animation frames, to look over a bake without the game.
Each frame is drawn over the standing legs, 2x, ten to a row (greyscale: the
palette is applied in game).
  tools/.venv/bin/python tools/anim_sheet.py TEMPLATE ANIMS DIRS OUT.png
  tools/.venv/bin/python tools/anim_sheet.py hero upper/schofield/aim,upper/schofield/reload_open 1,3,6 /tmp/s.png
ANIMS are keys of meta.json's chars[TEMPLATE]["anims"]; DIRS are 0-7."""
import json
import os
import sys

from PIL import Image

out_path = os.path.abspath(sys.argv[4])   # (before moving to the project root)
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
meta = json.load(open("assets/meta.json"))
tpl = sys.argv[1]
keys = sys.argv[2].split(",")
dirs = [int(d) for d in sys.argv[3].split(",")]
c = meta["chars"][tpl]
atlas = Image.open(c["atlas"].replace("res://", ""))
cells = []
for k in keys:
    a = c["anims"][k]
    for d in dirs:
        lx, ly, lw, lh, lox, loy = c["anims"]["legs/idle"]["frames"][d][0]
        legs = (atlas.crop((lx, ly, lx + lw, ly + lh)), lox, loy)
        for f in a["frames"][d]:
            x, y, w, h, ox, oy = f
            cells.append((legs, (atlas.crop((x, y, x + w, y + h)), ox, oy)))
W, H, cols = 110, 150, 10
rows = (len(cells) + cols - 1) // cols
out = Image.new("RGBA", (cols * W, rows * H), (200, 180, 150, 255))
for i, (lg, up) in enumerate(cells):
    cx, cy = (i % cols) * W + W // 2, (i // cols) * H + H - 20
    for im, ox, oy in (lg, up):
        out.alpha_composite(im, (int(cx + ox), int(cy + oy)))
out = out.resize((out.width * 2, out.height * 2), Image.NEAREST)
out.save(out_path)
