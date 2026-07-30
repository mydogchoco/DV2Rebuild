"""Atlas parsing for DV2 .img_plist files (two coexisting formats).

- Spine atlas (libgdx text): used by dragon/* spine assets. Region names match
  spine_json attachment names. May be multi-page.
- Cocos2d-x XML plist: used by monster/* and general sprite atlases.

detect_format(path) -> "spine" | "cocos"
parse_spine_atlas(path) -> {"pages":[{image,size}], "regions":{name:{page,xy,size,orig,offset,rotate}}}
parse_cocos_plist(path) -> {"image":<from metadata>, "frames":{name:{frame,offset,rotated,sourceSize}}}
"""
import plistlib, re, os


def detect_format(path):
    with open(path, "rb") as f:
        head = f.read(64).lstrip()
    return "cocos" if head.startswith(b"<?xml") or head.startswith(b"<plist") else "spine"


def _pair(s):
    a, b = s.split(",")
    return [int(a), int(b)]


def parse_spine_atlas(path):
    pages, regions = [], {}
    cur_page = None
    cur_region = None
    for raw in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if not raw.strip():
            cur_region = None
            continue
        if raw[0].isspace():  # region property
            if cur_region is None:
                continue
            k, _, v = raw.strip().partition(":")
            k, v = k.strip(), v.strip()
            r = regions[cur_region]
            if k == "rotate":
                r["rotate"] = (v == "true")
            elif k in ("xy", "size", "orig", "offset"):
                r[k] = _pair(v)
            continue
        line = raw.strip()
        if ":" in line:  # page-level header prop
            k, _, v = line.partition(":")
            if k.strip() == "size" and cur_page:
                cur_page["size"] = _pair(v.strip())
            continue
        if "." in line:  # page image filename
            cur_page = {"image": line, "size": None}
            pages.append(cur_page)
            cur_region = None
        else:  # region name
            cur_region = line
            regions[line] = {"page": len(pages) - 1, "rotate": False,
                             "xy": [0, 0], "size": [0, 0], "orig": [0, 0], "offset": [0, 0]}
    return {"pages": pages, "regions": regions}


def parse_cocos_plist(path):
    d = plistlib.load(open(path, "rb"))
    md = d.get("metadata", {})
    image = md.get("textureFileName") or md.get("realTextureFileName")
    out = {"image": image, "frames": {}}
    for name, fr in d.get("frames", {}).items():
        out["frames"][name] = fr
    return out


if __name__ == "__main__":
    import sys, json
    p = sys.argv[1]
    fmt = detect_format(p)
    print("format:", fmt)
    if fmt == "spine":
        a = parse_spine_atlas(p)
        print("pages:", a["pages"])
        rot = [n for n, r in a["regions"].items() if r["rotate"]]
        print(f"regions: {len(a['regions'])}, rotated: {len(rot)} {rot[:5]}")
        n0 = next(iter(a["regions"]))
        print("example:", n0, a["regions"][n0])
    else:
        a = parse_cocos_plist(p)
        print("image:", a["image"], "frames:", len(a["frames"]))
