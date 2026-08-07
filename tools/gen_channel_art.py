#!/usr/bin/env python3
"""
Phlix Roku channel art generator.

Generates every asset listed in docs/image_generation_info.md from a single
design system so the icon set and the splash set read as one brand.

Palette is taken from the colors already used in components/*.xml:
  ground   #1a1a2e / #0d0d1a
  accent   #ff6b35 -> #ffd700
"""

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "images")
FONT_BLACK = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"

GROUND_HI = (26, 26, 46)     # #1a1a2e
GROUND_LO = (13, 13, 26)     # #0d0d1a
ACCENT_A = (255, 107, 53)    # #ff6b35
ACCENT_B = (255, 215, 0)     # #ffd700
WHITE = (255, 255, 255)

SS = 4  # supersample factor


# ---------------------------------------------------------------- primitives

def linear_gradient(w, h, c0, c1, angle="diag"):
    """RGB gradient image. angle: 'vert' | 'diag'."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    if angle == "vert":
        t = ys / max(h - 1, 1)
    else:
        t = (xs / max(w - 1, 1) + ys / max(h - 1, 1)) / 2.0
    t = t[..., None]
    a = np.array(c0, np.float32)
    b = np.array(c1, np.float32)
    return Image.fromarray((a + (b - a) * t).astype(np.uint8), "RGB")


def radial_ground(w, h, center=(0.5, 0.42), inner=None, outer=None, falloff=1.15):
    """Soft radial ground: brighter navy at the focal point, near-black at the edges."""
    inner = inner or (36, 36, 62)
    outer = outer or GROUND_LO
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = center[0] * w, center[1] * h
    # normalise by the half-diagonal so the falloff is resolution independent
    r = np.sqrt(((xs - cx) / (w / 2.0)) ** 2 + ((ys - cy) / (h / 2.0)) ** 2)
    t = np.clip(r / 1.45, 0.0, 1.0) ** falloff
    t = t[..., None]
    a = np.array(inner, np.float32)
    b = np.array(outer, np.float32)
    return Image.fromarray((a + (b - a) * t).astype(np.uint8), "RGB")


def add_glow(base, cx, cy, radius, color, strength=0.30):
    """Screen-blend a soft coloured glow into an RGB image."""
    w, h = base.size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / max(radius, 1.0)
    g = np.clip(1.0 - r, 0.0, 1.0) ** 2.2 * strength
    g = g[..., None]
    arr = np.asarray(base, np.float32)
    col = np.array(color, np.float32)
    out = 255.0 - (255.0 - arr) * (255.0 - col * g) / 255.0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def add_grain(img, amount=2.0, seed=7):
    """Very light luminance noise — kills gradient banding on 8-bit TV panels."""
    rng = np.random.default_rng(seed)
    arr = np.asarray(img, np.float32)
    n = rng.normal(0.0, amount, arr.shape[:2])[..., None]
    return Image.fromarray(np.clip(arr + n, 0, 255).astype(np.uint8), "RGB")


# ---------------------------------------------------------------- brand mark

def make_badge(size, c0=ACCENT_A, c1=ACCENT_B, glyph=WHITE):
    """Gradient disc with a rounded play triangle. Returns RGBA size x size."""
    s = size * SS
    grad = linear_gradient(s, s, c0, c1, "diag")

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, s - 1, s - 1], fill=255)

    badge = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    badge.paste(grad, (0, 0), mask)

    # play triangle, optically centred (nudged right of true centre)
    c = s / 2.0
    r = s * 0.255
    cx = c + s * 0.028
    pts = [
        (cx + r, c),
        (cx - r * 0.52, c - r * 0.90),
        (cx - r * 0.52, c + r * 0.90),
    ]
    tri = Image.new("L", (s, s), 0)
    td = ImageDraw.Draw(tri)
    td.polygon(pts, fill=255)
    # re-stroking the outline with a round join is how we get rounded corners
    td.line(pts + [pts[0]], fill=255, width=int(s * 0.055), joint="curve")

    fill = Image.new("RGBA", (s, s), glyph + (255,))
    badge = Image.alpha_composite(badge, Image.composite(
        fill, Image.new("RGBA", (s, s), (0, 0, 0, 0)), tri))

    return badge.resize((size, size), Image.LANCZOS)


def make_wordmark(cap_height, color=WHITE, tracking=0.09, text="PHLIX"):
    """Tight-cropped RGBA wordmark scaled to `cap_height` pixels tall."""
    base = 400
    font = ImageFont.truetype(FONT_BLACK, base)
    track = int(base * tracking)

    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] for ch in text]
    total = sum(widths) + track * (len(text) - 1)

    pad = base
    canvas = Image.new("RGBA", (total + pad * 2, base * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    x = pad
    for ch, cw in zip(text, widths):
        bb = font.getbbox(ch)
        d.text((x - bb[0], base), ch, font=font, fill=color + (255,))
        x += cw + track

    canvas = canvas.crop(canvas.getbbox())
    w, h = canvas.size
    return canvas.resize((max(int(round(w * cap_height / h)), 1), cap_height), Image.LANCZOS)


def stacked_lockup(canvas, badge_px, cap_px, gap_px, center_y=None, wordmark_color=WHITE):
    """Badge above wordmark, horizontally centred on an RGB/RGBA canvas (in place)."""
    W, H = canvas.size
    badge = make_badge(badge_px)
    word = make_wordmark(cap_px, wordmark_color)

    block_h = badge_px + gap_px + cap_px
    top = int((H - block_h) / 2) if center_y is None else int(center_y - block_h / 2)

    canvas.paste(badge, (int((W - badge_px) / 2), top), badge)
    canvas.paste(word, (int((W - word.width) / 2), top + badge_px + gap_px), word)
    return canvas


# ---------------------------------------------------------------- assets

def make_icon(w, h, badge_f, cap_f, gap_f, path):
    """Home-screen icon: brand ground + warm glow + stacked lockup."""
    ground = linear_gradient(w, h, (30, 30, 54), GROUND_LO, "vert")
    ground = add_glow(ground, w / 2, h * 0.40, max(w, h) * 0.55, ACCENT_A, 0.22)
    ground = add_grain(ground, 1.6, seed=w * 31 + h)

    img = ground.convert("RGBA")
    badge = max(int(round(h * badge_f)), 8)
    cap = max(int(round(h * cap_f)), 6)
    gap = max(int(round(h * gap_f)), 2)
    stacked_lockup(img, badge, cap, gap, center_y=h * 0.50)

    img.convert("RGB").save(path, "PNG", optimize=True)
    return path


def make_splash(w, h, path):
    """Launch screen: radial navy ground, warm glow, centred lockup. No animation."""
    ground = radial_ground(w, h, center=(0.5, 0.44), inner=(38, 38, 66), outer=GROUND_LO)
    ground = add_glow(ground, w / 2, h * 0.43, max(w, h) * 0.42, ACCENT_A, 0.26)
    ground = add_glow(ground, w / 2, h * 0.43, max(w, h) * 0.18, ACCENT_B, 0.10)
    ground = add_grain(ground, 2.0, seed=w + h)

    img = ground.convert("RGBA")
    badge = int(round(h * 0.235))
    cap = int(round(h * 0.088))
    gap = int(round(h * 0.062))
    stacked_lockup(img, badge, cap, gap, center_y=h * 0.47)

    img.convert("RGB").save(path, "PNG", optimize=True)
    return path


def make_placeholder(w, h, path):
    """Poster placeholder: quiet, branded, intentionally low-contrast."""
    ground = linear_gradient(w, h, (32, 32, 56), (18, 18, 34), "vert")
    ground = add_grain(ground, 1.4, seed=99)
    img = ground.convert("RGBA")

    # hairline inset border so a missing poster still reads as a poster slot
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, w - 2, h - 2], outline=(58, 58, 88, 255), width=2)

    # slate mark, not a faded orange one — fading the accent over navy goes muddy brown
    badge_px = int(w * 0.34)
    badge = make_badge(badge_px, (58, 58, 92), (76, 76, 116), (128, 128, 158))
    img.paste(badge, (int((w - badge_px) / 2), int(h * 0.36 - badge_px / 2)), badge)

    word = make_wordmark(int(h * 0.052), (150, 150, 180))
    img.paste(word, (int((w - word.width) / 2), int(h * 0.56)), word)

    img.convert("RGB").save(path, "PNG", optimize=True)
    return path


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    made = []

    # --- icons (spec: docs/image_generation_info.md) ---
    made.append(make_icon(290, 218, 0.46, 0.20, 0.085, f"{OUT}/icon-focus-hd.png"))
    made.append(make_icon(246, 140, 0.44, 0.20, 0.080, f"{OUT}/icon-focus-sd.png"))
    made.append(make_icon(176, 110, 0.42, 0.20, 0.080, f"{OUT}/icon-side-hd.png"))

    # --- splash screens ---
    made.append(make_splash(720, 480, f"{OUT}/splash-sd.png"))
    made.append(make_splash(1280, 720, f"{OUT}/splash-hd.png"))
    made.append(make_splash(1920, 1080, f"{OUT}/splash-fhd.png"))

    # --- placeholder ---
    made.append(make_placeholder(280, 380, f"{OUT}/placeholder.png"))

    for p in made:
        print(f"{os.path.basename(p):20s} {Image.open(p).size}")
