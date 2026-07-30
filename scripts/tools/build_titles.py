#!/usr/bin/env python3
"""칭호(업적 칭호) 데이터 생성 — data/titles.json.

## 원작 근거
  · 화면 = `AchieveTitleLayer` (docs/ref/audit/AchieveTitleLayer.md)
      아틀라스 `title.img_plist` + `9patch` + `common` + `scene/achievement`
      `CCTableView` 목록 · 획득 표시 `common/checked.png` · 상세 `PopupTypeLayer`
  · 데이터 = `info_title_v` — 컬럼이 디컴프에 그대로:
        select title_no, name, comment, hidden from info_title_v
  · 칭호 아트 = `title/%d_kr.png` (언어별 `_en` 짝) — 추출 아틀라스에 **149종 실재**

## 이름이 유실이어도 괜찮은 이유
`info_title_v.name/comment` 는 서버 갱신분이라 유실이지만, **칭호 텍스트 자체가 이미지**다
(`title/<no>_kr.png` 가 렌더된 칭호 라벨). 즉 화면에 필요한 것은 다 있고,
DB 의 name 은 검색/정렬용 문자열일 뿐이다. → 이미지를 그대로 쓰고 name 은 비워 둔다.

## ⚠️ 자작한 것 (HARD RULE 6 예외, 사용자 승인 2026-07-27)
`RequestTitle`/`ResponseTitle` 이 NetworkManager 호출이라 **획득 조건이 서버 소유**였고 유실됐다.
오프라인용으로 **획득 조건을 자작**한다 — 우리가 이미 세는 지표(UserDB 퀘스트 카운터·보유 드래곤 수
·최고 레벨 등)에 문턱값을 걸었다. 조건 종류·문턱은 아래 UNLOCK_RULES 가 튜닝 노브.

    python scripts/tools/build_titles.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAN = REPO / "assets" / "converted" / "title_ui" / "_manifest.json"
OUT = REPO / "data" / "titles.json"

# ── 자작 획득 조건 ──────────────────────────────────────────────────────────
# stat = UserDB 가 실제로 세는 지표. 문턱은 칭호 번호가 커질수록 어려워지게 배분한다.
#   dragons   보유 드래곤 수
#   hatches   부화 횟수(UserDB.bump_quest("hatches"))
#   battles   전투 승리 수
#   max_level 보유 드래곤 최고 레벨
#   gold      누적 보유 골드
UNLOCK_RULES = [
    ("dragons",   [1, 3, 5, 10, 15, 20, 30, 40, 50, 70]),
    ("hatches",   [1, 5, 10, 20, 30, 50, 80, 120, 200, 300]),
    ("battles",   [1, 10, 30, 60, 100, 200, 350, 500, 800, 1200]),
    ("max_level", [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]),
    ("gold",      [10_000, 50_000, 100_000, 300_000, 500_000,
                   1_000_000, 3_000_000, 5_000_000, 10_000_000, 20_000_000]),
]
STAT_KR = {
    "dragons": "드래곤 %d마리 보유",
    "hatches": "부화 %d회",
    "battles": "전투 승리 %d회",
    "max_level": "드래곤 레벨 %d 달성",
    "gold": "골드 %d 보유",
}


def main() -> None:
    if not MAN.exists():
        raise SystemExit("title_ui 미변환 — python scripts/tools/cocos_export.py "
                         "DV2/480/title.img_plist title_ui 먼저 실행")
    man = json.loads(MAN.read_text(encoding="utf-8"))
    nos = sorted({int(m.group(1)) for k in man
                  if (m := re.match(r"title_(\d+)_kr$", k))})
    titles = []
    for i, no in enumerate(nos):
        stat, steps = UNLOCK_RULES[i % len(UNLOCK_RULES)]
        need = steps[(i // len(UNLOCK_RULES)) % len(steps)]
        titles.append({
            "title_no": no,
            "frame": "title_%d_kr" % no,          # assets/converted/title_ui/
            "name": "",                            # info_title_v.name = 유실(이미지가 곧 이름)
            "comment": STAT_KR[stat] % need,       # 자작 획득 조건 설명
            "hidden": False,
            "unlock": {"stat": stat, "need": need},
            "_authored_unlock": True,
        })
    data = {
        "_source": "원작 title.img_plist(149종 _kr 프레임) + AchieveTitleLayer.",
        "_re_basis": (
            "화면=AchieveTitleLayer(CCTableView + common/checked.png + PopupTypeLayer). "
            "DB 스키마=`select title_no, name, comment, hidden from info_title_v`(디컴프 실재). "
            "칭호 텍스트는 **이미지 자체**(title/<no>_kr.png)라 name 유실이 화면에 영향 없다."
        ),
        "_authored_note": (
            "⚠️ HARD RULE 6 예외(사용자 승인 2026-07-27): 원작 획득 조건은 서버 소유"
            "(RequestTitle/ResponseTitle = NetworkManager)라 유실 → 오프라인용으로 자작했다. "
            "튜닝 노브 = scripts/tools/build_titles.py UNLOCK_RULES. "
            "각 칭호의 _authored_unlock:true 가 자작 표식."
        ),
        "atlas_dir": "title_ui",
        "titles": titles,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[build_titles] wrote %s: %d titles (no %d~%d)"
          % (OUT.relative_to(REPO), len(titles), nos[0], nos[-1]))


if __name__ == "__main__":
    main()
