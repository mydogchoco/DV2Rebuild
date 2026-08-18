#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cocos_export

REPO = Path(__file__).resolve().parents[2]
ORIG = REPO / "DV2" / "480"
OUT = REPO / "assets" / "converted"

CUT_IN_LETTERS = ["a", "c", "d", "e", "f", "h", "l", "s", "w"]

def _export(plist: Path, out_name: str, skip_existing: bool = True) -> bool:
    if not plist.exists():
        print(f"  skip(원본 없음): {plist.relative_to(REPO)}")
        return False
    if skip_existing and (OUT / out_name).is_dir():
        return True
    cocos_export.export(str(plist), out_name)
    return True

def main() -> None:
    print("[1/5] 크리티컬 컷인 밴드 (dragon/cut_in_*)")
    for letter in CUT_IN_LETTERS:
        _export(ORIG / "dragon" / f"cut_in_{letter}.img_plist", f"cut_in_{letter}")

    print("[2/5] 드래곤별 크리티컬 아트 (dragon/dragon_N_critical)")
    n = 0
    for plist in sorted((ORIG / "dragon").glob("dragon_*_critical.img_plist")):
        did = plist.stem[len("dragon_"):-len("_critical")]
        if not did.isdigit():
            continue
        if _export(plist, f"critical_{did}"):
            n += 1
    print(f"  → {n}종")

    print("[3/5] 피격 유리깨짐 (monster/hit_effect)")
    _export(ORIG / "monster" / "hit_effect.img_plist", "hit_effect")

    print("[4/5] 타격 의성어 (monster/hit_talk)")
    _export(ORIG / "monster" / "hit_talk.img_plist", "hit_talk")

    print("[5/5] 탐험 카드게임 (scene/adventure/card_game)")
    _export(ORIG / "scene" / "adventure" / "card_game.img_plist", "card_game")

    print("완료. Godot 에디터를 한 번 열거나 `--headless --import` 로 임포트할 것.")

if __name__ == "__main__":
    main()
