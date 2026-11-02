"""Renders the icons that aren't hand-drawn: white line art on transparency, tinted in game. The
Options navigation icons at 64px, and the welcome window's choices at 128px, drawn on the same 64-unit
grid. Usage: python3 make_nav_icons.py <out_dir>"""
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


def save(image, name, size=SIZE):
    image.resize((size, size), Image.LANCZOS).save(f"{OUT}/{name}.png")


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


def changelog():
    """A page with lines of text."""
    image, draw = canvas()
    line(draw, 14, 8, 50, 8, 50, 56, 14, 56, 14, 8)
    for y in (21, 32, 43):
        line(draw, 23, y, 41, y)
    save(image, "nav_changelog")


BIG = 128  # the welcome window's choices


def raider():
    """A shield with a chevron."""
    image, draw = canvas()
    line(draw, 32, 7, 51, 13, 51, 30, 47, 41, 40, 50, 32, 57, 24, 50, 17, 41, 13, 30, 13, 13, 32, 7)
    line(draw, 21, 24, 32, 34, 43, 24)
    save(image, "welcome_raider", BIG)


def loot_master():
    """The master looter's crown, larger."""
    image, draw = canvas()
    line(draw, 12, 48, 8, 20, 22, 31, 32, 13, 42, 31, 56, 20, 52, 48, 12, 48)
    save(image, "welcome_lootmaster", BIG)


def import_rc():
    """An arrow carrying something into a box."""
    image, draw = canvas()
    line(draw, 8, 20, 30, 20)
    line(draw, 22, 12, 30, 20, 22, 28)
    line(draw, 36, 8, 56, 8, 56, 56, 16, 56, 16, 36)
    line(draw, 26, 44, 46, 44)
    save(image, "welcome_import", BIG)


def setup():
    """Three sliders."""
    image, draw = canvas()
    for y, knob in ((16, 40), (32, 22), (48, 34)):
        line(draw, 10, y, 54, y)
        draw.ellipse(s(knob - 6, y - 6, knob + 6, y + 6), fill=WHITE)
    save(image, "welcome_setup", BIG)


auto_loot()
master_looter()
preview()
about()
changelog()
raider()
loot_master()
import_rc()
setup()
