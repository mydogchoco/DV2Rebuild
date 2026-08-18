#!/usr/bin/env python3
from __future__ import annotations

import os
import plistlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "scene", "worldmap")
OUT = os.path.join(REPO, "assets", "converted")

SPINES = ["ani_sea_spine"]

TRANS = ("background_trans", "scene/worldmap/background_trans/bg.png", "worldmap_sea_trans")

def _rect(s: str):
    return [int(float(v)) for v in re.findall(r"-?\d+(?:\.\d+)?", s)]

def export_trans() -> bool:
    from PIL import Image

    atlas, key, outname = TRANS
    pl_path = os.path.join(SRC, atlas + ".img_plist")
    png_path = os.path.join(SRC, atlas + ".png")
    if not (os.path.exists(pl_path) and os.path.exists(png_path)):
        print(f"  ! {atlas}: 원본 없음")
        return False
    with open(pl_path, "rb") as f:
        pl = plistlib.load(f)
    fr = pl["frames"].get(key)
    if fr is None:
        print(f"  ! {key}: 프레임 없음")
        return False
    x, y, w, h = _rect(fr["frame"])
    rotated = bool(fr.get("rotated") or fr.get("textureRotated"))
    page = Image.open(png_path).convert("RGBA")
    im = page.crop((x, y, x + h, y + w)).transpose(Image.ROTATE_270) if rotated \
        else page.crop((x, y, x + w, y + h))
    outdir = os.path.join(OUT, "worldmap_sea")
    os.makedirs(outdir, exist_ok=True)
    im.save(os.path.join(outdir, outname + ".png"))
    print(f"  + {outname}.png  {im.size}  (원작 sourceSize={fr.get('sourceSize')})")
    return True

def main() -> None:
    if not os.path.isdir(SRC):
        raise SystemExit(f"원본 월드맵 폴더 없음: {SRC}")
    ok = fail = 0
    for name in SPINES:
        sj = os.path.join(SRC, name + ".spine_json")
        atlas = os.path.join(SRC, name + ".img_plist")
        if not os.path.exists(sj):
            print(f"  ! {name}: spine_json 없음")
            fail += 1
            continue
        try:
            out = spine_export.export_scene(sj, anim_filter="all", atlas_path=atlas)
            if out is None:
                fail += 1
                continue
            ok += 1
            print(f"  + {name}")
        except Exception as e:
            fail += 1
            print(f"  ! {name}: {e}")
    if not export_trans():
        fail += 1
    print(f"\n바다 층 자산: 스파인 {ok}종 변환 / 실패 {fail}")
    print("다음: godot --headless --script res://scripts/tools/build_worldmap_fx_scenes.gd")

if __name__ == "__main__":
    main()
