#!/usr/bin/env python3
"""Dark and tinted variants of the app icon (iOS 18 home screen appearances).

The light icon is artwork; these two redraw its elements (rings, orb, crescent moon, star) in the
design's night palette, so they stay recognisable next to the light one. Rerun after the final
icon is chosen and adjust the geometry below if the artwork changed:
    python3 scripts/make_icon_variants.py
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Dreamer/Resources/Assets.xcassets/AppIcon.appiconset"
S = 2048  # drawn at 2x, saved at 1024 for smooth edges
C = (S // 2, int(S * 0.494))  # orb centre, as in the artwork

# design-tokens.json (night palette of the app)
NIGHT_TOP = (13, 21, 44)
NIGHT_BOTTOM = (33, 49, 92)
ORB_DARK = (38, 54, 96)
MOON = (157, 184, 236)
STAR = (242, 164, 136)  # palette.peach


def scaled(value):
    return int(value * S / 1024)


def gradient(top, bottom):
    image = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(image)
    for y in range(S):
        t = y / (S - 1)
        draw.line([(0, y), (S, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return image


def circle(draw, centre, radius, **kwargs):
    x, y = centre
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], **kwargs)


def crescent_mask():
    """The moon: a disc minus a disc shifted up and right, like the artwork's crescent."""
    mask = Image.new("L", (S, S), 0)
    circle(ImageDraw.Draw(mask), (C[0] + scaled(4), C[1] + scaled(3)), scaled(135), fill=255)
    cut = Image.new("L", (S, S), 0)
    circle(ImageDraw.Draw(cut), (C[0] + scaled(50), C[1] - scaled(40)), scaled(128), fill=255)
    return ImageChops.subtract(mask, cut)


def star_polygon(centre, size):
    x, y = centre
    thin = size * 0.26
    return [(x, y - size), (x + thin, y - thin), (x + size, y), (x + thin, y + thin),
            (x, y + size), (x - thin, y + thin), (x - size, y), (x - thin, y - thin)]


def rings(layer, color):
    draw = ImageDraw.Draw(layer)
    for radius, alpha in ((scaled(318), 70), (scaled(368), 45)):
        circle(draw, C, radius, outline=color + (alpha,), width=scaled(3))


def dark():
    image = gradient(NIGHT_TOP, NIGHT_BOTTOM)
    overlay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rings(overlay, (170, 196, 240))
    image.alpha_composite(overlay)

    # Orb: dark glass with a soft light rim and glow.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    circle(ImageDraw.Draw(glow), C, scaled(290), fill=(120, 150, 220, 90))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(scaled(40))))
    orb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(orb)
    circle(draw, C, scaled(275), fill=ORB_DARK + (255,))
    circle(draw, C, scaled(275), outline=(150, 176, 230, 150), width=scaled(4))
    image.alpha_composite(orb)

    moon = Image.new("RGBA", (S, S), MOON + (255,))
    image.paste(moon, (0, 0), crescent_mask())
    ImageDraw.Draw(image).polygon(star_polygon((C[0] + scaled(88), C[1] - scaled(80)), scaled(32)), fill=STAR + (255,))
    return image.convert("RGB")


def tinted():
    """Grayscale on transparent: iOS lays its tint over the luminance."""
    image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rings(image, (255, 255, 255))
    orb = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    circle(ImageDraw.Draw(orb), C, scaled(275), fill=(255, 255, 255, 60), outline=(255, 255, 255, 140), width=scaled(4))
    image.alpha_composite(orb)
    image.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), crescent_mask())
    ImageDraw.Draw(image).polygon(star_polygon((C[0] + scaled(88), C[1] - scaled(80)), scaled(32)), fill=(235, 235, 235, 255))
    return image


def main():
    dark().resize((1024, 1024), Image.LANCZOS).save(ICONSET / "AppIcon-Dark-1024.png")
    tinted().resize((1024, 1024), Image.LANCZOS).save(ICONSET / "AppIcon-Tinted-1024.png")
    print("Wrote AppIcon-Dark-1024.png and AppIcon-Tinted-1024.png")


if __name__ == "__main__":
    main()
