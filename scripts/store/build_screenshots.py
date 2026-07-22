#!/usr/bin/env python3
"""Ghép ảnh chụp màn hình thô thành ảnh App Store có caption.

Đầu vào: ảnh chụp từ simulator (bất kỳ cỡ nào) trong features/images/.
Đầu ra: PNG 1320x2868 (khe 6.9" của App Store) trong features/store/.

Chạy:  python3 scripts/store/build_screenshots.py
Sửa caption ở SHOTS bên dưới rồi chạy lại — không cần mở Figma.

Ảnh chụp được thu nhỏ để nằm gọn trong khung nên nguồn 1206x2622
(iPhone 17 thường) là thừa dùng, không cần chụp lại bằng Pro Max.
"""

import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "features", "images")
OUT = os.path.join(ROOT, "features", "store")
FONT = os.path.join(ROOT, "assets", "fonts", "exo2", "Exo2-Variable.ttf")

# Khổ 6.9" — App Store tự co xuống cho máy nhỏ hơn.
W, H = 1320, 2868

# Màu lấy từ chính app icon để ảnh store khớp thương hiệu.
BG_TOP = (14, 150, 168)      # #0e96a8 teal của icon
BG_BOTTOM = (9, 106, 120)
TEXT = (255, 255, 255)
SUBTEXT = (198, 235, 240)

# (tên file trong features/images, dòng caption chính, dòng phụ)
# Thứ tự ở đây chính là thứ tự hiện trên App Store. Hai ảnh đầu là thứ
# người ta thấy mà không cần vuốt — để dành cho thứ khác biệt nhất.
SHOTS = [
    (
        "Simulator Screenshot - iPhone 17 - 2026-07-23 at 02.59.22.png",
        "Chạy xuyên Việt",
        "Lũng Cú đến Đất Mũi, từng km một",
    ),
    (
        "Simulator Screenshot - iPhone 17 - 2026-07-23 at 02.59.14.png",
        "Chinh phục cung đường có thật",
        "Marathon Athens · Mont Blanc · Xuyên Việt",
    ),
    (
        "Simulator Screenshot - iPhone 17 - 2026-07-23 at 02.58.32.png",
        "Xem mình đứng đâu trong club",
        "Bảng xếp hạng theo tuần, tháng",
    ),
    (
        "Simulator Screenshot - iPhone 17 - 2026-07-23 at 02.58.55.png",
        "Lập kèo với cả nhóm",
        "Chốt mục tiêu, cùng nhau về đích",
    ),
]


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:  # Exo2-Variable: chọn độ đậm nếu Pillow hỗ trợ trục variable
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), img.size], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap(draw, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def build(src_name, title, subtitle, index):
    canvas = Image.new("RGB", (W, H), BG_TOP)
    d = ImageDraw.Draw(canvas)

    # nền gradient dọc
    for y in range(H):
        t = y / H
        d.line(
            [(0, y), (W, y)],
            fill=tuple(
                int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
            ),
        )

    margin = 90
    y = 150

    f_title = font(76, 800)
    for line in wrap(d, title, f_title, W - margin * 2):
        d.text((W / 2, y), line, font=f_title, fill=TEXT, anchor="ma")
        y += 92

    y += 14
    f_sub = font(40, 500)
    for line in wrap(d, subtitle, f_sub, W - margin * 2):
        d.text((W / 2, y), line, font=f_sub, fill=SUBTEXT, anchor="ma")
        y += 52

    # ảnh chụp: co vừa phần còn lại, bo góc, có bóng đổ
    shot = Image.open(os.path.join(SRC, src_name)).convert("RGB")
    top = y + 70
    avail_h = H - top - 110
    avail_w = W - margin * 2
    scale = min(avail_w / shot.width, avail_h / shot.height)
    shot = shot.resize(
        (int(shot.width * scale), int(shot.height * scale)), Image.LANCZOS
    )
    shot = rounded(shot, 46)

    x = (W - shot.width) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [(x, top + 16), (x + shot.width, top + 16 + shot.height)], 46, fill=(0, 0, 0, 90)
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(shot, (x, top), shot)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{index:02d}.png")
    canvas.convert("RGB").save(path, "PNG", optimize=True)
    print(f"  {index:02d}.png  {title}")


if __name__ == "__main__":
    print(f"Dựng {len(SHOTS)} ảnh App Store ({W}x{H}) -> features/store/")
    for i, (name, title, sub) in enumerate(SHOTS, start=1):
        build(name, title, sub, i)
    print("Xong.")
