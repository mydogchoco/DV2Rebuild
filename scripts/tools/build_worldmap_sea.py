#!/usr/bin/env python3
"""월드맵 **바다 층**(원작 `WorldMapLayer::initWidget`)의 자산을 변환한다.

왜
--
원작 월드맵의 바다는 네 겹이다(`WorldMapLayer::initWidget` @01af12xx — **전 지역 공통
기반 클래스**라 유타칸·엘리시움·메탈타워·우노에 모두 걸린다):

  1. `scene/worldmap/background.jpg`                      바다 원경   `setScaleX((280+2048)/w)`
  2. `scene/worldmap/ani_sea_spine` anim=`nest`    scale 4.0  하얀 거품망
  3. `scene/worldmap/background_trans/bg.png`             반투명 비네트 `setScale(2048/w)` → `setScaleX((280+2048)/w)`
  4. `scene/worldmap/ani_sea_spine` anim=`dustwave` scale 4.0  흩날리는 물보라

넷 다 `addChild(node)`(vtable +0x188) = **z 기본값 0**, 위치는 `background.contentSize*0.5
+ CCSize(280,0)*0.5`. 우리는 1번만 그리고 있어 바다가 단색으로 보였다(사용자 지적 2026-07-29).

`ani_sea_spine.png`(783×237) 아틀라스를 열어 보면 **흰/하늘색 세포 모양 거품 무늬 2벌 +
물보라**다. 슬롯 이름도 `worldmap_sea_nest*` · `worldmap_sea_wave01*` · `worldmap_sea_dust*`.

파이프라인(2단계)
----------------
    python scripts/tools/build_worldmap_sea.py                        # 1) spine_json → 중간 JSON, 비네트 → PNG
    godot --headless --script res://scripts/tools/build_worldmap_fx_scenes.gd   # 2) 중간 JSON → .tscn

`assets/converted/`·`scenes/worldmap_fx/` 는 gitignore 대상이라 이 스크립트가 변환 기록이다.
"""
from __future__ import annotations

import os
import plistlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "DV2", "480", "scene", "worldmap")
OUT = os.path.join(REPO, "assets", "converted")

# 바다 거품 스파인. 지역 전용 파도(`ani_waves_spine`=드워프 · `ani_waves_new_spine`=엘프)는
# 각 레이어의 initAnimation 소유라 여기서 다루지 않는다.
SPINES = ["ani_sea_spine"]

# 반투명 비네트 — 아틀라스 1프레임짜리라 스파인이 아니라 낱장 PNG 로 뽑는다.
TRANS = ("background_trans", "scene/worldmap/background_trans/bg.png", "worldmap_sea_trans")


def _rect(s: str):
    return [int(float(v)) for v in re.findall(r"-?\d+(?:\.\d+)?", s)]


def export_trans() -> bool:
    """`background_trans/bg.png` 프레임을 낱장 PNG 로 잘라 낸다(회전 패킹 정규화 포함)."""
    from PIL import Image

    atlas, key, outname = TRANS
    pl_path = os.path.join(SRC, atlas + ".img_plist")
    png_path = os.path.join(SRC, atlas + ".png")
    if not (os.path.exists(pl_path) and os.path.exists(png_path)):
        print(f"  ! {atlas}: 원본 없음")
        return False
    with open(pl_path, "rb") as f:
        pl = plistlib.load(f)
    fr = pl["frames"].get(key)
    if fr is None:
        print(f"  ! {key}: 프레임 없음")
        return False
    x, y, w, h = _rect(fr["frame"])
    rotated = bool(fr.get("rotated") or fr.get("textureRotated"))
    page = Image.open(png_path).convert("RGBA")
    im = page.crop((x, y, x + h, y + w)).transpose(Image.ROTATE_270) if rotated \
        else page.crop((x, y, x + w, y + h))
    outdir = os.path.join(OUT, "worldmap_sea")
    os.makedirs(outdir, exist_ok=True)
    im.save(os.path.join(outdir, outname + ".png"))
    print(f"  + {outname}.png  {im.size}  (원작 sourceSize={fr.get('sourceSize')})")
    return True


def main() -> None:
    if not os.path.isdir(SRC):
        raise SystemExit(f"원본 월드맵 폴더 없음: {SRC}")
    ok = fail = 0
    for name in SPINES:
        sj = os.path.join(SRC, name + ".spine_json")
        atlas = os.path.join(SRC, name + ".img_plist")
        if not os.path.exists(sj):
            print(f"  ! {name}: spine_json 없음")
            fail += 1
            continue
        try:
            # `export_scene` 규약: assets/converted/scenespine_<name>/scene.json
            out = spine_export.export_scene(sj, anim_filter="all", atlas_path=atlas)
            if out is None:
                fail += 1
                continue
            ok += 1
            print(f"  + {name}")
        except Exception as e:                                  # noqa: BLE001
            fail += 1
            print(f"  ! {name}: {e}")
    if not export_trans():
        fail += 1
    print(f"\n바다 층 자산: 스파인 {ok}종 변환 / 실패 {fail}")
    print("다음: godot --headless --script res://scripts/tools/build_worldmap_fx_scenes.gd")


if __name__ == "__main__":
    main()
