#!/usr/bin/env python3
"""`data/gems.json` ↔ `docs/ref/wiki/gems.pdf` 툴팁 전수 대조.

## 왜 필요했나
사용자 질문(2026-07-27): "gems.pdf 에 각 젬 아이콘별로 효과 툴팁도 전부 적혀있는데,
우리 구현에 반영이 되어있나?" — 눈으로 훑어 "네" 라고 답하지 않기 위해 도구로 못박는다.

## 하는 일
위키 §2~§3 각 절의 "효과" 열("체력을 28만큼 올려준다." 등)을 파싱해 우리 `tiers[]` 와
**티어 단위로 1:1 비교**한다. 불일치가 있으면 목록을 찍고 exit 1.

`gems.json` 의 `_wiki_typos` 에 기재된 항목은 **의도된 정정**이므로 통과로 처리한다
(위키 오타를 절 제목대로 고친 것 — 예: 공격의 젬 1티어가 "체력을 7만큼"으로 적혀 있다).

    python scripts/tools/verify_gems_wiki.py          # 대조
    python scripts/tools/verify_gems_wiki.py --dump   # 위키에서 파싱한 표를 그대로 출력
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.exit("PyMuPDF 필요: python -m pip install pymupdf")

REPO = Path(__file__).resolve().parents[2]
PDF = REPO / "docs" / "ref" / "wiki" / "gems.pdf"
DATA = REPO / "data" / "gems.json"

# 위키 툴팁의 한글 스탯명 → 우리 키. cri/evd/blk 은 본디 %라 `_pct` 를 붙이지 않는다
# (Gem.SUB_KEYS 와 같은 규약).
KR = {"체력": "hp", "공격력": "att", "방어력": "def",
      "크리티컬 확률": "cri", "방어율": "blk", "회피율": "evd"}
PCTLESS = {"cri", "blk", "evd"}

# 의도된 정정(gems.json `_wiki_typos` 와 대응) — (젬 이름, 0-base 티어)
ACCEPTED_TYPOS = {
    ("공격의 젬", 0),
    ("체공젬", 0),
    ("방어의 소울젬", 9),   # 10단계 방어율 1% → 7% (사용자 확정, build_gems.TIER_OVERRIDES)
}


def parse_wiki() -> dict[str, list[dict]]:
    text = "".join(p.get_text() for p in fitz.open(PDF))
    # 목차가 본문과 같은 제목을 갖는다 → 본문(마지막 '2.1.1.')부터 자른다.
    starts = [m.start() for m in re.finditer(r"2\.1\.1\. 체력의 젬", text)]
    body = text[starts[-1]:]
    out: dict[str, list[dict]] = {}
    for sec in re.split(r"\n(?=\d\.\d(?:\.\d)?\. )", body):
        m = re.match(r"\d\.\d(?:\.\d)?\.\s*(.+)", sec)
        if not m:
            continue
        name = m.group(1).strip()
        rows: list[dict] = []
        for line in sec.splitlines():
            line = line.strip()
            if not line.endswith("올려준다."):
                continue
            d: dict[str, int] = {}
            # 샌즈 계열은 세 스탯을 한 줄에 쓴다. 두 형식이 섞여 있다:
            #   샌즈의 젬      "체력,공격력,방어력을 각각 28,4,4 만큼 올려준다."  (flat)
            #   샌즈의 소울젬  "체력,공격력,방어력을 6%만큼 올려준다."            (%)
            if line.startswith("체력,공격력,방어력을"):
                triple = re.search(r"각각\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", line)
                if triple:
                    d = {"hp": int(triple.group(1)), "att": int(triple.group(2)),
                         "def": int(triple.group(3))}
                else:
                    pm = re.search(r"(\d+)%", line)
                    if pm:
                        v = int(pm.group(1))
                        d = {"hp_pct": v, "att_pct": v, "def_pct": v}
            else:
                rest = re.sub(r"올려준다\.$", "", line).strip()
                last = None
                for part in (x.strip() for x in rest.split(",")):
                    sm = re.match(r"(.+?)을\s*(\d+)(%?)", part)
                    if sm and KR.get(sm.group(1).strip()):
                        last = KR[sm.group(1).strip()]
                        key = last if (last in PCTLESS or not sm.group(3)) else last + "_pct"
                        d[key] = int(sm.group(2))
                        continue
                    # "…, 5%만큼, …" 처럼 스탯명이 생략된 이어지는 항
                    pm2 = re.match(r"(\d+)(%?)만큼", part)
                    if pm2 and last:
                        key = last if (last in PCTLESS or not pm2.group(2)) else last + "_pct"
                        d[key] = int(pm2.group(1))
            if d:
                rows.append(d)
        if rows and name not in out:
            out[name] = rows
    return out


def main() -> None:
    wiki = parse_wiki()
    data = json.loads(DATA.read_text(encoding="utf-8"))
    gems = data["gems"]

    if "--dump" in sys.argv:
        for name, rows in wiki.items():
            print(f"== {name} ({len(rows)}티어)")
            for i, r in enumerate(rows, 1):
                print(f"   {i:2d} {r}")
        return

    bad, typo = 0, 0
    print(f"[verify_gems_wiki] 위키에서 젬 {len(wiki)}종 파싱")
    for name, rows in wiki.items():
        if name not in gems:
            print(f"  ! gems.json 에 없음: {name}")
            bad += 1
            continue
        ours = gems[name]["tiers"]
        if len(ours) != len(rows):
            print(f"  ! {name}: 티어 수 위키 {len(rows)} vs 우리 {len(ours)}")
            bad += 1
        for i, (w, o) in enumerate(zip(rows, ours)):
            ww = {k: v for k, v in w.items() if v}
            oo = {k: v for k, v in o.items() if v}
            if ww == oo:
                continue
            if (name, i) in ACCEPTED_TYPOS:
                print(f"  = {name} {i+1}티어: 위키 오타 정정분(문서화됨) 위키={ww} 우리={oo}")
                typo += 1
            else:
                print(f"  ! {name} {i+1}티어: 위키={ww} 우리={oo}")
                bad += 1

    total = sum(len(r) for r in wiki.values())
    print(f"[verify_gems_wiki] 티어 {total}행 대조 — 불일치 {bad}건 "
          f"(문서화된 위키 오타 정정 {typo}건은 제외)")
    if bad:
        sys.exit(1)
    print("  ✅ 위키 툴팁 전량이 data/gems.json 에 반영돼 있다.")


if __name__ == "__main__":
    main()
