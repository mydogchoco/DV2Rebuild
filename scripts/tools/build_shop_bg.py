#!/usr/bin/env python3
"""상점 배경 `scene/shop/shop_bg.jpg` 를 assets/converted/shop_bg/ 로 복사한다.

`assets/converted/` 는 gitignore 대상이라 이 스크립트가 변환 기록이자 재생성 수단이다.

근거: `audit_scene.py ShopScene` 의 리터럴 프레임 목록에 `scene/shop/shop_bg.jpg` 가 있고,
      `asset_index.py --grep "shop/shop_bg"` 결과가 🟠(원작 사용 / 우리 미사용)이었다.
      아틀라스가 아니라 낱장 jpg 라 cocos_export 대상이 아니고 단순 복사로 충분하다.
ⓘ 이 파일은 정확히 768×519 로, CLAUDE.md §9 의 "리소스 기준 해상도 768×519" 를 직접 확인해 준다.

    python scripts/tools/build_shop_bg.py
"""
from __future__ import annotations

import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "480" / "scene" / "shop" / "shop_bg.jpg"
DST = REPO / "assets" / "converted" / "shop_bg"


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"원본 없음: {SRC}")
    DST.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC, DST / SRC.name)
    print(f"{SRC.name} → {DST / SRC.name}")


if __name__ == "__main__":
    main()
