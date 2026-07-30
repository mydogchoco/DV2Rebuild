#!/usr/bin/env python3
"""엘피스 시설(점술집·연구소) 배경 jpg + 아틀라스를 assets/converted/ 로 변환한다.

`assets/converted/` 는 gitignore 대상이라 이 스크립트가 변환 기록이자 재생성 수단이다.

근거(3종 조회):
  · `audit_scene.py MagicShopScene` 리터럴 프레임 →
      scene/magicshop/magicshop_bg.jpg · magicshop_bg2.jpg(지하) · crystalball.png · table.png
    문자열 테이블 `<TitleMagicShop>점술집` / `<TitleMagicShopB1>점술집 지하` 로 용도 확정
    (⚠️ TacCardScene 은 전술카드=PvP CUT 이지 점술집이 아니다).
  · `audit_scene.py LaboratoryScene` 리터럴 프레임 →
      scene/laboratory/laboratory{,0,1,3}.jpg (층별 배경, changeFloor)
  · 아틀라스 `scene/magicshop.img_plist` 는 cocos_export 대상.
    `scene/laboratory.img_plist` 는 이미 assets/converted/laboratory_ui/ 로 변환돼 있다.

    python scripts/tools/build_facility_bg.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC480 = REPO / "DV2" / "480"
CONV = REPO / "assets" / "converted"

# (원본 상대경로, 대상 폴더)
JPGS = [
    ("scene/magicshop/magicshop_bg.jpg", "magicshop_bg"),    # 점술집 1층
    ("scene/magicshop/magicshop_bg2.jpg", "magicshop_bg"),   # 점술집 지하(changeFloor)
    ("scene/laboratory/laboratory.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory0.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory1.jpg", "laboratory_bg"),
    ("scene/laboratory/laboratory3.jpg", "laboratory_bg"),
    ("scene/mamorudiclab/mamorudic_bg.jpg", "mamorudiclab_bg"),   # 우노 마모루딕 연구소(DragonAwaken)
    ("scene/promote/bg.jpg", "promote_bg"),                       # 육성(PromoteScene) — bg_promote
]

# (플리스트 상대경로, 대상 폴더)
ATLASES = [
    ("scene/magicshop.img_plist", "magicshop_ui"),
    ("scene/magicshop/alchemy.img_plist", "magicshop_alchemy"),
    ("scene/mamorudiclab.img_plist", "mamorudiclab_ui"),
]


def main() -> None:
    n_jpg = n_atlas = 0
    for rel, sub in JPGS:
        src = SRC480 / rel
        if not src.exists():
            print(f"  ! 원본 없음: {rel}", file=sys.stderr)
            continue
        dst_dir = CONV / sub
        dst_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst_dir / src.name)
        n_jpg += 1
        print(f"  jpg  {rel} -> {sub}/{src.name}")
    for rel, sub in ATLASES:
        src = SRC480 / rel
        if not src.exists():
            print(f"  ! 원본 없음: {rel}", file=sys.stderr)
            continue
        r = subprocess.run(
            [sys.executable, str(REPO / "scripts" / "tools" / "cocos_export.py"), str(src), sub],
            cwd=REPO, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  ! 변환 실패 {rel}: {r.stderr.strip()[:200]}", file=sys.stderr)
            continue
        n_atlas += 1
        print(f"  atlas {rel} -> {sub}/")
    print(f"[build_facility_bg] jpg {n_jpg} / atlas {n_atlas}")


if __name__ == "__main__":
    main()
