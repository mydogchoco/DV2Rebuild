#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""드래곤 울음소리 검수 시트 — `docs/input/dragons/dragons.csv` 의 voice 열을 **단계별로** 쪼갠다.

왜
--
원작 울음소리 배정은 서버 `info_dragon_v2` 의 voice 컬럼이라 유실됐다(`Dragon.c:13478-13526`).
우리는 지금 `data/dragon_voices.json` 으로 **임시 배정**(성체=id순 블록 순차 · 해치/해츨링=시드
난수)해 두고 쓰고 있는데, 사용자가 그것을 눈으로 검수하려면 표에 값이 보여야 한다.

무엇을
------
종전 `dragon voice` 한 칸을 **성장 단계 3칸**으로 바꾸고 현재 배정값을 채워 넣는다:

    voice_해치(baby) · voice_해츨링(child) · voice_성체(adult)

값은 `assets/music/voiceN.mp3` 의 N(원작 `Bgm.sfx("voice%d")`). 고칠 칸만 고치면 되고,
비우면 그 단계는 소리 없음으로 처리된다.

되돌리기(반영)
-------------
사용자가 채운 뒤 `--apply` 로 `data/dragon_voices.json` `voices` 를 시트 값으로 덮어쓴다.
그때 `pools`/`anchors`(임시 배정 알고리즘의 입력)는 그대로 남겨 두되 `_re_basis` 에
"사용자 검수 반영" 을 적는다.

    python scripts/tools/build_dragon_voice_sheet.py            # 시트에 현재 배정 채우기
    python scripts/tools/build_dragon_voice_sheet.py --apply    # 시트 → data/dragon_voices.json
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = ROOT / "docs" / "input" / "dragons" / "dragons.csv"
VOICES = ROOT / "data" / "dragon_voices.json"

OLD_COL = "dragon voice"
COLS = {
    "baby": "voice_해치(baby)",
    "child": "voice_해츨링(child)",
    "adult": "voice_성체(adult)",
}
STAGES = ["baby", "child", "adult"]


def read_csv() -> tuple[list[str], list[dict]]:
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        return list(r.fieldnames or []), list(r)


def write_csv(fields: list[str], rows: list[dict]) -> None:
    # 엑셀이 바로 열게 UTF-8 BOM(시트 규약, docs/input/INDEX.md).
    with CSV_PATH.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def fill() -> int:
    fields, rows = read_csv()
    voices: dict = json.loads(VOICES.read_text(encoding="utf-8")).get("voices", {})

    # 열 교체: `dragon voice` 자리에 단계 3칸을 끼워 넣는다(이미 있으면 그대로 둔다).
    new_fields: list[str] = []
    for c in fields:
        if c == OLD_COL:
            new_fields.extend(COLS[s] for s in STAGES)
        elif c in COLS.values():
            continue                      # 재실행 — 아래에서 한 번만 넣는다
        else:
            new_fields.append(c)
    if COLS["baby"] not in new_fields:     # 이미 교체된 시트를 다시 돌린 경우
        idx = len(new_fields)
        for c in fields:
            if c in COLS.values():
                idx = min(idx, new_fields.index(c) if c in new_fields else idx)
        new_fields.extend(COLS[s] for s in STAGES)

    filled = 0
    kept = 0
    for r in rows:
        did = (r.get("id") or "").strip()
        v: dict = voices.get(did, {})
        for s in STAGES:
            col = COLS[s]
            cur = (r.get(col) or "").strip()
            if cur:                        # 사용자가 이미 적은 값은 절대 덮지 않는다
                kept += 1
                continue
            n = v.get(s)
            r[col] = str(int(n)) if n not in (None, "") else ""
            if r[col]:
                filled += 1
        r.pop(OLD_COL, None)
    write_csv(new_fields, rows)
    print(f"시트 갱신: {CSV_PATH.relative_to(ROOT)}")
    print(f"  드래곤 {len(rows)}행 · 임시 배정 채움 {filled}칸 · 사용자 기입 보존 {kept}칸")
    print(f"  열: {' · '.join(COLS[s] for s in STAGES)}  (값 = assets/music/voiceN.mp3 의 N)")
    return 0


def apply() -> int:
    fields, rows = read_csv()
    if COLS["baby"] not in fields:
        print("시트에 voice 단계 열이 없다 — 먼저 인자 없이 실행해 열을 만들어라.", file=sys.stderr)
        return 1
    doc = json.loads(VOICES.read_text(encoding="utf-8"))
    out: dict = {}
    bad: list[str] = []
    for r in rows:
        did = (r.get("id") or "").strip()
        if not did:
            continue
        entry: dict = {}
        for s in STAGES:
            raw = (r.get(COLS[s]) or "").strip()
            if not raw:
                continue
            if not raw.isdigit():
                bad.append(f"id={did} {COLS[s]}='{raw}'")
                continue
            entry[s] = int(raw)
        if entry:
            out[did] = entry
    if bad:
        print("⚠️ 숫자가 아닌 칸 — 건너뜀:", *bad, sep="\n   ")
    doc["voices"] = out
    doc["_re_basis"] = (
        "유실(원작은 info_dragon_v2 의 voice 컬럼, Dragon.c:13478-13526). "
        "값은 docs/input/dragons/dragons.csv 의 voice_해치/해츨링/성체 열 = **사용자 검수분**이다"
        "(빈 칸은 그 단계 소리 없음). 채우기·반영 도구 = scripts/tools/build_dragon_voice_sheet.py. "
        "pools/anchors 는 최초 임시 배정에 쓴 입력이라 참고용으로 남겨 둔다."
    )
    VOICES.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"반영: {VOICES.relative_to(ROOT)} — voices {len(out)}종")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="시트 → data/dragon_voices.json 반영")
    a = ap.parse_args()
    sys.exit(apply() if a.apply else fill())
