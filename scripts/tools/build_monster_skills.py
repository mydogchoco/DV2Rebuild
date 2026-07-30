#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""몬스터 스킬 배선 — `data/monsters.json`(위키) 의 스킬 목록을 `data/stages.json` 편성에 실어 준다.

왜 필요한가
-----------
원작 몬스터는 스킬을 쓴다 — `BattleMonster::setReadySkill` / `callReadySkill` /
`setAnimatedReadySkill`(스킬 준비 모션) 이 실재하고, `FightManager::getActorSkillNumber` /
`getTargetSkillNumber` 는 **진영 구분 없이** 행위자의 스킬 번호를 다룬다.
위키 던전 PDF 도 몬스터별 보유 스킬을 적고 있어 `extract_wiki.py` 가 이미
`data/monsters.json` 에 옮겨 뒀다. 그런데 전투가 실제로 읽는 편성표
(`data/stages.json` 의 `enemies`)에는 그 칸이 없어서 **몬스터가 스킬을 한 번도 쓰지
못하고 있었다**(우리 전투 엔진 `Battle.make_combatant` 는 진영 무관하게 skills 를 받는다).

이 스크립트가 하는 일
---------------------
1. `monsters.json` 의 몬스터를 **이름**으로 색인한다.
   ⚠️ `asset_id` 로 조인하면 안 된다 — 그 값은 위키 등장 순 자동부여(ASSUMPTION)라
   `stages.json` 의 확정 스프라이트 id(`monster_mapping.csv` 사용자 검수분)와 어긋난다.
   실측: id 조인은 120마리 중 27마리만 이름이 일치, 이름 조인은 118마리가 일치.
2. 스킬 이름 → `skills.json` 의 스킬 id 로 옮긴다(공백·괄호 무시 비교).
3. `stages.json` 각 편성의 몬스터에 `skills: [id, …]` 를 써 넣는다.
   대상: 스테이지 `enemies` + 변형 블록 `night.enemies` / `kades.enemies`.

멱등이다 — 다시 돌리면 같은 결과가 나오고, 이미 있는 `skills` 는 덮어쓴다.

    python scripts/tools/build_monster_skills.py            # 반영
    python scripts/tools/build_monster_skills.py --dry-run  # 보고만
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data"
STAGES = DATA / "stages.json"
MONSTERS = DATA / "monsters.json"
SKILLS = DATA / "skills.json"

BASIS = (
    "몬스터 보유 스킬 = 위키 dungeon_*.pdf(data/monsters.json) 를 이름으로 조인해 "
    "skills.json 의 스킬 id 로 옮긴 것. 원작 근거 = BattleMonster::setReadySkill/"
    "callReadySkill/setAnimatedReadySkill + FightManager::getActorSkillNumber(진영 무관). "
    "생성 도구 = scripts/tools/build_monster_skills.py. "
    "# ASSUMPTION: 몬스터 스킬 **레벨**은 원작 표가 서버와 함께 유실됐다 → 전투에서 1로 쓴다"
    "(scripts/ui/battle.gd `_enemy_skills`)."
)


def norm(s: object) -> str:
    """이름 비교용 정규화 — 괄호 영문 표기와 공백 차이를 무시한다."""
    return re.sub(r"\s+", "", re.sub(r"\([^)]*\)", "", str(s or "")))


def load(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="파일을 쓰지 않고 보고만")
    args = ap.parse_args()

    mons = [m for m in load(MONSTERS)["monsters"] if isinstance(m, dict)]
    skills = load(SKILLS)
    stages_doc = load(STAGES)

    # 스킬 이름 → id
    skill_id: dict[str, int] = {}
    for key, sd in skills.items():
        if not isinstance(sd, dict) or not sd.get("name"):
            continue
        skill_id[norm(sd["name"])] = int(sd.get("id", key))

    # 몬스터 이름 → 스킬 id 목록
    by_name: dict[str, list[str]] = {}
    conflict: list[str] = []
    for m in mons:
        n = norm(m.get("name"))
        sk = [s for s in (m.get("skills") or []) if s]
        if n in by_name and sorted(by_name[n]) != sorted(sk):
            conflict.append(m.get("name"))
        by_name.setdefault(n, sk)

    unmapped: Counter[str] = Counter()
    unmatched: list[str] = []
    stat = Counter()
    per_stage: dict[str, int] = defaultdict(int)

    def wire(enemies, label: str) -> None:
        for e in enemies:
            if not isinstance(e, dict):
                continue
            stat["enemies"] += 1
            key = norm(e.get("name"))
            if key not in by_name:
                stat["no_monster"] += 1
                unmatched.append(str(e.get("name")))
                e.pop("skills", None)
                continue
            ids: list[int] = []
            for sname in by_name[key]:
                sid = skill_id.get(norm(sname))
                if sid is None:
                    unmapped[sname] += 1
                    continue
                if sid not in ids:
                    ids.append(sid)
            if ids:
                e["skills"] = ids
                stat["wired"] += 1
                per_stage[label] += 1
            else:
                # 스킬이 없는 몬스터는 칸 자체를 두지 않는다(빈 배열로 노이즈를 남기지 않음).
                e.pop("skills", None)

    for sid, st in (stages_doc.get("stages") or {}).items():
        if not isinstance(st, dict):
            continue
        label = f"{sid} {st.get('name', '')}"
        wire(st.get("enemies") or [], label)
        for variant in ("night", "kades"):
            vv = st.get(variant)
            if isinstance(vv, dict):
                wire(vv.get("enemies") or [], f"{label} [{variant}]")

    stages_doc["_monster_skills_basis"] = BASIS

    print(f"편성 몬스터 {stat['enemies']}마리 — 스킬 배선 {stat['wired']} / "
          f"이름 미매칭 {stat['no_monster']}")
    for label, n in sorted(per_stage.items(), key=lambda kv: -kv[1])[:12]:
        print(f"   {label:34} {n}")
    if unmatched:
        print("⚠️ monsters.json 에 없는 몬스터:", sorted(set(unmatched)))
    if unmapped:
        print("⚠️ skills.json 에 없는 스킬(= 원작 '몬스터스킬' id 10 계열, 효과 유실):")
        for k, v in unmapped.most_common():
            print(f"   {k}  ×{v}")
    if conflict:
        print("⚠️ 같은 이름인데 스킬이 다른 몬스터:", sorted(set(conflict)))

    if args.dry_run:
        print("(--dry-run — 파일 미기록)")
        return 0
    STAGES.write_text(json.dumps(stages_doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"기록: {STAGES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
