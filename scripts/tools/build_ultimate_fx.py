#!/usr/bin/env python3
"""각성기(`UltimateLayer`) 연출용 원작 스파인 변환.

`assets/converted/` 와 `scenes/fx/` 는 gitignore 대상(파생물 + 저작권 자료)이라,
**어떤 원본을 어떤 이름으로 변환하는지는 이 스크립트가 유일한 기록**이다.

    python scripts/tools/build_ultimate_fx.py
    godot --headless --path . --import        # ← 페이지 PNG 임포트(안 하면 다음 줄이 텍스처를 못 찾는다)
    godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \
        assets/converted/scenespine_holy_wing_spine/scene.json scenes/fx/ultimate_holy_wing.tscn
    godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \
        assets/converted/scenespine_shadow_spine/scene.json scenes/fx/ultimate_shadow.tscn

무엇을 왜 변환하나
------------------
`skill/ultimate/holy/holy_wing_spine` — **신성 각성기의 콜로세움 추가 연출**.
원작 `UltimateLayer::initHoly_C` @0100ced0 이 `.spine_json` + `.img_plist` 를 함께 부른다.
빛나는 날개가 바닥 링 위에 겹친다. 애니 `animation` 1종(bones 11 / slots 14).

`skill/ultimate/shadow/shadow_spine` — **그림자 각성기의 연출 본체**.
`initShadow` @00fe6950 이 프레임 대신 이 스켈레톤을 세운다 — 그림자만 프레임 시퀀스가 아니라
스파인이 주인공이다(그래서 우리 프레임 기반 골격이 그림자에서 특히 빈약했다).
애니 **`s1` · `s2`** 2종(bones 15 / slots 27).

⚠️ 두 스파인은 각각 **자기 이름의 `.img_plist`** 를 쓴다(드래곤처럼 본체 아틀라스를 빌려오지
   않는다) — `--scene` 진입점의 기본 규약(`<base>.img_plist`)이 그대로 맞는다.

관련 = `docs/ref/porting/UltimateLayer.md` §7(선행 자산)
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spine_export  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

# (원본 spine_json, 만들 씬 경로) — 씬 이름은 읽는 쪽(ultimate_fx.gd)이 쓰는 논리 이름이다.
SPINES = [
    ("DV2/480/skill/ultimate/holy/holy_wing_spine.spine_json", "scenes/fx/ultimate_holy_wing.tscn"),
    ("DV2/480/skill/ultimate/shadow/shadow_spine.spine_json", "scenes/fx/ultimate_shadow.tscn"),
]


def main() -> int:
    import os
    os.chdir(REPO)
    for src, scene in SPINES:
        if not Path(src).exists():
            print("[skip] 원본 없음: %s" % src)
            continue
        out = spine_export.export_scene(src)
        print("  %s → %s   (씬: %s)" % (src, out, scene))
    print("\n다음: godot --headless --path . --import")
    for src, scene in SPINES:
        name = Path(src).stem
        print("      godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- "
              "assets/converted/scenespine_%s/scene.json %s" % (name, scene))
    return 0


if __name__ == "__main__":
    sys.exit(main())
