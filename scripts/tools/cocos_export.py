import sys, os, re, shutil, json
import atlas as atlaslib

try:
    from PIL import Image
except ImportError:
    Image = None

OUTROOT = "assets/converted"

def parse_braces(s):
    nums = [int(x) for x in re.findall(r"-?\d+", s)]
    return nums

def sanitize(name):
    return name.replace("/", "_").replace(".png", "")

def export(plist_path, out_sub, premultiply=False):
    if atlaslib.detect_format(plist_path) != "cocos":
        print("not a cocos plist:", plist_path); return
    data = atlaslib.parse_cocos_plist(plist_path)
    outdir = os.path.join(OUTROOT, out_sub)
    os.makedirs(outdir, exist_ok=True)

    stem = os.path.basename(data["image"]).split(".")[0]
    src_png = os.path.join(os.path.dirname(plist_path), stem + ".png")
    if not os.path.exists(src_png):
        print("missing page png:", src_png); return
    dst_png = os.path.join(outdir, os.path.basename(src_png))
    if premultiply:
        import spine_export
        spine_export.premultiply_png(src_png, dst_png)
        src_png = dst_png
    else:
        shutil.copyfile(src_png, dst_png)
    png_res = f"res://{outdir.replace(os.sep,'/')}/{os.path.basename(src_png)}"

    n, rotated = 0, 0
    manifest_path = os.path.join(outdir, "_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            manifest = json.load(open(manifest_path, encoding="utf-8"))
        except Exception:
            manifest = {}
    page_img = None
    for name, fr in data["frames"].items():
        x, y, w, h = parse_braces(fr.get("frame") or fr.get("textureRect", ""))
        rot = bool(fr.get("rotated") or fr.get("textureRotated"))
        if rot:
            rotated += 1
            rw, rh = h, w
        else:
            rw, rh = w, h
        sname = sanitize(name)
        tex_res, tx, ty, tw, th = png_res, x, y, rw, rh
        if rot and Image is not None:
            if page_img is None:
                page_img = Image.open(src_png).convert("RGBA")
            up = page_img.crop((x, y, x + rw, y + rh)).transpose(Image.ROTATE_90)
            up.save(os.path.join(outdir, sname + ".png"))
            tex_res = f"res://{outdir.replace(os.sep,'/')}/{sname}.png"
            tx, ty, tw, th = 0, 0, up.width, up.height
        tres = os.path.join(outdir, sname + ".tres")
        with open(tres, "w", encoding="utf-8") as f:
            f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
            f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % tex_res)
            f.write("[resource]\n")
            f.write('atlas = ExtResource("1")\n')
            f.write("region = Rect2(%d, %d, %d, %d)\n" % (tx, ty, tw, th))
            f.write("filter_clip = true\n")
        off = parse_braces(fr.get("offset", "{0,0}"))
        src = parse_braces(fr.get("sourceSize") or fr.get("spriteSourceSize", ""))
        entry = {"rotated": False, "w": w, "h": h} if rot and Image is not None \
            else {"rotated": rot, "w": w, "h": h}
        if rot and Image is not None:
            entry["was_rotated"] = True
        if len(off) == 2:
            entry["off"] = off
        if len(src) == 2:
            entry["src"] = src
        manifest[sname] = entry
        n += 1
    json.dump(manifest, open(manifest_path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"{out_sub}: {n} AtlasTexture .tres ({rotated} rotated). manifest written.")

if __name__ == "__main__":
    export(sys.argv[1], sys.argv[2])
