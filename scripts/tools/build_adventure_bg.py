"""던전(필드) 배경 변환 — DV2/480/scene/adventure/bg/<필드id>/ → assets/converted/adventure_bg/.

원작이 던전 배경으로 실제 쓰는 경로는 `scene/adventure/bg/%d/bg.jpg` 다(필드 id로 포맷).
  근거: WorldMapPopupLayer.c:9066 / SeekScene.c:2948 / WeeklyMainScene.c:851 /
        WorldAreaOpenLayer.c:348 / RaidMonsterDetailLayer.c:4381 — 전부 같은 포맷 문자열.
배경은 3파일 세트다:
  bg.jpg                     768×519 원경(디자인 해상도 그대로)
  item.png + item.img_plist  전경 오버레이 아틀라스. 프레임키 `.../item/bg_item.png`,
                             sourceSize {384,260}(=배경의 정확히 1/2) → 원작은 배경 스프라이트의
                             자식으로 **중앙정렬 + setScale(2.0)** 로 덮는다
                             (WorldMapPopupLayer.c:9216 `0x40000000`=2.0, :9222 z=2).

필드 id 규칙(실측):
  1~25    본편 던전(= stringsData_KR.xml `AdventureField_<id>` 와 1:1. 1=희망의 숲 … 23=화룡의 둥지)
  501~514 500+필드id = **밤** 변형(예: 501 = 희망의 숲 야간)
  601~614 600+필드id = **보라(오염/하드)** 변형
  1003/1004 특수(레이드 등)

usage: python scripts/tools/build_adventure_bg.py [--ids 1,2,3]
"""
import sys, os, re, json, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atlaslib

SRC = "DV2/480"
OUT = "assets/converted/adventure_bg"
# 원작이 부르는 경로 그대로(포맷 인자 = 필드 id). 이 리터럴이 곧 변환 대상 명세다.
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
    """<id>/item.img_plist 를 전경 프레임으로 변환. 페이지 png 는 item_<id>.png 로 복사."""
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
        # "scene/adventure/bg/23/item/bg_raid_item.png" -> "bg_23_raid_item"
        leaf = os.path.basename(name).replace(".png", "")      # bg_item / bg_raid_item
        key = "bg_%d_%s" % (fid, leaf[3:].lstrip("_"))          # bg_23_item / bg_23_raid_item
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
