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
