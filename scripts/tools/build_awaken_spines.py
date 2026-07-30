#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""각성체 스파인 일괄 변환 — `dragon_<id>_e_spine.spine_json` → 중간 JSON.

왜
--
각성 단계 전용 아트는 두 갈래다:
  · 초상 `dragon/<id>/box_evolution.png`  → 137종 **전부 변환돼 있다**
  · 스파인 `dragon_<id>_e_spine.spine_json` → **1종(고대신룡)만 변환돼 있었다**
그래서 도감·연출이 각성 스파인을 못 찾아 성체로 폴백했고, 반대로 오라성체 칸이 각성
스파인을 쓰던 버그(2026-07-30 수정)와 겹쳐 단계 구분이 무너져 보였다.

원작 근거: `Dragon::getImagePathSpineJson`(Dragon.c:9317)이 **각성 플래그가 설 때만**
`dragon/dragon_%d_e_spine.spine_json` 을 고른다(45레벨이어도 각성 전이면 `_adult_spine`).
각성 결과 연출(`scripts/ui/evol_layer.gd:203`)도 이 씬을 세운다.

2단 파이프라인의 1단이다 — 이걸 돌린 뒤 씬을 만들어야 한다:

    python scripts/tools/build_awaken_spines.py
    godot --headless --path . --script res://scripts/tools/build_all.gd
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export  # noqa: E402

SRC = "DV2/480/dragon"
STAGE = "e"


def main() -> int:
    ids = []
    for fn in sorted(os.listdir(SRC)):
        if fn.endswith(f"_{STAGE}_spine.spine_json") and fn.startswith("dragon_"):
            ids.append(fn.split("_")[1])
    print(f"원본 각성체 스파인: {len(ids)}종")

    ok = 0
    skipped = 0
    errors = []
    for did in ids:
        out = os.path.join("assets/converted", f"dragon_{did}", f"{STAGE}.json")
        if os.path.exists(out):
            skipped += 1
            continue
        try:
            spine_export.export(did, STAGE, "all")
            ok += 1
        except Exception as exc:                      # noqa: BLE001
            errors.append((did, repr(exc)))
    print(f"변환 {ok} · 이미 있어 건너뜀 {skipped} · 실패 {len(errors)}")
    for did, e in errors[:20]:
        print(f"   ERROR dragon {did}: {e}")
    print("다음 단계: godot --headless --path . --script res://scripts/tools/build_all.gd")
    return 0


if __name__ == "__main__":
    sys.exit(main())
