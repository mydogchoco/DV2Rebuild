"""Convert a Cocos2d-x XML plist sprite atlas -> Godot AtlasTexture .tres files.

For monster/UI sprite sheets (the non-Spine .img_plist variant). Each frame
becomes one AtlasTexture .tres referencing the copied page PNG.

⚠️ 회전 프레임(plist `rotated`) 은 페이지에 90° 돌아간 채 들어 있고 Godot
`AtlasTexture` 는 회전을 표현할 수 없다. 그래서 그 프레임만 **90° CCW 로 되돌린
낱장 PNG** 로 떼어내고 .tres 는 그 PNG 의 full-region 을 가리킨다
(회전 방향 근거·규모는 `fix_rotated_frames.py` 헤더 주석). 매니페스트에는
`rotated: false, was_rotated: true` 로 남긴다 — 소비자(gd)는 보정하지 않는다.

usage: cocos_export.py <plist_path> <out_subdir>
  e.g. cocos_export.py DV2/480/monster/1/1_image.img_plist monster_1
"""
import sys, os, re, shutil, json
import atlas as atlaslib

try:
    from PIL import Image
except ImportError:      # 회전 프레임이 없는 아틀라스는 PIL 없이도 변환된다.
    Image = None

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
    # sanitized_name -> {rotated, w, h}. 기존 매니페스트가 있으면 병합(한 폴더에 여러 plist 누적용).
    manifest_path = os.path.join(outdir, "_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            manifest = json.load(open(manifest_path, encoding="utf-8"))
        except Exception:
            manifest = {}
    page_img = None
    for name, fr in data["frames"].items():
        # frame "{{x,y},{w,h}}"
        x, y, w, h = parse_braces(fr.get("frame") or fr.get("textureRect", ""))
        rot = bool(fr.get("rotated") or fr.get("textureRotated"))
        if rot:
            rotated += 1
            rw, rh = h, w  # occupied (swapped) in page
        else:
            rw, rh = w, h
        sname = sanitize(name)
        # 회전 프레임 → 세운 낱장 PNG 로 떼어내고 region 은 (0,0,w,h).
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
        # 프레임 트림 오프셋/원본캔버스(cocos) — 애니 프레임 정렬용(중심정렬 드리프트 방지).
        # off=(트림중심 - 원본캔버스중심), cocos y-up. src=원본 untrimmed 크기.
        off = parse_braces(fr.get("offset", "{0,0}"))
        src = parse_braces(fr.get("sourceSize") or fr.get("spriteSourceSize", ""))
        # 회전을 실물로 흡수했으므로 소비자에게는 "회전 아님"으로 알린다(provenance 만 남김).
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
