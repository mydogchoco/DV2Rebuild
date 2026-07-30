#!/usr/bin/env python3
"""데이터 트랙 — 나무위키 스토리 PDF → `data/story.json` (회차 목차).

## 왜 위키인가 (조회 근거, 2026-07-28)

**대사는 원본에 전량 남아 있는데 "목차"만 없다.**
- 대사: `DV2/string/stringsData_KR.xml` 의 `ScenarioTalk<회차>_<n>` → `data/scenario.json`
  (`build_scenario.py`, 142편 5,029줄).
- 회차 **제목**: 같은 XML 전수 검색에서 **0건**. `<Scenario*>` 로 시작하는 키는
  `ScenarioTalk` / `ScenarioReward{Name,Noti,Title}` 뿐이다. 제목·챕터·해금조건은
  `ScenarioScript`(서버 JSON `ResponseScriptJson`) 소유 → 유실.
- ⇒ 위키가 유일한 출처다. 회차 번호가 `ScenarioTalk<N>` 의 N 과 **일치**하는 것을 교차확인했다:
  위키 35화 "결계의 저편" ↔ `ScenarioTalk35_5` = "- 결계의 저편... -",
  레퍼런스 스크린샷(`docs/ref/orig_image/story_mission/`)의 상단 배너도 "35화 결계의 저편".

## 원작 UI 문자열(이식 시 그대로 쓴다)

| 키 | 값 |
|---|---|
| `MissionMsg1` | `%1$d화` |
| `MissionMsg2` | `개방조건: 드래곤 %1$d레벨` |
| `QuestTitleSub` | `서브미션 : %s` |
| `ScenarioTitleNum` | `Chapter %1$d.` |

## 해금 레벨 — 관측 2점 + 레벨캡 일치

레퍼런스 스크린샷 2장이 앵커다: **1화 = 드래곤 1레벨**, **35화 = 드래곤 45레벨**.
그런데 `data/level_curve.json` 의 `cap` 이 **정확히 45** 다(각성 시 50).
⇒ 레벨 게이트는 35화에서 캡에 닿아 끝난다고 보는 것이 자연스럽다.

  · 1~35화  : `level = round(1 + (n-1) × 44/34)` — 두 앵커를 지나는 직선
  · 36화~   : 레벨 조건 없음(캡 도달) → **직전 회차 관람 여부**로 순차 해금

두 앵커 사이 보간과 36화 이후 규칙은 **ASSUMPTION** 이다(원작 값은 서버 유실).
`data/story.json` 의 `_unlock` 블록 한 곳만 고치면 전체가 바뀌는 튜닝 노브로 뒀다.

    python scripts/tools/build_story_index.py          # data/story.json 생성
    python scripts/tools/build_story_index.py --dry    # 출력만
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PDF = REPO / "docs" / "ref" / "orig_image" / "story_mission" / "드래곤빌리지2_스토리 - 나무위키.pdf"
OUT = REPO / "data" / "story.json"

# 관측 앵커(레퍼런스 스크린샷) + 레벨캡
ANCHOR_EP, ANCHOR_LV = 35, 45
LEVEL_CAP = 45


def unlock_level(no: int) -> int:
    """1~35화는 관측 두 점을 지나는 직선, 그 뒤는 0(레벨 조건 없음)."""
    if no >= ANCHOR_EP:
        return LEVEL_CAP if no == ANCHOR_EP else 0
    return max(1, min(LEVEL_CAP, round(1 + (no - 1) * (ANCHOR_LV - 1) / (ANCHOR_EP - 1))))


# 위키 오타 교정 — **레퍼런스 스크린샷으로 확인된 것만** 고친다.
TYPO = {
    1: "희망의 숲 이야기",   # 위키 "희망의 숲 야야기" — docs/ref/orig_image/story_mission/ 배너가 "이야기"
}


def pdf_text() -> str:
    try:
        import fitz  # PyMuPDF
    except ImportError:
        sys.exit("pymupdf 가 필요하다:  pip install pymupdf")
    doc = fitz.open(PDF)
    return "\n".join(p.get_text() for p in doc)


def parse(text: str):
    """본문을 순서대로 훑으며 챕터 헤더 / 회차 / 서브미션을 수집한다."""
    chapters: list[dict] = []
    episodes: list[dict] = []
    cur_ch = 0
    # 목차(문서 앞부분)에도 같은 헤더가 한 번 더 나온다 → 회차가 하나라도 나온 뒤의
    # 헤더만 본문으로 친다. 첫 챕터만 예외적으로 회차보다 먼저 나오므로 따로 받는다.
    seen_no: set[int] = set()
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"^\d+\.\s*Chapter(\d+)\s+(.+)$", line)
        if m:
            no, title = int(m.group(1)), m.group(2).strip()
            if not any(c["no"] == no for c in chapters):
                chapters.append({"no": no, "title": title})
            cur_ch = no
            continue
        m = re.match(r"^(\d+)화\s+(.+)$", line)
        if m:
            no, title = int(m.group(1)), m.group(2).strip()
            if no in seen_no:
                continue
            seen_no.add(no)
            # 각주 표기 `[62]` 제거
            title = re.sub(r"\[\d+\]", "", title).strip()
            title = TYPO.get(no, title)
            episodes.append({"no": no, "title": title, "chapter": cur_ch})
            continue
        m = re.match(r"^서브미션\s*[:：]\s*(.+)$", line)
        if m and episodes:
            sub = re.sub(r"\[\d+\]", "", m.group(1)).strip()
            episodes[-1]["submission"] = sub
    return chapters, episodes


def main() -> None:
    dry = "--dry" in sys.argv
    chapters, episodes = parse(pdf_text())
    if not episodes:
        sys.exit("회차를 하나도 못 뽑았다 — PDF 레이아웃 확인 필요")

    scen = json.loads((REPO / "data" / "scenario.json").read_text(encoding="utf-8"))
    have = scen.get("scenarios", {})

    out_eps = {}
    for e in episodes:
        no = e["no"]
        rec = {
            "title": e["title"],
            "chapter": e["chapter"],
            "unlock_level": unlock_level(no),
        }
        if "submission" in e:
            rec["submission"] = e["submission"]
        if str(no) not in have:
            # 위키에는 있는데 stringsData 에 대사가 없는 회차(140~146).
            rec["no_lines"] = True
        out_eps[str(no)] = rec

    # 챕터별 회차 범위
    for c in chapters:
        nos = [e["no"] for e in episodes if e["chapter"] == c["no"]]
        if nos:
            c["from"], c["to"] = min(nos), max(nos)

    data = {
        "_re_basis": (
            "회차 제목·챕터·서브미션 = 나무위키 '드래곤빌리지2/스토리' "
            "(docs/ref/orig_image/story_mission/*.pdf, 사용자 제공). 원작 stringsData_KR.xml 에는 "
            "회차 제목이 없다(<Scenario*> 키는 ScenarioTalk / ScenarioReward* 뿐) — "
            "제목·챕터·해금조건은 ScenarioScript(서버 JSON)라 유실. "
            "회차 번호 = ScenarioTalk<N> 의 N (35화 '결계의 저편' ↔ ScenarioTalk35_5 로 교차확인)."
        ),
        "_unlock": {
            "rule": "1~35화 = round(1 + (n-1)*44/34), 36화~ = 0(레벨 조건 없음, 직전 회차 관람으로 해금)",
            "basis": (
                "ASSUMPTION. 관측 앵커 2점 = 레퍼런스 스크린샷(1화 '개방조건: 드래곤 1레벨' / "
                "35화 '드래곤 45레벨'). 45 는 data/level_curve.json 의 cap 과 일치한다 "
                "⇒ 레벨 게이트가 35화에서 끝난다고 본다. 사이 보간과 36화 이후 규칙은 밸런스 노브."
            ),
            "anchor_episode": ANCHOR_EP,
            "anchor_level": ANCHOR_LV,
            "level_cap": LEVEL_CAP,
        },
        "_strings": {
            "episode": "%d화",
            "unlock": "개방조건: 드래곤 %d레벨",
            "submission": "서브미션 : %s",
            "chapter": "Chapter %d.",
            "_src": "stringsData_KR.xml MissionMsg1 / MissionMsg2 / QuestTitleSub / ScenarioTitleNum",
        },
        "chapters": chapters,
        "episodes": out_eps,
    }
    print(f"챕터 {len(chapters)} / 회차 {len(out_eps)} "
          f"(대사 없는 회차 {sum(1 for v in out_eps.values() if v.get('no_lines'))})")
    print(f"  서브미션 {sum(1 for v in out_eps.values() if 'submission' in v)}건")
    if dry:
        print(json.dumps(data, ensure_ascii=False, indent=1)[:1500])
        return
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  → {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
