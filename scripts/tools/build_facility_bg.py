#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC480 = REPO / "DV2" / "480"
CONV = REPO / "assets" / "converted"

JPGS = [
    ("scene/magicshop/magicshop_bg.jpg", "magicshop_bg"),
    ("scene/magicshop/magicshop_bg2.jpg", "magicshop_bg"),
    ("scene/laboratory/laboratory.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory0.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory1.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory3.jpg", "laboratory_bg"),
    ("scene/mamorudiclab/mamorudic_bg.jpg", "mamorudiclab_bg"),
    ("scene/promote/bg.jpg", "promote_bg"),
]

ATLASES = [
    ("scene/magicshop.img_plist", "magicshop_ui"),
    ("scene/magicshop/alchemy.img_plist", "magicshop_alchemy"),
    ("scene/mamorudiclab.img_plist", "mamorudiclab_ui"),
]

def main() -> None:
    n_jpg = n_atlas = 0
    for rel, sub in JPGS:
        src = SRC480 / rel
        if not src.exists():
            print(f"  ! 원본 없음: {rel}", file=sys.stderr)
            continue
        dst_dir = CONV / sub
        dst_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst_dir / src.name)
        n_jpg += 1
        print(f"  jpg  {rel} -> {sub}/{src.name}")
    for rel, sub in ATLASES:
        src = SRC480 / rel
        if not src.exists():
            print(f"  ! 원본 없음: {rel}", file=sys.stderr)
            continue
        r = subprocess.run(
            [sys.executable, str(REPO / "scripts" / "tools" / "cocos_export.py"), str(src), sub],
            cwd=REPO, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  ! 변환 실패 {rel}: {r.stderr.strip()[:200]}", file=sys.stderr)
            continue
        n_atlas += 1
        print(f"  atlas {rel} -> {sub}/")
    print(f"[build_facility_bg] jpg {n_jpg} / atlas {n_atlas}")

if __name__ == "__main__":
    main()
