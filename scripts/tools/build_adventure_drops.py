# -*- coding: utf-8 -*-
"""탐험지역별 **특수 드랍** 시트 ↔ data/stages.json `drops` 왕복 도구.

사용자 요청(2026-07-31):
  "각 탐험지역 전용 드랍 아이템 풀을 적어놓을 csv 표 만들어줘. 탐험에서 드래곤 알, 일반젬,
   먹이, 각 탐험지역에 맞는 속성 정기, 그리고 csv표에서 지정한 특수 드랍 아이템 외의
   아이템들은 드랍되지 않도록 구현해."
  "드랍 풀을 일반/영웅, 유타칸의 경우 (밤)까지 나눠야 해."

## 왜 CSV 인가
사용자는 md 표보다 CSV 기입을 선호한다(2026-07-28 확정, `build_input_sheets.py` 와 같은 규약).
BOM(`utf-8-sig`)으로 쓰므로 엑셀에서 바로 열린다.

## 무엇이 유실이고 무엇이 아닌가
탐험 드랍표는 **서버 소유였다** — 원작 `AdventureScene::initJsonReward` 가 파싱하던 키는
`reward`/`cnt`/`rarity`/`option`/`belong` 뿐이고 "무엇이 얼마나 나오는가"를 정하는 코드가
클라에 없다(포팅 카드 `docs/ref/porting/AdventureEventFlow.md` §6). 따라서 이 시트는
**사용자가 채우는 자작 데이터**다(CLAUDE.md 원칙 6 — 출처를 지어내지 않고 사용자 확정으로 둔다).

## 난이도 축 (사용자 확정 2026-07-31)
드랍 풀은 난이도마다 **따로** 둔다. `stages.json` 의 `drops` 가 `{난이도: [항목]}` 이 된다.

    normal : 일반
    hero   : 영웅
    kades  : 카데스의 공간(+600 변형). **행을 미리 만들지 않는다** — 이곳의 주 목적인
             아티팩트는 별도 규칙(`data/drops.json` `kades`)이라 표가 없어도 된다.
             직접 적고 싶으면 difficulty=kades 로 행을 추가하면 그대로 읽는다.

## 화이트리스트 (이 표가 다루지 않는 것)
탐험에서 나오는 것은 다음뿐이다. 앞의 넷은 **표 없이 규칙으로** 나오고, 이 시트는 **다섯째**만 담는다.
  1. 드래곤 알      — 그 탐험지 팝업 등재 드래곤(`stages.json` `dragons`)   → Drops.roll_egg
  2. 일반 젬        — `data/drops.json` `exploration.gem_pool`              → Drops.roll_exploration
  3. 먹이           — 그 지역 속성에 맞는 것만                              → Drops.roll_food
  4. 속성 정기      — 그 지역 속성의 `ele_*`(currency/essence)              → Drops.roll_essence
  5. **특수 드랍**  — 이 시트                                               → Drops.roll_special
  (+ 장비/아티팩트는 전 지역 공통 유지 — 사용자 확정 2026-07-31)

사용:
    python scripts/tools/build_adventure_drops.py --export   # stages.json → CSV (초기 생성/갱신)
    python scripts/tools/build_adventure_drops.py --import   # CSV → stages.json `drops`

⚠️ `--import` 는 CSV 가 비었으면 **거부**한다 — 실수로 기존 드랍표(우노 아니마/보네르)를
   날리지 않게. 어떤 난이도를 통째로 비우려면 그 행의 item_key 를 비운 채 남겨 둔다.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAGES = ROOT / "data" / "stages.json"
ITEMS = ROOT / "data" / "items.json"
SHEET = ROOT / "docs" / "input" / "sheets" / "adventure_drop_pool.csv"

# 사용자가 채우는 열 / 참고용(자동 생성) 열
# 한 행 = 후보 하나. `kind` 로 갈린다.
#   item          아이템 (target = items.json 키)
#   skill_scroll  스킬 스크롤 (target = 스킬 id, `levels`+`level_weights` 로 레벨 결정)
COLS = [
    "stage_id", "stage_name", "region", "element", "difficulty",  # ← 참고(자동). 고치지 말 것
    "kind", "target", "target_name",                              # ← 채우는 칸
    "levels", "level_weights", "chance", "min", "max", "boss_only",
    "note",
]

# ⛔ `night` 는 **없다**(사용자 확정 2026-07-31): 밤은 진입당 조우 1회로 끝나므로
#    지역 단위 필드 보상이 의미가 없다. 밤의 획득은 **몬스터별 드랍**이 담당한다
#    (docs/input/sheets/monster_drop_pool.csv ↔ build_monster_drops.py).
MODES = ("normal", "hero", "kades")
PREGEN = ("normal", "hero")              # 행을 미리 만들어 두는 난이도


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def item_names() -> dict:
    d = load(ITEMS)
    it = d.get("items", d)
    return {k: (v.get("name") or "") for k, v in it.items() if isinstance(v, dict)}


def as_tables(drops) -> dict:
    """`drops` 를 {난이도: [항목]} 으로 읽는다.

    구판은 **평평한 배열**이었고 난이도 구분 없이 `hero_min/hero_max` 로 수량만 갈랐다.
    그 형태를 만나면 normal/hero 두 표로 풀어 준다 — 우노 아니마·보네르(위키 확정
    일반 5~10 / 영웅 15~20)를 잃지 않기 위해서다.
    """
    if not drops:
        return {}
    if isinstance(drops, dict):
        return {k: v for k, v in drops.items() if not str(k).startswith("_")}
    out = {"normal": [], "hero": []}
    for d in drops:
        base = {"item": d.get("item", ""), "min": d.get("min", 1),
                "max": d.get("max", 1), "rate": d.get("rate", 100)}
        if d.get("note"):
            base["note"] = d["note"]
        out["normal"].append(dict(base))
        h = dict(base)
        if "hero_min" in d:
            h["min"] = d["hero_min"]
            h["max"] = d.get("hero_max", d["hero_min"])
        out["hero"].append(h)
    return out


def do_export(force: bool) -> int:
    if SHEET.exists() and not force:
        print("[skip] exists; use --force to overwrite: %s" % SHEET)
        return 0
    stages = load(STAGES)["stages"]
    names = item_names()
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for sid in sorted(stages, key=lambda x: int(x) if str(x).isdigit() else 9999):
        st = stages[sid]
        base = {
            "stage_id": sid,
            "stage_name": st.get("name") or "",
            "region": st.get("region") or "",
            "element": st.get("element") or "",
        }
        tables = as_tables(st.get("drops"))
        modes = list(PREGEN) + [m for m in tables if m not in PREGEN]
        for mode in modes:
            lst = tables.get(mode) or []
            if not lst:
                rows.append({**base, "difficulty": mode, "kind": "", "target": "",
                             "target_name": "", "levels": "", "level_weights": "",
                             "chance": "", "min": "", "max": "", "boss_only": "", "note": ""})
                continue
            for d in lst:
                k = d.get("kind", "item")
                if k == "skill_scroll":
                    tgt, tn = d.get("skill", ""), d.get("skill_name", "")
                else:
                    tgt = d.get("item", d.get("key", ""))
                    tn = names.get(tgt, "")
                rows.append({**base, "difficulty": mode, "kind": k,
                             "target": tgt, "target_name": tn,
                             "levels": ":".join(str(x) for x in (d.get("levels") or [])),
                             "level_weights": ":".join(str(x) for x in (d.get("level_weights") or [])),
                             "chance": d.get("chance", d.get("rate", "")),
                             "min": d.get("min", ""), "max": d.get("max", ""),
                             "boss_only": 1 if d.get("boss_only") else "",
                             "note": d.get("note", "")})
    with io.open(SHEET, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        w.writerows(rows)
    # ⚠️ 콘솔이 cp949 라 em-dash(—)·중점(·) 같은 글자가 UnicodeEncodeError 를 낸다.
    #    안내문은 ASCII 로만 쓴다(파일 내용은 UTF-8 이라 무관).
    print("[export] %d rows -> %s" % (len(rows), SHEET))
    print("  - stage_id/stage_name/region/element/difficulty are auto columns (do not edit)")
    print("  - fill one row per (stage_id, difficulty); add rows for multiple items")
    print("  - rate = 1..100(%), min/max = count")
    return 0


def do_import() -> int:
    if not SHEET.exists():
        print("[error] sheet not found (run --export first): %s" % SHEET)
        return 1
    with io.open(SHEET, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print("[error] sheet is empty; aborting so existing drops are not wiped")
        return 1

    doc = load(STAGES)
    stages = doc["stages"]
    per: dict = {}
    bad = 0
    names = item_names()
    for i, r in enumerate(rows, start=2):
        sid = (r.get("stage_id") or "").strip()
        mode = ((r.get("difficulty") or "").strip() or "normal")
        if not sid:
            continue
        if sid not in stages:
            print(f"  [warn] {SHEET.name}:{i} 모르는 stage_id={sid}")
            bad += 1
            continue
        if mode not in MODES:
            print(f"  [warn] {SHEET.name}:{i} 모르는 difficulty={mode} (허용: {'/'.join(MODES)})")
            bad += 1
            continue
        per.setdefault(sid, {}).setdefault(mode, [])
        kind = (r.get("kind") or "").strip()
        if not kind:
            continue
        tgt = (r.get("target") or "").strip()

        def num(col, dflt=None, f=False):
            v = (r.get(col) or "").strip()
            if v == "":
                return dflt
            try:
                return float(v) if f else int(float(v))
            except ValueError:
                print(f"  [warn] {SHEET.name}:{i} {col}='{v}' 숫자가 아니다")
                return dflt

        def seq(col):
            return [int(float(x)) for x in (r.get(col) or "").split(":") if x.strip()]

        e = {"kind": kind}
        if kind == "skill_scroll":
            e["skill"] = int(tgt)
            if (r.get("target_name") or "").strip():
                e["skill_name"] = r["target_name"].strip()
            lv, lw = seq("levels"), seq("level_weights")
            if lv:
                e["levels"] = lv
            e["level_weights"] = lw or [1]
        else:
            if tgt not in names:
                print(f"  [warn] {SHEET.name}:{i} items.json 에 없는 target={tgt}")
                bad += 1
                continue
            e["item"] = tgt
            e["min"] = num("min", 1)
            e["max"] = num("max", 1)
        e["chance"] = num("chance", 100, f=True)
        if (r.get("boss_only") or "").strip():
            e["boss_only"] = True
        note = (r.get("note") or "").strip()
        if note:
            e["note"] = note
        per[sid][mode].append(e)

    changed = 0
    for sid, tables in per.items():
        cur = stages[sid].get("drops")
        # 시트에 나오지 않은 난이도는 건드리지 않는다(kades 를 직접 넣어 둔 경우 보존).
        merged = dict(as_tables(cur))
        merged.update(tables)
        merged = {k: v for k, v in merged.items() if v}
        if cur != merged:
            stages[sid]["drops"] = merged
            changed += 1

    doc["_drops_basis"] = (
        "탐험 특수 드랍표. `drops` = {난이도: [항목]} — normal/hero/night/kades 로 **풀이 나뉜다** "
        "(사용자 확정 2026-07-31). 원작은 이 표가 서버 소유였다(initJsonReward 에 확률이 없다) → "
        "사용자가 docs/input/sheets/adventure_drop_pool.csv 에 채우고 "
        "scripts/tools/build_adventure_drops.py --import 로 반영한다. "
        "그 밖의 탐험 드랍(알/일반젬/먹이/속성정기/장비)은 표가 아니라 규칙이다 — "
        "scripts/systems/drops.gd 화이트리스트 참조.")
    STAGES.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("[import] %d stages updated (%d warnings) -> %s" % (changed, bad, STAGES))
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", action="store_true", help="stages.json → CSV")
    ap.add_argument("--import", dest="imp", action="store_true", help="CSV → stages.json")
    ap.add_argument("--force", action="store_true", help="--export 시 기존 CSV 덮어쓰기")
    a = ap.parse_args()
    if a.imp:
        return do_import()
    return do_export(a.force)


if __name__ == "__main__":
    sys.exit(main())
