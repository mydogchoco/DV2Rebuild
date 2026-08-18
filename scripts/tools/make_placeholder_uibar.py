from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]
DST = REPO / "DV2" / "ORIGINAL" / "UIbar.png"

W, H = 1000, 123
SS = 4

SLOT_CX = [43.0, 136.5, 249.0, 564.0, 658.5, 758.5, 853.5, 949.0]
SLOT_TOP = [57, 79, 79, 56, 73, 82, 79, 61]
PLATE_HW = 47.0
CAVE = (409.5, 83.0, 58.0)
RAIL_TOP_EDGE, RAIL_SAG = 84.0, 4.0

GEM_R = 5.0

C_PLATE_TOP = (223, 227, 233)
C_PLATE_BOT = (169, 177, 189)
C_RAIL_TOP = (166, 174, 186)
C_RAIL_BOT = (116, 125, 140)
C_EDGE = (108, 117, 132)
C_GEM = (94, 196, 190)
C_GEM_EDGE = (46, 122, 124)
C_CAVE_IN = (140, 149, 163)

def _vgrad(box, top_rgb, bot_rgb) -> Image.Image:
    x0, y0, x1, y1 = box
    w, h = int(x1 - x0), int(y1 - y0)
    g = Image.new("RGB", (1, max(1, h)))
    for i in range(max(1, h)):
        t = i / max(1.0, h - 1.0)
        g.putpixel((0, i), tuple(int(round(a + (b - a) * t)) for a, b in zip(top_rgb, bot_rgb)))
    return g.resize((w, h), Image.NEAREST)

def _rail_top(x: float) -> float:
    return RAIL_TOP_EDGE + RAIL_SAG * math.sin(math.pi * x / (W - 1.0))

def draw_bar() -> Image.Image:
    w, h = W * SS, H * SS
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    rail_mask = Image.new("L", (w, h), 0)
    rd = ImageDraw.Draw(rail_mask)
    for px in range(w):
        rd.line([(px, int(_rail_top(px / SS) * SS)), (px, h)], fill=255)
    rail = Image.new("RGB", (w, h))
    rail.paste(_vgrad((0, 0, w, h), C_RAIL_TOP, C_RAIL_BOT), (0, 0))
    canvas.paste(rail, (0, 0), rail_mask)
    ImageDraw.Draw(canvas).line(
        [(px, int(_rail_top(px / SS) * SS)) for px in range(w)],
        fill=C_EDGE + (255,), width=2 * SS)

    cx, cy, r = (v * SS for v in CAVE)
    ring = Image.new("L", (w, h), 0)
    ImageDraw.Draw(ring).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    plate = Image.new("RGB", (w, h))
    plate.paste(_vgrad((0, 0, w, h), C_PLATE_TOP, C_PLATE_BOT), (0, 0))
    canvas.paste(plate, (0, 0), ring)
    d = ImageDraw.Draw(canvas)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=C_EDGE + (255,), width=3 * SS)
    ri = r - 11 * SS
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=C_CAVE_IN + (255,))
    d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], outline=C_EDGE + (255,), width=2 * SS)

    for i, scx in enumerate(SLOT_CX):
        x0, x1 = (scx - PLATE_HW) * SS, (scx + PLATE_HW) * SS
        y0 = SLOT_TOP[i] * SS
        rad = 10 * SS
        pm = Image.new("L", (w, h), 0)
        ImageDraw.Draw(pm).rounded_rectangle([x0, y0, x1, h + rad], radius=rad, fill=255)
        canvas.paste(plate, (0, 0), pm)
        d.rounded_rectangle([x0, y0, x1, h + rad], radius=rad,
                            outline=C_EDGE + (255,), width=2 * SS)

    for a, b in zip(SLOT_CX, SLOT_CX[1:]):
        if b - a > 200.0:
            continue
        gx, gy, gr = (a + b) * 0.5 * SS, _rail_top((a + b) * 0.5) * SS + 6 * SS, GEM_R * SS
        d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr],
                  fill=C_GEM + (255,), outline=C_GEM_EDGE + (255,), width=SS)

    return canvas.resize((W, H), Image.LANCZOS)

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DST))
    a = ap.parse_args()
    im = draw_bar()
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    im.save(a.out, "PNG")
    alpha = im.split()[3]
    bottom_solid = sum(1 for x in range(W) if alpha.getpixel((x, H - 1)) > 16)
    print("wrote %s  %dx%d RGBA" % (a.out, im.width, im.height))
    print("아랫변에 붙은 열: %d/%d  (0 이면 despeckle 이 그림을 통째로 지운다)"
          % (bottom_solid, W))

if __name__ == "__main__":
    main()
