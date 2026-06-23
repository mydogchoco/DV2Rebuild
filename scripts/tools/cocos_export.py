"""Convert a Cocos2d-x XML plist sprite atlas -> Godot AtlasTexture .tres files.

For monster/UI sprite sheets (the non-Spine .img_plist variant). Each frame
becomes one AtlasTexture .tres referencing the copied page PNG.

usage: cocos_export.py <plist_path> <out_subdir>
  e.g. cocos_export.py DV2/480/monster/1/1_image.img_plist monster_1
"""
import sys, os, re, shutil
import atlas as atlaslib

OUTROOT = "assets/converted"


def parse_braces(s):
    nums = [int(x) for x in re.findall(r"-?\d+", s)]
    return nums


def sanitize(name):
    return name.replace("/", "_").replace(".png", "")


def export(plist_path, out_sub):
    if atlaslib.detect_format(plist_path) != "cocos":
        print("not a cocos plist:", plist_path); return
    data = atlaslib.parse_cocos_plist(plist_path)
    outdir = os.path.join(OUTROOT, out_sub)
    os.makedirs(outdir, exist_ok=True)

    # page png: metadata image "X.pvr.ccz" -> sibling "X.png"
    stem = os.path.basename(data["image"]).split(".")[0]
    src_png = os.path.join(os.path.dirname(plist_path), stem + ".png")
    if not os.path.exists(src_png):
        print("missing page png:", src_png); return
    shutil.copyfile(src_png, os.path.join(outdir, os.path.basename(src_png)))
    png_res = f"res://{outdir.replace(os.sep,'/')}/{os.path.basename(src_png)}"

    n, rotated = 0, 0
    for name, fr in data["frames"].items():
        # frame "{{x,y},{w,h}}"
        x, y, w, h = parse_braces(fr.get("frame") or fr.get("textureRect", ""))
        rot = bool(fr.get("rotated") or fr.get("textureRotated"))
        if rot:
            rotated += 1
            rw, rh = h, w  # occupied (swapped) in page
        else:
            rw, rh = w, h
        tres = os.path.join(outdir, sanitize(name) + ".tres")
        with open(tres, "w", encoding="utf-8") as f:
            f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
            f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
            f.write("[resource]\n")
            f.write('atlas = ExtResource("1")\n')
            f.write("region = Rect2(%d, %d, %d, %d)\n" % (x, y, rw, rh))
        n += 1
    print(f"{out_sub}: {n} AtlasTexture .tres ({rotated} rotated - need 90deg fix in scene)")


if __name__ == "__main__":
    export(sys.argv[1], sys.argv[2])
