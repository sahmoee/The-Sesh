#!/usr/bin/env python3
"""
Export the High Thoughts master icon into a complete iOS AppIcon.appiconset.
All outputs are flattened to RGB (no alpha / no transparency), as the App Store
requires for the marketing icon and as looks correct for an opaque design.
"""

import json
import os
from PIL import Image

MASTER = "/home/claude/icon_master_1024.png"
OUT = "/home/claude/MoodWeedJournal/MoodWeedJournal/Assets.xcassets/AppIcon.appiconset"
BG = (0x16, 0x1B, 0x12)  # opaque fallback matte (never seen, but guarantees no alpha)

# (idiom, size_pt, scale) -> filename pixel size = size_pt * scale
SPECS = [
    ("iphone", 20, 2), ("iphone", 20, 3),
    ("iphone", 29, 1), ("iphone", 29, 2), ("iphone", 29, 3),
    ("iphone", 40, 2), ("iphone", 40, 3),
    ("iphone", 60, 2), ("iphone", 60, 3),
    ("ipad", 20, 1), ("ipad", 20, 2),
    ("ipad", 29, 1), ("ipad", 29, 2),
    ("ipad", 40, 1), ("ipad", 40, 2),
    ("ipad", 76, 1), ("ipad", 76, 2),
    ("ipad", 83.5, 2),
    ("ios-marketing", 1024, 1),
]


def flatten(im):
    """Return an opaque RGB image (drop any alpha onto BG)."""
    if im.mode == "RGB":
        return im
    im = im.convert("RGBA")
    bg = Image.new("RGB", im.size, BG)
    bg.paste(im, mask=im.split()[-1])
    return bg


def main():
    os.makedirs(OUT, exist_ok=True)
    master = flatten(Image.open(MASTER)).resize((1024, 1024), Image.LANCZOS)

    images = []
    made = {}
    for idiom, pt, scale in SPECS:
        px = int(round(pt * scale))
        fname = f"icon_{px}.png"
        if px not in made:
            img = master.resize((px, px), Image.LANCZOS)
            img = flatten(img)  # ensure RGB, no alpha
            img.save(os.path.join(OUT, fname))
            made[px] = fname
        size_str = (f"{int(pt)}x{int(pt)}" if float(pt).is_integer()
                    else f"{pt:g}x{pt:g}")
        images.append({
            "idiom": idiom,
            "size": size_str,
            "scale": f"{scale}x",
            "filename": made[px],
        })

    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    # Verify no alpha anywhere
    bad = []
    for fn in sorted(set(made.values())):
        im = Image.open(os.path.join(OUT, fn))
        if im.mode != "RGB":
            bad.append((fn, im.mode))
    print(f"Wrote {len(set(made.values()))} unique PNGs + Contents.json to:")
    print(OUT)
    print("All RGB (no alpha):", "YES" if not bad else f"NO -> {bad}")


if __name__ == "__main__":
    main()
