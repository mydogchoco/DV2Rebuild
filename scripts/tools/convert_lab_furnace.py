"""일회성: MakeSkillLayer/BreakDownSkillLayer의 마모루딕 랩 스파인 변환.
근거: MakeSkillLayer.c drawSpineCenter('scene/mamorudiclab/furnace/furnace_normal.spine_json',
      'scene/mamorudiclab/furnace/normal_spine.img_plist') setAnimation('animation',loop).
      BreakDownSkillLayer.c: machine/bg_black_island.spine_json + machine/normal_spine.img_plist."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import spine_export

SRC = "DV2/480/scene/mamorudiclab"
JOBS = [
    ("lab_furnace", f"{SRC}/furnace/furnace_normal.spine_json", [f"{SRC}/furnace/normal_spine.img_plist"]),
    ("lab_machine", f"{SRC}/machine/bg_black_island.spine_json", [f"{SRC}/machine/normal_spine.img_plist"]),
]
for name, sj, atlases in JOBS:
    outdir = os.path.join("assets/converted", name)
    if not os.path.exists(sj):
        print("skip", name, "no json:", sj); continue
    spine_export.export("0", "fx", "all", sj_path=sj, atlas_paths=atlases, outdir=outdir)
    print("exported", name, "->", os.path.join(outdir, "fx.json"))
