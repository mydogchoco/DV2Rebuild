"""Estimate Spine attachment complexity: region vs mesh/weighted/deform.

Region attachments map cleanly to Sprite2D/Bone2D (easy custom player / native
convert). Mesh/weighted/FFD attachments need polygon deform (much harder).
"""
import json, glob, os, sys, random
from collections import Counter

ROOT = sys.argv[1] if len(sys.argv) > 1 else "DV2"
files = glob.glob(os.path.join(ROOT, "**", "*.spine_json"), recursive=True)
random.seed(1)
sample = random.sample(files, min(200, len(files)))

att_types = Counter()
files_with_mesh = 0
files_with_deform = 0
ver_cluster = Counter()

def walk_attachments(skins):
    # old format: skins is dict {skinName: {slotName: {attName: {att}}}}
    if isinstance(skins, dict):
        for skin in skins.values():
            if not isinstance(skin, dict): continue
            for slot in skin.values():
                if not isinstance(slot, dict): continue
                for att in slot.values():
                    if isinstance(att, dict):
                        yield att

for f in sample:
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception:
        continue
    sk = d.get("skeleton") or {}
    v = (sk.get("spine") or "noblock")
    ver_cluster[v.split(".")[0] + ("." + v.split(".")[1] if "." in v else "")] += 1
    has_mesh = False
    for att in walk_attachments(d.get("skins")):
        t = att.get("type", "region")
        att_types[t] += 1
        if t in ("mesh", "skinnedmesh", "weightedmesh", "linkedmesh"):
            has_mesh = True
    if has_mesh:
        files_with_mesh += 1
    # deform/FFD timelines live under animations[*].deform or .ffd
    anims = d.get("animations") or {}
    if isinstance(anims, dict) and any(
        isinstance(a, dict) and ("deform" in a or "ffd" in a) for a in anims.values()
    ):
        files_with_deform += 1

n = len(sample)
print(f"sampled files: {n}")
print("\n=== attachment types (all attachments in sample) ===")
for t, c in att_types.most_common():
    print(f"  {t}: {c}")
print(f"\nfiles containing >=1 mesh attachment: {files_with_mesh}/{n} ({100*files_with_mesh//n}%)")
print(f"files with deform/ffd timelines:      {files_with_deform}/{n} ({100*files_with_deform//n}%)")
print("\n=== version clusters in sample ===")
for v, c in ver_cluster.most_common():
    print(f"  {v}: {c}")
