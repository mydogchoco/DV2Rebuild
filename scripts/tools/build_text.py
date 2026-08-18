from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "data"
OUT = DATA / "text"
XML = REPO / "DV2" / "string" / "stringsData_KR.xml"

def load_bundle() -> dict:
    if not XML.exists():
        return {}
    raw = XML.read_text(encoding="utf-8", errors="replace")
    out = {}
    for m in re.finditer(r"<([A-Za-z_]\w*)>([^<]*)</\1>", raw):
        out[m.group(1)] = unescape(m.group(2).strip())
    return out

def unescape(s: str) -> str:
    s = re.sub(r"&#(\d+);", lambda m: chr(int(m.group(1))), s)
    s = re.sub(r"&#x([0-9a-fA-F]+);", lambda m: chr(int(m.group(1), 16)), s)
    for a, b in (("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'),
                 ("&apos;", "'"), ("&amp;", "&")):
        s = s.replace(a, b)
    return s

def restore_scenario(bundle: dict) -> tuple[dict, int, int]:
    doc = json.loads((DATA / "scenario.json").read_text(encoding="utf-8"))
    hit = miss = 0
    for no, sc in (doc.get("scenarios") or {}).items():
        for part in sc.get("parts") or []:
            m = part.get("m")
            gender = str(part.get("gender") or "")
            for ln in part.get("lines") or []:
                k = ln.get("k")
                if k is None:
                    continue
                if gender == "F":
                    name = f"ScenarioTalk{no}_F_{k}"
                elif m is not None:
                    name = f"ScenarioTalk{no}_{m}_{k}"
                else:
                    name = f"ScenarioTalk{no}_{k}"
                if name in bundle:
                    ln["text"] = bundle[name]
                    hit += 1
                else:
                    miss += 1
    pro = doc.get("prologue")
    if isinstance(pro, list):
        for i in range(len(pro)):
            key = f"PrologueTalk{i}"
            if key in bundle:
                pro[i] = bundle[key]
                hit += 1
    return doc, hit, miss

def restore_by_key(fname: str, bundle: dict) -> tuple[dict, int, int]:
    p = DATA / fname
    if not p.exists():
        return {}, 0, 0
    doc = json.loads(p.read_text(encoding="utf-8"))
    hit = miss = 0

    def walk(node):
        nonlocal hit, miss
        if isinstance(node, dict):
            for kk in ("talk_key", "name_key", "key"):
                v = node.get(kk)
                if isinstance(v, str) and v and v in bundle:
                    target = {"talk_key": "lines", "name_key": "name"}.get(kk)
                    if target and target in node:
                        val = bundle[v]
                        node[target] = [val] if isinstance(node[target], list) else val
                        hit += 1
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc)
    return doc, hit, miss

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    bundle = load_bundle()
    if not bundle:
        print(f"문자열 번들을 찾지 못했다: {XML}")
        print("원작 추출본을 DV2/ 에 넣은 뒤 다시 실행할 것.")
        return 1
    print(f"번들 항목 {len(bundle):,}개")

    if args.check:
        n = sum(1 for k in bundle if k.startswith(("ScenarioTalk", "PrologueTalk")))
        print(f"  스토리 대사 키 {n:,}개 복원 가능")
        return 0

    OUT.mkdir(exist_ok=True)
    doc, hit, miss = restore_scenario(bundle)
    (OUT / "scenario.json").write_text(
        json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"scenario.json: 대사 {hit:,}줄 복원 (번들에 없는 줄 {miss:,})")

    for f in ("npc_lines.json", "npc_talk.json"):
        d, h, _ = restore_by_key(f, bundle)
        if h:
            (OUT / f).write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n",
                                 encoding="utf-8", newline="\n")
            print(f"{f}: {h}건 복원")

    print("\n남은 문자열(도감 설명·아이템 설명 등)은 번들 밖이라 이 경로로 복원되지 않는다.")
    print("완료. 게임을 다시 실행하면 반영된다.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
