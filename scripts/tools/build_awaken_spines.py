#!/usr/bin/env python
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export

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
        except Exception as exc:
            errors.append((did, repr(exc)))
    print(f"변환 {ok} · 이미 있어 건너뜀 {skipped} · 실패 {len(errors)}")
    for did, e in errors[:20]:
        print(f"   ERROR dragon {did}: {e}")
    print("다음 단계: godot --headless --path . --script res://scripts/tools/build_all.gd")
    return 0

if __name__ == "__main__":
    sys.exit(main())
