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

✅ **사용자 재확인 2026-07-31**: 33화 전투의 다크프로스티가 **Lv50 · #75** 인 것이 확실하고,
   **92화에도 #75 다크프로스티가 등장**한다(위키 확인). 원작이 `battleNo` 15(33화)와
   29(92화) 두 곳에서 #75 를 부르는 것과 일치한다 ⇒ 번호 확정.

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
#   `level` = 🟦 사용자 확정 2026-07-31 **셋 다 50 으로 통일**.
#     원작 `initEventBattle`(battleNo 11·12·14)은 레벨을 리터럴로 안 들고 몬스터 DB 값을 쓴다
#     (`setMonster(this, no, iVar3, …)`) — 그 DB 가 없으므로 사용자 확정값을 쓴다.
#     switch 경로의 battleNo 15 는 원작이 Lv50 을 리터럴로 들고 있어 서로 어긋나지 않는다.
MONSTERS = [
    {
        # 원작 `AdventureScene::initEventBattle` case 11 → 몬스터 #73. 사용자 확정 27화 ⇒ 11=27화.
        "id": 73, "id_confirmed": True, "battle_no": {"27": 11},
        # 전투 위치 = **그 대사 바로 뒤**(사용자 확정 2026-07-31).
        #   27화 29줄 = "- 아놀드와 플로렌스가 보고 있는 것은 몬스터 만드라고낙…
        #                하지만 평소와는 다르다! -"
        "battle_after_line": {"27": 29},
        "name": "기계 만드라고낙", "episodes": [27], "stage": 10,
        "hp_max": 2170, "att": 185, "def": 185, "level": 50,
        "_stats_status": "사용자 확정 2026-07-31",
    },
    {
        # `initEventBattle` case 12 → #74. 사용자 확정 28화 ⇒ 12=28화.
        "id": 74, "id_confirmed": True, "battle_no": {"28": 12},
        # 28화 13줄 = 즈믄 "이쪽으로 온다!"
        "battle_after_line": {"28": 13},
        "name": "정령 스파이크젤", "episodes": [28], "stage": 11,
        "hp_max": 2170, "att": 185, "def": 185, "level": 50,
        "_stats_status": "사용자 확정 2026-07-31 (기계 만드라고낙과 같은 값)",
    },
    {
        # 번호 확정 — mapping_sheet 의 빈 세 자리 배치가 맞았다. 교차검증 3중:
        #   ① 원작 battleNo 15 → #75 Lv50 (33화)  ② battleNo 29 → #75 Lv50 (92화)
        #   ③ 문자열 <AdventureEvent33> 이 "다크프로스티" 를 직접 부른다
        #   + 사용자 재확인 2026-07-31(33화 Lv50 #75 확실 · 92화 재등장도 위키 확인).
        "id": 75, "id_confirmed": True, "name": "다크프로스티",
        "episodes": [32, 33, 92], "stage": 14,
        # 원작 전투번호 ↔ 회차. 15 = 33화(사용자 확정 Lv50 #75 + <AdventureEvent33> 문자열),
        # 29 = 92화(getEventBattleData, 사용자 위키 재확인).
        # 전투가 **셋**이다: `initEventBattle` case 14 · switch case 15 · 이벤트 29(92화).
        # 32화·33화 중 어느 쪽이 14/15 인지는 원작에서 못 갈랐지만,
        # 🟦 사용자 확정 2026-07-31 "전부 50으로 통일" ⇒ **동작에 차이가 없다**
        #    (switch 15 도 원작 Lv50 · 이벤트 29 도 lv50). 그래서 그대로 짝지어 둔다.
        "battle_no": {"32": 14, "33": 15, "92": 29},
        # 전투 위치(사용자 확정 2026-07-31) —
        #   32화 4줄  "- 기계와 정령이 융합된 다크프로스티의 모습…. 이미 제정신이 아니다! -"
        #   33화 10줄 "- 플로렌스가 빌어준 축복의 힘을 최대한 활용해야만 한다! -"
        # 92화는 원작에서 이미 `scenarioBattle` 스텝이 뽑혀 있어 주입 대상이 아니다.
        "battle_after_line": {"32": 4, "33": 10},
        "hp_max": 1200, "att": 160, "def": 80, "pure": 1000, "level": 50,
        "_stats_status": "사용자 확정 2026-07-31 (32·33화 기준). 92화(원작 이벤트 전투 29)는 별도 스탯 lv50 hp1100/공200/방125 — story_subquest.json event_battle.",
        "_pure_basis": "사용자 확정: '공격 시 고정 데미지 1000'. 우리 전투의 `pure`"
                       "(방어·막기를 무시하고 더해지는 flat 피해, battle.gd::_pure_damage)에 해당한다.",
    },
    {
        # 🟦 사용자 지목 2026-08-04 "46화 도중 라이트 오브와의 전투가 발생해야 한다".
        #
        # 회차↔전투번호는 §14 대로 코드에서 직접 못 뽑지만, 이번엔 **근거 셋이 한 점에서
        # 만난다** — 그래서 사용자 확정과 같은 무게로 싣는다:
        #   ① 문자열 `<AdventureEvent46>` 이 실재한다("녀석을 물리치고 난 그 비밀을…")
        #      = 46화에 이벤트 전투가 있다.
        #   ② `AdventureScene::scene` 호출 16곳을 바이트 스캔해 각각 주변 ±0x600 의 대사 키
        #      회차를 읽으면, **46화 키만** 둘러싼 호출은 `scene(field=1, battle=16)` 하나다.
        #   ③ `Data.story_battle(16)` 이 실제로 **라이트 오브**로 풀린다
        #      (monster_by_battle 16 → monster_no 72 lv55) — 사용자가 지목한 바로 그 몬스터.
        #
        # ⚠️ 전투 **위치**(어느 대사 뒤인가)는 여전히 미상이라 `battle_after_line` 이 없다 →
        #    `inject_story_battles` 가 **회차 끝**에 꽂는다. 사용자가 앵커 대사를 주면 그때
        #    여기에 적는다(32·33화와 같은 방식).
        "id": 67, "id_confirmed": False, "name": "라이트 오브 (Light Orb)",
        "episodes": [46],
        "battle_no": {"46": 16},
        "_battle_no_basis": "①<AdventureEvent46> ②scene(1,16) 주변 대사키가 46화뿐 "
                            "③story_battle(16)=라이트 오브. 2026-08-04 실측.",
        # 스탯은 원작 표(`monster_by_battle` 16 = lv55)를 그대로 쓴다 — 여기서 덮지 않는다.
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
