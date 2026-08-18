#!/usr/bin/env python3
from __future__ import annotations

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "skill")
OUT = os.path.join(REPO, "assets", "converted")

def main() -> None:
    if not os.path.isdir(SRC):
        raise SystemExit(f"원본 스킬 폴더 없음: {SRC}")
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    ok = fail = 0
    for sj in sorted(glob.glob(os.path.join(SRC, "skill_*_spine.spine_json"))):
        name = os.path.basename(sj)[: -len(".spine_json")]
        key = name[len("skill_"):-len("_spine")]
        if only and key not in only:
            continue
        atlas = os.path.join(SRC, f"{name}.img_plist")
        if not os.path.exists(atlas):
            atlas = os.path.join(REPO, "DV2", "480", "skill.img_plist")
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
    print(f"\n스킬 이펙트 스파인 {ok}종 변환 / 실패 {fail}")
    print("다음: godot --headless --script res://scripts/tools/build_all.gd (중간 JSON → .tscn)")

if __name__ == "__main__":
    main()
