#!/usr/bin/env python3
"""Draws the FuseOS app icon for both clients.

Writes macOS's AppIcon.icns and Android's legacy launcher PNGs. Android's real icon is
the adaptive vector in `res/`; these PNGs only cover launchers that reach for the legacy
asset anyway, which ColorOS and friends still do.

The mark is generated rather than traced from a PNG so it stays sharp at 16pt and at
1024pt from one definition, and so it cannot drift from the same mark the apps draw in
their wordmark. Run after changing the mark; the output is committed.

Usage: python3 make-icon.py
"""

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
ICONSET = HERE / "macos" / ".build" / "AppIcon.iconset"
OUT = HERE / "macos" / "Resources" / "AppIcon.icns"
ANDROID_RES = HERE / "android" / "app" / "src" / "main" / "res"

# The legacy launcher buckets, in the 48dp baseline Android expects.
ANDROID_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# "Filament": slate ground, one warm ember accent — the same palette as the apps.
BG_TOP = (24, 27, 36)
BG_BOTTOM = (12, 14, 20)
EMBER = (232, 93, 42)
RING = (236, 239, 244)

# Rendered large and downsampled, which anti-aliases the curves for free.
CANVAS = 1024


def rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255
    )
    return mask


def draw_icon() -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Vertical gradient ground, drawn a row at a time — a solid fill reads flat at
    # 1024pt, where macOS shows the icon largest.
    ground = Image.new("RGBA", (CANVAS, CANVAS))
    painter = ImageDraw.Draw(ground)
    for y in range(CANVAS):
        t = y / (CANVAS - 1)
        painter.line(
            [(0, y), (CANVAS, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,),
        )
    # macOS icons are squircles; 0.225 is close to the system shape at this size.
    image.paste(ground, (0, 0), rounded_mask(CANVAS, 0.225))

    painter = ImageDraw.Draw(image)
    mid = CANVAS // 2
    # The mark: a hollow device, a link, a filled device. Sized so the whole group sits
    # inside the ~80% safe area Apple's grid expects, with room to breathe.
    ring_r = int(CANVAS * 0.105)
    dot_r = int(CANVAS * 0.105)
    gap = int(CANVAS * 0.20)
    stroke = int(CANVAS * 0.045)

    left = mid - gap
    right = mid + gap

    # Starts at the ring's edge, not its centre: drawn through, the bar leaves a stray
    # ember dot inside the hollow device and the ring stops reading as hollow.
    painter.line(
        [(left + ring_r, mid), (right, mid)], fill=EMBER + (255,), width=int(CANVAS * 0.035)
    )
    painter.ellipse(
        [left - ring_r, mid - ring_r, left + ring_r, mid + ring_r],
        outline=RING + (255,),
        width=stroke,
    )
    # The link's own node, so the bar reads as a connection rather than a hyphen.
    node_r = int(CANVAS * 0.035)
    painter.ellipse([mid - node_r, mid - node_r, mid + node_r, mid + node_r], fill=EMBER + (255,))
    painter.ellipse([right - dot_r, mid - dot_r, right + dot_r, mid + dot_r], fill=EMBER + (255,))

    return image


def main() -> int:
    icon = draw_icon()
    ICONSET.mkdir(parents=True, exist_ok=True)

    # The exact set `iconutil` expects; a missing size makes it refuse the whole bundle.
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(
            ICONSET / f"icon_{size}x{size}@2x.png"
        )

    for bucket, size in ANDROID_DENSITIES.items():
        directory = ANDROID_RES / f"mipmap-{bucket}"
        directory.mkdir(parents=True, exist_ok=True)
        scaled = icon.resize((size, size), Image.LANCZOS)
        scaled.save(directory / "ic_launcher.png")
        # Round launchers crop to a circle; handing them a squircle leaves clipped
        # corners, so the round variant is masked to a circle up front.
        circle = Image.new("L", (size, size), 0)
        ImageDraw.Draw(circle).ellipse((0, 0, size - 1, size - 1), fill=255)
        rounded = scaled.copy()
        rounded.putalpha(circle)
        rounded.save(directory / "ic_launcher_round.png")
    print(f"wrote Android launcher PNGs for {len(ANDROID_DENSITIES)} densities")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(OUT)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return result.returncode
    print(f"wrote {OUT.relative_to(HERE)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
