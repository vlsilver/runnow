# Ghep hero collage kieu LUOI 2 hang (4 tren + 3 duoi) tu anh CC0 trong
# assets/journey/capitals/ -> assets/journey/images/dong_nam_a.jpg.
# Grid cho moi anh ti le vuong van, can doi hon dai phim doc hep.
import os
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "../../assets/journey/capitals")
OUT = os.path.join(BASE, "../../assets/journey/images/dong_nam_a.jpg")
FONT = os.path.join(BASE, "../../assets/fonts/exo2/Exo2-Variable.ttf")
W, H = 900, 600
SEA = (52, 176, 165)
GOLD, INK = (255, 208, 92), (14, 40, 38)

# Thu tu hanh trinh: 4 tren, 3 duoi.
caps = [
    ("ha_noi", "Hà Nội"), ("vientiane", "Viêng Chăn"),
    ("naypyidaw", "Naypyidaw"), ("bangkok", "Bangkok"),
    ("phnom_penh", "Phnom Penh"), ("kuala_lumpur", "Kuala Lumpur"),
    ("singapore", "Singapore"),
]
ROWS = [caps[:4], caps[4:]]


def cover(im, tw, th):
    iw, ih = im.size
    s = max(tw / iw, th / ih)
    im = im.resize((int(iw * s + 0.5), int(ih * s + 0.5)), Image.LANCZOS)
    x = (im.width - tw) // 2
    y = (im.height - th) // 2
    return im.crop((x, y, x + tw, y + th))


mg, gap = 16, 8
row_h = (H - 2 * mg - gap) // 2
tile_w = (W - 2 * mg - 3 * gap) // 4   # rong theo hang 4 o; hang 3 dung cung rong

img = Image.new("RGB", (W, H), SEA)
d = ImageDraw.Draw(img, "RGBA")
fname = ImageFont.truetype(FONT, 20)
fnum = ImageFont.truetype(FONT, 18)

order = 0
for r, row in enumerate(ROWS):
    y0 = mg + r * (row_h + gap)
    total_w = len(row) * tile_w + (len(row) - 1) * gap
    x_start = (W - total_w) // 2   # hang 3 tu dong canh giua
    for c, (slug, name) in enumerate(row):
        order += 1
        x0 = x_start + c * (tile_w + gap)
        tile = cover(Image.open(os.path.join(SRC, slug + ".jpg")).convert("RGB"), tile_w, row_h)
        # gradient toi day cho ten
        g = Image.new("L", (tile_w, row_h), 0)
        gd = ImageDraw.Draw(g)
        for yy in range(row_h):
            a = 0 if yy < row_h - 74 else int(205 * ((yy - (row_h - 74)) / 74))
            gd.line([(0, yy), (tile_w, yy)], fill=a)
        tile = Image.composite(Image.new("RGB", (tile_w, row_h), (0, 0, 0)), tile, g)
        mask = Image.new("L", (tile_w, row_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile_w - 1, row_h - 1], radius=16, fill=255)
        img.paste(tile, (x0, y0), mask)
        d.rounded_rectangle([x0, y0, x0 + tile_w, y0 + row_h], radius=16, outline=(255, 255, 255, 140), width=1)
        # badge so thu tu (thu tu hanh trinh)
        bx, by = x0 + 12, y0 + 12
        d.ellipse([bx, by, bx + 26, by + 26], fill=GOLD)
        d.text((bx + 13, by + 13), str(order), font=fnum, fill=INK, anchor="mm")
        # ten
        d.text((x0 + tile_w / 2, y0 + row_h - 18), name, font=fname, fill=(255, 255, 255), anchor="mm")

img.save(OUT, quality=90)
print("wrote", OUT, "grid 4+3, tile", tile_w, "x", row_h)
