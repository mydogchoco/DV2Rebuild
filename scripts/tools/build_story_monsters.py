# -*- coding: utf-8 -*-
"""스토리 전용 몬스터 3종 → `data/story_monsters.json`.

## 왜 별도 파일인가

이 셋은 **던전 편성에 없다.** `mapping_sheet.md`(사용자 검수 `_v`)가 스테이지 목록 끝에
`(스토리 전용)` 으로만 달아 뒀고, `stages.json` 의 `enemies` 에는 들어가지 않는다.
원작에서도 1~78화 구간은 `scenarioBattle` 호출이 **0건**이고(xref 전수)
서브퀘스트 표(`subquest_field`/`mark_field`/`click_count`)도 79화부터라
그 구간 퀘스트 정의(로컬 SQLite `info_quest_v2`)와 함께 유실됐다.
⇒ **사용자 지식이 유일한 출처**다.

## 🔴 스프라이트 번호 축이 둘이고, 맞는 쪽은 mapping_sheet 다

    mapping_sheet.md (_v 검수) :  #73 기계 만드라고낙 · #74 정령 스파이크젤 · #75 다크프로스티
    data/monsters.json         :  #73 G스컬 · #74 다크닉스 · #75 그리파르

후자가 틀렸다. `monsters.json` 의 `asset_id` 는 `extract_wiki.py` 가 **위키 등장 순으로
자동 부여**한 값이라 근거가 없고(그 파일 스스로 "asset_id=이미지 매칭 TODO" 라고 적는다,
`build_monster_skills.py:18` 도 "asset_id 로 조인하면 안 된다" 고 경고한다),
실제로 게임이 쓰는 `stages.json` 은 같은 몬스터를 다른 번호로 부른다:

    G스컬 #30(해골 요새) · 다크닉스 #36(혼돈의 틈새) · 그리파르 #138 · 발레포르 #139

⇒ 73/74/75 는 비어 있는 자리이고 그게 스토리 몹 셋의 자리다.

**파생 정정**: 원작 이벤트 전투 29(`getEventBattleData`)의 `monster_no = 75` 를
`monsters.json` 으로 풀면 '그리파르'가 되는데, 그건 위 오류 때문이다. 옳게 풀면
**다크프로스티**이고 스탯도 그쪽에 맞는다 —
이벤트 29 = lv50 hp1100/공200/방125 vs 다크프로스티 hp1200/공160/방80 (같은 자릿수),
그리파르 = hp14850 (13배 차이).

사용:  python scripts/tools/build_story_monsters.py
"""
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "story_monsters.json"

# sprite_no, 이름, 등장 회차, 기본 스테이지(mapping_sheet 가 매단 곳), 스탯, 특수
#   `pure` = 방어 무시 고정 대미지(battle.gd `_pure_damage`). 원작 위키 표현 "고정 데미지".
MONSTERS = [
    {
        "id": 73, "name": "기계 만드라고낙", "episodes": [27], "stage": 10,
        "_stats_status": "미상 — 사용자 확인 대기",
    },
    {
        "id": 74, "name": "정령 스파이크젤", "episodes": [28], "stage": 11,
        "_stats_status": "미상 — 사용자 확인 대기",
    },
    {
        "id": 75, "name": "다크프로스티", "episodes": [32, 33], "stage": 14,
        "hp_max": 1200, "att": 160, "def": 80, "pure": 1000,
        "_stats_status": "사용자 확정 2026-07-31",
        "_pure_basis": "사용자 확정: '공격 시 고정 데미지 1000'. 우리 전투의 `pure`"
                       "(방어·막기를 무시하고 더해지는 flat 피해, battle.gd::_pure_damage)에 해당한다.",
    },
]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    doc = OrderedDict()
    doc["_re_basis"] = (
        "스토리 전용 몬스터 3종. 배정(몬스터↔회차) = 사용자 확정 2026-07-31. "
        "원작 1~78화에는 scenarioBattle 호출이 0건이고(xref 전수) 서브퀘스트 표도 79화부터라 "
        "그 구간 퀘스트 정의(info_quest_v2, 로컬 SQLite·덤프에 없음)와 함께 유실됐다 — "
        "사용자 지식이 유일한 출처다."
    )
    doc["_id_basis"] = (
        "id = mapping_sheet.md(_v 검수)의 스프라이트 번호. "
        "⚠️ data/monsters.json 의 asset_id 73/74/75(G스컬·다크닉스·그리파르)는 "
        "extract_wiki.py 의 자동 부여라 **틀렸다** — 게임이 실제로 쓰는 stages.json 은 "
        "G스컬 #30 · 다크닉스 #36 · 그리파르 #138 이다."
    )
    doc["_tool"] = "scripts/tools/build_story_monsters.py"
    doc["monsters"] = MONSTERS
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    have = sum(1 for m in MONSTERS if "hp_max" in m)
    print(f"-> {OUT.relative_to(ROOT)}  {len(MONSTERS)}종 (스탯 확정 {have} · 미상 {len(MONSTERS) - have})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
