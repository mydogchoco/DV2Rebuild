"""엘피스 하늘 배경(elpis_sky.jpg) 복사 — 아틀라스가 아니라 낱장 JPG라 전용 진입점.
원작 TownLayer 의 섹션 0 이 이 이미지를 쓴다(폭 1229 = 뷰포트, 스크롤하지 않음).
사용: python scripts/tools/build_town_sky.py
"""
import os, shutil
SRC = {"elpis_sky.jpg": "DV2/480/scene/town/elpis_bg/elpis_sky.jpg",
       "elpis_sky_night.jpg": "DV2/480/scene/town/elpis_bg_night/elpis_sky.jpg"}
OUT = "assets/converted/town_elpis_sky"
os.makedirs(OUT, exist_ok=True)
for dst, src in SRC.items():
    if os.path.exists(src):
        shutil.copyfile(src, os.path.join(OUT, dst)); print("copied", dst)
    else:
        print("[skip] 원본 없음:", src)
