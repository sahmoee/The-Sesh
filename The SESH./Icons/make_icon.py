#!/usr/bin/env python3
"""
High Thoughts — app icon generator.
Renders a fully opaque (no alpha) master icon and exports all iOS sizes.
Motif: a glowing candle flame rising into a stylized cannabis leaf, over the
app's dark-olive vertical gradient, with a subtle gold ring — matching the
hero on the Home screen.
"""

import math
from PIL import Image, ImageDraw, ImageFilter

# ---- Palette (from Theme.swift) ----
BG_TOP      = (0x20, 0x27, 0x1B)   # 20271B
BG_BOTTOM   = (0x10, 0x14, 0x0D)   # 10140D  (deep hero bottom for drama)
GREEN       = (0x5C, 0x6B, 0x41)
GREEN_BR    = (0x6E, 0x80, 0x49)
GREEN_DEEP  = (0x47, 0x54, 0x2F)
GREEN_LIGHT = (0x8C, 0xA0, 0x5E)
GOLD        = (0xC9, 0xA2, 0x4B)
GOLD_SOFT   = (0xD8, 0xB9, 0x68)
GOLD_BRIGHT = (0xF0, 0xD9, 0x92)
CREAM       = (0xEB, 0xE2, 0xCE)

SS = 4               # supersample factor
BASE = 1024
S = BASE * SS        # working canvas


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical_gradient(size, top, bottom):
    """Opaque vertical gradient image."""
    img = Image.new("RGB", (1, size), top)
    px = img.load()
    for y in range(size):
        px[0, y] = lerp(top, bottom, y / max(1, size - 1))
    return img.resize((size, size))


def radial_glow(size, center, radius, color, max_alpha):
    """Soft radial glow on its own RGBA layer (composited later)."""
    w, h = (size, size) if isinstance(size, int) else size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 60
    cx, cy = center
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        a = int(max_alpha * (1 - t) ** 1.7)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.06))


def leaf_blade(draw, origin, angle_deg, length, width, color):
    """One pointed cannabis leaflet as a filled polygon with serrations."""
    ang = math.radians(angle_deg)
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx  # perpendicular
    ox, oy = origin

    tip = (ox + dx * length, oy + dy * length)
    pts = [origin]
    serr = 5
    for i in range(1, serr + 1):
        t = i / (serr + 1)
        # width tapers toward tip following a curve
        w = width * (1 - t) * (0.55 + 0.45 * math.sin(t * math.pi))
        cx = ox + dx * length * t
        cy = oy + dy * length * t
        notch = 0.78 if i % 1 == 0 else 1.0
        pts.append((cx + px * w * notch, cy + py * w * notch))
    pts.append(tip)
    for i in range(serr, 0, -1):
        t = i / (serr + 1)
        w = width * (1 - t) * (0.55 + 0.45 * math.sin(t * math.pi))
        cx = ox + dx * length * t
        cy = oy + dy * length * t
        notch = 0.78
        pts.append((cx - px * w * notch, cy - py * w * notch))
    draw.polygon(pts, fill=color)


def draw_leaf(img, center, scale, color, vein=None):
    """A 7-point cannabis leaf rising upward."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    # angles measured from straight up (-90 deg). symmetric pairs + center.
    specs = [
        (-90, 1.00, 0.150),
        (-66, 0.86, 0.130), (-114, 0.86, 0.130),
        (-42, 0.66, 0.110), (-138, 0.66, 0.110),
        (-20, 0.44, 0.090), (-160, 0.44, 0.090),
    ]
    for ang, lf, wf in specs:
        leaf_blade(d, (cx, cy), ang, S * scale * lf, S * scale * wf, color + (255,))
    # longer stem reaching down toward the flame
    d.line([(cx, cy), (cx, cy + S * scale * 0.62)], fill=color + (255,),
           width=int(S * scale * 0.020))
    if vein:
        for ang, lf, _ in specs:
            a = math.radians(ang)
            d.line([(cx, cy), (cx + math.cos(a) * S * scale * lf * 0.92,
                                cy + math.sin(a) * S * scale * lf * 0.92)],
                   fill=vein + (90,), width=int(S * scale * 0.012))
    img.alpha_composite(layer)


def draw_flame(img, base_center, scale):
    """A candle flame: rounded bulb low, smooth taper to a tall pointed tip."""
    cx, cy = base_center  # cy = base (bottom) of the flame
    h = S * scale
    maxw = S * scale * 0.30   # half-width at the widest point

    # outer glow centered on the flame body
    img.alpha_composite(radial_glow(img.size, (cx, cy - h * 0.5),
                                    maxw * 4.0, GOLD, 130))

    def shape(scl, color, layer_img):
        d = ImageDraw.Draw(layer_img)
        left, right = [], []
        n = 100
        for i in range(n + 1):
            t = i / n                      # 0 = base, 1 = tip
            y = cy - t * h * scl
            # width: 0 at base, swells to max around t~0.30, tapers to 0 at tip.
            # f(t) = (t^a)*(1-t)^b normalized to peak 1.
            a, b = 0.5, 1.6
            f = (t ** a) * ((1 - t) ** b)
            peak = (a / (a + b)) ** a * (b / (a + b)) ** b  # max of f on [0,1]
            ww = maxw * scl * (f / peak)
            left.append((cx - ww, y))
            right.append((cx + ww, y))
        d.polygon(left + list(reversed(right)), fill=color)

    flame = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shape(1.00, GOLD + (255,), flame)
    shape(0.62, GOLD_SOFT + (255,), flame)
    shape(0.30, GOLD_BRIGHT + (255,), flame)
    flame = flame.filter(ImageFilter.GaussianBlur(S * 0.0035))
    img.alpha_composite(flame)


def build_master():
    # base opaque gradient
    base = vertical_gradient(S, BG_TOP, BG_BOTTOM).convert("RGBA")

    # vignette glow behind motif (cool green ambient)
    base.alpha_composite(radial_glow(S, (S * 0.5, S * 0.46), S * 0.5, GREEN_DEEP, 90))

    cx = S * 0.5

    # subtle gold ring framing
    ring = Image.new("RGBA", base.size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    margin = S * 0.085
    rd.ellipse([margin, margin, S - margin, S - margin],
               outline=GOLD + (70,), width=int(S * 0.006))
    ring = ring.filter(ImageFilter.GaussianBlur(S * 0.002))
    base.alpha_composite(ring)

    # leaf (upper area), glowing green; stem points down toward the flame
    draw_leaf(base, (cx, S * 0.40), 0.32, GREEN_BR, vein=GREEN_LIGHT)
    sheen = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw_leaf(sheen, (cx, S * 0.40), 0.32, GREEN_LIGHT)
    sheen = sheen.filter(ImageFilter.GaussianBlur(S * 0.01))
    base.alpha_composite(Image.blend(Image.new("RGBA", base.size, (0, 0, 0, 0)), sheen, 0.30))

    # flame: base low, tall tip rising to meet the leaf's stem
    draw_flame(base, (cx, S * 0.80), 0.30)

    # downsample to 1024 (antialias) and flatten to fully opaque RGB
    master = base.resize((BASE, BASE), Image.LANCZOS).convert("RGB")
    return master


if __name__ == "__main__":
    master = build_master()
    master.save("/home/claude/icon_master_1024.png")
    print("master saved", master.size, master.mode)
