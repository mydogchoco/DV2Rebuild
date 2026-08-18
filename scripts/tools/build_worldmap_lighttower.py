#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "scene", "worldmap")
NAME = "ani_lighttower_spine"

FIXUPS = [("touch_wind", "top020202020202", "worldmap_top_wind", "worldmap_top_wind02")]

def main() -> None:
    sj = os.path.join(SRC, NAME + ".spine_json")
    atlas = os.path.join(SRC, NAME + ".img_plist")
    if not (os.path.exists(sj) and os.path.exists(atlas)):
        raise SystemExit(f"원본 없음: {sj}")

    with open(sj, encoding="utf-8") as f:
        skel = json.load(f)

    fixed = 0
    for anim, slot, wrong, right in FIXUPS:
        tl = skel.get("animations", {}).get(anim, {}).get("slots", {}).get(slot, {})
        for k in tl.get("attachment", []):
            if k.get("name") == wrong:
                k["name"] = right
                fixed += 1
    print(f"어태치먼트 오타 보정 {fixed}건 ({', '.join(a + '/' + s for a, s, _w, _r in FIXUPS)})")
    if fixed == 0:
        print("  ! 보정 대상이 없다 — 원본이 이미 다르거나 슬롯 이름이 바뀌었다. 표를 다시 확인할 것.")

    tmp = tempfile.mkdtemp(prefix="lighttower_")
    try:
        tsj = os.path.join(tmp, NAME + ".spine_json")
        with open(tsj, "w", encoding="utf-8") as f:
            json.dump(skel, f, ensure_ascii=False)
        shutil.copy2(atlas, os.path.join(tmp, NAME + ".img_plist"))
        shutil.copy2(os.path.join(SRC, NAME + ".png"), os.path.join(tmp, NAME + ".png"))
        out = spine_export.export_scene(tsj, anim_filter="all",
                                        atlas_path=os.path.join(tmp, NAME + ".img_plist"))
        print("→", out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\n다음: godot --headless --path . --script res://scripts/tools/build_worldmap_fx_scenes.gd")

if __name__ == "__main__":
    main()
