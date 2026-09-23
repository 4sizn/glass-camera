#!/usr/bin/env python3
"""Lay the store captures out as brandsite images (light surface, bezelled phones)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(".artifacts/store")
OUT = Path(sys.argv[1])
CREAM, TINT = (246, 245, 240), (233, 241, 216)

def background(w, h):
    base = Image.new("RGB", (w, h), CREAM)
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([w * 0.55, h * 0.1, w * 1.25, h * 1.4], fill=255)
    return Image.composite(Image.new("RGB", (w, h), TINT), base,
                           glow.filter(ImageFilter.GaussianBlur(w * 0.12)))

def phone(name, screen_w):
    shot = Image.open(SRC / f"store-{name}.png").convert("RGB")
    sh = round(screen_w * shot.height / shot.width)
    shot = shot.resize((screen_w, sh), Image.LANCZOS)
    bezel = max(4, round(screen_w * 0.035))
    radius = round(screen_w * 0.14)
    w, h = screen_w + bezel * 2, sh + bezel * 2
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=(18, 18, 20, 255))
    inner = Image.new("L", (screen_w, sh), 0)
    ImageDraw.Draw(inner).rounded_rectangle([0, 0, screen_w - 1, sh - 1],
                                            radius=max(2, radius - bezel), fill=255)
    body.paste(shot, (bezel, bezel), inner)
    return body

def place(canvas, device, x, y, angle=0.0):
    if angle:
        device = device.rotate(angle, resample=Image.BICUBIC, expand=True)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", device.size, (60, 58, 50, 70)), (x, y + 14), device)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    canvas.alpha_composite(device, (x, y))

def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(path)
    print("wrote", path)

# Card hero: three phones stepping up to the right, bleeding off the bottom edge.
hero = background(1152, 500).convert("RGBA")
for name, x, y, sw, rot in (("5-original", 430, 150, 165, 0), ("4-dial", 640, 95, 180, 0),
                            ("1-quadra", 875, 40, 200, 0)):
    place(hero, phone(name, sw), x, y, rot)
save(hero, OUT / "images/games/yuri-camera.png")

# Office gallery: one phone, centred, cut at the bottom the way the other cards are.
for name, out in (("1-quadra", "yuri-glass.png"), ("2-diamond", "yuri-patterns.png"),
                  ("4-dial", "yuri-dial.png")):
    c = background(800, 600).convert("RGBA")
    place(c, phone(name, 290), 232, 45)
    save(c, OUT / "images/office" / out)

# News thumbnail.
n = background(960, 576).convert("RGBA")
place(n, phone("1-quadra", 250), 240, 60)
save(n, OUT / "images/news/yuri-review.jpg")
