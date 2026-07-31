#!/usr/bin/env python3
"""원작 오프닝 튜토리얼(시나리오 0)의 스텝 표를 디컴프에서 뽑는다 → `data/tutorial_flow.json`.

## 원작 구조 (근거)

튜토리얼은 별도 씬이 아니라 **시나리오 0 위에 얹힌 상태기계**다.
`ScenarioLayer::setNextSelecteMode(string)` @016caaac (29,828B) 이 `SN_0_<대사번호>[_<하위>]`
문자열을 `memcmp` 사슬로 받아 분기하고, 각 분기가
  · `setScNextArrow(delay, this, pos, rotation, parent)` — 안내 화살표
  · `CCMenuItemImageEx::createWithSpriteFrameName(<대상 프레임>, onClickBtnListener)` — **대상 버튼의
    복제본**을 그 자리에 만들어 그것만 눌리게 한다(나머지 입력은 딤이 먹는다)
  · `CaveScene::scene(0)` / `AdventureScene::scene(1,4)` / `CaveScene::onClickNicName` 등 씬 훅
  · `ScenarioDialogLayer` — 확인 창(부화 확인 `PrologueEggBorn`, 완료 확인)
을 실행한다. 버튼 탭은 `ScenarioLayer::onClickBtnListener` @016d3048 이 tag 로 받아
`CaveScene::setBtnClick(1~5)` 같은 후속 동작을 건다.

### 🔑 SN 번호 = 시나리오 0 의 **대사 인덱스** (2026-08-01 확정)

대사는 두 문자열 계열이 이어 붙은 하나의 목록이다:
    인덱스 0~34  → `<PrologueTalk%d>`      (35줄, 프롤로그 = 누리/즈믄/알/마을 습격)
    인덱스 37~   → `<Tutorial_%d>`(N−36)   (45줄, UI 가이드 투어)

근거(오프셋 36 은 8건 이상이 동시에 맞는다 — 우연이 아니다):
    SN_0_14_1 월드맵 동굴버튼 화살표   ↔ PrologueTalk14 "여기가 동굴이야."
    SN_0_17_6 `PrologueEggBorn` 확인창 ↔ PrologueTalk15/16 자연·즉시 부화 설명
    SN_0_18   `onClickNicName`         ↔ PrologueTalk17 "이름을 지어주는 건 어때?"
    SN_0_20   —                        ↔ PrologueTalk20 "마을 사람들이 공격받고 있어!"
    SN_0_26   `AdventureScene::scene(1,4)` ↔ PrologueTalk26 "드래곤을 다룰 수 있잖아?"
    SN_0_41   월드맵 동굴버튼 화살표   ↔ Tutorial_5  "화살표를 따라 동굴로 들어가봅시다."
    SN_0_45   좌향(flipX) 화살표       ↔ Tutorial_9  "동굴 왼쪽에서 … 드래곤들을 볼 수 있습니다."
    SN_0_51   `scene/cave/book.png`    ↔ Tutorial_15 "드래곤 도감입니다!"
    SN_0_53   `scene/cave/card.png`    ↔ Tutorial_17 "드래곤 카드입니다."
    SN_0_56   `scene/cave/bag.png`     ↔ Tutorial_20 "가방을 열면 …"
    SN_0_58   아래 화살표(rot 90)      ↔ Tutorial_22 "이곳은 전투 아이템 슬롯입니다."
    SN_0_60   〃                       ↔ Tutorial_24 "이곳은 장착 젬 슬롯 입니다."
    SN_0_63   〃                       ↔ Tutorial_27 "이곳은 스킬 슬롯입니다."
    SN_0_77   `stand/stand1.png`+화살표2 ↔ Tutorial_41 "드래곤 머리 위로 이상한 말풍선이"
    SN_0_81   —                        ↔ Tutorial_45 "정말 수고하셨습니다!"

### ⚠️ `setScNextArrow` 의 인자 순서 (Ghidra 인자 밀림 주의)

원형 주석은 `setScNextArrow(CCPoint, int, float, CCNode*)` 인데 디컴프 시그니처는
`(float param_1, ScenarioLayer *this, undefined8 param_3, int param_4, long *param_5)` 다.
본문을 읽으면 실제 의미는:
    param_1 = **지연(초)**            0x3e99999a=0.3 · 0x3f000000=0.5 · 0=즉시
    param_3 = 위치(CCPoint)
    param_4 = **회전(도)**            0x2d=45 · 0x5a=90 · 0=0 · 0xb4=180 은 회전 대신 `setFlipX(true)`
    param_5 = 부모(0 이면 `this` 의 tag 0x71 자식에 붙인다)
프레임은 `common/btn_arrow2.png`, tag 0x65, 초기 opacity 0.
동작 = `Delay(param_1)` → `Spawn(FadeIn(0.3), CallFuncN(setArrowForever))`,
`setArrowForever` = `RepeatForever(ScaleTo(0.5,1.5), ScaleTo(0.5,1.0))` — 맥동.

## 하는 일

`setNextSelecteMode` 본문을 `memcmp("SN_0_…")` 경계로 잘라 블록마다 위 리터럴을 긁어
스텝 표로 만든다. **추측하지 않는다** — 못 읽은 인자는 아예 안 적는다(널 필드 금지).

    python scripts/tools/extract_tutorial_flow.py          # data/tutorial_flow.json 생성
    python scripts/tools/extract_tutorial_flow.py --dry    # 표만 출력
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "data" / "tutorial_flow.json"
STRINGS = REPO / "DV2" / "string" / "stringsData_KR.xml"

## 대사 인덱스 → 문자열 키. 위 §🔑 참조.
PROLOGUE_MAX = 34          # <PrologueTalk0..34>
TUTORIAL_OFFSET = 36       # 인덱스 N(≥37) → <Tutorial_(N-36)>

## 대상 프레임 → 우리 씬이 등록한 안내 대상 id(`guide_target`). 프레임이 곧 근거다.
FRAME_TARGET = {
    "scene/worldmap/ma_btn_cave_image.png": "cave",
    "scene/cave/bag.png": "bag",
    "scene/cave/book.png": "book",
    "scene/cave/card.png": "card",
    "stand/stand1.png": "stand",
}
## 프레임 리터럴이 없는 스텝의 대상 — **원작 대사가 무엇을 가리키는지 말해 준다**.
## 각 항목의 근거를 대사 원문으로 남긴다(추측 아님, 문면 근거).
TALK_TARGET = {
    "SN_0_45": ("dragon_list", "Tutorial_9 '동굴 왼쪽에서 내가 갖고 있는 드래곤들을 볼 수 있습니다.'"),
    "SN_0_48": ("skin", "Tutorial_12 '동굴의 스킨과 드래곤의 스탠드를 변경하는 아이콘입니다.'"),
    "SN_0_58": ("slot_item", "Tutorial_22 '이곳은 전투 아이템 슬롯입니다.'"),
    "SN_0_60": ("slot_gem", "Tutorial_24 '이곳은 장착 젬 슬롯 입니다.'"),
    "SN_0_63": ("slot_skill", "Tutorial_27 '이곳은 스킬 슬롯입니다.'"),
    "SN_0_69": ("slot_gem", "Tutorial_33 '젬과 전투 아이템을 모두 장착했어요!'"),
}

BRANCH = re.compile(r'memcmp\(\w+,"(SN_0_[0-9A-Za-z_]+)"')
ARROW = re.compile(r'setScNextArrow\(\(ScenarioLayer \*\)(0x[0-9a-f]+|0),\w+,\w+,(0x[0-9a-f]+|\d+),(\w+)\)')
FRAME = re.compile(r'"((?:scene|common|stand)/[A-Za-z0-9_/]+\.png)"')
ADVENTURE = re.compile(r'AdventureScene::scene\((\d+),(\d+)')


def f32(h: str) -> float:
    """디컴프가 float 를 정수 리터럴로 흘린 것 — 비트 재해석."""
    import struct
    v = int(h, 16)
    if v == 0:
        return 0.0
    return round(struct.unpack("<f", struct.pack("<I", v))[0], 3)


def talk_key(idx: int) -> str | None:
    if idx <= PROLOGUE_MAX:
        return "PrologueTalk%d" % idx
    n = idx - TUTORIAL_OFFSET
    return "Tutorial_%d" % n if n >= 1 else None


def load_strings() -> dict[str, str]:
    text = STRINGS.read_text(encoding="utf-8", errors="replace")
    out = {}
    for k, v in re.findall(r"<(PrologueTalk\d+|Tutorial_\d+)>(.*?)</\1>", text, re.S):
        out[k] = v.replace("&#10;", "\n").strip()
    return out


def main() -> int:
    dry = "--dry" in sys.argv
    body = subprocess.run(
        [sys.executable, str(REPO / "scripts/tools/decomp_fn.py"), "ScenarioLayer", "setNextSelecteMode"],
        capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    lines = [l.strip() for l in body.split("\n") if l.strip()]

    # memcmp 경계로 블록 분할
    marks = [(i, m.group(1)) for i, l in enumerate(lines) for m in [BRANCH.search(l)] if m]
    if not marks:
        print("SN_0_* 분기를 못 찾았다 — 디컴프가 바뀌었는지 확인할 것"); return 1
    steps = {}
    for j, (i, key) in enumerate(marks):
        end = marks[j + 1][0] if j + 1 < len(marks) else len(lines)
        blk = "\n".join(lines[i:end])
        st: dict = {}
        arrows = []
        for delay, rot, parent in ARROW.findall(blk):
            r = int(rot, 16) if rot.startswith("0x") else int(rot)
            a = {"delay": f32(delay), "flip_x": r == 180}
            if r != 180:
                a["rot"] = r
            if parent != "0":
                a["on_target"] = True     # 원작은 대상 노드의 자식으로 붙인다(z=999999)
            arrows.append(a)
        if arrows:
            st["arrows"] = arrows
        frames = [f for f in dict.fromkeys(FRAME.findall(blk)) if not f.startswith("scene/cave/tap_")]
        if frames:
            st["frames"] = frames
        # 화살표 대상. **TALK_TARGET 이 우선**한다 — memcmp 블록 경계가 정확히 그 분기의 끝이라는
        # 보장이 없어(다음 분기의 리터럴이 딸려 오는 일이 있다) 프레임만 믿으면 어긋난다.
        # 실측: `SN_0_48` 은 프레임으로는 book 이 잡히는데 대사는 Tutorial_12(스킨/단상)이고,
        # 바로 다음 `SN_0_51` 의 대사가 Tutorial_15 '드래곤 도감입니다!' 다 ⇒ book 은 흘러든 것.
        if key in TALK_TARGET:
            st["target"], st["target_basis"] = TALK_TARGET[key]
        else:
            for f in frames:
                if f in FRAME_TARGET:
                    st["target"] = FRAME_TARGET[f]
                    st["target_basis"] = "원작 프레임 %s" % f
                    break
        if "CaveScene::scene(0)" in blk:
            st["action"] = "enter_cave"
        elif "CaveScene::onClickNicName" in blk:
            st["action"] = "name_dragon"
        elif "setFinishTutorial" in blk:
            st["action"] = "finish"
        m = ADVENTURE.search(blk)
        if m:
            st["action"] = "adventure"
            st["field"] = int(m.group(1))
            st["battle"] = int(m.group(2))
        if "PrologueEggBorn" in blk:
            st["action"] = "hatch_confirm"
        elif "ScenarioDialogLayer::create" in blk and "action" not in st:
            st["action"] = "dialog"
        # 대사 인덱스 = 키의 첫 숫자
        idx = int(key.split("_")[2])
        st["talk_index"] = idx
        tk = talk_key(idx)
        if tk:
            st["talk"] = tk
        steps[key] = st

    strings = load_strings()
    # 대사 원문을 스텝에 실어 둔다 — `scenario.prologue` 와 같은 취급(원작 문자열의 데이터화).
    # 런타임이 별도 문자열 파이프라인 없이 이 파일만 읽으면 되게 한다.
    for st in steps.values():
        t = strings.get(st.get("talk", ""))
        if t:
            st["text"] = t
    doc = {
        "_re_basis": ("원작 ScenarioLayer::setNextSelecteMode @016caaac 의 SN_0_* 분기를 그대로 뽑은 표. "
                      "SN 번호 = 시나리오 0 대사 인덱스(0~34=PrologueTalk, 37~=Tutorial_(N-36)). "
                      "추출 = scripts/tools/extract_tutorial_flow.py. 화살표 인자 의미와 오프셋 근거는 그 파일 주석."),
        "talk_offset": {"prologue_max": PROLOGUE_MAX, "tutorial_offset": TUTORIAL_OFFSET},
        "steps": steps,
    }
    order = sorted(steps, key=lambda k: (int(k.split("_")[2]),
                                         k.split("_")[3] if len(k.split("_")) > 3 else ""))
    doc["order"] = order

    print("%-18s %-11s %-22s %s" % ("step", "action", "arrows", "talk"))
    for k in order:
        s = steps[k]
        arr = ",".join(("flip" if a.get("flip_x") else "rot%d" % a.get("rot", 0)) +
                       ("@%.1fs" % a["delay"] if a["delay"] else "") for a in s.get("arrows", []))
        line = strings.get(s.get("talk", ""), "").split("\n")[0][:46]
        print("%-18s %-11s %-22s %s" % (k, s.get("action", "-"), arr or "-",
                                        "%s %s" % (s.get("talk", "-"), line)))
    if not dry:
        OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
        print("\n→ %s (%d스텝)" % (OUT.relative_to(REPO), len(steps)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
