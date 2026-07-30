#!/usr/bin/env python3
"""회전 패킹된 아틀라스 프레임을 낱장 PNG로 정규화(90° CCW 되돌림).

## 왜 필요했나 (2026-07-27 실측)

Cocos2d-x 아틀라스는 공간을 아끼려고 프레임을 90° 돌려서 페이지에 넣고
plist 에 `<key>rotated</key><true/>` 를 남긴다. 원작 런타임(`CCSpriteFrame`)은
그 플래그를 보고 쿼드 UV 를 돌려 그린다.

우리 `cocos_export.py` 는 **좌표만 (h,w) 로 스왑한 AtlasTexture** 를 썼다.
Godot `AtlasTexture` 는 회전을 표현할 방법이 없다 → 그 프레임은 **옆으로 누워서**
렌더된다. 실측 규모:

    전체 8,089 프레임 중 2,519개(31%)가 회전 프레임
    item_small_ui 102/561 · common_ui 64/236 · item_accessory 51/127
    item_gem 36/190 · item_etc 43/109 · ninepatch_ui 29/125 · adventure_ui 57/121

지금까지는 **호출처마다** `Sprite2D.rotation = -PI/2` 로 땜질해 왔다
(`cave.gd:73`, `town.gd:794`, `battle.gd:454`, `laboratory.gd:55` …20여 곳).
그래서 (a) TextureRect·NinePatchRect 소비자는 보정이 없고 — 젬/장비 아이콘 로더
`Icons.rect()` 가 그 경우다 —, (b) 보정 방향이 호출처마다 어긋났다
(`cave.gd:3040` 은 `PI/2 + flip_h`, 즉 거울상).

## 회전 방향 근거(실측, 추측 아님)

    item_food/heal_potion3   날개+후광 달린 물약병 → CCW 90° 에서만 똑바로 선다
    common/btn_arrow1,2      CCW 90° 에서 각각 ◀ / ▶ (prev/next 짝이 성립)

Godot 의 `-PI/2` 회전과 같은 방향이다(기존 땜질들이 쓰던 값과 일치).

## 하는 일 (멱등)

이미 변환된 `assets/converted/<dir>/` 를 그대로 훑는다 — 원본 plist 재파싱이
필요 없다(폴더↔plist 매핑이 기록돼 있지 않기 때문).

    1. `_manifest.json` 에서 `rotated: true` 프레임을 찾는다
    2. `<frame>.tres` 의 region 을 페이지 PNG 에서 잘라 **90° CCW 회전**
    3. 낱장 `<frame>.png` 으로 저장
    4. `<frame>.tres` 를 그 PNG 의 full-region AtlasTexture 로 재작성
       → **리소스 경로가 그대로라 소비자 코드는 무수정**
    5. 매니페스트를 `rotated: false, was_rotated: true` 로 갱신
       → `rotated` 를 읽는 gd 코드가 "보정 불필요" 를 올바르게 보게 된다

`was_rotated` 가 이미 박힌 프레임은 건너뛴다(재실행 안전).

    python scripts/tools/fix_rotated_frames.py --dry     # 무엇을 고칠지만 보고
    python scripts/tools/fix_rotated_frames.py           # 전체 폴더
    python scripts/tools/fix_rotated_frames.py item_gem item_accessory   # 지정 폴더만

⚠️ 이후 Godot 가 새 PNG 들을 임포트해야 한다(에디터 실행 또는 `--headless --import`).
"""
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
    """(고친 프레임 수, 건너뛴 수). 매니페스트가 없으면 (0,0)."""
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
            continue                      # 이미 낱장으로 분리된 프레임
        if dry:
            fixed += 1
            continue
        if page_name not in pages:
            p = d / page_name
            if not p.exists():
                print(f"  ! 페이지 PNG 없음: {p}", file=sys.stderr)
                continue
            pages[page_name] = Image.open(p).convert("RGBA")
        # 페이지에는 (h,w) 로 누워 있다 → 잘라서 CCW 90° 로 세운다.
        img = pages[page_name].crop((x, y, x + rw, y + rh)).transpose(Image.ROTATE_90)
        img.save(d / (key + ".png"))
        tres.write_text(
            TRES.format(png=f"res://assets/converted/{d.name}/{key}.png",
                        w=img.width, h=img.height),
            encoding="utf-8")
        # 회전을 실물로 흡수했다 → 소비자는 더 이상 보정하면 안 된다.
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
