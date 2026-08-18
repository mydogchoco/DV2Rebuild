import sys, os, re, json, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atlaslib

SRC = "DV2/480"
OUT = "assets/converted/adventure_bg"
ORIG_BG = "scene/adventure/bg/%d/bg.jpg"
ORIG_ITEM = "scene/adventure/bg/%d/item/bg_item.png"
ORIG_PLIST = "scene/adventure/bg/%d/item.img_plist"

def orig(fmt, fid):
    return os.path.join(SRC, fmt % fid)

def parse_braces(s):
    return [int(x) for x in re.findall(r"-?\d+", s)]

def field_ids():
    root = os.path.join(SRC, "scene/adventure/bg")
    out = []
    for name in os.listdir(root):
        if name.isdigit() and os.path.exists(orig(ORIG_BG, int(name))):
            out.append(int(name))
    return sorted(out)

def export_items(fid, manifest):
    plist = orig(ORIG_PLIST, fid)
    src_png = os.path.join(os.path.dirname(plist), "item.png")
    if not (os.path.exists(plist) and os.path.exists(src_png)):
        return 0
    data = atlaslib.parse_cocos_plist(plist)
    page = "item_%d.png" % fid
    shutil.copyfile(src_png, os.path.join(OUT, page))
    png_res = "res://%s/%s" % (OUT.replace(os.sep, "/"), page)

    n = 0
    for name, fr in data["frames"].items():
        leaf = os.path.basename(name).replace(".png", "")
        key = "bg_%d_%s" % (fid, leaf[3:].lstrip("_"))
        x, y, w, h = parse_braces(fr.get("frame") or fr.get("textureRect", ""))
        rot = bool(fr.get("rotated") or fr.get("textureRotated"))
        rw, rh = (h, w) if rot else (w, h)
        with open(os.path.join(OUT, key + ".tres"), "w", encoding="utf-8") as f:
            f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
            f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
            f.write("[resource]\n")
            f.write('atlas = ExtResource("1")\n')
            f.write("region = Rect2(%d, %d, %d, %d)\n" % (x, y, rw, rh))
            f.write("filter_clip = true\n")
        entry = {"rotated": rot, "w": w, "h": h}
        off = parse_braces(fr.get("offset", "{0,0}"))
        src = parse_braces(fr.get("sourceSize") or fr.get("spriteSourceSize", ""))
        if len(off) == 2:
            entry["off"] = off
        if len(src) == 2:
            entry["src"] = src
        manifest[key] = entry
        n += 1
    return n

def main(ids=None):
    os.makedirs(OUT, exist_ok=True)
    todo = ids if ids else field_ids()
    manifest_path = os.path.join(OUT, "_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            manifest = json.load(open(manifest_path, encoding="utf-8"))
        except Exception:
            manifest = {}

    bgs, items = 0, 0
    for fid in todo:
        src = orig(ORIG_BG, fid)
        if not os.path.exists(src):
            print("missing:", src); continue
        shutil.copyfile(src, os.path.join(OUT, "bg_%d.jpg" % fid))
        bgs += 1
        items += export_items(fid, manifest)

    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("adventure_bg: %d bg.jpg, %d overlay frames -> %s" % (bgs, items, OUT))

if __name__ == "__main__":
    arg = None
    if "--ids" in sys.argv:
        arg = [int(x) for x in sys.argv[sys.argv.index("--ids") + 1].split(",")]
    main(arg)
