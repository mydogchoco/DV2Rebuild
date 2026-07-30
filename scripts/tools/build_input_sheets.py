# -*- coding: utf-8 -*-
"""docs/input/sheets/*.csv 생성 — 사용자가 채우는 시트를 CSV(엑셀)로 뽑는다.

사용자가 md 표보다 csv/xlsx 기입을 선호해서(2026-07-28), INDEX 의 ⏳ 시트를 CSV 로 재구성한다.
데이터로 뽑을 수 있는 열(스테이지·몬스터 배정·시나리오 대사·NPC 목록)은 **미리 채워** 넣고,
유실된 값(원칙2)만 빈 칸으로 남긴다.

    python scripts/tools/build_input_sheets.py            # 전부 재생성
    python scripts/tools/build_input_sheets.py --only scenario_cast

⚠️ 이미 사용자가 채운 CSV 는 덮어쓰지 않는다(--force 로만 덮어씀).
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data"
OUT = ROOT / "docs" / "input" / "sheets"
REVIEW = ROOT / "docs" / "input" / "review"

# 엑셀이 한글을 깨지 않게 BOM 포함 UTF-8.
ENC = "utf-8-sig"


def load(name: str) -> dict:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def write(fname: str, header: list[str], rows: list[list], force: bool) -> str:
    path = OUT / fname
    if path.exists() and not force:
        # 사용자가 채운 값을 지우지 않는다.
        prev = list(csv.reader(path.open(encoding=ENC)))
        filled = sum(1 for r in prev[1:] if any(c.strip() for c in r[len(header) - 1:]))
        return f"skip  {fname} (이미 있음, 채워진 흔적 {filled}행 — 덮어쓰려면 --force)"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding=ENC, newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return f"write {fname:28s} {len(rows):5d}행"


# ---------------------------------------------------------------- 시트별 빌더


def sheet_stage_intro() -> tuple[str, list[str], list[list]]:
    """던전 진입 2번째 줄 (lost_text_sheet §1) — 채워진 것도 보여 주고 빈 것만 받는다."""
    stages = load("stages.json")["stages"]
    rows = []
    for sid, st in sorted(stages.items(), key=lambda kv: int(kv[0])):
        rows.append([
            sid, st.get("name", ""), st.get("region", ""),
            st.get("intro", ""), "",
        ])
    return ("stage_intro.csv",
            ["stage_id", "던전명", "지역", "현재_2번째줄(있으면 반영됨)", "고칠_2번째줄(비면 현재값 유지)"],
            rows)


def sheet_monster_mapping() -> tuple[str, list[str], list[list]]:
    """스테이지별 몬스터 배정 점검 (mapping_sheet.md 를 파싱해 CSV 로)."""
    md = (REVIEW / "mapping_sheet.md").read_text(encoding="utf-8")
    head = re.compile(r"^##\s+stage\s+(\d+)\s+—\s+(.+?)\s+\((\w+)\)\s*(_[va])?\s*(.*)$")
    item = re.compile(r"^-\s+#\s*(\d+)\s+(.+?)\s*$")
    rows, cur = [], None
    for line in md.splitlines():
        m = head.match(line)
        if m:
            cur = m.groups()
            continue
        m = item.match(line)
        if m and cur:
            no, name = m.group(1), m.group(2)
            tag = ""
            for t in ("[보스]", "[스토리 전용]", "[스토리전용]"):
                if t in name:
                    tag = t.strip("[]")
                    name = name.replace(t, "").strip()
            rows.append([cur[0], cur[1], cur[2], cur[3] or "", no, name, tag, "", "", ""])
    return ("monster_mapping.csv",
            ["stage", "던전명", "지역", "확정도(_v확정/_a추정)", "몬스터번호", "몬스터이름", "구분",
             "맞나요(O/X)", "틀리면_올바른_몬스터번호", "비고"],
            rows)


def sheet_scenario_cast() -> tuple[str, list[str], list[list]]:
    """시나리오 대사 줄별 화자 (scenario_sheet §3) — 5,029줄 전량."""
    sc = load("scenario.json")["scenarios"]
    rows = []
    for no in sorted(sc, key=lambda x: int(x)):
        for pi, part in enumerate(sc[no]["parts"]):
            for ln in part["lines"]:
                rows.append([no, pi, ln["k"], ln["text"], "", ""])
    return ("scenario_cast.csv",
            ["시나리오번호", "파트인덱스", "대사번호", "대사", "화자(npc키 — npc_keys.csv 참고)", "비고"],
            rows)


def sheet_npc_keys() -> tuple[str, list[str], list[list]]:
    """화자 칸에 쓸 수 있는 npc 키 목록 (읽기 전용 참고 시트)."""
    names = load("scenario.json")["npc_names"]
    npc_dir = ROOT / "DV2" / "480" / "npc"
    have = {p.name.split(".")[0] for p in npc_dir.glob("*")} if npc_dir.exists() else set()
    rows = [[k, v, "O" if k in have else ""] for k, v in sorted(names.items())]
    return ("npc_keys.csv", ["npc키", "표시이름", "초상보유(O)"], rows)


def sheet_scenario_trigger() -> tuple[str, list[str], list[list]]:
    """시나리오 발동 조건 (scenario_sheet §4)."""
    sc = load("scenario.json")["scenarios"]
    rows = []
    for no in sorted(sc, key=lambda x: int(x)):
        s = sc[no]
        for pi, part in enumerate(s["parts"]):
            first = part["lines"][0]["text"] if part["lines"] else ""
            rows.append([no, pi, len(part["lines"]), len(s.get("illust", [])),
                         first[:60], "", "", ""])
    return ("scenario_trigger.csv",
            ["시나리오번호", "파트인덱스", "대사줄수", "삽화수", "첫대사",
             "언제_발동?(예: 희망의숲 3회 클리어 후 동굴 진입)", "어디서(동굴/탐험/마을/월드맵)", "비고"],
            rows)


def sheet_npc_lines() -> tuple[str, list[str], list[list]]:
    """NPC 대사 (lost_text_sheet §2). 원작 문자열에서 복원된 것은 미리 채워 보여 준다."""
    nl = load("npc_lines.json")["npcs"]
    npc_dir = ROOT / "DV2" / "480" / "npc"
    folders = sorted({p.name.split(".")[0] for p in npc_dir.glob("*")}) if npc_dir.exists() else []
    names = load("scenario.json")["npc_names"]
    rows = []
    for key in folders:
        if key in ("icon", "emoticon"):
            continue  # 초상 파츠가 아니라 아이콘 아틀라스
        info = nl.get(key)
        disp = (info or {}).get("name") or names.get(key, "")
        if info and info.get("lines"):
            for line in info["lines"]:
                rows.append([key, disp, "원작복원", "", line, ""])
        else:
            for _ in range(3):
                rows.append([key, disp, "유실", "", "", ""])
    return ("npc_lines.csv",
            ["npc키", "이름", "상태", "등장상황(마을/상점/탐험조우 등)", "대사", "비고"],
            rows)


def sheet_box_loot() -> tuple[str, list[str], list[list]]:
    """상자 내용물 (box_contents_mapping.md)."""
    md = (ROOT / "docs" / "input" / "box_contents_mapping.md").read_text(encoding="utf-8")
    boxes = []
    for line in md.splitlines():
        m = re.match(r"^\|\s*`([a-z_]+)`\s*\|\s*([^|]+?)\s*\|", line)
        if m:
            boxes.append((m.group(1), m.group(2)))
    rows = []
    for key, name in boxes:
        for _ in range(3):
            rows.append([key, name, "", "", "", "", ""])
    return ("box_loot.csv",
            ["box키", "상자이름", "지급방식(확정/랜덤)", "나오는아이템(이름 또는 items.json 키)",
             "개수", "확률%(랜덤일 때, 모르면 비움)", "비고"],
            rows)


def sheet_combine_item() -> tuple[str, list[str], list[list]]:
    """아이템 조합 레시피 (combine_item_sheet.md)."""
    rows = [["", "", "", "", "", "", "gold", ""] for _ in range(20)]
    return ("combine_item.csv",
            ["결과아이템(target)", "재료1", "재료1개수", "재료2", "재료2개수",
             "비용", "비용종류(gold/dia)", "비고"],
            rows)


def sheet_skill_awaken() -> tuple[str, list[str], list[list]]:
    """각성 스킬 **목록**만 (skill_awaken_sheet 표A).

    배정(어느 드래곤이 어느 각성스킬)은 `dragons.csv` 의 `각성스킬id` 열에 **이 표의 id 숫자**만
    적는 방식으로 분리한다(2026-07-28 사용자 결정) — 같은 각성스킬을 여러 드래곤이 공유하므로
    이름을 390번 반복해 적지 않게 하기 위함.

    **스킬 id 와 아이콘 id 는 다른 축이다**(2026-07-29 사용자 확인 — 서로 다른 각성스킬이 같은
    아이콘을 쓰는 경우가 있다). 그래서 `id` = 각성스킬 번호(우리 번호), `아이콘id` = 1~18
    (`skill/evolution/<n>.png`, `skill_awaken_icons.png` 격자 번호) 로 열을 나눈다.

    아이콘 경로 근거: `AwakenPopup.c` :288 `Dragon::getAwakenSkill` → :290
    `CCString::createWithFormat("skill/evolution/%d.png", …)` (AwakenDragonLayer 도 같은 포맷) ·
    `DV2/480/skill/evolution.img_plist` 에 프레임 1~18.
    """
    keys = list(range(1, 41))
    # 이미 채운 값은 id 기준으로 이어받는다(--force 로 다시 뽑아도 입력이 날아가지 않게).
    prev: dict[str, list[str]] = {}
    path = OUT / "skill_awaken.csv"
    if path.exists():
        for r in list(csv.reader(path.open(encoding=ENC)))[1:]:
            if r and r[0].strip():
                prev[r[0].strip()] = r
    def pad(r: list[str]) -> list[str]:
        return (list(r[1:]) + [""] * 4)[:4]

    rows = [[i, *pad(prev.get(str(i), []))] for i in keys]
    # 40 을 넘겨 적은 행이 있으면 버리지 않고 뒤에 남긴다.
    for k, r in sorted(prev.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
        if k.isdigit() and int(k) not in keys and any(c.strip() for c in r[1:]):
            rows.append([k, *pad(r)])
    # 열 구성은 사용자가 시트에서 확정한 것을 따른다(2026-07-29).
    return ("skill_awaken.csv",
            ["id(우리 번호 — dragons.csv 의 각성스킬id 에 이 숫자를 적는다)",
             "각성스킬 이름", "아이콘 id", "설명", "비고"],
            rows)


# ------------------------------------------------------------ 각성스킬 아이콘 몽타주

ICON_DIR = "skill_evolution"          # assets/converted/<여기>  (원본 DV2/480/skill/evolution)
ICON_MONTAGE = OUT / "skill_awaken_icons.png"


def icon_numbers() -> list[int]:
    """변환된 각성스킬 아이콘 번호 목록."""
    d = ROOT / "assets" / "converted" / ICON_DIR
    out = []
    for p in d.glob("skill_evolution_*.tres"):
        try:
            out.append(int(p.stem.rsplit("_", 1)[1]))
        except ValueError:
            pass
    return sorted(out)


def build_icon_montage(force: bool) -> str:
    """`skill_awaken.csv` 의 id 옆에 놓고 볼 아이콘 격자를 그린다 (items_01.png 와 같은 방식).

    프레임 로딩·PMA 합성은 `build_item_sheet.py` 의 헬퍼를 그대로 쓴다(중복 구현 금지).
    """
    if ICON_MONTAGE.exists() and not force:
        return f"skip  {ICON_MONTAGE.name} (이미 있음 — 덮어쓰려면 --force)"
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import build_item_sheet as bis          # load_frames / crop_icon / font / BG / GRID
    from PIL import Image, ImageDraw

    bis.ICON_BOX = 150                      # 원본 75px → 아래에서 2배로 키운다
    frames = bis.load_frames(ICON_DIR)
    nums = icon_numbers()
    if not nums:
        return "skip  skill_awaken_icons.png (변환 아이콘 없음 — cocos_export.py 부터)"

    cols, cell_w, cell_h, margin, hdr = 6, 190, 215, 24, 54
    rows_n = (len(nums) + cols - 1) // cols
    page = Image.new("RGB", (margin * 2 + cell_w * cols,
                             margin * 2 + hdr + cell_h * rows_n), bis.BG)
    draw = ImageDraw.Draw(page)
    f_hdr, f_no, f_path = bis.font(30, True), bis.font(34, True), bis.font(15)

    draw.text((margin, margin), "각성스킬 아이콘 — #번호 = skill_awaken.csv 의 id (원작 no)",
              font=f_hdr, fill=(235, 235, 235))
    for i, n in enumerate(nums):
        x = margin + (i % cols) * cell_w
        y = margin + hdr + (i // cols) * cell_h
        draw.rectangle([x, y, x + cell_w - 8, y + cell_h - 8], outline=bis.GRID)
        png, rect = frames[f"skill_evolution_{n}"]
        ic = bis.crop_icon(png, rect)
        ic = ic.resize((ic.width * 2, ic.height * 2), Image.LANCZOS)
        page.paste(ic, (x + (cell_w - 8 - ic.width) // 2, y + 10))
        draw.text((x + 12, y + cell_h - 62), f"#{n}", font=f_no, fill=(255, 214, 92))
        draw.text((x + 12, y + cell_h - 26), f"skill/evolution/{n}.png",
                  font=f_path, fill=(150, 150, 150))

    ICON_MONTAGE.parent.mkdir(parents=True, exist_ok=True)
    page.save(ICON_MONTAGE)
    return f"write {ICON_MONTAGE.name:28s} 아이콘 {len(nums)}종 ({cols}×{rows_n})"


def sheet_artifact_by_dungeon() -> tuple[str, list[str], list[list]]:
    """카데스의 공간 — 던전별 아티팩트 종류 (equipment_sheet §2-1)."""
    stages = load("stages.json")["stages"]
    rows = []
    for sid, st in sorted(stages.items(), key=lambda kv: int(kv[0])):
        if st.get("region") == "yutakan":
            rows.append([sid, st.get("name", ""), "", ""])
    return ("artifact_by_dungeon.csv",
            ["stage_id", "유타칸 던전", "나오는 아티팩트(이그니스/루멘/마리스/옵스큐럼/벤투스/테라)", "비고"],
            rows)


def sheet_open_questions() -> tuple[str, list[str], list[list]]:
    """각 시트에 흩어져 있던 ⚠️ASSUMPTION·확인요청을 한 장으로."""
    q = [
        ["gem", "일반·혼성젬 강화 성공률", "100 − 5×티어 (최저 10%)", "ASSUMPTION",
         "build_gems.py SUCCESS", ""],
        ["gem", "소울젬 강화 성공률", "90 − 7×티어", "ASSUMPTION", "build_gems.py SUCCESS", ""],
        ["gem", "골드 뽑기 1회 가격", "5,000골드", "ASSUMPTION", "drops.json slot.price_gold", ""],
        ["skill", "스킬 슬롯 모양 일치 시 추가효과", "스킬 피해 +15%", "ASSUMPTION",
         "combat.json skill_slot_match.power_pct", ""],
        ["equipment", "카데스의 공간 모드 구현할까요?", "미구현(진입점 없음)", "결정 필요",
         "worldmap 진입 토글 + battle/adventure params.kades", ""],
        ["equipment", "부적 효과 해석", "행동불능 치유 확률(위키 효과표)", "위키 두 서술 충돌",
         "대안: 패배 시 부활 확률", ""],
        ["equipment", "피오드·발록 장비 획득처", "원정·길드 = 오프라인 CUT", "결정 필요",
         "솔로 레이드로 옮길지", ""],
        ["combat", "pure(방어관통) 해석", "고정 추가 피해(크리·속성 배수 없음)", "확인 요청",
         "combat.json", ""],
        ["combat", "cri_pow 해석", "크리 배수 × (1 + cri_pow/100)", "확인 요청", "combat.json", ""],
    ]
    return ("open_questions.csv",
            ["분류", "질문", "현재값/현재해석", "성격", "바뀌면 고칠 곳", "답(기입)"],
            q)


BUILDERS = {
    "stage_intro": sheet_stage_intro,
    "monster_mapping": sheet_monster_mapping,
    "scenario_cast": sheet_scenario_cast,
    "scenario_trigger": sheet_scenario_trigger,
    "npc_keys": sheet_npc_keys,
    "npc_lines": sheet_npc_lines,
    "box_loot": sheet_box_loot,
    "combine_item": sheet_combine_item,
    "skill_awaken": sheet_skill_awaken,
    "artifact_by_dungeon": sheet_artifact_by_dungeon,
    "open_questions": sheet_open_questions,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=sorted(BUILDERS) + ["skill_awaken_icons"])
    ap.add_argument("--force", action="store_true", help="이미 있는 CSV도 덮어쓴다")
    args = ap.parse_args()

    sys.stdout.reconfigure(encoding="utf-8")
    for name in (args.only or sorted(BUILDERS) + ["skill_awaken_icons"]):
        if name == "skill_awaken_icons":
            print(build_icon_montage(args.force))
            continue
        fname, header, rows = BUILDERS[name]()
        print(write(fname, header, rows, args.force))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
