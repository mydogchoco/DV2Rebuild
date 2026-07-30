#!/usr/bin/env python3
"""원작 **스킬 이펙트 스파인**(`DV2/480/skill/skill_*_spine.spine_json`)을 중간 JSON으로 변환한다.

왜
--
`asset_index.py --gap skill` → 217건 미사용. 그중 스파인 34종이
`skill/skill_{N}_spine.spine_json` 형태로 있고, **N이 곧 스킬 id**다:

    skills.json 스킬 id 39종 vs 스파인 N 34종 → 교집합 33, 스킬 id가 아닌 N은 `2` 하나뿐
    (사운드 `effect_skill_{id}.mp3` 24종이 전부 스킬 id였던 것과 같은 규약)

우리 전투는 스킬 이펙트를 `_SKILL_FX`(카테고리별 도형/트윈)로 대체하고 있었다 —
CLAUDE.md §3 "원본에 있는 스파인을 도형·트윈으로 대체" 위반 신호다.

파이프라인(2단계)
----------------
    python scripts/tools/build_skill_fx.py            # 1) spine_json → 중간 JSON
    godot --headless --script res://scripts/tools/build_all.gd   # 2) 중간 JSON → .tscn

`assets/converted/`·`scenes/fx/` 는 gitignore 대상이라 이 스크립트가 변환 기록이다.
"""
from __future__ import annotations

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "skill")
OUT = os.path.join(REPO, "assets", "converted")


def main() -> None:
    if not os.path.isdir(SRC):
        raise SystemExit(f"원본 스킬 폴더 없음: {SRC}")
    only = {a for a in sys.argv[1:] if not a.startswith("--")}
    ok = fail = 0
    for sj in sorted(glob.glob(os.path.join(SRC, "skill_*_spine.spine_json"))):
        name = os.path.basename(sj)[: -len(".spine_json")]     # skill_11_spine
        key = name[len("skill_"):-len("_spine")]               # 11
        if only and key not in only:
            continue
        atlas = os.path.join(SRC, f"{name}.img_plist")
        if not os.path.exists(atlas):
            # 일부는 스킬 공용 아틀라스(skill.img_plist)를 쓴다.
            atlas = os.path.join(REPO, "DV2", "480", "skill.img_plist")
        try:
            # `export_scene` 은 씬용 스파인 규약(outdir=scenespine_<name>/scene.json)을 쓴다.
            # build_all.gd 가 그 규약을 알고 .tscn 을 만들어 준다.
            out = spine_export.export_scene(sj, anim_filter="all", atlas_path=atlas)
            if out is None:
                fail += 1
                continue
            ok += 1
            print(f"  + {name}")
        except Exception as e:                                  # noqa: BLE001
            fail += 1
            print(f"  ! {name}: {e}")
    print(f"\n스킬 이펙트 스파인 {ok}종 변환 / 실패 {fail}")
    print("다음: godot --headless --script res://scripts/tools/build_all.gd (중간 JSON → .tscn)")


if __name__ == "__main__":
    main()
