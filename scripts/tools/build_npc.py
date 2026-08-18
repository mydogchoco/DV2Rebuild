#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cocos_export

REPO = Path(__file__).resolve().parents[2]
NPC_DIR = REPO / "DV2" / "480" / "npc"
OUT = REPO / "assets" / "converted"

def main() -> None:
    if not NPC_DIR.is_dir():
        raise SystemExit(f"원본 NPC 폴더 없음: {NPC_DIR}")
    wanted = set(sys.argv[1:])
    n = 0
    for plist in sorted(NPC_DIR.glob("*.img_plist")):
        name = plist.stem
        if wanted and name not in wanted:
            continue
        out_name = f"npc_{name}"
        if (OUT / out_name).is_dir():
            n += 1
            continue
        cocos_export.export(str(plist), out_name)
        n += 1
    print(f"NPC {n}종 변환/확인 완료 → assets/converted/npc_*")

if __name__ == "__main__":
    main()
