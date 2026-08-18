from __future__ import annotations
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export
import cocos_export

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(REPO)
SRC = "DV2/ORIGINAL/Loki"
OUT = "assets/converted"
DID = 800

SPINES = [
    ("child1",      "3607", "baby",   1.0),
    ("child2",      "3607", "child",  1.0),
    ("adult",       "3607", "adult",  1.0),
    ("transcended", "3607", "aura",   1.0),
    ("288",         "",     "e",      0.42),
    ("advent",      "3607", "advent", 1.0),
]

ANIM_MAP = {"att": "attack"}

PROFILE_MAP = {
    "1": "egg",
    "2": "box_baby",
    "3": "box_child",
    "4": "box_adult",
    "7": "box_aura",
    "8": "box_evolution",
}
EGG_SMALL_RATIO = 67.0 / 111.0

def _pair(s):
    return [int(x) for x in re.findall(r"-?\d+", s)]

def _premul(im: Image.Image) -> Image.Image:
    from PIL import ImageChops
    r, g, b, a = im.convert("RGBA").split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a),
                                ImageChops.multiply(g, a),
                                ImageChops.multiply(b, a), a))

def _write_tres(path: str, png_res: str, w: int, h: int) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
        f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
        f.write("[resource]\n")
        f.write('atlas = ExtResource("1")\n')
        f.write("region = Rect2(0, 0, %d, %d)\n" % (w, h))
        f.write("filter_clip = true\n")

def _emit_frame(outdir: str, sub: str, name: str, img: Image.Image, manifest: dict,
                off=None, src=None) -> None:
    img.save(os.path.join(outdir, name + ".png"))
    _write_tres(os.path.join(outdir, name + ".tres"),
                "res://assets/converted/%s/%s.png" % (sub, name), img.width, img.height)
    manifest[name] = {"rotated": False, "w": img.width, "h": img.height,
                      "off": off or [0, 0], "src": src or [img.width, img.height]}

def load_src(rel: str) -> dict:
    return json.load(open(os.path.join(SRC, rel), encoding="utf-8"))

def cut_region(page: Image.Image, reg: dict) -> Image.Image:
    x, y = reg["xy"]
    w, h = reg["size"]
    rot = bool(reg.get("rotate"))
    box = (x, y, x + (h if rot else w), y + (w if rot else h))
    c = page.crop(box)
    if rot:
        c = c.transpose(Image.ROTATE_90)
    return c

def build_spines() -> None:
    outdir = os.path.join(OUT, "dragon_%d" % DID)
    for stem, folder, stage, rscale in SPINES:
        base = os.path.join(SRC, folder, stem) if folder else os.path.join(SRC, stem)
        sj = base + ".src.json"
        if not os.path.exists(sj):
            print("  [skip] 원본 없음:", sj)
            continue
        print("[spine] %s -> %s (x%.2f)" % (stem, stage, rscale))
        spine_export.export(DID, stage, "all", sj_path=sj, outdir=outdir,
                            region_basename=True, premultiply=True, anim_map=ANIM_MAP,
                            root_scale=rscale)

def build_portrait() -> None:
    sub = "portrait_%d" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    doc = load_src("3607/profile.src.json")
    page = _premul(Image.open(os.path.join(SRC, "3607", doc["pages"][0]["image"])))
    manifest, egg = {}, None
    for key, fr in doc["regions"].items():
        num = key.rsplit("/", 1)[-1]
        dv2 = PROFILE_MAP.get(num)
        if dv2 is None:
            print("  [skip] 매핑 없는 profile 번호:", num)
            continue
        img = cut_region(page, fr)
        name = "dragon_dragon_%d_%s" % (DID, dv2)
        _emit_frame(outdir, sub, name, img, manifest)
        if dv2 == "egg":
            egg = img
    if egg is not None:
        small = egg.resize((max(1, round(egg.width * EGG_SMALL_RATIO)),
                            max(1, round(egg.height * EGG_SMALL_RATIO))), Image.LANCZOS)
        _emit_frame(outdir, sub, "dragon_dragon_%d_egg_small" % DID, small, manifest)
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[portrait] %d 프레임 -> %s" % (len(manifest), sub))

CUTIN = [
    ("att1", (240, 195, 750, 350), "e_cut_in"),
    ("att3", (170, 150, 680, 320), "cut_in"),
]
CUTIN_H = 112

def build_cutin() -> None:
    sub = "critical_%d" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    manifest = {}
    doc = load_src("288.src.json")
    page = _premul(Image.open(os.path.join(SRC, doc["pages"][0]["image"])))
    for att, box, suffix in CUTIN:
        r = doc["regions"]["monster/288/" + att]
        x, y = r["xy"]; w, h = r["size"]
        cut = page.crop((x, y, x + w, y + h)).crop(box)
        scale = CUTIN_H / float(cut.height)
        cut = cut.resize((max(1, round(cut.width * scale)), CUTIN_H), Image.LANCZOS)
        _emit_frame(outdir, sub, "dragon_dragon_%d_critical_%s" % (DID, suffix), cut, manifest)
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[cutin] %d 프레임 -> %s" % (len(manifest), sub))

FX_SETS = [
    ("3607/effect_adventure.src.json",          "3607/effect_adventure.png",          "adv"),
    ("3607/effect_pvp/col_action10.src.json",   "3607/effect_pvp/col_action10.png",   "col"),
    ("3607/effect_pvp/col_action20.src.json",   "3607/effect_pvp/col_action20.png",   "col"),
]

def build_fx() -> None:
    sub = "dragon_%d_fx" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    manifest = {}
    for src_rel, png_rel, _tag in FX_SETS:
        doc = load_src(src_rel)
        page = _premul(Image.open(os.path.join(SRC, png_rel)))
        for key, fr in sorted(doc["regions"].items()):
            tail = key.split("/effect/", 1)[-1].replace("/", "_")
            name = "dragon_%d_%s" % (DID, tail)
            _emit_frame(outdir, sub, name, cut_region(page, fr), manifest,
                        off=fr["offset"], src=fr["orig"])
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[fx] %d 프레임 -> %s" % (len(manifest), sub))

def main() -> None:
    args = sys.argv[1:]
    todo = [a.lstrip("-") for a in args if a.startswith("--")] or \
        ["spine", "portrait", "cutin", "fx"]
    if "spine" in todo:
        build_spines()
    if "portrait" in todo:
        build_portrait()
    if "cutin" in todo:
        build_cutin()
    if "fx" in todo:
        build_fx()

if __name__ == "__main__":
    main()
