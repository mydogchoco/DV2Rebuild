#!/usr/bin/env python3
"""빛의 탑 터치 연출 스파인(`ani_lighttower_spine`)을 **원작 저작 오타를 고쳐** 변환한다.

왜 전용 스크립트인가
--------------------
원작 `touch_wind` 애니에 **어태치먼트 오타**가 있다. 슬롯 `top020202020202`(위로 솟는 가는
빛줄기)가 다른 7개 원소에서는 전부 `*_02`(34×106 줄기)를 쓰는데, `wind` 만 `worldmap_top_wind`
(184×302 = **탑 건물 통짜 그림**)을 가리킨다:

    touch_chaos    top020202020202 → worldmap_top_chaos02  [34,106]
    touch_dark     …               → worldmap_top_dark02   [34,106]
    touch_fire     …               → worldmap_top_fire02   [34,106]
    touch_ground   …               → worldmap_top_ground02 [34,106]
    touch_holy     …               → worldmap_top_holy02   [34,106]
    touch_right    …               → worldmap_top_light02  [28,106]
    touch_water    …               → worldmap_top_water02  [34,106]
    touch_wind     …               → worldmap_top_wind     [184,302]   ← 🔴 탑 그림
                                     (= worldmap_toptop 슬롯이 쓰는 것과 **같은** 어태치먼트)

그 슬롯의 본은 `touch_wind` 에서 y 10 → 220 을 0.6초에 이동한다 ⇒ **탑 건물이 빛기둥과 함께
빠르게 솟구쳐 오르는** 것으로 보인다(사용자 지적 2026-07-29). 셋업 포즈에서 이 슬롯의
어태치먼트가 `worldmap_top_wind02` 인 것이 저작 의도를 뒷받침한다 — `02` 를 빠뜨린 오타다.

⇒ 변환할 때 `touch_wind` 의 그 키만 `worldmap_top_wind02` 로 고친다. **원본은 건드리지 않는다**
(`DV2/` 는 읽기 전용, CLAUDE.md §4) — 메모리에서 고친 뒤 내보낸다.

파이프라인
---------
    python scripts/tools/build_worldmap_lighttower.py
    godot --headless --path . --script res://scripts/tools/build_worldmap_fx_scenes.gd
    godot --headless --path . --script res://scripts/tools/test_lighttower_spine.gd --quit-after 30

검증: `test_lighttower_spine.gd` 가 touch_* 에서 탑 본체·배경판이 숨는지, 원소 변형이 1개만
보이는지, 그리고 이 오타가 고쳐졌는지 확인한다.
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "scene", "worldmap")
NAME = "ani_lighttower_spine"

# (애니, 슬롯, 잘못된 어태치먼트) → 올바른 어태치먼트
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

    # 원본을 건드리지 않기 위해 임시 디렉터리에 스켈레톤+아틀라스 사본을 만들어 내보낸다.
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
