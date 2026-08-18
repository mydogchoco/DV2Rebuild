#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAN = REPO / "assets" / "converted" / "title_ui" / "_manifest.json"
OUT = REPO / "data" / "titles.json"

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
            "frame": "title_%d_kr" % no,
            "name": "",
            "comment": STAT_KR[stat] % need,
            "hidden": False,
            "unlock": {"stat": stat, "need": need},
            "_authored_unlock": True,
        })
    data = {
        "_source": "원작 title.img_plist(149종 _kr 프레임) + AchieveTitleLayer.",
        "_re_basis": (
            "화면=AchieveTitleLayer(CCTableView + common/checked.png + PopupTypeLayer). "
            "DB 스키마=`select title_no, name, comment, hidden from info_title_v`. "
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
