"""Phase 0 spike: detect the Spine JSON format version of DV2 assets.

Modern spine-godot targets Spine 4.x. DV2's spine_json predates 'skeleton.spine'
version fields, so we fingerprint the structure to estimate the era and decide
the animation strategy. Read-only; touches a sample of files.
"""
import json, glob, os, sys, random
from collections import Counter

ROOT = sys.argv[1] if len(sys.argv) > 1 else "DV2"
files = glob.glob(os.path.join(ROOT, "**", "*.spine_json"), recursive=True)
print(f"total spine_json: {len(files)}")
if not files:
    sys.exit(0)

random.seed(0)
sample = random.sample(files, min(60, len(files)))

versions = Counter()
anim_struct = Counter()    # dict vs list
skin_struct = Counter()
has_skeleton = 0
curve_styles = Counter()
all_anim_keys = Counter()

for f in sample:
    try:
        d = json.load(open(f, encoding="utf-8"))
    except Exception as e:
        anim_struct[f"PARSE_FAIL:{type(e).__name__}"] += 1
        continue
    sk = d.get("skeleton")
    if isinstance(sk, dict):
        has_skeleton += 1
        versions[sk.get("spine", "?")] += 1
    else:
        versions["<no skeleton block>"] += 1
    anims = d.get("animations")
    anim_struct["dict" if isinstance(anims, dict) else type(anims).__name__] += 1
    if isinstance(anims, dict):
        for k in anims:
            all_anim_keys[k] += 1
    skins = d.get("skins")
    skin_struct["dict" if isinstance(skins, dict) else type(skins).__name__] += 1
    # curve fingerprint: spine 2.x uses "curve":[x1,y1,x2,y2] arrays inside dict anims
    s = json.dumps(d)[:200000]
    if '"curve":[' in s:
        curve_styles["array (<=3.7 style)"] += 1
    elif '"curve":"' in s:
        curve_styles["string/stepped"] += 1

print("\n=== skeleton.spine version field ===")
for k, v in versions.most_common():
    print(f"  {k!r}: {v}")
print(f"has skeleton block: {has_skeleton}/{len(sample)}")
print("\n=== animations container ===", dict(anim_struct))
print("=== skins container ===", dict(skin_struct))
print("=== curve encoding ===", dict(curve_styles))
print("\n=== most common animation keys (sample) ===")
for k, v in all_anim_keys.most_common(20):
    print(f"  {k}: {v}")
