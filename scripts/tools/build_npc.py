#!/usr/bin/env python3
"""원작 NPC 아틀라스(DV2/480/npc/*.img_plist) 변환.

`assets/converted/` 는 gitignore 대상이라 이 스크립트가 변환 기록이자 재생성 수단이다.

    python scripts/tools/build_npc.py            # 전체
    python scripts/tools/build_npc.py nuri pino  # 특정 NPC만

왜
--
`asset_index.py --gap npc` → **83건 전량 미사용**(카테고리 npc, 우리 ours=0)이었다.
원작은 NPC를 **body + eye + mouth 파츠 합성**으로 그린다:
    PopSeekFinishLayer.c:149  `npc/nuri/body_1.png`  (앵커 bottom-center, VisibleRect 기준)
    PopSeekFinishLayer.c:202  `npc/nuri/mouth_3_2.png` @ body-local (103, 310)
    PopSeekFinishLayer.c:215  `npc/nuri/eye_4_1.png`   @ body-local (104, 346)
프레임 이름 규약: `body_{N}` / `eye_{N}_{M}` / `mouth_{N}_{M}`.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cocos_export  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
NPC_DIR = REPO / "DV2" / "480" / "npc"
OUT = REPO / "assets" / "converted"


def main() -> None:
    if not NPC_DIR.is_dir():
        raise SystemExit(f"원본 NPC 폴더 없음: {NPC_DIR}")
    wanted = set(sys.argv[1:])
    n = 0
    for plist in sorted(NPC_DIR.glob("*.img_plist")):
        name = plist.stem
        if wanted and name not in wanted:
            continue
        out_name = f"npc_{name}"
        if (OUT / out_name).is_dir():
            n += 1
            continue
        cocos_export.export(str(plist), out_name)
        n += 1
    print(f"NPC {n}종 변환/확인 완료 → assets/converted/npc_*")


if __name__ == "__main__":
    main()
