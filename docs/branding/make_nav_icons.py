"""Renders the Options navigation icons that aren't hand-drawn: white line art on transparency, tinted
in game. Usage: python3 make_nav_icons.py <out_dir>"""
import math
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
SIZE = 64
SCALE = 8  # drawn large and scaled down, for clean edges
STROKE = 4 * SCALE
WHITE = (255, 255, 255, 255)


def canvas():
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (255, 255, 255, 0))
    return image, ImageDraw.Draw(image)


def s(*values):
    return [v * SCALE for v in values]


def line(draw, *points):
    draw.line(s(*points), fill=WHITE, width=STROKE, joint="curve")
    for x, y in zip(points[0::2], points[1::2]):
        draw.ellipse(s(x, y, x, y), fill=WHITE)
        r = STROKE / 2
        draw.ellipse((x * SCALE - r, y * SCALE - r, x * SCALE + r, y * SCALE + r), fill=WHITE)


def save(image, name):
    image.resize((SIZE, SIZE), Image.LANCZOS).save(f"{OUT}/{name}.png")


def auto_loot():
    """An arrow dropping into a tray."""
    image, draw = canvas()
    line(draw, 32, 9, 32, 38)
    line(draw, 19, 26, 32, 39, 45, 26)
    line(draw, 10, 40, 10, 54, 54, 54, 54, 40)
    save(image, "nav_autoloot")


def preview():
    """A play triangle in a ring."""
    image, draw = canvas()
    draw.ellipse(s(8, 8, 56, 56), outline=WHITE, width=STROKE)
    draw.polygon(s(26, 21, 26, 43, 45, 32), fill=WHITE)
    save(image, "nav_preview")


def about():
    """An "i" in a ring."""
    image, draw = canvas()
    draw.ellipse(s(8, 8, 56, 56), outline=WHITE, width=STROKE)
    draw.ellipse(s(28.5, 18, 35.5, 25), fill=WHITE)
    line(draw, 32, 31, 32, 44)
    save(image, "nav_about")


def master_looter():
    """A crown."""
    image, draw = canvas()
    line(draw, 12, 48, 8, 20, 22, 31, 32, 13, 42, 31, 56, 20, 52, 48, 12, 48)
    save(image, "nav_masterlooter")


auto_loot()
master_looter()
preview()
about()
