from __future__ import annotations
import json, os, sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(REPO)

SRC = "DV2/ORIGINAL/WildSP/normal.png"
SUB = "npc_sundaegun"
OUT = os.path.join("assets/converted", SUB)
KEY = "npc_sundaegun_body_1"

CROP_BOTTOM = 0.65
TARGET_H = 340

POPO = "assets/converted/npc_popo"
MOUTH_POS = (148.5, 120.5)
TILT = 20.0
SS = 8
EMOS = (1, 2, 3, 4, 5, 6)
CUTS = {(1, 1): 4, (1, 2): 7, (1, 3): 10, (2, 1): 4, (2, 2): 7, (2, 3): 10,
        (3, 1): 4, (3, 2): 8, (3, 3): 12, (4, 1): 4, (4, 2): 7, (4, 3): 12,
        (5, 1): 5, (5, 2): 8, (5, 3): 9, (6, 1): 5, (6, 2): 9, (6, 3): 14}
STAMP_SRC = (136, 105, 154, 111)
STAMP_DST = (136, 114)

def premultiply(im: Image.Image) -> Image.Image:
    from PIL import ImageChops
    r, g, b, a = im.convert("RGBA").split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a),
                                ImageChops.multiply(g, a),
                                ImageChops.multiply(b, a), a))

def write_tres(path: str, png_res: str, w: int, h: int) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
        f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
        f.write("[resource]\n")
        f.write('atlas = ExtResource("1")\n')
        f.write("region = Rect2(0, 0, %d, %d)\n" % (w, h))
        f.write("filter_clip = true\n")

def unpremultiply(im: Image.Image) -> Image.Image:
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, r * 255 // a), min(255, g * 255 // a),
                            min(255, b * 255 // a), a)
    return im

def load_popo_frame(key: str, atlas: Image.Image) -> Image.Image:
    import re
    p = os.path.join(POPO, key + ".png")
    if os.path.exists(p):
        return unpremultiply(Image.open(p).convert("RGBA"))
    t = open(os.path.join(POPO, key + ".tres"), encoding="utf-8").read()
    m = re.search(r"region = Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", t)
    x, y, w, h = (int(float(v)) for v in m.groups())
    return unpremultiply(atlas.crop((x, y, x + w, y + h)))

def prep_mouth(e: int, f: int, pman: dict, atlas: Image.Image) -> Image.Image:
    key = "npc_popo_mouth_%d_%d" % (e, f)
    info = pman[key]
    im = load_popo_frame(key, atlas)
    px = im.load()
    for y in range(CUTS[(e, f)], im.height):
        for x in range(im.width):
            px[x, y] = (0, 0, 0, 0)
    w, h, src, off = info["w"], info["h"], info["src"], info["off"]
    box = Image.new("RGBA", (src[0], src[1]), (0, 0, 0, 0))
    box.alpha_composite(im, ((src[0] - w) // 2 + off[0], (src[1] - h) // 2 - off[1]))
    big = box.resize((src[0] * SS, src[1] * SS), Image.LANCZOS)
    big = big.rotate(TILT, resample=Image.BICUBIC, expand=True)
    return big.resize((big.width // SS, big.height // SS), Image.LANCZOS)

def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if not os.path.exists(SRC):
        sys.exit("원본 없음: %s" % SRC)
    im = Image.open(SRC).convert("RGBA")
    box = im.getbbox()
    if box is None:
        sys.exit("원본이 전부 투명하다: %s" % SRC)
    im2 = im.crop(box)
    im = im2.crop((0, 0, im2.width, round(im2.height * CROP_BOTTOM)))
    box2 = im.getbbox()
    if box2 is not None:
        im = im.crop((box2[0], 0, box2[2], im.height))
    w = max(1, round(im.width * TARGET_H / im.height))
    body = im.resize((w, TARGET_H), Image.LANCZOS)
    body.paste(body.crop(STAMP_SRC), STAMP_DST)

    pman = json.load(open(os.path.join(POPO, "_manifest.json"), encoding="utf-8"))
    atlas = Image.open(os.path.join(POPO, "popo.png")).convert("RGBA")
    frames = {(e, f): prep_mouth(e, f, pman, atlas) for e in EMOS for f in (1, 2, 3)}
    bw = max(f.width for f in frames.values())
    bh = max(f.height for f in frames.values())

    os.makedirs(OUT, exist_ok=True)
    man: dict[str, dict] = {}

    def save(key: str, img: Image.Image, src: list | None = None) -> None:
        premultiply(img).save(os.path.join(OUT, key + ".png"))
        write_tres(os.path.join(OUT, key + ".tres"),
                   "res://assets/converted/%s/%s.png" % (SUB, key), img.width, img.height)
        man[key] = {"rotated": False, "w": img.width, "h": img.height,
                    "off": [0, 0], "src": src or [img.width, img.height]}

    save(KEY, body)
    for (e, f), img in sorted(frames.items()):
        save("npc_sundaegun_mouth_%d_%d" % (e, f), img, [bw, bh])
    json.dump(man, open(os.path.join(OUT, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    S = 4.0 / 3.0
    tlx, tly = MOUTH_POS[0] - bw * 0.5, MOUTH_POS[1] - bh * 0.5
    face = {"sundaegun": {"?": {"mouth": [round(tlx * S, 3), round(tly * S, 3)]}}}
    json.dump(face, open(os.path.join(OUT, "_face.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    npc_face_path = "data/npc_face.json"
    doc = json.load(open(npc_face_path, encoding="utf-8"))
    doc.setdefault("npc", {}).update(face)
    json.dump(doc, open(npc_face_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    print("[sundaegun] body %d×%d · mouth %d장(공통상자 %d×%d, 중심 %s) -> %s"
          % (body.width, body.height, len(frames), bw, bh, MOUTH_POS, OUT))
    print("[sundaegun] ⚠️ 재임포트 필수:  godot --headless --path . --import")

if __name__ == "__main__":
    main()
