# -*- coding: utf-8 -*-
"""docs/input/sheets/AdminStory/*.csv 생성 — 관리자 모드(UserDB.ADMIN) 스토리 개작 시트.

🟦 사용자 확정 2026-08-07: `IsAdmin == true` 일 때만 ① 스토리 스크립트의 **특정 파트 대사를
바꾸고** ② **주인공 독백에 오리지널 캐릭터 '선대군' 초상 + 대사별 표정**을 붙인다.
대사 개작과 표정 배정은 **사용자가 직접** 한다 → 이 도구는 그 작업판(회차별 CSV)만 뽑는다.

행의 출처(지어낸 값 0):
  · 대사 원문   `data/scenario.json` — 원작 `stringsData_KR.xml` 무손실 추출(build_scenario.py)
  · 화자·표정·연출 `data/scenario_flow.json` — 원작 클라 하드코딩 흐름 복원
                (`extract_scenario_flow.py` + `parse_scenario_flow.py` + `extract_switch_flow.py`)
  · 회차 제목·챕터 `data/story.json`
행 순서는 **`scripts/ui/story.gd` 의 재생 순서를 그대로 시뮬레이션**해서 만든다
(`_play_flow` → `setTalk` 는 키(`ScenarioTalk<회차>_<줄>`)로 줄을 집고, 나머지 대사 함수는
순서대로 한 줄씩 소비한다). 그래서 시트의 행 순서 = 게임에서 실제로 보이는 순서다.

    python scripts/tools/build_admin_story.py                 # 전부 생성
    python scripts/tools/build_admin_story.py --only 102      # 한 회차만
    python scripts/tools/build_admin_story.py --force         # 채워진 시트까지 덮어쓰기

⚠️ **사용자가 채운 시트는 덮어쓰지 않는다** — 관리자 열(관리자대사/표정/위치/이름표/비고)에
값이 하나라도 있으면 건너뛴다(`--force` 로만 덮어씀).
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data"
OUT = ROOT / "docs" / "input" / "sheets" / "AdminStory"

# 엑셀이 한글을 깨지 않게 BOM 포함 UTF-8([[dv2-user-prefers-csv-sheets]]).
ENC = "utf-8-sig"

# 대사를 내는 원작 함수 4종 — `story.gd` TALK_OPS 와 같은 목록(같은 순서로 줄을 소비한다).
TALK_OPS = ("setNpcTalk", "setUserTalk", "setTalker", "setTalk")

# `story.gd::_line_by_key` 와 **같은 정규식**. 키가 이 꼴이 아니면 순서대로 폴백한다.
KEY_RE = re.compile(r"^ScenarioTalk\d+(?:_\d+)?_(\d+)$")

HEADER = [
    "회차", "스텝", "종류", "원작함수", "파트", "줄번호",
    "화자키", "화자", "독백",
    "원본대사",
    "관리자대사", "표정(1~6)", "위치(1좌/2우/3중)", "이름표", "비고",
]
# 사용자가 채우는 열(= 채워졌는지 검사할 열)의 시작 인덱스.
ADMIN_COL0 = HEADER.index("관리자대사")


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def esc(text: str) -> str:
    r"""줄바꿈을 `\n` 두 글자로. 원문에 역슬래시가 0건이라 되돌리기가 모호하지 않다(전수 확인)."""
    return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", r"\n")


# ---------------------------------------------------------------- 연출 행 요약


def stage_note(op: str, o: dict, flow: dict) -> str:
    """대사가 아닌 스텝 한 줄 요약. 표정을 배정할 때 장면 맥락이 보이게 하는 용도다."""
    bgm = flow.get("bgm", {})
    bgs = flow.get("backgrounds", {})

    def rest(skip: tuple[str, ...]) -> str:
        kv = [f"{k}={v}" for k, v in o.items() if k != "op" and k not in skip and v is not None]
        return " · ".join(kv)

    if op == "playBackground":
        return f"BGM · {o.get('track', '')}"
    if op == "playBackGroundFieldMusic":
        f = str(o.get("field", ""))
        return f"BGM(필드 {f}) · {bgm.get(f, '(무음)')}"
    if op == "playEffect":
        return f"효과음 · {o.get('track', '')}"
    if op in ("changeBackGround", "changeBackGroundPass"):
        b = str(o.get("bg", ""))
        paths = bgs.get(b, [])
        tail = " 유지/숨김" if not paths else " " + paths[0]
        return f"배경 → {b}{tail}" + ("(전환없음)" if op.endswith("Pass") else "")
    if op == "showCut":
        return f"컷 · {o.get('frame', '')}"
    if op == "drawIllust":
        return f"일러스트 {o.get('illust', '')} (kind {o.get('kind', '')})"
    if op == "removeIllust":
        return "일러스트 제거"
    if op == "setOutTalker":
        return f"NPC 퇴장 · {rest(())}"
    if op == "scenarioBattle":
        return f"전투 · {rest(())}"
    if op == "setSubQuest":
        return f"서브퀘스트 · {rest(())}"
    if op == "setTitleScenario":
        return "회차 제목 표시"
    if op == "initScenarioTalk":
        return "대사창 초기화"
    if op == "scenarioBlackLayer":
        return f"암전 · {rest(())}"
    if op == "showScenarioItem":
        return f"아이템 연출 · {rest(())}"
    if op == "showMonster" or op == "deleteMonster":
        return f"몬스터 {'등장' if op == 'showMonster' else '퇴장'} · {rest(())}"
    r = rest(())
    return f"{op}" + (f" · {r}" if r else "")


# ---------------------------------------------------------------- 회차 한 장


def build_rows(no: str, scen: dict, flow_all: dict, npc_kr: dict) -> list[list]:
    """회차 하나의 시트 행. `story.gd` 의 재생 순서를 그대로 따라간다."""
    parts = scen.get("parts", [])
    # 원작 스텝은 회차의 파트를 순서대로 관통한다(story.gd:128 과 같은 평탄화).
    lines: list[tuple[int, int, str]] = []
    for pi, p in enumerate(parts):
        for l in p.get("lines", []):
            lines.append((pi, int(l.get("k", 0)), str(l.get("text", ""))))

    flows = flow_all.get("flows", {})
    flow = flows.get(no, [])
    num_names = flow_all.get("npc_names", {})       # 스텝의 NPC **번호** → 폴더
    rows: list[list] = []
    used: set[int] = set()

    def kr(folder: str) -> str:
        return npc_kr.get(folder, folder) if folder else ""

    def emit(step, kind, op, i, folder, mono, text_override=None):
        part = lines[i][0] if i is not None else ""
        k = lines[i][1] if i is not None else ""
        text = text_override if text_override is not None else (esc(lines[i][2]) if i is not None else "")
        rows.append([no, step, kind, op, part, k, folder, kr(folder), mono, text,
                     "", "", "", "", ""])

    if flow:
        idx = 0
        for step, o in enumerate(flow):
            op = str(o.get("op", ""))
            if op not in TALK_OPS:
                emit(step, "연출", op, None, "", "", stage_note(op, o, flow_all))
                continue
            # ── 화자 (story.gd::_play_flow 와 같은 규칙)
            folder = ""
            if op in ("setTalk", "setTalker"):
                v = o.get("npc_name")
                folder = v if isinstance(v, str) else ""
            elif op == "setNpcTalk":
                folder = str(num_names.get(str(o.get("npc", 0)), ""))
            # ── 줄 집기
            i = None
            if op == "setTalk":
                m = KEY_RE.match(str(o.get("key", "")))
                if m:
                    want = int(m.group(1))
                    for j, (_, k, _t) in enumerate(lines):
                        if k == want:
                            i, idx = j, j + 1
                            break
            if i is None and idx < len(lines):       # _next_line
                i, idx = idx, idx + 1
            if i is not None:
                used.add(i)
            # ── 독백 구분: 이름칸이 비는 행이 곧 주인공 독백/지문 자리다
            #    (원작 `ScenarioLayer::setTalk` 는 끝에서 화자 멤버를 비운다 — story.gd:368 주석)
            mono = "" if folder else ("주인공" if op == "setUserTalk" else "무명")
            emit(step, "대사", op, i, folder, mono)
    else:
        # 흐름 미복원 회차(102~139화) — story.gd 는 파트 0 을 화자 없이 순서대로 낸다.
        for i, (pi, _k, _t) in enumerate(lines):
            if pi != 0:
                continue
            used.add(i)
            emit("", "대사", "", i, "", "순차")

    # 재생에서 소비되지 않은 줄 — 빠뜨리지 않게 뒤에 붙인다(게임에는 안 나온다).
    for i in range(len(lines)):
        if i not in used:
            emit("", "미사용", "", i, "", "")
    return rows


# ---------------------------------------------------------------- 쓰기


def filled(path: Path) -> int:
    """이미 채워진 관리자 열이 있는 행 수(있으면 덮어쓰지 않는다)."""
    try:
        prev = list(csv.reader(path.open(encoding=ENC)))
    except OSError:
        return 0
    return sum(1 for r in prev[1:] if any(c.strip() for c in r[ADMIN_COL0:]))


def write_csv(path: Path, header: list[str], rows: list[list], force: bool) -> str:
    if path.exists() and not force:
        n = filled(path)
        if n:
            return f"skip  {path.name} (채워진 흔적 {n}행 — 덮어쓰려면 --force)"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding=ENC, newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return f"write {path.name:14s} {len(rows):5d}행"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="회차 번호 하나만")
    ap.add_argument("--force", action="store_true", help="채워진 시트까지 덮어쓰기")
    args = ap.parse_args()

    scenario = load("scenario.json")
    flow_all = load("scenario_flow.json")
    story = load("story.json")
    npc_kr = scenario.get("npc_names", {})
    eps = story.get("episodes", {})

    index_rows: list[list] = []
    for no in sorted(scenario.get("scenarios", {}), key=lambda x: int(x)):
        if args.only and no != args.only:
            continue
        scen = scenario["scenarios"][no]
        # 본문이 한 줄도 없으면 원작에도 열람 대상이 아니다(StoryQuest.implemented_with).
        if not any(p.get("lines") for p in scen.get("parts", [])):
            continue
        rows = build_rows(no, scen, flow_all, npc_kr)
        talk = sum(1 for r in rows if r[2] == "대사")
        mono = sum(1 for r in rows if r[2] == "대사" and r[8])
        stage = sum(1 for r in rows if r[2] == "연출")
        unused = sum(1 for r in rows if r[2] == "미사용")
        ep = eps.get(no, {})
        print(write_csv(OUT / f"ep_{int(no):03d}.csv", HEADER, rows, args.force))
        index_rows.append([
            no, ep.get("title", ""), ep.get("chapter", ""), f"ep_{int(no):03d}.csv",
            talk, mono, stage, unused,
            "O" if flow_all.get("flows", {}).get(no) else "X", "",
        ])

    if not args.only:
        print(write_csv(OUT / "_INDEX.csv", [
            "회차", "제목", "챕터", "파일", "대사행", "독백행", "연출행", "미사용행",
            "흐름복원", "진행(사용자 기입)",
        ], index_rows, True))
    tot = sum(r[4] for r in index_rows)
    mono = sum(r[5] for r in index_rows)
    print(f"\n회차 {len(index_rows)} · 대사 {tot}행 · 그중 독백/지문 {mono}행")


if __name__ == "__main__":
    main()
