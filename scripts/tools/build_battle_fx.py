#!/usr/bin/env python3
"""전투 연출용 원작 아틀라스 변환 — 크리티컬 컷인 · 피격 유리깨짐 · 타격 의성어.

`assets/converted/` 는 gitignore 대상(파생물)이라, 어떤 원본을 어떤 이름으로 변환하는지는
이 스크립트가 유일한 기록이다. 새로 체크아웃했으면 이걸 돌려서 재생성한다.

    python scripts/tools/build_battle_fx.py

무엇을 왜 변환하나 (전부 `asset_index.py --grep` 으로 원작 사용을 확인한 것들)
--------------------------------------------------------------------------
1. `dragon/cut_in_{a,c,d,e,f,h,l,s,w}.img_plist` → `cut_in_{letter}/`
   크리티컬 컷인의 스피드라인 밴드 `bg_cut1~3`(576×121, 3프레임).
   letter 는 드래곤 race 로 정해진다 — docs/ref/orig_code/decomp/Dragon.c:8790-8851
     0=e(땅) 1=a(물) 2=f(불) 3=w(바람) 4=l(빛) 5=d(어둠) 6=h(신성) 7=c(혼돈) 8=s(그림자)

2. `dragon/dragon_{N}_critical.img_plist` → `critical_{N}/`
   컷인 얼굴 `cut_in`(576×112) + 타격 아트 `critical`(384×260).
   경로 근거: Dragon.c:8631 `dragon/dragon_%d_critical/critical.png`,
              Dragon.c:8938 `dragon/dragon_%d_critical/cut_in.png`

3. `monster/hit_effect.img_plist` → `hit_effect/`
   피격 유리깨짐 `hit_effect_1/2`(384×260). 레퍼런스 docs/ref/orig_image/battle/몬스터공격.png

4. `monster/hit_talk.img_plist` → `hit_talk/`
   붓글씨 타격 의성어 `story{N}_{KR|EN|JP}`(31종 × 3언어).
   레퍼런스 docs/ref/orig_image/battle/몬스터피격2.png 우상단 "우쩍"

5. `scene/adventure/card_game.img_plist` → `card_game/`
   탐험 카드 뽑기 미니게임: `card`(앞면) · `card_back`(뒷면, 152×214) · `heart_*` · `txt_go`.
   원작 클래스 CardMiniGameLayer / CardItem / ShuffleCardMenuItem
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cocos_export  # noqa: E402

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
    # 원작 CardMiniGameLayer/CardItem/ShuffleCardMenuItem 이 쓰는 카드 앞/뒷면·하트·GO 아트.
    _export(ORIG / "scene" / "adventure" / "card_game.img_plist", "card_game")

    print("완료. Godot 에디터를 한 번 열거나 `--headless --import` 로 임포트할 것.")


if __name__ == "__main__":
    main()
