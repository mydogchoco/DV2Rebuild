#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spine_export

REPO = Path(__file__).resolve().parents[2]

SPINES = [
    ("DV2/480/skill/ultimate/holy/holy_wing_spine.spine_json", "scenes/fx/ultimate_holy_wing.tscn"),
    ("DV2/480/skill/ultimate/shadow/shadow_spine.spine_json", "scenes/fx/ultimate_shadow.tscn"),
]

def main() -> int:
    import os
    os.chdir(REPO)
    for src, scene in SPINES:
        if not Path(src).exists():
            print("[skip] 원본 없음: %s" % src)
            continue
        out = spine_export.export_scene(src)
        print("  %s → %s   (씬: %s)" % (src, out, scene))
    print("\n다음: godot --headless --path . --import")
    for src, scene in SPINES:
        name = Path(src).stem
        print("      godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- "
              "assets/converted/scenespine_%s/scene.json %s" % (name, scene))
    return 0

if __name__ == "__main__":
    sys.exit(main())
