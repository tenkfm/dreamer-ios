#!/usr/bin/env python3
"""App Store screenshots: a caption over the design's sky, the raw screen below it.

Reads fastlane/screenshots/raw/<name>.png (taken by `fastlane screenshots`) and writes the
6.9" (1320 x 2868) and 6.5" (1284 x 2778) versions into fastlane/screenshots/en-US for deliver.
Captions come from fastlane/screenshots.json; colors and fonts are the design system's.
"""
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "fastlane/screenshots.json").read_text())
RAW = ROOT / "fastlane/screenshots/raw"
OUT = ROOT / "fastlane/screenshots/en-US"
FONT = ROOT / "Dreamer/Resources/Fonts/Quicksand-Medium.ttf"

# design-tokens.json
SKY_TOP = (143, 180, 232)       # the top of the day sky
BACKGROUND = (238, 244, 251)    # palette.background
TEXT = (30, 42, 74)             # palette.textPrimary
SHADOW = (80, 110, 170)         # palette.shadow

SIZES = {"APP_IPHONE_69": (1320, 2868), "APP_IPHONE_65": (1284, 2778)}


def gradient(size):
    width, height = size
    image = Image.new("RGB", size, BACKGROUND)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = min(1.0, y / (height * 0.55))
        color = tuple(round(SKY_TOP[i] + (BACKGROUND[i] - SKY_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (width, y)], fill=color)
    return image


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), image.size], radius=radius, fill=255)
    image = image.convert("RGBA")
    image.putalpha(mask)
    return image


def frame(raw, caption, size):
    width, height = size
    canvas = gradient(size).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    font = ImageFont.truetype(str(FONT), round(width * 0.075))
    top = round(height * 0.07)
    draw.multiline_text((width / 2, top), caption, font=font, fill=TEXT, anchor="ma", align="center",
                        spacing=round(width * 0.02))

    # The screen: 84% of the width, rounded like the device, a soft blue shadow, running off the bottom.
    screen_width = round(width * 0.84)
    screen = raw.resize((screen_width, round(raw.height * screen_width / raw.width)), Image.LANCZOS)
    screen = rounded(screen, round(screen_width * 0.1))
    x = (width - screen_width) // 2
    y = round(height * 0.27)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(x, y + 30), (x + screen_width, y + screen.height + 30)],
                                             radius=round(screen_width * 0.1), fill=SHADOW + (90,))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(screen, (x, y))
    return canvas.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    missing = []
    for shot in CONFIG["shots"]:
        path = RAW / f"{shot['name']}.png"
        if not path.exists():
            missing.append(path.name)
            continue
        raw = Image.open(path).convert("RGB")
        for prefix, size in SIZES.items():
            frame(raw, shot["caption"], size).save(OUT / f"{prefix}_{shot['name']}.png", optimize=True)
    if missing:
        sys.exit(f"Missing raw screenshots: {', '.join(missing)}")
    print(f"Framed {len(CONFIG['shots'])} screenshots into {OUT}")


if __name__ == "__main__":
    main()
