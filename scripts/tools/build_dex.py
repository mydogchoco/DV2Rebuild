import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import atlas as atlaslib
import cocos_export

DRAGONS = "data/dragons.json"
OUT_META = "data/dex_meta.json"

def main():
    cocos_export.export("DV2/480/item/etc.img_plist", "item_etc")
    dragons = json.load(open(DRAGONS, encoding="utf-8"))
    meta, converted, missing = {}, 0, []
    for d in dragons:
        did = d["id"]
        art = int(d.get("art_id", did))
        plist = "DV2/480/dragon/dragon_%d.img_plist" % art
        if not os.path.exists(plist):
            man = "assets/converted/portrait_%d/_manifest.json" % art
            if not os.path.exists(man):
                missing.append(did); continue
            names = set(k.replace("dragon_dragon_%d_" % art, "")
                        for k in json.load(open(man, encoding="utf-8")))
            box = set(n for n in names if n.startswith("box_") and "skin" not in n)
            meta[str(did)] = {"awaken": "box_s01" in box, "evo": "box_evolution" in box}
            converted += 1
            continue
        if art == did:
            cocos_export.export(plist, "portrait_%d" % did)
        names = set(n.split("/")[-1].replace(".png", "")
                    for n in atlaslib.parse_cocos_plist(plist)["frames"])
        box = set(n for n in names if n.startswith("box_") and "skin" not in n)
        meta[str(did)] = {"awaken": "box_s01" in box, "evo": "box_evolution" in box}
        converted += 1
    json.dump(meta, open(OUT_META, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    aw = sum(1 for v in meta.values() if v["awaken"])
    ev = sum(1 for v in meta.values() if v["evo"])
    print("portraits=%d missing=%d  awaken=%d evo=%d  -> %s" % (converted, len(missing), aw, ev, OUT_META))
    if missing:
        print("missing ids:", missing[:30])

if __name__ == "__main__":
    main()
