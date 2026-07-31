# -*- coding: utf-8 -*-
"""스토리 전투 전수 → `data/story_battles.json`.

## 🔴 1~78화에도 전투가 있다 (2026-07-31 확정)

앞서 "`scenarioBattle` xref 가 Scenario1~8 에 0건이므로 1~81화엔 전투가 없다"고 했는데
**틀렸다.** 그 구간은 `ScenarioSupport::scenarioBattle` 을 안 거치고
**`AdventureScene::scene(FieldType, BattleType, string)` 을 직접** 부른다.

    Scenario2~7 안의 직접 호출 16건 · 전부 `mov w0,#1`(FieldType=1)
    FieldType 은 던전 id 가 아니라 **모드 enum** 이다 —
    레이드 23 · DungeonScene 6 · WorldMapScene 8 · EventLayer 4/5 … 스토리 1.
    ⇒ 실제 던전은 이 인자가 아니라 이벤트 데이터/서브퀘스트 쪽이 정한다.

## 회차 귀속 방법

스텝 블록은 스텝 테이블 타깃과 타깃 사이에 연속으로 놓인다. 그래서
**"호출 주소 이하인 가장 큰 스텝 타깃"** 이 그 호출을 감싸는 블록이고,
그 타깃이 속한 회차가 답이다. (공유 꼬리를 걸어가며 줍는 방식은 안 된다 —
회차마다 같은 값이 나온다. 실제로 그렇게 틀렸다.)

## 교차검증

원작 문자열 `<AdventureEvent%d>`(%d = 회차 sn, `AdventureScene.c` 의
`"AdventureEvent" << mScenarioManager()->0x168`)은 33·46·62·91 넷뿐인데:

    battleNo 15 → 32화   (32화 제목이 "실험체 다크 프로스티" · <AdventureEvent33> 이 그 이름을 부른다)
    battleNo 16 → 46화   (<AdventureEvent46> "태초의 비밀…")
    battleNo 28 → 91화   (<AdventureEvent91> 각성 · scenarioBattle 경유)

세 개가 독립적으로 맞아떨어진다.

사용:  python scripts/tools/extract_story_battles.py
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import OrderedDict
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "data" / "story_battles.json"
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"

## `AdventureScene` 의 `switch(battleNo)` — 전투번호 → (몬스터 번호, 레벨).
## 앵커 = `"AdventureEvent" << sn` 직후. 파서는 extract_story_subquest.parse_adventure_battles.
def monster_switch() -> dict[int, dict]:
    src = (DECOMP / "AdventureScene.c").read_text(encoding="utf-8", errors="replace")
    seg = src[src.index('"AdventureEvent",0xe'):][:40000]
    out: dict[int, dict] = {}
    cur: list[int] = []
    for line in seg.splitlines():
        m = re.match(r"\s*case (0x[0-9a-f]+|\d+):", line)
        if m:
            cur.append(int(m.group(1), 0))
            continue
        m = re.search(r"setMonster\(this,(0x[0-9a-f]+|\d+),(0x[0-9a-f]+|\d+),", line)
        if m and cur:
            for b in cur:
                out[b] = {"monster_no": int(m.group(1), 0), "level": int(m.group(2), 0)}
            cur = []
    return out


def scene_calls():
    """`AdventureScene::scene` 직접 호출 → [(주소, field, battleNo)]."""
    import pyghidra
    pyghidra.start()
    so = REPO / "lib" / "arm64-v8a" / "libgame.so"
    if not so.exists():
        so = REPO / "libgame.so"
    pd = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
    rows = []
    with pyghidra.open_program(str(so), project_location=str(pd),
                               project_name="dv2", analyze=False) as flat:
        prog = flat.getCurrentProgram()
        fm, listing = prog.getFunctionManager(), prog.getListing()
        af, rm = prog.getAddressFactory().getDefaultAddressSpace(), prog.getReferenceManager()

        def T(i):
            return re.sub(r",\s+", ",", re.sub(r"\s+", " ", str(i).strip()))

        owners = sorted((f.getEntryPoint().getOffset(),
                         f.getName(True).rsplit("::", 2)[-2] if "::" in f.getName(True) else "")
                        for f in fm.getFunctions(True) if "::Scenario" in ("::" + f.getName(True)))
        tgt = [f.getEntryPoint().getOffset() for f in fm.getFunctions(True)
               if f.getName() == "scene" and "AdventureScene" in f.getName(True)]
        for off in tgt:
            for ref in rm.getReferencesTo(af.getAddress(off)):
                src = ref.getFromAddress()
                ins = listing.getInstructionAt(src)
                if ins is None or ins.getMnemonicString() != "bl":
                    continue
                fn = fm.getFunctionContaining(src)
                if fn is not None and "Scenario" not in fn.getName(True):
                    continue                       # 스토리 밖(레이드·던전·월드맵)은 대상 아님
                a = src.getOffset()
                cls = ""
                for o, c in owners:
                    if o <= a:
                        cls = c
                    else:
                        break
                if not cls:
                    continue
                args = {}
                cur = ins
                for _ in range(14):
                    cur = listing.getInstructionBefore(cur.getAddress())
                    if cur is None or cur.getMnemonicString() == "bl":
                        break            # 이전 호출을 넘어가면 남의 인자다
                    m = re.fullmatch(r"(mov|movz|orr) (w[01]),(?:wzr,)?#(0x[0-9a-f]+|\d+)", T(cur))
                    if m:
                        args.setdefault(m.group(2), int(m.group(3), 0))
                rows.append({"addr": a, "class": cls,
                             "field_type": args.get("w0"), "battle_no": args.get("w1")})
    rows.sort(key=lambda r: r["addr"])
    return rows


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sw = monster_switch()
    calls = scene_calls()
    doc = OrderedDict()
    doc["_re_basis"] = (
        "1~78화의 스토리 전투는 ScenarioSupport::scenarioBattle 이 아니라 "
        "AdventureScene::scene(FieldType, BattleType, string) 직접 호출이다(xref 전수 16건). "
        "FieldType=1 은 던전 id 가 아니라 모드 enum(레이드 23 · 던전 6 · 월드맵 8 · 스토리 1)."
    )
    doc["_monster_basis"] = (
        "battle_no → 몬스터·레벨 = AdventureScene 의 switch(battleNo). "
        "표에 없는 번호(5~14)는 default 분기라 런타임 값이고, 그중 26·27·29 는 "
        "ScenarioSubQuestData::getEventBattleData 가 덮어쓴다(data/story_subquest.json event_battle)."
    )
    doc["_episode_basis"] = (
        "회차 귀속 = '호출 주소 이하인 가장 큰 스텝 테이블 타깃' 이 감싸는 블록의 회차. "
        "교차검증: battleNo 15→32화(<AdventureEvent33> 이 '다크프로스티'를 부른다) · "
        "16→46화(<AdventureEvent46> '태초의 비밀') · 28→91화(<AdventureEvent91> 각성)."
    )
    doc["_tool"] = "scripts/tools/extract_story_battles.py"
    doc["monster_by_battle"] = {str(k): v for k, v in sorted(sw.items())}
    doc["scene_calls"] = calls
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"-> {OUT.relative_to(REPO)}  직접호출 {len(calls)}건 · 몬스터표 {len(sw)}번호")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
