#!/usr/bin/env python3
"""콜로세움 연출용 원작 스파인 변환.

`assets/converted/` 와 `scenes/fx/` 는 gitignore 대상(파생물 + 저작권 자료)이라,
**어떤 원본을 어떤 이름으로 변환하는지는 이 스크립트가 유일한 기록**이다.
새로 체크아웃했으면 이걸 돌려서 재생성한다.

    python scripts/tools/build_colosseum_fx.py
    godot --headless --path . --import        # ← 페이지 PNG 임포트(안 하면 다음 줄이 텍스처를 못 찾는다)
    godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \
        assets/converted/scenecolosseum_fight_spine/scene.json scenes/fx/colosseum_fight.tscn

무엇을 왜 변환하나
------------------
`scene/colosseum/fight_spine` — 대전 시작 **"FIGHT!" 연출**. 원작 `MakeInterface` 가
콜로세움 전투 진입에 쓴다(`asset_index.py --grep colosseum` → orig=MakeInterface).
읽는 쪽 = `scripts/ui/fight.gd::_vs_intro`.

`scene/colosseum/colo_waiting_spine` — 매칭 대기 연출(원작 `LoadingLayer`).
⚫ 우리는 봇 상대라 **매칭 대기가 없다** → 변환은 하되 지금 쓰는 곳은 없다.
(원작 대기 화면을 흉내 내려고 억지로 끼워 넣지 않는다.)

`scene/colosseum/scene_colosseum_lightning_spine` — 무대 번개 앰비언트.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spine_export  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

# (원본 spine_json, 만들어질 씬 경로) — 씬 빌드는 엔진이 필요해 여기서 하지 않는다(위 명령 참고).
SCENE_SPINES = [
    ("DV2/480/scene/colosseum/fight_spine.spine_json", "scenes/fx/colosseum_fight.tscn"),
    ("DV2/480/scene/colosseum/scene_colosseum_lightning_spine.spine_json",
     "scenes/fx/colosseum_lightning.tscn"),
]


def main() -> int:
    import os
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    os.chdir(REPO)
    for src, out in SCENE_SPINES:
        if not Path(src).exists():
            print(f"[skip] 원본 없음: {src}")
            continue
        js = spine_export.export_scene(src)
        print(f"  -> {js}\n     다음: build_spine_scene.gd -- {js} {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
