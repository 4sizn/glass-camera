#!/usr/bin/env python3
"""Render the app icon: four glass cells lit from the top left, on near-black."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 1024
BG = (8, 9, 7)
LIME = (215, 242, 140)
PALE = (250, 252, 244)

def vertical_gradient(w, h, top, bottom):
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize((w, h))

img = Image.new("RGB", (S, S), BG)
# One soft light source behind the plate, the way the app lights its synthetic scene.
halo = Image.new("L", (S, S), 0)
ImageDraw.Draw(halo).ellipse([-120, -180, 700, 620], fill=200)
img = Image.composite(Image.new("RGB", (S, S), (58, 74, 30)),
                      img, halo.filter(ImageFilter.GaussianBlur(170)))

pad, gap = 188, 34
side = int((S - 2 * pad - gap) / 2)
cell = vertical_gradient(side, side, LIME, (96, 126, 44))
mask = Image.new("L", (side, side), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, side - 1, side - 1], radius=int(side * 0.24), fill=255)

# Each cell refracts a little differently; brightness stands in for that.
for (cx, cy, lit) in ((0, 0, 1.00), (1, 0, 0.70), (0, 1, 0.66), (1, 1, 0.92)):
    tile = Image.eval(cell, lambda v, k=lit: round(v * k))
    td = ImageDraw.Draw(tile)
    # Specular streak across the rolled top of the cell.
    td.polygon([(0, int(side * 0.34)), (side, int(side * 0.06)),
                (side, int(side * 0.20)), (0, int(side * 0.50))],
               fill=tuple(round(c * lit) for c in PALE))
    td.rounded_rectangle([2, 2, side - 3, side - 3], radius=int(side * 0.24),
                         outline=tuple(round(c * lit) for c in PALE), width=int(side * 0.05))
    img.paste(tile, (pad + cx * (side + gap), pad + cy * (side + gap)), mask)

out = Path(__file__).resolve().parent.parent / "QuadraCamera/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
out.parent.mkdir(parents=True, exist_ok=True)
img.save(out)
print("wrote", out)
