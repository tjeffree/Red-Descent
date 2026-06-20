from PIL import Image, ImageDraw

sheet = Image.open('assets/kenney_pixel_platformer/Tilemap/tilemap_packed.png').convert('RGBA')
T = 18
cols = sheet.width // T
rows = sheet.height // T
scale = 6
big = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
out = Image.new('RGBA', big.size, (20, 20, 20, 255))
out.alpha_composite(big)
d = ImageDraw.Draw(out)
for c in range(cols + 1):
    d.line([(c * T * scale, 0), (c * T * scale, out.height)], fill=(0, 255, 0, 120))
for r in range(rows + 1):
    d.line([(0, r * T * scale), (out.width, r * T * scale)], fill=(0, 255, 0, 120))
for r in range(rows):
    for c in range(cols):
        d.text((c * T * scale + 2, r * T * scale + 1), str(r * cols + c), fill=(255, 255, 0, 255))
out.save('grid.png')
print('cols', cols, 'rows', rows, 'index = row*%d + col' % cols)
