# -*- coding: utf-8 -*-
"""**몬스터별** 고유 드랍 시트 ↔ data/monster_drops.json 왕복 도구.

사용자 요청(2026-07-31):
  "(밤) 지역 전체 랜덤 조우 몬스터가 3마리 있는데(#160 골드 임프, #161 실버 임프,
   #162 검은 로브의 사도) … 이 몬스터들은 고유 드랍이 몬스터별로 지정되어 있어.
   마찬가지로 '혼돈의 틈새' 출현 보스도 보스별로 고유 드랍이 지정되어 있어."

## 왜 지역 시트(adventure_drop_pool.csv)와 **따로** 두나
키 축이 다르다.
  · `adventure_drop_pool.csv` = **(지역 × 난이도)** — 그 장소에서 나오는 것
  · 이 시트                    = **몬스터**        — 그 몬스터가 떨구는 것
#160·161·162·175 는 밤 12지역 **전부**에 나오므로 지역 시트에 넣으면 4종×12지역 = 48줄을
중복 관리해야 한다. 혼돈의 틈새 보스 3종은 **진입 시 랜덤으로 뽑히는 대상**이라 드랍이
장소가 아니라 그 보스에 붙는다.

⇒ 두 표는 **합산**된다. 한 조우에서 지역 표와 몬스터 표가 둘 다 판정된다.

## 무엇이 유실인가
원작 드랍표는 서버 소유였다(`AdventureScene::initJsonReward` 에 확률이 없다 —
포팅 카드 `docs/ref/porting/AdventureEventFlow.md` §6). 이 시트는 **사용자가 채우는 자작 데이터**다.

## 키
`stages.json` 의 적 `id`(= 몬스터/스프라이트 번호)를 쓴다. `data/monsters.json` 은 **이름**으로
키가 잡혀 있어(위키 추출본) 런타임 조인에 못 쓴다 — 전투가 손에 쥐고 있는 건 이 `id` 다.

사용:
    python scripts/tools/build_monster_drops.py --export   # 후보 몬스터 → CSV
    python scripts/tools/build_monster_drops.py --import   # CSV → data/monster_drops.json
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
OUT = ROOT / "data" / "monster_drops.json"
SHEET = ROOT / "docs" / "input" / "sheets" / "monster_drop_pool.csv"

# 한 행 = 후보 하나. 같은 monster_id + 같은 kind 끼리 `weight` 로 하나를 고른 뒤
# 그 행의 `chance`(%) 로 판정한다. 사용자가 적은 `3:2:1:1` 같은 비율이 곧 weight 다.
COLS = [
    "monster_id", "monster_name", "appears_in",    # ← 참고(자동). 고치지 말 것
    "kind",                                        # item | skill_scroll | egg | currency
    "target", "target_name",                       # 아이템키 / 스킬id / 드래곤id / diamond|gold
    "weight", "level_weights", "chance", "min", "max",
    "note",
]


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def item_names() -> dict:
    d = load(ITEMS)
    it = d.get("items", d)
    return {k: (v.get("name") or "") for k, v in it.items() if isinstance(v, dict)}


def candidates() -> list:
    """행을 미리 만들어 둘 몬스터 = **드랍이 장소가 아니라 몬스터에 붙는** 것들.

    1. 밤 지역 공용 조우 몬스터 — 12지역 전부에 나온다(사용자 지목 + 실측).
    2. 밤 지역 보스 — 지역마다 1종이라 지역 시트로도 되지만, 밤 보스는 '그 몬스터'가
       주는 것이라 여기 둔다(지역 시트와 합산되므로 어느 쪽에 적어도 동작한다).
    3. `random_boss` 스테이지(혼돈의 틈새 8)의 보스 — 진입 시 랜덤으로 뽑히는 대상.

    반환: [{id, name, appears_in}]  (id 오름차순)
    """
    stages = load(STAGES)["stages"]
    seen: dict = {}

    def add(mid, name, where):
        e = seen.setdefault(int(mid), {"id": int(mid), "name": name, "where": []})
        if where not in e["where"]:
            e["where"].append(where)

    for sid, st in stages.items():
        if not isinstance(st, dict):
            continue
        nb = st.get("night") or {}
        for e in (nb.get("enemies") or []):
            add(e.get("id", 0), e.get("name", ""),
                "밤 보스 %s" % st.get("name", sid) if e.get("boss") else "밤 공용")
        if st.get("random_boss"):
            for e in (st.get("enemies") or []):
                add(e.get("id", 0), e.get("name", ""), "랜덤보스 %s" % st.get("name", sid))

    out = []
    for mid in sorted(seen):
        if mid <= 0:
            continue
        e = seen[mid]
        where = e["where"]
        # 밤 공용은 12지역 전부라 나열하지 않고 한 마디로 적는다.
        if where.count("밤 공용") or "밤 공용" in where:
            where = ["밤 전 지역 공용 조우"] + [w for w in where if w != "밤 공용"]
        out.append({"id": mid, "name": e["name"], "appears_in": " / ".join(where)})
    return out


def do_export(force: bool) -> int:
    if SHEET.exists() and not force:
        print("[skip] exists; use --force to overwrite: %s" % SHEET)
        return 0
    names = item_names()
    doc = load(OUT) if OUT.exists() else {}
    cur = doc.get("drops", {})
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for c in candidates():
        base = {"monster_id": c["id"], "monster_name": c["name"], "appears_in": c["appears_in"]}
        lst = cur.get(str(c["id"])) or []
        if not lst:
            rows.append({**base, "kind": "", "target": "", "target_name": "", "weight": "",
                         "level_weights": "", "chance": "", "min": "", "max": "", "note": ""})
            continue
        for d in lst:
            k = d.get("kind", "item")
            if k == "item":
                tgt, tn = d.get("key", ""), d.get("item_name") or names.get(d.get("key", ""), "")
            elif k == "skill_scroll":
                tgt, tn = d.get("skill", ""), d.get("skill_name", "")
            elif k == "egg":
                tgt, tn = d.get("dragon", ""), d.get("dragon_name", "")
            else:
                tgt, tn = d.get("currency", ""), ""
            lw = d.get("level_weights") or []
            rows.append({**base, "kind": k, "target": tgt, "target_name": tn,
                         "weight": d.get("weight", ""),
                         "level_weights": ":".join(str(x) for x in lw),
                         "chance": d.get("chance", ""),
                         "min": d.get("min", ""), "max": d.get("max", ""),
                         "note": d.get("note", "")})
    with io.open(SHEET, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        w.writerows(rows)
    print("[export] %d rows -> %s" % (len(rows), SHEET))
    print("  - kind: item | skill_scroll | egg | currency")
    print("  - target: item key / skill id / dragon id / diamond|gold")
    print("  - weight: pick ratio among same-kind rows (your 3:2:1:1 becomes 3,2,1,1)")
    print("  - level_weights: scroll level 1..4 weights, e.g. 7:2:1:1")
    print("  - chance: percent, decimals allowed (0.2 = 0.2%)")
    return 0


def do_import() -> int:
    if not SHEET.exists():
        print("[error] sheet not found (run --export first): %s" % SHEET)
        return 1
    with io.open(SHEET, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print("[error] sheet is empty; aborting")
        return 1

    names = item_names()
    drops: dict = {}
    bad = 0

    def num(r, col, dflt=None, allow_float=False):
        v = (r.get(col) or "").strip()
        if v == "":
            return dflt
        try:
            return float(v) if allow_float else int(float(v))
        except ValueError:
            return dflt

    for i, r in enumerate(rows, start=2):
        mid = (r.get("monster_id") or "").strip()
        kind = (r.get("kind") or "").strip()
        if not mid or not mid.isdigit():
            continue
        drops.setdefault(mid, [])
        if not kind:
            continue
        tgt = (r.get("target") or "").strip()
        e = {"kind": kind}
        if kind == "item":
            if tgt not in names:
                print(f"  [warn] {SHEET.name}:{i} items.json 에 없는 key={tgt}")
                bad += 1
                continue
            e["key"] = tgt
            e["item_name"] = names[tgt]
        elif kind == "skill_scroll":
            e["skill"] = int(tgt)
            if (r.get("target_name") or "").strip():
                e["skill_name"] = r["target_name"].strip()
            lw = [int(float(x)) for x in (r.get("level_weights") or "").split(":") if x.strip()]
            e["level_weights"] = lw or [1]
        elif kind == "egg":
            e["dragon"] = int(tgt)
            if (r.get("target_name") or "").strip():
                e["dragon_name"] = r["target_name"].strip()
        elif kind == "currency":
            e["currency"] = tgt
        else:
            print(f"  [warn] {SHEET.name}:{i} 모르는 kind={kind}")
            bad += 1
            continue
        w = num(r, "weight")
        if w is not None:
            e["weight"] = w
        e["chance"] = num(r, "chance", 100, allow_float=True)
        if kind != "skill_scroll":
            e["min"] = num(r, "min", 1)
            e["max"] = num(r, "max", 1)
        note = (r.get("note") or "").strip()
        if note:
            e["note"] = note
        drops[mid].append(e)

    drops = {k: v for k, v in drops.items() if v}
    doc = {
        "_source": (
            "몬스터별 고유 드랍. 키 = stages.json 의 적 `id`(스프라이트/몬스터 번호). "
            "사용자가 docs/input/sheets/monster_drop_pool.csv 에 채우고 "
            "scripts/tools/build_monster_drops.py --import 로 반영한다."),
        "_authored": (
            "원작 드랍표는 서버 소유였다(AdventureScene::initJsonReward 에 확률이 없다) → 자작 데이터. "
            "사용자 확정 2026-07-31: 밤 공용 조우 몬스터(#160 골드 임프·#161 실버 임프·"
            "#162 검은 로브의 사도, +실측으로 #175 칼리고마가도 12지역 공용)와 "
            "혼돈의 틈새 랜덤 보스(#36 다크닉스·#138 그리파르·#139 발레포르)는 "
            "**몬스터별로** 고유 드랍을 갖는다."),
        "_stacking": (
            "지역 표(stages.json `drops`)와 **합산**된다 — 한 조우에서 둘 다 판정한다. "
            "판정 = scripts/systems/drops.gd `roll_monster`."),
        "_key_note": (
            "data/monsters.json 은 **이름**으로 키가 잡힌 위키 추출본이라 런타임 조인에 못 쓴다. "
            "전투가 쥐고 있는 것은 stages.json 의 적 `id` 다."),
        "drops": drops,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("[import] %d monsters -> %s (%d warnings)" % (len(drops), OUT, bad))
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--export", action="store_true")
    ap.add_argument("--import", dest="imp", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    return do_import() if a.imp else do_export(a.force)


if __name__ == "__main__":
    sys.exit(main())
