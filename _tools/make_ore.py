import os
from PIL import Image

T = 18
# Solid grey rock block (Kenney Pixel Platformer Blocks, CC0).
base = Image.open('assets/kenney_pixel_platformer_blocks/Tiles/Stone/tile_0000.png').convert('RGBA')
base = base.resize((T, T), Image.NEAREST)

# Cyan gem = tile index 67 in the Pixel Platformer sheet (row 3, col 7), CC0.
sheet = Image.open('assets/kenney_pixel_platformer/Tilemap/tilemap_packed.png').convert('RGBA')
cols = sheet.width // T
idx = 67
gx, gy = (idx % cols) * T, (idx // cols) * T
gem = sheet.crop((gx, gy, gx + T, gy + T))

# Shrink the gem a touch so the surrounding rock reads, then centre it.
gscale = 13
gem_small = gem.resize((gscale, gscale), Image.NEAREST)
off = (T - gscale) // 2
out = base.copy()
out.alpha_composite(gem_small, (off, off))

os.makedirs('assets/generated', exist_ok=True)
out.save('assets/generated/ore_tile.png')
print('wrote assets/generated/ore_tile.png', out.size)
