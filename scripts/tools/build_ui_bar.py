from __future__ import annotations

import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "ORIGINAL" / "UIbar.png"
OUT = REPO / "assets" / "converted" / "mainbar_ui"

def _erase_glyphs(out, x0, y0, x1, y1, anchor=4, thresh=4.0, grow=2):
    h = out.shape[0]
    top = np.median(out[max(0, y0 - anchor):y0, x0:x1].astype(np.float32), axis=0)
    bot = np.median(out[y1:min(h, y1 + anchor), x0:x1].astype(np.float32), axis=0)
    n = y1 - y0
    for i in range(n):
        t = float(i) / max(1.0, float(n - 1))
        bg = top * (1.0 - t) + bot * t
        row = out[y0 + i, x0:x1].astype(np.float32)
        sel = row.mean(1) < bg.mean(1) - thresh
        for k in range(1, grow + 1):
            sel[k:] |= sel[:-k].copy()
            sel[:-k] |= sel[k:].copy()
        row[sel] = _bridge(row, sel, bg)[sel]
        out[y0 + i, x0:x1] = np.clip(row, 0, 255).astype(np.uint8)

def _bridge(row, sel, bg):
    out = row.copy()
    n = row.shape[0]
    i = 0
    while i < n:
        if not sel[i]:
            i += 1
            continue
        j = i
        while j < n and sel[j]:
            j += 1
        left = row[i - 1] if i > 0 else (row[j] if j < n else bg[i])
        right = row[j] if j < n else left
        span = max(1, j - i + 1)
        for k in range(i, j):
            a = float(k - i + 1) / float(span)
            out[k] = left * (1.0 - a) + right * a
        i = j
    return out

LABEL_BOXES = [
    (25, 91, 61, 114),
    (118, 91, 156, 114),
    (223, 91, 275, 114),
    (546, 91, 582, 114),
    (641, 91, 676, 114),
    (740, 91, 777, 114),
    (836, 91, 871, 114),
    (930, 91, 968, 114),
]
BADGE_BOX = (768, 84, 794, 108)
BADGE_MIRROR_CX = 758.5
BADGE_FEATHER = 3

SLOT_CX = [43.0, 136.5, 249.0, 564.0, 658.5, 758.5, 853.5, 949.0]
SLOT_W = 87.0
LABEL_CY = 102.0
LABEL_H = 16.0
CAVE = (409.5, 83.0, 58.0)

def despeckle(rgba: np.ndarray) -> np.ndarray:
    out = rgba.copy()
    m = out[..., 3] > 16
    h, w = m.shape
    keep = np.zeros_like(m)
    q: deque = deque()
    for x in range(w):
        if m[h - 1, x]:
            keep[h - 1, x] = True
            q.append((h - 1, x))
    while q:
        y, x = q.popleft()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not keep[ny, nx]:
                    keep[ny, nx] = True
                    q.append((ny, nx))
    stray = m & ~keep
    out[..., 3][stray] = 0
    above = 0
    for x in range(w):
        ys = np.nonzero(keep[:, x])[0]
        top = int(ys[0]) if ys.size else h
        above += int((out[:top, x, 3] > 0).sum())
        out[:top, x, 3] = 0
    print("despeckle: 부유 픽셀 %d개 · 윗변 위 헤일로 %d픽셀 제거" % (int(stray.sum()), above))
    return out

def mirror_patch(out: np.ndarray, box, cx: float, feather: int = 3) -> None:
    x0, y0, x1, y1 = box
    src = out[y0:y1, :][:, [int(round(2.0 * cx)) - x for x in range(x0, x1)]].astype(np.float32)
    dst = out[y0:y1, x0:x1].astype(np.float32)
    w, h = x1 - x0, y1 - y0
    wx = np.minimum(np.minimum(np.arange(w), np.arange(w)[::-1]) / max(1, feather), 1.0)
    wy = np.minimum(np.minimum(np.arange(h), np.arange(h)[::-1]) / max(1, feather), 1.0)
    a = (wy[:, None] * wx[None, :])[..., None]
    out[y0:y1, x0:x1] = np.clip(dst * (1.0 - a) + src * a, 0, 255).astype(np.uint8)

def plate_tops(alpha: np.ndarray) -> list[int]:
    h, w = alpha.shape
    tops = []
    for cx in SLOT_CX:
        x0, x1 = max(0, int(cx - SLOT_W * 0.5)), min(w, int(cx + SLOT_W * 0.5))
        best = h
        for x in range(x0, x1):
            ys = np.nonzero(alpha[:, x] > 16)[0]
            if ys.size:
                best = min(best, int(ys[0]))
        tops.append(best)
    return tops

def edge_top(alpha: np.ndarray, x0: int) -> int:
    h, w = alpha.shape
    return min(int(np.nonzero(alpha[:, x] > 16)[0][0])
               for x in range(x0, w) if (alpha[:, x] > 16).any())

def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    rgba = despeckle(np.asarray(im))
    h, w, _ = rgba.shape

    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(OUT / "uibar.png")

    clean = rgba.copy()
    rgb = clean[..., :3]
    for box in LABEL_BOXES:
        _erase_glyphs(rgb, *box)
    mirror_patch(rgb, BADGE_BOX, BADGE_MIRROR_CX, BADGE_FEATHER)
    clean[..., :3] = rgb
    Image.fromarray(clean, "RGBA").save(OUT / "uibar_clean.png")

    tops = plate_tops(rgba[..., 3])
    right = edge_top(rgba[..., 3], int(SLOT_CX[-1] - SLOT_W * 0.5))
    meta = {
        "_source": "DV2/ORIGINAL/UIbar.png (1000x123 RGBA, 사용자 제공 컷 2026-08-08)",
        "_tool": "scripts/tools/build_ui_bar.py",
        "src_size": [w, h],
        "crop": {"x": 0, "y": 0, "w": w, "h": h},
        "slot_cx": SLOT_CX,
        "slot_w": SLOT_W,
        "slot_top": tops,
        "cave_circle": {"cx": CAVE[0], "cy": CAVE[1], "r": CAVE[2]},
        "label_center_y": LABEL_CY,
        "label_h": LABEL_H,
        "right_edge_top": right,
        "_note": "좌표는 전부 uibar.png 픽셀. main_hud.gd 는 k = vis.x / src_size[0] 로 화면에 옮긴다.",
    }
    (OUT / "_uibar_meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")

    print("wrote", OUT)
    print("\n--- main_hud.gd 상수 (그대로 붙여 넣는다) ---")
    print("const BAR_REF_W := %.1f" % w)
    print("const BAR_REF_H_FALLBACK := %.1f" % h)
    print("const BAR_REF_TOP_FALLBACK := 0.0")
    print("const BAR_SLOT_CX := %s" % ("[" + ", ".join("%.1f" % c for c in SLOT_CX) + "]"))
    print("const BAR_SLOT_W := %.1f" % SLOT_W)
    print("const BAR_SLOT_TOP := %s" % ("[" + ", ".join("%.1f" % t for t in tops) + "]"))
    print("const BAR_LABEL_CY := %.1f" % LABEL_CY)
    print("const BAR_LABEL_H := %.1f" % LABEL_H)
    print("const BAR_CAVE := Vector3(%.1f, %.1f, %.1f)" % CAVE)
    print("const SET_BTN_EDGE := %.1f" % right)

if __name__ == "__main__":
    main()
