"""Build master data JSON from user-restored sources.

  docs/match/dragons.csv  + docs/DragonStat.xlsx  ->  data/dragons.json + data/stat_table.json

- normalizes element 'water' -> 'aqua' (asset/spec key)
- stat_table[type][tier] = {base:{hp,att,def}, growth:{hp,att,def}}  (tier: 2/3/4/5/6a/6b)
"""
import csv, json, os, re, zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
ELEMENT_FIX = {"water": "aqua"}
TYPE_ROWS = ["atk", "hp", "def", "ha", "ad", "hd"]          # sheet rows 2..7 order
TIER_COLS = ["2", "3", "4", "5", "6a", "6b", "custom"]       # sheet cols B..H order


def read_xlsx(path):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root:
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))
    sheets = {}
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid_to_target = {r.get("Id"): r.get("Target")
                     for r in rels if r.tag.endswith("Relationship")}
    order = []
    for s in wb.iter(NS + "sheet"):
        rid = s.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        order.append((s.get("name"), rid_to_target[rid]))
    for name, target in order:
        path_in = "xl/" + target.lstrip("/")
        root = ET.fromstring(z.read(path_in))
        grid = {}
        for c in root.iter(NS + "c"):
            ref = c.get("r"); t = c.get("t")
            v = c.find(NS + "v")
            if v is None:
                continue
            val = shared[int(v.text)] if t == "s" else v.text
            col = re.match(r"[A-Z]+", ref).group()
            row = int(re.match(r"[A-Z]+(\d+)", ref).group(1))
            grid[(row, col)] = val
        sheets[name] = grid
    return sheets


def parse_triplet(s):
    h, a, d = (int(x) for x in s.split("/"))
    return {"hp": h, "att": a, "def": d}


def build_stat_table(xlsx_path):
    sheets = read_xlsx(xlsx_path)
    names = list(sheets)
    base_grid = sheets[names[0]]    # "1레벨 최대 능력치"
    grow_grid = sheets[names[1]]    # "레벨업 최대 상승폭"
    cols = ["B", "C", "D", "E", "F", "G", "H"]
    table = {}
    for ri, typ in enumerate(TYPE_ROWS):
        row = ri + 2
        table[typ] = {}
        for ci, tier in enumerate(TIER_COLS):
            col = cols[ci]
            b = base_grid.get((row, col)); g = grow_grid.get((row, col))
            if not b or not g:
                continue
            table[typ][tier] = {"base": parse_triplet(b), "growth": parse_triplet(g)}
    return table


def tier_for(star, generation):
    s = str(star).strip()
    if s == "6":
        # split by generation: 4세대+ -> 6b, else 6a
        try:
            return "6b" if float(re.findall(r"[\d.]+", str(generation))[0]) >= 4 else "6a"
        except Exception:
            return "6a"
    return s if s in ("2", "3", "4", "5") else "4"


def build_dragons(csv_path):
    SRC = "DV2/480/dragon"
    out = []
    for r in csv.DictReader(open(csv_path, encoding="utf-8-sig")):
        if not r["name"].strip():
            continue
        did = r["id"].strip()
        el = r["element"].strip().lower()
        el = ELEMENT_FIX.get(el, el)
        stages = {}
        for st in ("baby", "child", "adult"):
            p = f"{SRC}/dragon_{did}_{st}_spine.spine_json"
            if os.path.exists(p):
                stages[st] = f"dragon_{did}_{st}_spine"
        out.append({
            "id": int(did),
            "name": r["name"].strip(),
            "element": el or None,
            "type": r["type"].strip() or None,
            "star": int(r["star"]) if r["star"].strip().isdigit() else None,
            "generation": r["generation"].strip() or None,
            "stat_tier": tier_for(r["star"], r["generation"]) if r["star"].strip().isdigit() else None,
            "stages": stages,
        })
    return out


if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)
    table = build_stat_table("docs/DragonStat.xlsx")
    json.dump(table, open("data/stat_table.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    dragons = build_dragons("docs/match/dragons.csv")
    json.dump(dragons, open("data/dragons.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"data/stat_table.json: types={list(table)} tiers(atk)={list(table['atk'])}")
    print(f"data/dragons.json: {len(dragons)} dragons")
    # quick validation
    from collections import Counter
    bad_el = sorted(set(d["element"] for d in dragons if d["element"] not in
                    {"aqua","earth","fire","wind","light","dark","holy","chaos","shadow",None}))
    bad_ty = sorted(set(d["type"] for d in dragons if d["type"] not in
                    {"atk","hp","def","ha","ad","hd",None}))
    print("  unexpected elements:", bad_el or "none")
    print("  unexpected types:", bad_ty or "none")
    print("  example:", json.dumps(dragons[0], ensure_ascii=False))
