"""Generate a fillable dragon matching sheet: docs/match/dragons.csv

Auto-fills id + which spine variants exist per dragon (from DV2/480/dragon).
User fills name/element/type/star/generation (absent from assets & strings).
CSV is UTF-8-BOM so Excel opens Korean correctly.
"""
import os, re, csv, glob
from collections import defaultdict

SRC = "DV2/480/dragon"
OUTDIR = "docs/match"
os.makedirs(OUTDIR, exist_ok=True)
OUT = os.path.join(OUTDIR, "dragons.csv")

VARIANTS = {
    "baby":   "dragon_{i}_baby_spine.spine_json",
    "child":  "dragon_{i}_child_spine.spine_json",
    "adult":  "dragon_{i}_adult_spine.spine_json",
    "critical": "dragon_{i}_critical_spine.spine_json",
    "e":      "dragon_{i}_e_spine.spine_json",
}

# collect ids from any dragon_<id>* file
ids = set()
for p in glob.glob(os.path.join(SRC, "dragon_*")):
    m = re.match(r"dragon_(\d+)", os.path.basename(p))
    if m:
        ids.add(int(m.group(1)))

def has(i, tmpl):
    return os.path.exists(os.path.join(SRC, tmpl.format(i=i)))

cols = ["id", "name", "element", "type", "star", "generation",
        "has_baby", "has_child", "has_adult", "has_critical", "has_e", "notes"]

with open(OUT, "w", encoding="utf-8-sig", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(cols)
    for i in sorted(ids):
        row = [i, "", "", "", "", ""]
        for v in ("baby", "child", "adult", "critical", "e"):
            row.append("Y" if has(i, VARIANTS[v]) else "")
        row.append("")
        wr.writerow(row)

print(f"wrote {OUT}  ({len(ids)} dragons)")
