#!/usr/bin/env python3
"""동굴(둥지) 연출용 원작 스파인 변환 — 부화 빛기둥.

`assets/converted/` 와 `scenes/fx/` 는 gitignore 대상(파생물 + 저작권 자료)이라,
**어떤 원본을 어떤 이름으로 변환하는지는 이 스크립트가 유일한 기록**이다.
새로 체크아웃했으면 이걸 돌려서 재생성한다.

    python scripts/tools/build_cave_fx.py
    godot --headless --path . --import        # ← 페이지 PNG 임포트 (안 하면 다음 줄이 텍스처를 못 찾는다)
    godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \
        assets/converted/scenespine_egglight_spine/scene.json scenes/fx/egglight.tscn

무엇을 왜 변환하나
------------------
`scene/cave/egglight_spine` — 알 부화 연출의 **빛기둥**. 원작 `CaveScene::sResultEgg` 가
`createWithFile("scene/cave/egglight_spine.spine_json", ".img_plist", 1.0)` 로 만들어
알 레이어의 `(w/2−7, h/2−100)` 에 붙이고 `setAnimation("egglight", loop=false)`,
`setScale(0.7 if dragonNo==23 else 0.93)`, 4.5초 뒤 0.5초 페이드아웃으로 지운다.
읽는 쪽 = `scripts/ui/cave.gd::_hatch_ceremony` · 포팅 카드 = `docs/ref/porting/EggHatch.md`.

⚠️ 이 스켈레톤은 **어태치먼트 크기가 이미 포인트 단위**다(어태치먼트 ÷ 아틀라스 리전 = 4/3).
   따라서 렌더에서 `Design.ASSET_SCALE` 을 또 곱하면 안 되고 `setScale` 값을 그대로 쓴다.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spine_export  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

# (원본 spine_json, 만들어질 씬 경로) — 씬 빌드는 엔진이 필요해 여기서 하지 않는다(위 명령 참고).
SCENE_SPINES = [
    ("DV2/480/scene/cave/egglight_spine.spine_json", "scenes/fx/egglight.tscn"),
]


def main() -> int:
    import os
    os.chdir(REPO)
    for src, out in SCENE_SPINES:
        if not Path(src).exists():
            print(f"[skip] 원본 없음: {src}")
            continue
        js = spine_export.export_scene(src)
        print(f"  → {js}\n    다음: build_spine_scene.gd -- {js} {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
