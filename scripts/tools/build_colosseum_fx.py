#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spine_export

REPO = Path(__file__).resolve().parents[2]

SCENE_SPINES = [
    ("DV2/480/scene/colosseum/fight_spine.spine_json", "scenes/fx/colosseum_fight.tscn"),
    ("DV2/480/scene/colosseum/scene_colosseum_lightning_spine.spine_json",
     "scenes/fx/colosseum_lightning.tscn"),
    ("DV2/480/scene/colosseum/colo_waiting_spine.spine_json",
     "scenes/fx/colosseum_waiting.tscn"),
]

def main() -> int:
    import os
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    os.chdir(REPO)
    for src, out in SCENE_SPINES:
        if not Path(src).exists():
            print(f"[skip] 원본 없음: {src}")
            continue
        js = spine_export.export_scene(src)
        print(f"  -> {js}\n     다음: build_spine_scene.gd -- {js} {out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
