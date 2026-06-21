"""Mask the four ship-wreckage repair stages onto transparent backgrounds.

The artist supplied four illustrations of the same ship on a flat ~(128,128,128)
grey field, progressing from crashed wreck (stage 0) to fully repaired and
standing on its legs (stage 3). The hull occupies the SAME pixel region in every
image; only its condition changes (holes -> patched -> dish/antenna -> pristine
hull with venting thrusters). Below the hull each later stage grows a descent
gangway / landing legs / elevator that, in game, would sit at or below the
surface line — plus a decorative sparkle in the corner.

We therefore use ONE common crop box that captures the hull and its top-mounted
antennas/dish (and stage 3's right-side thrusters) but stops at the hull's base,
so the four sprites are pixel-aligned and the lower structure / sparkle drop out.
For each: border flood-fill the grey to alpha, crop, feather the cut edge.
Outputs: assets/generated/wreckage-0.png .. wreckage-3.png (RGBA).
"""
import os
from collections import deque
from PIL import Image, ImageFilter

STAGES = [
    'assets/wreckage-sprite.jpg',
    'assets/wreckage-sprite-repair-1.jpg',
    'assets/wreckage-sprite-repair-2.jpg',
    'assets/wreckage-sprite-repair-3.jpg',
]

# Common crop (left, top, right, bottom), right/bottom exclusive. Found by the
# per-row foreground scan in _tools/analyze_wreckage.py: hull + antennas/dish +
# stage-3 thrusters, cut just below the hull base (y~288) to shed gangway/legs.
CROP = (58, 8, 828, 288)

BG = (128, 128, 128)
TOL = 30        # max per-channel distance from grey to flood through
NEUTRAL = 16    # max channel spread; tinted ship panels survive


def is_bg(p):
    return (abs(p[0] - BG[0]) <= TOL and
            abs(p[1] - BG[1]) <= TOL and
            abs(p[2] - BG[2]) <= TOL and
            max(p[0], p[1], p[2]) - min(p[0], p[1], p[2]) <= NEUTRAL)


def mask_one(src, out):
    im = Image.open(src).convert('RGBA')
    W, H = im.size
    px = im.load()

    # Alpha mask: 0 for background-connected grey (flood from the border, so
    # grey panels *inside* the ship are never punched out).
    visited = bytearray(W * H)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            i = y * W + x
            if not visited[i] and is_bg(px[x, y]):
                visited[i] = 1
                q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            i = y * W + x
            if not visited[i] and is_bg(px[x, y]):
                visited[i] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H:
                i = ny * W + nx
                if not visited[i] and is_bg(px[nx, ny]):
                    visited[i] = 1
                    q.append((nx, ny))

    for y in range(H):
        for x in range(W):
            if visited[y * W + x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)

    ship = im.crop(CROP)

    # Feather: erode the alpha edge 1px to bury the grey JPEG halo, then smooth
    # so the cut doesn't read as a hard sticker line at game scale.
    a = ship.getchannel('A')
    a = a.filter(ImageFilter.MinFilter(3))
    a = a.filter(ImageFilter.GaussianBlur(0.6))
    ship.putalpha(a)

    ship.save(out)
    print('wrote %s %r' % (out, ship.size))


def main():
    os.makedirs('assets/generated', exist_ok=True)
    for i, src in enumerate(STAGES):
        mask_one(src, 'assets/generated/wreckage-%d.png' % i)


main()
