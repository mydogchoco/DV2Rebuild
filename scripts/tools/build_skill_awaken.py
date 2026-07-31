"""각성 스킬 마스터 데이터 빌드 — 사용자 시트 → data/skill_awaken.json.

입력: docs/input/sheets/skill_awaken.csv (사용자 기입, UTF-8 BOM)
      열 = id · 각성스킬 이름 · 아이콘 id · 설명 · 비고(보유 드래곤 이름들)

원작 근거(스키마): `SkillAwaken::setInfo` → `select name, comment from info_skill_awaken where no=%d`
  (docs/ref/orig_code/decomp/SkillAwaken.c). 아이콘은 `skill/evolution/<N>.png` 18종
  (`AwakenPopup.c` :290 `"skill/evolution/%d.png"`).

⚠️ 원작 코드는 **스킬 번호 = 아이콘 번호**로 아이콘을 불렀지만, 실제 게임에는 서로 다른
각성스킬이 같은 아이콘을 쓰는 사례가 있다(사용자 확인 2026-07-29). 그래서 두 축을 분리해
`no`(스킬 번호, 우리 번호) 와 `icon`(1~18) 을 따로 싣는다.

배정(어느 드래곤이 어떤 각성스킬을 갖나)은 시트의 **비고** 칸에 드래곤 이름으로 적혀 있다
(`dragons.csv` 의 `각성스킬id` 열은 비어 있음). 여기서 `data/dragons.json` 의 이름과 대조해
드래곤 id 로 변환하고, 못 찾은 이름은 그대로 남겨 보고한다(지어내지 않는다 — HARD RULE 6).

usage: python scripts/tools/build_skill_awaken.py [--report]
"""
from __future__ import annotations
import csv, io, json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SHEET = REPO / "docs/input/sheets/skill_awaken.csv"
DRAGONS = REPO / "data/dragons.json"
OUT = REPO / "data/skill_awaken.json"

# 시트의 표기 → dragons.json 의 정식 이름. 정규화(공백제거/로마숫자/‘드래곤’ 접미)로도 못 잡는 것만.
ALIAS = {
    "봄버 드래곤": "붐버 드래곤",   # 시트 오탈자 — dragons.json id 186 이 '붐버 드래곤'
}

# 시트는 로마숫자 글리프(Ⅱ), dragons.json 은 라틴 문자(II) 를 쓴다.
ROMAN = {"Ⅰ": "I", "Ⅱ": "II", "Ⅲ": "III", "Ⅳ": "IV", "Ⅴ": "V"}


def norm(s: str) -> str:
    """비교용 정규화 — 공백/가운뎃점 제거 + 로마숫자 글리프 통일."""
    for k, v in ROMAN.items():
        s = s.replace(k, v)
    return re.sub(r"[\s·]", "", s)


def build_index(dragons: list) -> dict:
    """정규화 이름 → id. '○○ 드래곤' 은 '○○' 로도 찾을 수 있게 넣는다."""
    idx: dict[str, int] = {}
    for d in dragons:
        nm = str(d.get("name", ""))
        if not nm:
            continue
        idx.setdefault(norm(nm), int(d["id"]))
        if nm.endswith(" 드래곤"):
            idx.setdefault(norm(nm[:-4]), int(d["id"]))
        if nm.endswith("드래곤"):
            idx.setdefault(norm(nm[:-3]), int(d["id"]))
    return idx


def split_dragons(cell: str) -> list[str]:
    out = []
    for part in cell.split(","):
        p = part.strip()
        if p:
            out.append(p)
    return out


# 이름이 없는 드래곤(선택권으로 이름을 정하는 600·700)은 비고에 **id 로** 적는다:
#   `dragon id 600 전용스킬`
ID_RE = re.compile(r"dragon\s*id\s*(?P<id>\d+)", re.I)


def main() -> int:
    rows = list(csv.DictReader(io.open(SHEET, encoding="utf-8-sig")))
    dragons = json.load(io.open(DRAGONS, encoding="utf-8"))
    idx = build_index(dragons)
    known_ids = {int(d["id"]) for d in dragons}

    id_col = next(k for k in rows[0] if k.startswith("id"))
    skills, unmatched = [], []
    for r in rows:
        raw_id = (r.get(id_col) or "").strip()
        if not raw_id:
            continue
        name = (r.get("각성스킬 이름") or "").strip()
        if not name:
            continue
        icon = (r.get("아이콘 id") or "").strip()
        comment = (r.get("설명") or "").strip()
        names, ids = [], []
        for nm in split_dragons(r.get("비고") or ""):
            nm = ALIAS.get(nm, nm)
            names.append(nm)
            m = ID_RE.search(nm)
            if m:
                # 이름 대신 도감 id 로 지목한 경우(600·700 = 이름이 선택권으로 정해지는 드래곤)
                did = int(m.group("id"))
                if did in known_ids:
                    ids.append(did)
                else:
                    unmatched.append((int(raw_id), nm))
                continue
            did = idx.get(norm(nm))
            if did:
                ids.append(did)
            else:
                unmatched.append((int(raw_id), nm))
        skills.append({
            "no": int(raw_id),
            "name": name,
            "comment": comment,
            "icon": int(icon) if icon.isdigit() else 0,
            "dragons": sorted(set(ids)),
            "dragon_names": names,
        })

    by_dragon: dict[str, list[int]] = {}
    for s in skills:
        for did in s["dragons"]:
            by_dragon.setdefault(str(did), []).append(s["no"])
    for k in by_dragon:
        by_dragon[k] = sorted(set(by_dragon[k]))

    doc = {
        "_source": "docs/input/sheets/skill_awaken.csv (사용자 기입 2026-07-29) — "
                   "빌드: scripts/tools/build_skill_awaken.py",
        "_re_basis": [
            "스키마=클라 복원: SkillAwaken::setInfo `select name, comment from info_skill_awaken "
            "where no=%d` (docs/ref/orig_code/decomp/SkillAwaken.c) + getName/getComment.",
            "행 값(이름·설명·효과·드래곤 배정)은 서버 소실 → 원작 경험자(사용자)가 시트로 복원.",
            "아이콘은 원작 자산 `skill/evolution/1~18.png` (AwakenPopup.c :290). "
            "원작 코드는 스킬 번호로 아이콘을 직접 불렀으나, 실제로는 서로 다른 스킬이 같은 "
            "아이콘을 쓰는 사례가 있어(사용자 확인 2026-07-29) `no` 와 `icon` 을 분리한다.",
            "`comment` 는 효과의 **서술**이다. 전투 엔진에 태울 수치화(effect 딕셔너리)는 "
            "아직 하지 않았다 — 서술→수치 변환은 별도 작업(HARD RULE 6).",
        ],
        "_schema": {
            "no": "int — 각성 스킬 번호(우리 번호). dragon 레코드의 awaken_skill 이 이 값",
            "name": "string — 각성 스킬 이름 (원작 name 컬럼)",
            "comment": "string — 각성 스킬 설명 (원작 comment 컬럼)",
            "icon": "int 1~18 — assets/converted/skill_evolution/skill_evolution_<icon>.tres",
            "dragons": "int[] — 이 각성스킬을 갖는 드래곤 도감 id (dragons.json)",
            "dragon_names": "string[] — 시트에 적힌 원문 이름(대조용, id 매칭 실패분 포함)",
        },
        "by_dragon": by_dragon,
        "_by_dragon_note": "드래곤 도감 id → 각성스킬 no 목록. 각성 시 이 표에서 배정한다"
                           "(Data.awaken_skill_of). 여러 개인 드래곤은 첫 번째를 기본으로 쓴다.",
        "skills": skills,
    }
    if unmatched:
        doc["_unmatched_names"] = [{"no": n, "name": nm} for n, nm in unmatched]
        doc["_unmatched_note"] = ("dragons.json 에서 이름을 못 찾은 항목. 오탈자이거나 "
                                  "우리 도감에 없는 드래곤이다 — 사용자 확인 대상.")

    # ---- 교차검증: 같은 사실이 시트 두 곳에 적혀 있다 ----
    # 여기(`비고` = 스킬 → 드래곤 이름들) 와 `dragons.csv` 의 `각성스킬id` 열(드래곤 → 스킬 no).
    # 후자가 정본(`build_data.py` 가 dragons.json `awaken_skill` 로 싣는다) — 어긋나면
    # 어느 한쪽 시트를 고치다 만 것이므로 조용히 넘기지 않고 보고한다(HARD RULE 6).
    drift = []
    for d in dragons:
        did = int(d["id"])
        sheet = int(d.get("awaken_skill", 0))
        here = by_dragon.get(str(did), [])
        if sheet and sheet not in here:
            drift.append((did, d.get("name", ""), sheet, here))
        elif not sheet and here:
            drift.append((did, d.get("name", ""), 0, here))
    if drift:
        doc["_drift"] = [{"dragon": i, "name": n, "dragons_csv": s, "sheet_비고": h}
                         for i, n, s, h in drift]
        doc["_drift_note"] = ("dragons.csv `각성스킬id`(정본) 와 skill_awaken.csv `비고` 가 "
                              "가리키는 배정이 다르다 — 한쪽 시트만 고친 상태다.")

    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print("skills: %d" % len(skills))
    print("dragons mapped: %d" % len(by_dragon))
    if unmatched:
        print("UNMATCHED %d:" % len(unmatched))
        for n, nm in unmatched:
            print("  no=%d  %s" % (n, nm))
    if drift:
        print("DRIFT %d (dragons.csv vs skill_awaken.csv 비고):" % len(drift))
        for i, n, s, h in drift:
            print("  id=%d %s  dragons.csv=%s  비고=%s" % (i, n, s or "-", h or "-"))
    else:
        print("drift: none (dragons.csv 각성스킬id 와 비고 배정 일치)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
