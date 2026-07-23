#!/usr/bin/env python3
"""Dựng ảnh bắt buộc cho Google Play: app icon 512x512 và feature graphic
1024x500.

Chạy:  python3 scripts/store/build_play_assets.py
Đầu ra: features/store/play/

Hai ảnh này Play bắt buộc phải có mới cho publish, và không có công cụ nào
trong repo sinh ra chúng — trước giờ chỉ có build_screenshots.py cho App
Store. Màu và font lấy trùng với ảnh App Store để hai store nhìn như một.
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "features", "store", "play")
FONT = os.path.join(ROOT, "assets", "fonts", "exo2", "Exo2-Variable.ttf")
ICON_SRC = os.path.join(ROOT, "features", "Icon 3I Export", "runow-3i-1024.png")
MARK_SRC = os.path.join(ROOT, "assets", "brand", "3i-mark-transparent.png")

# Cùng bảng màu với build_screenshots.py — lấy từ chính app icon.
BG_TOP = (14, 150, 168)
BG_BOTTOM = (9, 106, 120)
TEXT = (255, 255, 255)
SUBTEXT = (198, 235, 240)


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:  # Exo2-Variable: chọn độ đậm nếu Pillow hỗ trợ trục variable
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def gradient(width, height):
    base = Image.new("RGB", (width, height), BG_TOP)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(
                round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
            ),
        )
    return base


def build_icon():
    """512x512, không alpha.

    Play tự bo góc và đổ bóng, nên icon phải là hình vuông đặc. Alpha để
    lại sẽ thành viền đen trên nền tối ở một số launcher.
    """
    icon = Image.open(ICON_SRC).convert("RGBA")
    flat = Image.new("RGB", icon.size, BG_TOP)
    flat.paste(icon, mask=icon.split()[3])
    flat = flat.resize((512, 512), Image.LANCZOS)
    path = os.path.join(OUT, "app-icon-512.png")
    flat.save(path, "PNG")
    return path


def build_feature_graphic():
    """1024x500.

    Play cắt bớt hai mép ở một số vị trí hiển thị và có thể chồng nút play
    lên giữa khi listing có video, nên nội dung dồn về giữa theo chiều dọc
    và chừa lề rộng hai bên.
    """
    width, height = 1024, 500
    canvas = gradient(width, height)
    draw = ImageDraw.Draw(canvas)

    mark = Image.open(MARK_SRC).convert("RGBA")
    mark_size = 210
    mark = mark.resize((mark_size, mark_size), Image.LANCZOS)

    # Logo đã đọc là "3i" nên phần chữ chỉ còn "Run" — ghép lại vẫn ra
    # "3i Run". Viết đủ "3i Run" cạnh logo sẽ thành "3i 3i Run".
    title_font = font(96, 800)
    tag_font = font(34, 500)
    title = "Run"
    tagline = "INTENT · IMPROVE · INVOLVE"

    title_w = draw.textlength(title, font=title_font)
    gap = 34
    block_w = mark_size + gap + title_w
    left = (width - block_w) / 2
    center_y = height / 2 - 26

    canvas.paste(mark, (round(left), round(center_y - mark_size / 2)), mark)
    draw.text(
        (left + mark_size + gap, center_y),
        title,
        font=title_font,
        fill=TEXT,
        anchor="lm",
    )
    draw.text(
        (width / 2, center_y + mark_size / 2 + 30),
        tagline,
        font=tag_font,
        fill=SUBTEXT,
        anchor="mm",
    )

    path = os.path.join(OUT, "feature-graphic-1024x500.png")
    canvas.save(path, "PNG")
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in (build_icon(), build_feature_graphic()):
        size = os.path.getsize(path)
        print(f"{os.path.relpath(path, ROOT)}  ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
