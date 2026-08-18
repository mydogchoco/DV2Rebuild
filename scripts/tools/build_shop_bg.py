#!/usr/bin/env python3
from __future__ import annotations

import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "480" / "scene" / "shop" / "shop_bg.jpg"
DST = REPO / "assets" / "converted" / "shop_bg"

def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"원본 없음: {SRC}")
    DST.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC, DST / SRC.name)
    print(f"{SRC.name} → {DST / SRC.name}")

if __name__ == "__main__":
    main()
