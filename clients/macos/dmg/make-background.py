"""Draws the DMG window's background: dmg/background.tiff (1x + 2x in one file).

Run after changing the layout (needs Pillow); the output is committed, so releases don't need
Pillow. Positions here must match dmg/settings.py.

Finder draws icon labels black in Light mode and white in Dark mode, so each label sits on a
mid-tone pill that both can be read against.
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
# Taller than the layout needs: newer Finders always show the toolbar and status bar (~125 pt),
# older ones hide them. Everything that matters sits in the top 410 pt, visible either way.
W, H = 660, 540
APP, APPS, README = (170, 180), (490, 180), (330, 320)  # icon centres, as in settings.py
ICON = 96
BG = (14, 16, 23)
EMBER = (255, 106, 61)
AMBER = (255, 176, 92)
INK = (236, 238, 243)
MUTED = (150, 156, 168)
PILL = (116, 119, 127)  # ~4.5:1 against both black and white label text
SF = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def draw(scale):
    s = lambda v: int(round(v * scale))
    img = Image.new("RGB", (s(W), s(H)), BG)

    # The ember glow rising from the bottom, as on the website.
    glow = Image.new("RGB", img.size, BG)
    g = ImageDraw.Draw(glow)
    g.ellipse((s(-60), s(250), s(W + 60), s(H + 260)), fill=(78, 34, 22))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(s(70))), 0.9)
    d = ImageDraw.Draw(img)

    title = "Drag FuseOS into Applications"
    f = font(s(22), 700)
    d.text((s(W / 2), s(48)), title, font=f, fill=INK, anchor="mm")
    d.text(
        (s(W / 2), s(76)),
        "Then open Read Me First — it lists what to switch on.",
        font=font(s(13), 450),
        fill=MUTED,
        anchor="mm",
    )

    # The arrow from the app to Applications.
    y = APP[1]
    x0, x1 = APP[0] + ICON / 2 + 26, APPS[0] - ICON / 2 - 26
    d.line((s(x0), s(y), s(x1 - 12), s(y)), fill=EMBER, width=s(4))
    d.polygon([(s(x1), s(y)), (s(x1 - 16), s(y - 10)), (s(x1 - 16), s(y + 10))], fill=AMBER)

    # Label pills under each icon (Finder writes the label on top).
    for (cx, cy), width in ((APP, 92), (APPS, 118), (README, 132)):
        top = cy + ICON / 2 + 4
        d.rounded_rectangle(
            (s(cx - width / 2), s(top), s(cx + width / 2), s(top + 22)), radius=s(11), fill=PILL
        )
    return img


out = HERE / "background"
draw(1).save(f"{out}.png")
draw(2).save(f"{out}@2x.png")
subprocess.run(
    ["tiffutil", "-cathidpicheck", f"{out}.png", f"{out}@2x.png", "-out", f"{out}.tiff"],
    check=True,
    capture_output=True,
)
Path(f"{out}.png").unlink()
Path(f"{out}@2x.png").unlink()
print(f"wrote {out}.tiff")
