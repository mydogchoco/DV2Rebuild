#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("PIL(Pillow) 필요: python -m pip install pillow")

REPO = Path(__file__).resolve().parents[2]
CONV = REPO / "assets" / "converted"

RE_REGION = re.compile(r"region = Rect2\(([\d.-]+), ([\d.-]+), ([\d.-]+), ([\d.-]+)\)")
RE_PAGE = re.compile(r'path="res://assets/converted/[^/]+/([^"]+)"')

TRES = (
    '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
    '[ext_resource type="Texture2D" path="{png}" id="1"]\n\n'
    "[resource]\n"
    'atlas = ExtResource("1")\n'
    "region = Rect2(0, 0, {w}, {h})\n"
    "filter_clip = true\n"
)

def fix_dir(d: Path, dry: bool) -> tuple[int, int]:
    mpath = d / "_manifest.json"
    if not mpath.exists():
        return 0, 0
    man = json.loads(mpath.read_text(encoding="utf-8"))
    todo = [k for k, v in man.items()
            if v.get("rotated") and not v.get("was_rotated")]
    if not todo:
        return 0, sum(1 for v in man.values() if v.get("was_rotated"))

    pages: dict[str, Image.Image] = {}
    fixed = 0
    for key in todo:
        tres = d / (key + ".tres")
        if not tres.exists():
            print(f"  ! .tres 없음: {d.name}/{key}", file=sys.stderr)
            continue
        text = tres.read_text(encoding="utf-8")
        mr, mp = RE_REGION.search(text), RE_PAGE.search(text)
        if not mr or not mp:
            print(f"  ! region/page 파싱 실패: {d.name}/{key}", file=sys.stderr)
            continue
        x, y, rw, rh = (int(float(v)) for v in mr.groups())
        page_name = mp.group(1)
        if page_name == key + ".png":
            continue
        if dry:
            fixed += 1
            continue
        if page_name not in pages:
            p = d / page_name
            if not p.exists():
                print(f"  ! 페이지 PNG 없음: {p}", file=sys.stderr)
                continue
            pages[page_name] = Image.open(p).convert("RGBA")
        img = pages[page_name].crop((x, y, x + rw, y + rh)).transpose(Image.ROTATE_90)
        img.save(d / (key + ".png"))
        tres.write_text(
            TRES.format(png=f"res://assets/converted/{d.name}/{key}.png",
                        w=img.width, h=img.height),
            encoding="utf-8")
        man[key]["rotated"] = False
        man[key]["was_rotated"] = True
        fixed += 1

    if fixed and not dry:
        mpath.write_text(json.dumps(man, ensure_ascii=False, indent=1), encoding="utf-8")
    return fixed, 0

def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry = "--dry" in sys.argv
    dirs = [CONV / a for a in args] if args else sorted(
        p.parent for p in CONV.glob("*/_manifest.json"))

    total = already = touched_dirs = 0
    for d in dirs:
        n, skip = fix_dir(d, dry)
        already += skip
        if n:
            total += n
            touched_dirs += 1
            print(f"  {'[dry] ' if dry else ''}{d.name}: {n} 프레임")
    verb = "고칠 대상" if dry else "정규화"
    print(f"[fix_rotated_frames] {verb} {total} 프레임 / {touched_dirs} 폴더"
          f"  (이미 처리됨 {already})")
    if total and not dry:
        print("  → Godot 로 새 PNG 임포트 필요: "
              "godot --headless --path . --import --quit")

if __name__ == "__main__":
    main()
