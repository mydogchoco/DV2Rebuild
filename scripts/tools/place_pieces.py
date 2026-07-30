"""월드맵 조각 자동 배치 — 레시피 ptA(cocos) ↔ background1 슬롯(bgtex) 정합.

레시피(`data/recipes/WorldMap<Region>Layer.json`)의 조각 ptA(원작 cocos 상대배치)와,
`map_<region>_new/background1.png`의 투명 슬롯(빈칸 절대위치)을 **어파인 브루트포스로 정합**한다.
조각 수가 적어(4~5) 배정 순열을 전탐색해 잔차 최소 어파인을 찾고, 슬롯이 부족한(바다에 열린)
조각은 그 어파인으로 ptA를 변환해 채운다. → 각 조각의 bg-atlas px 위치 산출(worldmap.json native용).

유타칸에서 수동으로 한 슬롯매칭을 일반화. 결과는 rough 자동배치(사용자 미세조정 여지).

사용:  python scripts/tools/place_pieces.py elf
"""
from __future__ import annotations
import sys, json, itertools
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

REPO = Path(__file__).resolve().parents[2]


def detect_slots(bg_png: Path, min_size=2000):
    a = np.array(Image.open(bg_png).convert("RGBA"))[:, :, 3]
    H, W = a.shape
    lbl, n = ndimage.label(a < 60)
    border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
    border.discard(0)
    slots = []
    for i in range(1, n + 1):
        if i in border:
            continue
        ys, xs = np.where(lbl == i)
        if len(xs) < min_size:
            continue
        slots.append([float(xs.mean()), float(ys.mean())])
    return slots, (W, H)


def fit_affine(src, dst):
    """대각 모델: bgtex_x=a*cx+b, bgtex_y=c*cy+d (4-param, x/y독립, y-flip 자연처리).
    전(全)어파인(6-param)은 조각 3개 등 소수에서 shear 과적합→외삽붕괴 → 대각으로 제한.
    returns ((a,b,c,d), residual)."""
    cx, cy = src[:, 0], src[:, 1]
    dx, dy = dst[:, 0], dst[:, 1]
    a, b = np.polyfit(cx, dx, 1)
    c, d = np.polyfit(cy, dy, 1)
    px, py = a * cx + b, c * cy + d
    res = float(np.sqrt((px - dx) ** 2 + (py - dy) ** 2).mean())
    return (a, b, c, d), res


def apply_diag(P, pta):
    a, b, c, d = P
    pta = np.array(pta, float)
    return np.stack([a * pta[:, 0] + b, c * pta[:, 1] + d], axis=1)


def best_assignment(pta, slots):
    """조각 ptA(cocos) ↔ 슬롯(bgtex) 최적 배정+어파인 브루트포스.
    슬롯 수 k ≤ 조각 수 m. 조각 중 k개를 슬롯에 배정하는 순열 전탐색."""
    m, k = len(pta), len(slots)
    pta = np.array(pta, float)
    slots = np.array(slots, float)
    best = (None, 1e18, None)  # (A, res, assignment idx)
    for combo in itertools.permutations(range(m), k):
        src = pta[list(combo)]
        A, res = fit_affine(src, slots)
        if res < best[1]:
            best = (A, res, combo)
    return best


def main():
    region = sys.argv[1] if len(sys.argv) > 1 else "elf"
    cls = {"elf": "WorldMapElfLayer", "dwarf": "WorldMapDwarfLayer"}[region]
    rec = json.load(open(REPO / "data" / "recipes" / f"{cls}.json", encoding="utf-8"))
    pieces = []
    for items in rec["methods"].values():
        for it in items:
            if it["kind"] == "piece" and it.get("ptA"):
                pieces.append(it)
    pta = [p["ptA"] for p in pieces]
    bg_png = REPO / "DV2" / "480" / "scene" / "worldmap" / f"map_{region}_new" / "background1.png"
    slots, (W, H) = detect_slots(bg_png)
    print(f"{region}: pieces {len(pieces)}, interior slots {len(slots)}, bg {W}x{H}")

    A, res, combo = best_assignment(pta, slots)
    print(f"  best diag-fit residual {res:.1f}px (assigned pieces idx {combo} → slots)")
    # 전체 조각 위치 = 대각변환(ptA)
    pos = apply_diag(A, pta)
    for p, xy in zip(pieces, pos):
        frame = p["raw"].split("/")[-1]
        p["_pos_bgtex"] = [round(float(xy[0]), 1), round(float(xy[1]), 1)]
        print(f"   field={p['field']:5} {frame:12s} ptA={p['ptA']} → bgtex {p['_pos_bgtex']}")
    # 참고 좌표블록 값 제안(bg_tex_center=half, scale=yutakan 0.72 기준)
    print(f"  bg_tex_center=[{W/2},{H/2}]  (scale/ bg_design은 yutakan 블록 참고해 렌더서 조정)")
    # 저장(후속 native 블록 작성용)
    out = REPO / "scratch_shots" / f"place_{region}.json"
    json.dump({"region": region, "bg_size": [W, H], "residual": res,
               "pieces": [{"field": p["field"], "frame_raw": p["raw"],
                           "pos_bgtex": p["_pos_bgtex"]} for p in pieces]},
              open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"  -> {out}")


if __name__ == "__main__":
    main()
