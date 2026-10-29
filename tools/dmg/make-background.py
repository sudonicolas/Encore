#!/usr/bin/env python3
"""Draws the install window's backdrop: the one image behind the Encore icon and the
Applications shortcut in the disk image. Writes <out>.png (1x) and <out>@2x.png.

    make-background.py OUT_BASE [--first-launch-note]

The window is 660 x 420 pt. Finder places the two icons at (180, 200) and (480, 200), the
centres of the drop targets drawn here; keep make-dmg.sh in step if you move either.
--first-launch-note adds the line about "Open Anyway" that an app not notarized by Apple needs.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 660, 420
APP_X, APPS_X, ICON_Y = 180, 480, 200
GROUND = (245, 245, 245)       # neutral, no hue (see docs/COLOR.md)
INK = (29, 29, 31)
DIM = (110, 110, 115)
BORDEAUX = (110, 28, 45)       # #6E1C2D, the icon field
SANS = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight):
    f = ImageFont.truetype(SANS, size)
    f.set_variation_by_name(weight)
    return f


def render(scale, note):
    s = scale
    img = Image.new("RGB", (W * s, H * s), GROUND)
    d = ImageDraw.Draw(img)

    def centred(text, y, f, fill, cx=W / 2):
        w = d.textlength(text, font=f)
        d.text((cx * s - w / 2, y * s), text, font=f, fill=fill)

    centred("Install Encore", 34, font(26 * s, "Bold"), INK)
    centred("Drag Encore into your Applications folder.", 72, font(15 * s, "Regular"), DIM)

    # Arrow from the app to the folder: a shaft and a right-angle head, as in the mark.
    y, x0, x1, t = ICON_Y * s, (APP_X + 82) * s, (APPS_X - 82) * s, 5 * s
    d.line([(x0, y), (x1 - 4 * s, y)], fill=BORDEAUX, width=t)
    head = 14 * s
    d.line([(x1 - head, y - head), (x1, y), (x1 - head, y + head)], fill=BORDEAUX, width=t, joint="curve")
    for cx, cy in ((x1 - head, y - head), (x1 - head, y + head), (x0, y)):
        d.ellipse([cx - t / 2, cy - t / 2, cx + t / 2, cy + t / 2], fill=BORDEAUX)

    if note:
        d.line([(60 * s, 318 * s), ((W - 60) * s, 318 * s)], fill=(222, 222, 224), width=s)
        centred("First time opening it?", 332, font(13 * s, "Semibold"), INK)
        centred("macOS may say it can't verify Encore. Open System Settings → Privacy & Security,", 354, font(12 * s, "Regular"), DIM)
        centred("scroll down and click Open Anyway. You only do this once.", 372, font(12 * s, "Regular"), DIM)
    return img


if __name__ == "__main__":
    base = sys.argv[1]
    note = "--first-launch-note" in sys.argv[2:]
    render(1, note).save(f"{base}.png")
    render(2, note).save(f"{base}@2x.png")
