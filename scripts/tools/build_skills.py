"""스킬 마스터 데이터(data 계층) 빌드: docs/input/skills/skills_skeleton.csv -> data/skills.json.

출처: 사용자 작성 docs/input/skills/skills_skeleton.csv (위키/경험 복원). 아이콘 skill/{id}.png.
effect_text는 자유서술이라 _raw로 보존하고, 효과 구조화/수식 해석은 전투 엔진(scripts/systems/)에서 단계적으로.
인코딩: 엑셀(cp949) 또는 utf-8 자동 판별.

usage: python scripts/tools/build_skills.py
"""
import csv, io, json, os

SRC = "docs/input/skills/skills_skeleton.csv"
OUT = "data/skills.json"


def read_rows(path):
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-8", "cp949"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    return list(csv.DictReader(io.StringIO(text)))


def parse_limit(s):
    """number_limit: 정수면 int, 'n/a'/'' 면 None(무제한/패시브), '2+스킬레벨' 등은 raw 유지."""
    s = (s or "").strip()
    if s == "" or s.lower() == "n/a":
        return None, s
    if s.isdigit():
        return int(s), s
    return None, s   # 수식형(2+스킬레벨 등)은 base 파싱을 엔진에 위임, raw만 보존


def main():
    rows = read_rows(SRC)
    skills = {}
    for r in rows:
        sid = (r.get("id") or "").strip()
        if not sid.isdigit():
            continue
        name = (r.get("name") or "").strip()
        notes = (r.get("notes") or "").strip()
        category = (r.get("category") or "").strip()
        # id56 망각의 망치: 카테고리 공란 = 반응형 인터럽트(Claude 분류). 엔진이 특수 처리.
        if sid == "56":
            category = "interrupt"
        limit, limit_raw = parse_limit(r.get("number_limit"))
        usable = ("사용불가" not in notes) and (name != "몬스터스킬")
        skills[sid] = {
            "id": int(sid),
            "name": name,
            "slot": (r.get("slot") or "").strip(),          # tri/sq/cir/star
            "active": (r.get("active_passive") or "").strip().lower() != "p",
            "category": category,                            # attack/defense/buff/debuff/dot/heal/cleanse/interrupt
            "target": (r.get("target") or "").strip(),       # single/enemy_all/self/ally_all
            "number_limit": limit,                           # int 또는 null(무제한/수식형)
            "number_limit_raw": limit_raw,
            "effect_text": (r.get("effect_text") or "").strip(),   # 자유서술(엔진이 해석)
            "notes": notes,
            "usable": usable,
            "max_level": 5,                                  # §C: 스킬 1~5레벨
        }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(skills, f, ensure_ascii=False, indent=1)
    usable_n = sum(1 for s in skills.values() if s["usable"])
    print("skills.json: %d개 (사용가능 %d) -> %s" % (len(skills), usable_n, OUT))


if __name__ == "__main__":
    main()
