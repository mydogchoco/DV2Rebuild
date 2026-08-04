#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""각성기(`UltimateLayer`) 레시피 추출 — 속성 9종의 **좌표·프레임·타이밍 전량**을 기계로 뽑는다.

왜
--
각성기 연출은 서버가 아니라 **클라가 100% 갖고 있다**(사용자 지적 2026-08-05). 그런데 우리
이식분은 "바닥 링 + 가장 긴 프레임 계열" 골격뿐이라 원작의 1/20 도 안 나온다. 원작 한 속성이
스프라이트 수백 장을 **개별 좌표·개별 지연**으로 터뜨리기 때문에 손으로 옮길 양이 아니다.

    예) 불 = 폭발 지점 20곳 × (explosion + earthquake + fillar + 돌 14~19개)
        지연 0.25s 부터 5.1s 까지 20단 캐스케이드, 지점마다 z 층이 따로 있다.

⇒ 디컴프에서 **레시피로 뽑아** `data/recipes/ultimate_layer.json` 에 싣고, 렌더가 그걸 읽어
   그리게 한다(프로젝트의 스켈레톤-우선 파이프라인과 같은 방식).

무엇을 뽑나
----------
`init<El>` / `init<El>_C` 에서:
  · batch      — `CCSpriteBatchNode::create("<아틀라스>", <용량>)`
  · anchors    — `CCPoint::CCPoint(stack, X, Y)` 누적 → `CCPoint::operator=((CCPoint*)(this+off), …)`
                 원작은 **레이어 중심 + (dir*dx, dy) + (0,50)** 처럼 항을 더해 만든다.
                 그 항들을 순서대로 문자열로 보존한다(수식 그대로가 근거다).
  · consts     — `*(undefined8 *)(this + off) = 0x…` 8바이트 상수쓰기 = float 2개 또는 int 2개.
                 불의 경우 0x378~ 이 **폭발 지연 20개**, 0x3c8~ 이 **z 층 20개**였다.
  · frames     — `FUN_01001244("<png>")`(프레임명 룩업) · `CCString::createWithFormat("<fmt>", N)`
  · anims      — `CCAnimation::create()` + `addSpriteFrame` 묶음 + 지연(`vtable+0x38`, 하위 float)
  · addChild   — 배치노드에 붙는 z/tag 수식

`run<El>` / `run<El>_C` / `action<El>_C` / `damage<El>_C` 에서:
  · timeline   — `CC*::create(...)` 호출을 **순서대로** + `runAction(node, …)` 경계
                 (Ghidra 가 시퀀스 조립을 지역변수로 흩어 놓아 완전 복원은 불가 —
                  순서와 인자는 정확하므로 사람이 읽어 안무를 재구성하는 입력으로 쓴다)

사용
----
    python scripts/tools/extract_ultimate_recipe.py            # data/recipes/ultimate_layer.json
    python scripts/tools/extract_ultimate_recipe.py --md       # 사람이 읽는 표도 함께
    python scripts/tools/extract_ultimate_recipe.py --el fire  # 한 속성만 화면에 덤프
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp" / "UltimateLayer.c"
OUT_JSON = REPO / "data" / "recipes" / "ultimate_layer.json"
OUT_MD = REPO / "docs" / "ref" / "design" / "ultimate_layer_recipe.md"

# `setColosseum`/`setElement` 의 switch 순서 = 원작 속성 번호.
ELEMENTS = {
    1: "aqua", 2: "chaos", 3: "dark", 4: "earth", 5: "fire",
    6: "holy", 7: "light", 8: "wind", 9: "shadow",
}
CAP = {e: e.capitalize() for e in ELEMENTS.values()}

HEAD = re.compile(r"^/\* ==== (?P<name>[A-Za-z_0-9~]+) @ (?P<addr>[0-9a-fA-Fx]+) \(size=(?P<size>\d+)\) ==== \*/")

RE_BATCH = re.compile(r'CCSpriteBatchNode::create\("([^"]+)",(0x[0-9a-f]+|\d+)\)')
RE_POINT = re.compile(r"CCPoint::CCPoint\((?:\(CCPoint \*\))?[A-Za-z_0-9]+,(.+?)\);")
RE_ASSIGN = re.compile(r"CCPoint::operator=\(\(CCPoint \*\)\(this \+ (0x[0-9a-f]+|\d+)\)")
RE_CONST8 = re.compile(r"\*\(undefined8 \*\)\(this \+ (0x[0-9a-f]+|\d+)\) = (0x[0-9a-f]+);")
RE_CONST4 = re.compile(r"\*\(undefined4 \*\)\(this \+ (0x[0-9a-f]+|\d+)\) = (0x[0-9a-f]+);")
RE_FRAME = re.compile(r'FUN_[0-9a-f]+\("([^"]+\.png)"\)')
RE_FMT = re.compile(r'CCString::createWithFormat\("([^"]+)",(\d+)\)')
RE_ANIM_NEW = re.compile(r"(this_\d+) = \(CCAnimation \*\)CCAnimation::create\(\)")
RE_ANIM_ADD = re.compile(r"CCAnimation::addSpriteFrame\((this_\d+),")
RE_ANIM_DELAY = re.compile(r"\(\*\*\(code \*\*\)\(\*\(long \*\)(this_\d+) \+ 0x38\)\)\((0x[0-9a-f]+),")
RE_ADDCHILD = re.compile(r"\(\*\(long \*\*\)\(this \+ (?:0x[0-9a-f]+)\),\s*(\w+),(.+)$")
RE_ACTION = re.compile(r"(CC[A-Za-z]+)::create\((.*?)\);")
RE_RUNACTION = re.compile(r"CCNode::runAction\(\(?(?:CCNode \*\))?([A-Za-z_0-9]+),")
RE_SPINE = re.compile(r'"([^"]+\.spine_json)"')
RE_PARTICLE = re.compile(r'"([^"]+\.plist)"')


def f32(word: int) -> float:
    return struct.unpack("<f", struct.pack("<I", word & 0xFFFFFFFF))[0]


def nice(v: float) -> float:
    r = round(v, 4)
    return int(r) if r == int(r) else r


def blocks() -> dict:
    """{함수명: [줄…]} — 같은 이름이 여러 번이면 **가장 큰 본문**을 쓴다(썽크 16B 배제)."""
    out, cur, best = {}, None, {}
    for line in DECOMP.read_text(encoding="utf-8", errors="replace").splitlines():
        m = HEAD.match(line)
        if m:
            if cur and (cur[0] not in best or best[cur[0]] < cur[1]):
                out[cur[0]] = cur[2]
                best[cur[0]] = cur[1]
            cur = [m["name"], int(m["size"]), []]
        elif cur:
            cur[2].append(line)
    if cur and (cur[0] not in best or best[cur[0]] < cur[1]):
        out[cur[0]] = cur[2]
    return out


def clean_expr(s: str) -> str:
    """Ghidra 임시변수를 읽히는 이름으로. 근거가 되는 수식 모양은 보존한다."""
    s = s.strip()
    # getContentSize() 접근 — `(**(code **)(*(long *)this + 0x110))(this)` 계열
    s = re.sub(r"\*\(float \*\)\(\w+ \+ 4\)", "H", s)
    s = re.sub(r"\*pfVar\d+", "W", s)
    # ⚠️ 방향 변수를 **먼저** 바꾼다 — `fVar1[0-9]`(폭) 규칙이 fVar18 까지 삼켜
    #    `dir * W * 0.25` 가 `W * W * 0.25` 로 나오던 것을 2026-08-05 교정.
    s = re.sub(r"fVar18\b", "dir", s)
    s = re.sub(r"fVar1[0-9]", "W", s)
    s = re.sub(r"\s+", " ", s)
    return s


RE_ADD = re.compile(r"\+ 0x198\)\)\((?:\*\(long \*\*\)\(this \+ 0x[0-9a-f]+\)|\w+),(\w+),(.+?),(.+?)\);")
RE_SCALE = re.compile(r"\+ 0x(?:158|160)\)\)\((\w+),(.+?)\);")
RE_LOOPEND = re.compile(r"\}\s*while\s*\((.+)\);")


def parse_init(lines: list[str]) -> dict:
    """init<El> / init<El>_C — 자산·좌표·상수 + **순서 있는 연출 스트림**(`ops`).

    속성마다 좌표를 두는 방식이 다르다(불은 멤버 슬롯 20개, 땅은 기준점+오프셋 직접 배치).
    그래서 의미를 모델링하지 않고 **일어난 순서 그대로** 남긴다 — 사람이 읽어 안무를 복원하는
    입력이고, 이게 근거다.
    """
    rec: dict = {"batch": [], "anchors": [], "consts": [], "frames": [], "anims": [],
                 "addchild": [], "spines": [], "particles": [], "ops": []}
    pend: list[str] = []
    anims: dict[str, dict] = {}
    for ln in lines:
        # ── 순서 스트림 ──────────────────────────────────────────────────
        m = RE_FRAME.search(ln)
        if m:
            rec["ops"].append("FRAME %s" % m.group(1).split("/")[-1])
        for m2 in RE_POINT.finditer(ln):
            rec["ops"].append("PT (%s)" % clean_expr(m2.group(1)))
        m = RE_ADD.search(ln)
        if m:
            rec["ops"].append("ADD z=%s tag=%s" % (m.group(2).strip(), m.group(3).strip()))
        if "do {" in ln:
            rec["ops"].append("LOOP {")
        m = RE_LOOPEND.search(ln)
        if m:
            rec["ops"].append("} while %s" % m.group(1).strip())
        m = RE_CONST8.search(ln) or RE_CONST4.search(ln)
        if m:
            rec["ops"].append("CONST 0x%x" % int(m.group(1), 0))
    for ln in lines:
        m = RE_BATCH.search(ln)
        if m:
            rec["batch"].append({"atlas": m.group(1), "capacity": int(m.group(2), 0)})
        for m in RE_POINT.finditer(ln):
            pend.append(clean_expr(m.group(1)))
        m = RE_ASSIGN.search(ln)
        if m:
            rec["anchors"].append({"slot": m.group(1), "terms": pend[:]})
            pend = []
        m = RE_CONST8.search(ln)
        if m:
            off, word = int(m.group(1), 0), int(m.group(2), 16)
            lo, hi = word & 0xFFFFFFFF, (word >> 32) & 0xFFFFFFFF
            rec["consts"].append({"off": off, "words": [lo, hi],
                                  "as_float": [nice(f32(lo)), nice(f32(hi))],
                                  "as_int": [lo, hi]})
        m = RE_CONST4.search(ln)
        if m:
            off, word = int(m.group(1), 0), int(m.group(2), 16)
            rec["consts"].append({"off": off, "words": [word],
                                  "as_float": [nice(f32(word))], "as_int": [word]})
        for m in RE_FRAME.finditer(ln):
            if m.group(1) not in rec["frames"]:
                rec["frames"].append(m.group(1))
        m = RE_ANIM_NEW.search(ln)
        if m:
            anims.setdefault(m.group(1), {"var": m.group(1), "frames": [], "delay": None})
        m = RE_FMT.search(ln)
        if m:
            pend_fmt = m.group(1) % int(m.group(2)) if "%d" in m.group(1) else m.group(1)
            rec.setdefault("_fmt", []).append(pend_fmt)
        m = RE_ANIM_ADD.search(ln)
        if m:
            a = anims.setdefault(m.group(1), {"var": m.group(1), "frames": [], "delay": None})
            fmts = rec.get("_fmt", [])
            if fmts:
                a["frames"].append(fmts.pop(0))
        m = RE_ANIM_DELAY.search(ln)
        if m and m.group(1) in anims:
            anims[m.group(1)]["delay"] = nice(f32(int(m.group(2), 16)))
        for m in RE_SPINE.finditer(ln):
            if m.group(1) not in rec["spines"]:
                rec["spines"].append(m.group(1))
        for m in RE_PARTICLE.finditer(ln):
            if m.group(1) not in rec["particles"]:
                rec["particles"].append(m.group(1))
    rec.pop("_fmt", None)
    rec["anims"] = list(anims.values())
    return rec


def parse_run(lines: list[str]) -> list[dict]:
    """run/action/damage — CC* 액션 호출을 **순서대로**. runAction 을 만나면 한 덩이로 끊는다."""
    out: list[dict] = []
    cur: list[str] = []
    for ln in lines:
        for m in RE_ACTION.finditer(ln):
            kind, args = m.group(1), m.group(2)
            if kind in ("CCString", "CCSpriteBatchNode", "CCAnimation"):
                continue
            cur.append("%s(%s)" % (kind, clean_expr(args)))
        m = RE_RUNACTION.search(ln)
        if m:
            out.append({"target": m.group(1), "actions": cur})
            cur = []
    if cur:
        out.append({"target": "(미귀속)", "actions": cur})
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", action="store_true", help="사람이 읽는 표도 쓴다")
    ap.add_argument("--el", help="한 속성만 화면에 덤프")
    args = ap.parse_args()

    fns = blocks()
    recipe: dict = {
        "_source": "docs/ref/orig_code/decomp/UltimateLayer.c",
        "_tool": "scripts/tools/extract_ultimate_recipe.py",
        "_note": "각성기 연출 레시피. 좌표는 원작 수식 그대로(W=레이어폭 H=레이어높이 dir=시전 방향 ±1).",
        "elements": {},
    }
    for no, el in ELEMENTS.items():
        c = CAP[el]
        e: dict = {"no": no}
        for suffix, key in (("", "init"), ("_C", "init_C")):
            name = "init%s%s" % (c, suffix)
            if name in fns:
                e[key] = parse_init(fns[name])
        for name, key in (("run%s" % c, "run"), ("run%s_C" % c, "run_C"),
                          ("action%s_C" % c, "action_C"), ("damage%s_C" % c, "damage_C")):
            if name in fns:
                e[key] = parse_run(fns[name])
        recipe["elements"][el] = e

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(recipe, ensure_ascii=False, indent=1), encoding="utf-8")
    print("wrote %s" % OUT_JSON.relative_to(REPO))

    for el, e in recipe["elements"].items():
        ini = e.get("init", {})
        cap = ini.get("batch", [{}])
        print("  %-7s 앵커 %2d · 프레임 %2d · 애니 %d · 상수쓰기 %2d · 배치용량 %s" % (
            el, len(ini.get("anchors", [])), len(ini.get("frames", [])),
            len(ini.get("anims", [])), len(ini.get("consts", [])),
            cap[0].get("capacity", "-") if cap else "-"))

    if args.el:
        print(json.dumps(recipe["elements"][args.el], ensure_ascii=False, indent=1))
    if args.md:
        write_md(recipe)
    return 0


def write_md(recipe: dict) -> None:
    L = ["# 각성기 `UltimateLayer` 레시피 (기계 추출)", "",
         "> 생성: `python scripts/tools/extract_ultimate_recipe.py --md` — 손으로 고치지 말 것.",
         "> 좌표 수식의 `W`/`H` = 레이어 contentSize, `dir` = 시전 방향(±1).", ""]
    for el, e in recipe["elements"].items():
        L.append("## %s (원작 번호 %d)" % (el, e["no"]))
        for key, label in (("init", "init"), ("init_C", "init_C(콜로세움 추가분)")):
            ini = e.get(key)
            if not ini:
                continue
            L.append("### %s" % label)
            for b in ini["batch"]:
                L.append("- 배치노드 `%s` 용량 %d" % (b["atlas"], b["capacity"]))
            if ini["frames"]:
                L.append("- 프레임 %d종: %s" % (len(ini["frames"]),
                                              ", ".join(f.split("/")[-1] for f in ini["frames"])))
            for a in ini["anims"]:
                L.append("- 애니 `%s` %d프레임 지연 %s: %s" % (
                    a["var"], len(a["frames"]), a["delay"],
                    ", ".join(f.split("/")[-1] for f in a["frames"])))
            if ini["spines"]:
                L.append("- 스파인: %s" % ", ".join(ini["spines"]))
            if ini["anchors"]:
                L.append("")
                L.append("| 슬롯 | 좌표 항(순서대로 더한다) |")
                L.append("|---|---|")
                for an in ini["anchors"]:
                    L.append("| `%s` | %s |" % (an["slot"], " + ".join("`%s`" % t for t in an["terms"])))
            if ini["consts"]:
                L.append("")
                L.append("| 멤버 | float | int |")
                L.append("|---|---|---|")
                for c in ini["consts"]:
                    L.append("| `0x%x` | %s | %s |" % (c["off"], c["as_float"], c["as_int"]))
            L.append("")
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)
    OUT_MD.write_text("\n".join(L), encoding="utf-8")
    print("wrote %s" % OUT_MD.relative_to(REPO))


if __name__ == "__main__":
    sys.exit(main())
