"""A top-down plan of a map's layout (data/*.json): the tile grid numbered, streets
outlined, objects as boxes (walls brown, cover green, others blue), gang posts red,
sleepers orange, townsfolk blue. For placing things in tools/make_*.py by tile.
  tools/.venv/bin/python tools/map_plan.py data/cruz_verde.json OUT.png [x0,y0,x1,y1]"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from world import BUILDINGS  # noqa: E402

d = json.load(open(sys.argv[1]))
if len(sys.argv) > 3:
    x0, y0, x1, y1 = (int(v) for v in sys.argv[3].split(","))
else:
    x0, y0 = 0, 0
    x1, y1 = d["size"] if isinstance(d["size"], list) else (d["size"], d["size"])
S = 22
im = Image.new("RGB", ((x1 - x0) * S, (y1 - y0) * S), (220, 200, 160))
dr = ImageDraw.Draw(im)
for i in range(x0, x1):
    dr.line([((i - x0) * S, 0), ((i - x0) * S, im.height)], fill=(205, 185, 145))
    dr.text(((i - x0) * S + 2, 2), str(i), fill=(120, 100, 80))
for j in range(y0, y1):
    dr.line([(0, (j - y0) * S), (im.width, (j - y0) * S)], fill=(205, 185, 145))
    dr.text((2, (j - y0) * S + 2), str(j), fill=(120, 100, 80))
for r in d.get("streets", []):
    dr.rectangle([((r[0] - x0) * S, (r[1] - y0) * S), ((r[2] - x0) * S, (r[3] - y0) * S)], outline=(160, 140, 220))
for o in d["objects"]:
    w, h = BUILDINGS[o["type"]][1]
    c = BUILDINGS[o["type"]][2]
    col = {"wall": (110, 80, 60), "cover": (60, 140, 60), "none": (200, 200, 200)}.get(c, (60, 60, 160))
    box = [((o["x"] - x0) * S, (o["y"] - y0) * S), ((o["x"] + w - x0) * S, (o["y"] + h - y0) * S)]
    dr.rectangle(box, fill=col, outline=(0, 0, 0))
    if w * S > 30:
        dr.text((box[0][0] + 2, box[0][1] + 2), o["type"][:10], fill=(255, 255, 255))
for group, r, col in (("enemies", 4, (220, 0, 0)), ("sleepers", 4, (255, 140, 0)), ("civilians", 3, (0, 120, 255))):
    for e in d.get(group, []):
        dr.ellipse([((e["x"] - x0) * S - r, (e["y"] - y0) * S - r), ((e["x"] - x0) * S + r, (e["y"] - y0) * S + r)], fill=col)
im.save(sys.argv[2])
