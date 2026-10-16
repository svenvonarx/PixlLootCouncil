"""Renders the CurseForge/project logo from the PixlLootCouncil mark (the same five rectangles as
textures/UI/logo.png, redrawn as vectors). Usage: python3 make_logo.py <out_dir>"""
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SIZE = 1024

# The mark, in the coordinates of textures/UI/logo.png (98 x 128).
MARK_W, MARK_H = 98, 128
RECTS = [
    (0, 1, 20, 20),     # the pixel
    (39, 20, 98, 39),   # top of the bowl
    (20, 39, 39, 128),  # stem
    (78, 39, 98, 88),   # right of the bowl
    (20, 88, 98, 108),  # bottom of the bowl
]

GOLD_TOP = (244, 186, 92)
GOLD_BOTTOM = (214, 140, 40)
BG_TOP = (30, 32, 40)
BG_BOTTOM = (12, 13, 17)


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        grad.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def mark_mask(scale, offset):
    mask = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(mask)
    ox, oy = offset
    for x0, y0, x1, y1 in RECTS:
        d.rectangle([ox + x0 * scale, oy + y0 * scale, ox + x1 * scale - 1, oy + y1 * scale - 1], fill=255)
    return mask


def render():
    # Background: dark vertical gradient, a faint warm light behind the mark, a thin inner rim.
    img = vertical_gradient((SIZE, SIZE), BG_TOP, BG_BOTTOM).convert("RGBA")
    halo = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(halo).ellipse([SIZE * 0.18, SIZE * 0.16, SIZE * 0.82, SIZE * 0.84], fill=70)
    halo = halo.filter(ImageFilter.GaussianBlur(SIZE * 0.12))
    img.paste(Image.new("RGBA", (SIZE, SIZE), GOLD_BOTTOM + (255,)), (0, 0), halo)

    # The mark: ~62% of the height, optically centered (the stem makes it bottom-left heavy).
    scale = SIZE * 0.62 / MARK_H
    w, h = MARK_W * scale, MARK_H * scale
    offset = ((SIZE - w) / 2 + SIZE * 0.012, (SIZE - h) / 2)
    mask = mark_mask(scale, offset)

    glow = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.02)).point(lambda v: v * 0.55)
    img.paste(Image.new("RGBA", (SIZE, SIZE), GOLD_TOP + (255,)), (0, 0), glow)

    shadow = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.008)).point(lambda v: v * 0.6)
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -SIZE * 0.008))
    img.paste(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255)), (0, 0), shadow)

    top = int(offset[1])
    gold = vertical_gradient((SIZE, int(h) + 2), GOLD_TOP, GOLD_BOTTOM)
    gold_full = Image.new("RGB", (SIZE, SIZE), GOLD_BOTTOM)
    gold_full.paste(gold, (0, top))
    img.paste(gold_full, (0, 0), mask)

    rim = Image.new("L", (SIZE, SIZE), 0)
    inset = SIZE * 0.035
    ImageDraw.Draw(rim).rounded_rectangle([inset, inset, SIZE - inset, SIZE - inset], radius=SIZE * 0.06,
                                          outline=255, width=max(2, SIZE // 256))
    img.paste(Image.new("RGBA", (SIZE, SIZE), GOLD_BOTTOM + (255,)), (0, 0), rim.point(lambda v: v * 0.35))
    return img.convert("RGB")


logo = render()
logo.save(f"{OUT}/logo-1024.png", optimize=True)
logo.resize((400, 400), Image.LANCZOS).save(f"{OUT}/logo-400.png", optimize=True)
print("written:", f"{OUT}/logo-1024.png", f"{OUT}/logo-400.png")
