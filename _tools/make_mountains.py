#!/usr/bin/env python3
"""Key the white background out of the Martian mountain art and auto-crop to the
silhouette, so the layers can be composited over the sky as parallax backdrops.

Sources (committed, white-backed RGB): assets/martian-surface-{near,far}.png
Outputs (committed, RGBA, trimmed):     assets/generated/martian-surface-{near,far}.png

The background is near-white (min channel >= ~238) and the mountains are clearly
darker/coloured (min channel <= ~192), so alpha is a smooth ramp on the per-pixel
min channel: white -> transparent, mountain -> opaque, with a soft edge band.
"""
import os
from PIL import Image

SRC_DIR = os.path.join(os.path.dirname(__file__), "..", "assets")
OUT_DIR = os.path.join(SRC_DIR, "generated")

# Alpha ramp on min(r,g,b): >= HI is background (a=0), <= LO is solid (a=255).
LO, HI = 210, 238
# Crop to where alpha is at least this, so faint haze margins don't inflate the
# bbox — the silhouette's solid base ends up at the image bottom (seats on ground).
BBOX_ALPHA = 40


def key(name):
    im = Image.open(os.path.join(SRC_DIR, name + ".png")).convert("RGB")
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            m = min(r, g, b)
            if m >= HI:
                a = 0
            elif m <= LO:
                a = 255
            else:
                a = int(round(255 * (HI - m) / (HI - LO)))
            op[x, y] = (r, g, b, a)
    # Trim faint margins (alpha < BBOX_ALPHA) so the solid silhouette base sits at
    # the image bottom and seats cleanly on the ground.
    mask = out.split()[-1].point(lambda v: 255 if v >= BBOX_ALPHA else 0)
    bbox = mask.getbbox()
    if bbox:
        out = out.crop(bbox)
    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, name + ".png")
    out.save(dst)
    print(f"{name}: {im.size} -> cropped {out.size}  ({dst})")


for n in ("martian-surface-far", "martian-surface-near"):
    key(n)
