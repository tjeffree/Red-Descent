"""Bake Martian-palette block textures for Red Descent's terrain.

Each terrain material is drawn as a single solid 18x18 tile repeated across the
side-view dig grid, so a tile here is one self-contained block: a flat Mars
base colour + deterministic surface grain + scattered pebbles/flecks + a subtle
1px bevel (dark border, lit top row) so blocks read as discrete chunks in the
GDD's "chunky, high-contrast pixel art" direction.

Output -> assets/generated/mars_<name>.png  (committed; wired up in world.gd).
The Ore tile composites the Kenney cyan gem (CC0) onto a Mars-red host rock so
veins stay high-contrast and readable against the red regolith.

Run from the project root:  python _tools/make_mars_tiles.py
Deterministic: every material uses a fixed RNG seed so re-runs are byte-stable.
"""
import os
import random

from PIL import Image

T = 18

# Martian palette per material: base fill, darker edge/pebble, lighter fleck.
# Hand-tuned toward Mars regolith reds/ochres (Crust) deepening to warm
# volcanic charcoal (Mantle basalt); permafrost is dirty subsurface ice.
PALETTES = {
    "dirt": {       # surface regolith: butterscotch rust ochre
        "base": (158, 86, 54), "dark": (110, 58, 38), "light": (192, 122, 82),
        "grain": 16, "pebbles": 5, "flecks": 10, "seed": 101,
    },
    "rock": {       # reddish-brown basaltic stone, dust-coated
        "base": (122, 64, 50), "dark": (84, 44, 36), "light": (152, 90, 72),
        "grain": 14, "pebbles": 7, "flecks": 8, "seed": 102,
    },
    "basalt": {     # deep Mantle: warm near-black volcanic charcoal
        "base": (64, 45, 43), "dark": (38, 27, 27), "light": (96, 70, 66),
        "grain": 12, "pebbles": 8, "flecks": 6, "seed": 103,
    },
    "permafrost": {  # dusty subsurface ice: cool blue-grey, dirty flecks
        "base": (176, 196, 206), "dark": (128, 150, 166), "light": (232, 240, 246),
        "grain": 10, "pebbles": 4, "flecks": 14, "seed": 104,
    },
}


def _clampb(v):
    return max(0, min(255, int(v)))


def _jitter(rng, color, amount):
    """Brightness-jitter an RGB colour by +/- amount (keeps hue stable)."""
    d = rng.randint(-amount, amount)
    return (_clampb(color[0] + d), _clampb(color[1] + d), _clampb(color[2] + d))


def make_block(palette):
    rng = random.Random(palette["seed"])
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    px = img.load()

    # 1. Base fill with subtle per-pixel grain.
    for y in range(T):
        for x in range(T):
            px[x, y] = _jitter(rng, palette["base"], palette["grain"]) + (255,)

    # 2. Scattered 2x2 pebbles (darker clumps).
    for _ in range(palette["pebbles"]):
        cx, cy = rng.randint(1, T - 3), rng.randint(2, T - 3)
        col = _jitter(rng, palette["dark"], palette["grain"]) + (255,)
        for dx in range(2):
            for dy in range(2):
                px[cx + dx, cy + dy] = col

    # 3. Single-pixel highlight flecks (mineral sparkle / dust catch).
    for _ in range(palette["flecks"]):
        fx, fy = rng.randint(0, T - 1), rng.randint(1, T - 1)
        px[fx, fy] = _jitter(rng, palette["light"], palette["grain"]) + (255,)

    # 4. Chunky bevel: dark 1px border all round, lit top + left inner edge.
    dark = palette["dark"]
    light = palette["light"]
    for i in range(T):
        px[i, 0] = dark + (255,)
        px[i, T - 1] = dark + (255,)
        px[0, i] = dark + (255,)
        px[T - 1, i] = dark + (255,)
    for i in range(1, T - 1):
        px[i, 1] = light + (255,)      # top inner highlight row
        px[1, i] = light + (255,)      # left inner highlight column

    return img


def main():
    os.makedirs("assets/generated", exist_ok=True)
    for name, palette in PALETTES.items():
        img = make_block(palette)
        out = "assets/generated/mars_%s.png" % name
        img.save(out)
        print("wrote", out, img.size)

    # Ore: Kenney cyan gem (CC0) on a Mars-red host rock for high contrast.
    rock = make_block(PALETTES["rock"])
    sheet = Image.open("assets/kenney_pixel_platformer/Tilemap/tilemap_packed.png").convert("RGBA")
    cols = sheet.width // T
    idx = 67  # cyan gem (row 3, col 7) — same index make_ore.py used
    gx, gy = (idx % cols) * T, (idx // cols) * T
    gem = sheet.crop((gx, gy, gx + T, gy + T))
    gscale = 13
    gem_small = gem.resize((gscale, gscale), Image.NEAREST)
    off = (T - gscale) // 2
    ore = rock.copy()
    ore.alpha_composite(gem_small, (off, off))
    ore.save("assets/generated/mars_ore.png")
    print("wrote assets/generated/mars_ore.png", ore.size)


if __name__ == "__main__":
    main()
