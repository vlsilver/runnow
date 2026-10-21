# Ve PLACEHOLDER map toi gian cho cung dong_nam_a tu chinh polyline that
# (nen xanh ngoc + duong di + moc thu do). Dung tam cho toi khi co anh chup that.
# Chay: python3 build_placeholder_map.py
import json
import math
import os
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
ROUTE = os.path.join(BASE, "../../assets/journey/dong_nam_a_route.json")
OUT = os.path.join(BASE, "../../assets/journey/images/dong_nam_a.jpg")
FONT = os.path.join(BASE, "../../assets/fonts/exo2/Exo2-Variable.ttf")

W, H, PAD = 900, 600, 96
SEA, SEA2 = (58, 182, 170), (48, 168, 157)
LINE, LINE_SH = (255, 246, 233), (36, 140, 130)
DOT, DOT_HL, LABEL = (255, 122, 89), (255, 208, 92), (18, 74, 69)

data = json.load(open(ROUTE))
pts = data["points"]
ms = data["milestones"]
lats = [p[0] for p in pts]
lons = [p[1] for p in pts]
klon = math.cos(math.radians(sum(lats) / len(lats)))
xs = [lo * klon for lo in lons]
ys = lats
minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
spanx, spany = (maxx - minx) or 1, (maxy - miny) or 1
scale = min((W - 2 * PAD) / spanx, (H - 2 * PAD) / spany)
offx = (W - spanx * scale) / 2
offy = (H - spany * scale) / 2


def proj(lat, lon):
    return (offx + (lon * klon - minx) * scale, offy + (maxy - lat) * scale)


top = Image.new("RGB", (W, H), SEA)
bot = Image.new("RGB", (W, H), SEA2)
mask = Image.new("L", (W, H))
mask.putdata([int(255 * (y / H)) for y in range(H) for _ in range(W)])
img = Image.composite(bot, top, mask)
d = ImageDraw.Draw(img, "RGBA")


def wave(cx, cy, w=46, a=6, col=(255, 255, 255, 60)):
    for k in range(3):
        yy = cy + k * 10
        d.line([(cx + i, yy + int(a * math.sin(i / 7))) for i in range(0, w, 2)], fill=col, width=3)


for (cx, cy) in [(70, 120), (W - 150, 90), (120, H - 90), (W - 120, H - 150)]:
    wave(cx, cy)

line = [proj(la, lo) for la, lo in zip(lats, lons)]
d.line(line, fill=LINE_SH, width=9, joint="curve")
d.line(line, fill=LINE, width=5, joint="curve")

f = ImageFont.truetype(FONT, 20)
fb = ImageFont.truetype(FONT, 22)


def short(n):
    return n.split("(")[0].strip().replace("Về ", "")


for m in ms:
    name = short(m["name"])
    x, y = proj(m["lat"], m["lon"])
    ends = ("xuất phát" in m["name"]) or ("kết thúc" in m["name"])
    r = 9 if ends else 6
    d.ellipse([x - r - 3, y - r - 3, x + r + 3, y + r + 3], fill=(255, 255, 255, 235))
    d.ellipse([x - r, y - r, x + r, y + r], fill=DOT_HL if ends else DOT)
    fnt = fb if ends else f
    tw = d.textlength(name, font=fnt)
    if x < W / 2:
        lx, anchor = x + r + 8, "lm"
    else:
        lx, anchor = x - r - 8 - tw, "lm"
    for ox, oy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
        d.text((lx + ox, y + oy), name, font=fnt, fill=(255, 255, 255, 180), anchor=anchor)
    d.text((lx, y), name, font=fnt, fill=LABEL, anchor=anchor)

img.save(OUT, quality=90)
print("wrote", OUT, img.size)
