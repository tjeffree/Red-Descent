"""Process the raw rig sprites in assets/rig/ into clean, aligned animation
frames under assets/generated/rig/.

The raw art (1024x1024 each) has a solid BLACK background and the rig's own
outlines are near-black, so we strip the background by flood-filling inward from
the canvas edges (interior black outlines are never reached and survive).

`rig-move.png` is a 2-frame walk sheet (frames side by side); the rest are single
poses. Every frame is re-composited onto a uniform canvas, anchored on the
centroid of the rig's glowing green chest screen, so the body stays put when the
game swaps animations (only legs / flames / drill move between poses).
"""
import os
from PIL import Image, ImageDraw

SRC = "C:/Projects/red-descent/assets/rig"
OUT = "C:/Projects/red-descent/assets/generated/rig"
SENTINEL = (255, 0, 255)        # temporary key colour for the flooded background
BG_THRESH = 60                  # how far from corner-black still counts as background
CANVAS = 1024                   # uniform output canvas (square)
# Where the green-screen anchor lands in the output canvas. Slightly above centre
# so dangling legs / thruster flames have room below without clipping.
ANCHOR = (CANVAS // 2, int(CANVAS * 0.46))


def strip_background(im):
    """Return an RGBA copy with the contiguous edge background made transparent."""
    im = im.convert("RGBA")
    rgb = im.convert("RGB")
    # Flood-fill from every edge pixel; ImageDraw.floodfill is contiguous so it
    # only eats the connected background, never enclosed dark outlines.
    seeds = []
    w, h = rgb.size
    for x in range(0, w, 8):
        seeds.append((x, 0)); seeds.append((x, h - 1))
    for y in range(0, h, 8):
        seeds.append((0, y)); seeds.append((w - 1, y))
    for s in seeds:
        if rgb.getpixel(s) != SENTINEL:
            ImageDraw.floodfill(rgb, s, SENTINEL, thresh=BG_THRESH)
    out = im.copy()
    op = out.load()
    rp = rgb.load()
    for y in range(h):
        for x in range(w):
            if rp[x, y] == SENTINEL:
                op[x, y] = (0, 0, 0, 0)
    return out


def green_anchor(im):
    """Centroid of the rig's bright-green screen pixels (px coords)."""
    px = im.load()
    w, h = im.size
    sx = sy = n = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b, a = px[x, y]
            if a > 0 and g > 120 and g > r + 40 and g > b + 40:
                sx += x; sy += y; n += 1
    if n == 0:
        # fall back to the alpha bbox centre
        bb = im.getbbox()
        return ((bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2)
    return (sx // n, sy // n)


def green_height(im):
    """Vertical extent (px) of the rig's green chest screen. The screen is a
    rigid, shared feature, so its height is the most reliable cross-pose size
    gauge (rotation about the vertical axis barely changes it)."""
    px = im.load()
    w, h = im.size
    ys = [y for y in range(h) for x in range(0, w, 2)
          if (lambda p: p[3] > 0 and p[1] > 120 and p[1] > p[0] + 40 and p[1] > p[2] + 40)(px[x, y])]
    return (max(ys) - min(ys)) if ys else 0


def normalize(im, target_h):
    """Uniformly scale `im` so its green-screen height matches target_h. The
    source poses were authored at different zooms; this makes the rig one size."""
    gh = green_height(im)
    if gh <= 0:
        return im
    f = float(target_h) / float(gh)
    if abs(f - 1.0) < 0.01:
        return im
    return im.resize((max(1, round(im.width * f)), max(1, round(im.height * f))),
                     Image.LANCZOS)


def recenter(im):
    """Paste `im` onto a CANVAS-square so its green anchor sits at ANCHOR."""
    ax, ay = green_anchor(im)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(im, (ANCHOR[0] - ax, ANCHOR[1] - ay))
    return canvas


def split_move(im):
    """Split the walk sheet into its two frames by the transparent gap."""
    px = im.load()
    w, h = im.size
    occ = []
    for x in range(w):
        col = any(px[x, y][3] > 0 for y in range(0, h, 4))
        occ.append(col)
    runs = []
    start = None
    for x, o in enumerate(occ):
        if o and start is None:
            start = x
        elif not o and start is not None:
            runs.append((start, x - 1)); start = None
    if start is not None:
        runs.append((start, w - 1))
    # keep the two widest runs (guards against stray specks)
    runs.sort(key=lambda r: r[1] - r[0], reverse=True)
    runs = sorted(runs[:2])
    frames = []
    for (x0, x1) in runs:
        pad = 8
        frames.append(im.crop((max(0, x0 - pad), 0, min(w, x1 + 1 + pad), h)))
    return frames


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {
        "rig-jump.png": "jump",
        "rig-thrust.png": "thrust",
        "rig-thust-side.png": "thrust_side",
    }
    # Background-strip everything first (move splits into its two walk frames).
    raw = {}  # name -> background-stripped RGBA (original zoom)
    for fname, name in jobs.items():
        raw[name] = strip_background(Image.open(os.path.join(SRC, fname)))
    move = strip_background(Image.open(os.path.join(SRC, "rig-move.png")))
    for i, fr in enumerate(split_move(move)):
        raw["move_%d" % i] = fr

    # The walk frames are the canonical size (the in-game scale is tuned on them),
    # so normalize every pose's green-screen height to the walk frames' average.
    target_h = round((green_height(raw["move_0"]) + green_height(raw["move_1"])) / 2.0)

    frames = {}  # name -> normalized + recentred RGBA on the shared CANVAS
    for name, im in raw.items():
        frames[name] = recenter(normalize(im, target_h))
        print("%-12s green_h %3d -> %3d" % (name, green_height(im), target_h))

    # One common crop rectangle for every frame keeps them pixel-aligned (all
    # centred=true on the same point) while trimming the huge transparent margin.
    union = None
    for im in frames.values():
        bb = im.getbbox()
        if bb is None:
            continue
        union = bb if union is None else (
            min(union[0], bb[0]), min(union[1], bb[1]),
            max(union[2], bb[2]), max(union[3], bb[3]))
    pad = 4
    union = (max(0, union[0] - pad), max(0, union[1] - pad),
             min(CANVAS, union[2] + pad), min(CANVAS, union[3] + pad))
    for name, im in frames.items():
        im.crop(union).save(os.path.join(OUT, name + ".png"))
        print("wrote %s.png" % name)
    print("common frame size:", (union[2] - union[0], union[3] - union[1]))


if __name__ == "__main__":
    main()
