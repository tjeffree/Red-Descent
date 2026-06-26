"""Slice `assets/many tiles.png` into per-block-type variant tiles.

The sheet is a 9-column x 7-row grid of framed, rounded-corner blocks on a black
background, one block type per row (Dirt, Rock, Basalt, Permafrost, Ore, Bulkhead,
Vault), 9 variants each. For each tile we:

  1. find the tile's solid square (the connected, non-black region at the cell
     centre) and crop to its bounding box,
  2. fill the black rounded-corner notches with the nearest neighbouring colour so
     the tile becomes a full square that tiles seamlessly (Basalt's *internal*
     dark craters are left alone -- only background-connected black is filled),
  3. downscale to 32x32 (Lanczos) and save as
     assets/generated/tiles/<name>_<variant>.png.

Run from the repo root:  python _tools/slice_tiles.py
"""
import os
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "many tiles.png")
OUT = os.path.join(ROOT, "assets", "generated", "tiles")

ROWS = ["dirt", "rock", "basalt", "permafrost", "ore", "bulkhead", "vault"]
COLS = 9
OUT_SIZE = 32
DARK = 50          # RGB-sum below this counts as black background
PAD = 56           # half-window around each cell centre (tile pitch ~113)


def runs(arr, thresh):
    out, inr, start = [], False, 0
    for i, v in enumerate(arr):
        if v > thresh and not inr:
            start, inr = i, True
        elif v <= thresh and inr:
            out.append((start, i - 1)); inr = False
    if inr:
        out.append((start, len(arr) - 1))
    return out


def centers(arr, thresh, expect):
    r = runs(arr, thresh)
    assert len(r) == expect, f"expected {expect} bands, got {len(r)}: {r}"
    return [(a + b) // 2 for a, b in r]


def slice_tile(img, cx, cy):
    """Return a clean square RGB tile centred on (cx, cy)."""
    H, W, _ = img.shape
    x0, x1 = max(0, cx - PAD), min(W, cx + PAD)
    y0, y1 = max(0, cy - PAD), min(H, cy + PAD)
    win = img[y0:y1, x0:x1]
    h, w, _ = win.shape
    dark = win.sum(2) < DARK

    # Exterior background = black flood-filled from the four window corners.
    ext = np.zeros((h, w), bool)
    dq = deque()
    for (yy, xx) in [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)]:
        if dark[yy, xx] and not ext[yy, xx]:
            ext[yy, xx] = True; dq.append((yy, xx))
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and dark[ny, nx] and not ext[ny, nx]:
                ext[ny, nx] = True; dq.append((ny, nx))

    # The tile = the non-exterior blob connected to the window centre.
    comp = np.zeros((h, w), bool)
    cy0, cx0 = h // 2, w // 2
    comp[cy0, cx0] = True
    dq = deque([(cy0, cx0)])
    while dq:
        y, x = dq.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not ext[ny, nx] and not comp[ny, nx]:
                comp[ny, nx] = True; dq.append((ny, nx))

    ys, xs = np.where(comp)
    ty0, ty1, tx0, tx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    tile = win[ty0:ty1, tx0:tx1].astype(np.float32).copy()
    hole = ~comp[ty0:ty1, tx0:tx1]          # corner notches to fill

    # Inpaint holes: repeatedly set each hole pixel bordering filled pixels to the
    # mean of those filled neighbours, until no holes remain.
    th, tw, _ = tile.shape
    while hole.any():
        filled = ~hole
        acc = np.zeros_like(tile)
        cnt = np.zeros((th, tw), np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sy0, sy1 = max(0, dy), th + min(0, dy)
            sx0, sx1 = max(0, dx), tw + min(0, dx)
            dy0, dy1 = max(0, -dy), th + min(0, -dy)
            dx0, dx1 = max(0, -dx), tw + min(0, -dx)
            src_f = filled[dy0:dy1, dx0:dx1]
            acc[sy0:sy1, sx0:sx1][src_f] += tile[dy0:dy1, dx0:dx1][src_f]
            cnt[sy0:sy1, sx0:sx1] += src_f
        paint = hole & (cnt > 0)
        tile[paint] = acc[paint] / cnt[paint, None]
        hole[paint] = False

    out = Image.fromarray(tile.round().clip(0, 255).astype(np.uint8), "RGB")
    return out.resize((OUT_SIZE, OUT_SIZE), Image.Resampling.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    img = np.array(Image.open(SRC).convert("RGB")).astype(int)
    mask = img.sum(2) > 60          # above the near-black background
    col_c = centers(mask.sum(0), 250, COLS)
    row_c = centers(mask.sum(1), 250, len(ROWS))
    n = 0
    for r, name in enumerate(ROWS):
        for c in range(COLS):
            tile = slice_tile(img, col_c[c], row_c[r])
            tile.save(os.path.join(OUT, f"{name}_{c}.png"))
            n += 1
    print(f"wrote {n} tiles to {OUT}")


if __name__ == "__main__":
    main()
