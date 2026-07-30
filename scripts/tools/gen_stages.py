"""데이터 트랙 연결 — 위키 몬스터/스테이지 → data/stages.json(전투 스테이지).

worldmap 던전 조각(target="battle:<field>")을 위키 스테이지(이름 조인)와 몬스터 스탯(monsters.json)에
연결해 `data/stages.json`의 `stages`를 채운다. → 월드맵→battle:<field>→실몬스터 전투 파이프라인 완성.

조인: worldmap piece.label(레벨접미 제거) + region ↔ stages_wiki.name + region ↔ monsters.json.name.
element: 위키 한글속성 → battle 코드(무→none, 땅→earth, 불→fire, 물→water, 빛→light, 어둠→dark, 바람→wind, 혼돈→chaos).
⚠️ hp/att/def=위키 서술값(ASSUMPTION), bg=미매칭(TODO), rewards=미확정(빈값). 사용자 검수.

사용:  python scripts/tools/gen_stages.py
"""
from __future__ import annotations
import re, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ELEM = {"무": "none", "땅": "earth", "불": "fire", "물": "water", "빛": "light",
        "어둠": "dark", "바람": "wind", "혼돈": "chaos", "": "none"}


def strip_lv(label: str) -> str:
    return re.sub(r"\s*\(Lv\.\d+\)\s*$", "", label).strip()


def main():
    wm = json.load(open(REPO / "data/worldmap.json", encoding="utf-8"))
    wiki = json.load(open(REPO / "data/stages_wiki.json", encoding="utf-8"))["stages"]
    mons = {m["name"]: m for m in json.load(open(REPO / "data/monsters.json", encoding="utf-8"))["monsters"]}
    # 위키 스테이지 인덱스: (region, name) → stage (낮 우선)
    widx = {}
    for s in wiki:
        key = (s["region"], s["name"])
        if key not in widx or s["phase"] == "day":
            widx[key] = s

    stages = {}
    unmatched = []
    for reg in wm["regions"]:
        rid = reg["id"]
        for p in reg.get("pieces", []):
            tgt = str(p.get("target", ""))
            if not tgt.startswith("battle:"):
                continue
            sid = tgt.split(":", 1)[1]         # field 번호 = 스테이지 id
            name = strip_lv(p.get("label", ""))
            ws = widx.get((rid, name))
            if ws is None:
                unmatched.append((rid, name)); continue
            enemies = []
            for mn in ws["monsters"]:
                m = mons.get(mn)
                if m is None:
                    continue
                enemies.append({"id": m.get("asset_id"), "name": mn,
                                "level": ws.get("level") or 1,
                                "element": ELEM.get(m.get("element", "무"), "none"),
                                "hp_max": m["hp"], "att": m["att"], "def": m["def"],
                                "boss": bool(m.get("boss", False))})
            stages[sid] = {"name": name, "region": rid, "bg": None,
                           "level": ws.get("level"),
                           "enemies": enemies,
                           "boss": ws.get("boss", ""),
                           "rewards": {"exp": None, "gold": None, "items": []}}
    # 기록: 기존 _re_basis/_schema/_example 보존, stages만 교체
    doc = json.load(open(REPO / "data/stages.json", encoding="utf-8"))
    doc["_generated"] = ("stages는 gen_stages.py로 위키(monsters/stages_wiki)+worldmap 조인 생성. "
                         "id=field번호. enemy id(몬스터에셋)·bg·rewards=TODO. 사용자 검수.")
    doc["stages"] = stages
    json.dump(doc, open(REPO / "data/stages.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"stages 생성: {len(stages)}개")
    for sid, s in sorted(stages.items(), key=lambda kv: (kv[1]['region'], int(kv[0]))):
        print(f"  battle:{sid:4} [{s['region']:7}] {s['name']:14s} 적{len(s['enemies'])} 보스={s['boss']}")
    if unmatched:
        print("미매칭(위키 없음):", unmatched)


if __name__ == "__main__":
    main()
