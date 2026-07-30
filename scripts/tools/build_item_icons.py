#!/usr/bin/env python3
"""아이템/장비/젬 아이콘 아틀라스 변환 + 카탈로그 키 매핑 생성.

`assets/converted/` 는 gitignore 대상이라 이 스크립트가 변환 기록이자 재생성 수단이다.

## 왜 필요했나 (asset_index.py 실측, 2026-07-27)
미사용 자산 최대 묶음이 아이템 아이콘이었다: `item/item_small` 520 + `item/accessory` 121
+ `item/item_small/acc` 42 ≈ **683건**. 그런데 그 아이콘들이 우리가 이미 만든 데이터와
**등급/티어 단위로 1:1**로 맞는다:

    item/accessory/feather1..7  claw1..7          ← equipment.json basic 7등급
    item/accessory/catseye1..6                    ← 묘안석 6등급
    item/accessory/obsidian*/platina*             ← 흑요석/백금석
    item/accessory/artifact_bg1..6                ← 아티팩트 6등급
    item/gem/gem_att0..18 gem_def* gem_hp* …      ← gems.json 19티어(자갈→…→원형)

즉 UI 가 텍스트 목록인 채로 원본 아이콘을 놀리고 있었다.

## 하는 일
1. 미변환 아틀라스를 `cocos_export.py` 로 변환
2. 변환 결과 프레임명을 훑어 **논리키 → 프레임키** 매핑을 `data/icon_map.json` 으로 저장
   (§8.4 에셋 카탈로그 계층: logic/data 는 파일 경로를 모르고 논리키만 쓴다)

    python scripts/tools/build_item_icons.py
    python scripts/tools/build_item_icons.py --dry
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "480"
CONV = REPO / "assets" / "converted"
OUT = REPO / "data" / "icon_map.json"

# (플리스트 상대경로, 대상 폴더)
ATLASES = [
    ("item/accessory.img_plist", "item_accessory"),
    ("item/gem.img_plist", "item_gem"),
    ("item/item_small/acc.img_plist", "item_small_acc"),
    ("item/item_small/egg_piece.img_plist", "item_small_egg_piece"),
    ("item/item_small/event_item.img_plist", "item_small_event"),
    ("item/item_small/evol.img_plist", "item_small_evol"),
    ("item/item_small/new_item_small.img_plist", "item_small_new"),
    ("item/item_small/slot_item.img_plist", "item_small_slot"),
]

# ── 장비 아이콘 매핑 ────────────────────────────────────────────────────────
# equipment.json 의 basic 종류 → item/accessory 프레임 접두어(1-base 번호).
# 접두어는 추측이 아니라 변환된 `_manifest.json` 실제 프레임명에서 확인했다:
#   feather1..7 claw1..7 talisman1..7 / catseye1..6 obsidian1..6 platinum1..6
#   (각각 `_bg` 짝이 따로 있다 — 등급 테두리)
BASIC_PREFIX = {
    "깃털": "feather",
    "발톱": "claw",
    "부적": "talisman",     # 원작 파일명 talisman(부적)
    "묘안석": "catseye",
    "흑요석": "obsidian",
    "백금석": "platinum",   # platina 아님
}

# 아티팩트 6종 — 원작이 종류별×등급별 아이콘을 갖고 있다(ignis_1..6 등).
ARTIFACT_PREFIX = {
    "이그니스": "ignis_", "마리스": "maris_", "벤투스": "ventus_",
    "루멘": "lumen_", "옵스큐럼": "obscurum_", "테라": "terra_",
}

# 젬 코드 → item/gem 프레임 접두어(0-base 티어). 실제 프레임: 10종 × 19티어 = 190.
#   gem_hp/att/def(일반3) · gem_hp_att/hp_def/att_hp/att_def/def_hp/def_att(혼성6)
#   gem_white(19) = 샌즈의 젬 — 위키 §2.2.7 "하얀색 외형을 가지고 있다" 와 일치.
# ⚠️ 소울젬 4종 아이콘은 이 덤프에 없다(소울젬=후기 업데이트). 같은 축의 일반젬
#   최고티어 아이콘으로 폴백한다(SOUL_FALLBACK).
GEM_PREFIX = {
    "HP": "gem_hp", "ATT": "gem_att", "DEF": "gem_def",
    "HPATT": "gem_hp_att", "HPDEF": "gem_hp_def",
    "ATTHP": "gem_att_hp", "ATTDEF": "gem_att_def",
    "DEFHP": "gem_def_hp", "DEFATT": "gem_def_att",
    "ATTDEFHP": "gem_white",     # 샌즈의 젬(원작 typeDetail = ATTDEFHP)
}
SOUL_FALLBACK = {"SOULHP": "gem_hp", "SOULATT": "gem_att",
                 "SOULDEF": "gem_def", "SOULALL": "gem_white"}

# 이벤트 장비 — 원작이 개별 아이콘을 갖고 있다. equipment.json event[].name 과 연결.
EVENT_ICON = {
    "크리스마스 별장식": "christmas_star",
    "눈사람 인형": "christmas_snow",
    "크리스마스 리본": "christmas_ribbon",
    "어린이 풍선": "children_balloon",
    "장난감 총": "children_popgun",
    "곰 인형": "children_teddy",
}


def convert() -> list[str]:
    done = []
    for rel, sub in ATLASES:
        src = SRC / rel
        if not src.exists():
            print(f"  ! 원본 없음: {rel}", file=sys.stderr)
            continue
        if (CONV / sub / "_manifest.json").exists():
            print(f"  = 이미 변환됨: {sub}")
            done.append(sub)
            continue
        r = subprocess.run(
            [sys.executable, str(REPO / "scripts" / "tools" / "cocos_export.py"), str(src), sub],
            cwd=REPO, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  ! 변환 실패 {rel}: {r.stderr.strip()[:160]}", file=sys.stderr)
            continue
        print(f"  + {rel} -> {sub}/")
        done.append(sub)
    return done


def load_frames(sub: str) -> dict:
    p = CONV / sub / "_manifest.json"
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def build_map(subs: list[str]) -> dict:
    """논리키 → {"dir": 변환폴더, "frame": 프레임키} 매핑."""
    frames: dict[str, str] = {}          # 프레임키 → 폴더
    for sub in subs + ["item_small_ui", "item_etc", "item_mtr", "item_egg",
                       "item_food", "item_spc", "item_doc", "item_quest"]:
        for k in load_frames(sub):
            frames.setdefault(k, sub)

    def find(*cands: str) -> tuple[str, str] | None:
        for c in cands:
            if c in frames:
                return frames[c], c
        return None

    out: dict = {"_source": "scripts/tools/build_item_icons.py — 원본 아틀라스 프레임명 스캔",
                 "_note": "논리키 → {dir, frame}. render 층만 이 표를 보고 AtlasTexture 를 로드한다(§8.4).",
                 "_soul_note": "소울젬 4종 아이콘은 원작 후기 추가분이라 이 덤프에 없다 → 같은 축 일반젬 "
                               "최고티어 아이콘으로 폴백(gem[SOUL*:n] 이 그것).",
                 "_bg_note": "equipment_bg = 아이콘 **뒤**에 깔고 희귀도 색을 입히는 흰 실루엣. "
                             "원작 `Equip::getGradeImageSmallSprite` 가 `<이름>_bg.png` 로 만들어 "
                             "rarity(2~6)에 따라 setColor 한다(1=일반은 아예 안 그림). "
                             "논리키는 equipment_basic/artifact/event 와 같다.",
                 "equipment_basic": {}, "artifact": {}, "event": {}, "gem": {},
                 "equipment_bg": {}, "shop": {}}

    # 일반 장비: <종류>:<등급인덱스(0-base)> → feather3 등
    for kr, pre in BASIC_PREFIX.items():
        for gi in range(7):
            hit = find(f"item_accessory_{pre}{gi + 1}", f"item_small_acc_{pre}{gi + 1}")
            if hit:
                out["equipment_basic"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    # 아티팩트: <종류>:<등급인덱스> → ignis_3 등 (종류별 아이콘이 실재)
    for kr, pre in ARTIFACT_PREFIX.items():
        for gi in range(6):
            hit = find(f"item_accessory_{pre}{gi + 1}", f"item_small_acc_{pre}{gi + 1}")
            if hit:
                out["artifact"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    # 이벤트 장비: 이름 → 개별 아이콘
    for kr, pre in EVENT_ICON.items():
        hit = find(f"item_accessory_{pre}", f"item_small_acc_{pre}")
        if hit:
            out["event"][kr] = {"dir": hit[0], "frame": hit[1]}
    # 젬: <코드>:<티어(0-base)> → gem_att7 등
    for code, pre in GEM_PREFIX.items():
        for t in range(19):
            hit = find(f"item_gem_{pre}{t}")
            if hit:
                out["gem"][f"{code}:{t}"] = {"dir": hit[0], "frame": hit[1]}
    # 소울젬 폴백(아이콘 부재) — 같은 축 일반젬 최고티어.
    for code, pre in SOUL_FALLBACK.items():
        hit = find(f"item_gem_{pre}18")
        if hit:
            for t in range(10):
                out["gem"][f"{code}:{t}"] = {"dir": hit[0], "frame": hit[1], "fallback": True}

    # 희귀도 실루엣(`<이름>_bg`). 논리키는 위 3섹션과 동일하게 맞춰 render 가 같은 키로 찾게 한다.
    # ⚠️ 부적(talisman)만 원본에 `talisman6_bg` 한 장뿐이다 — 나머지 등급은 그 한 장으로 폴백한다
    #    (실루엣은 등급별로 모양이 거의 같고, 없으면 희귀도 표현이 통째로 빠지기 때문).
    for kr, pre in BASIC_PREFIX.items():
        for gi in range(7):
            hit = find(f"item_accessory_{pre}{gi + 1}_bg")
            fb = False
            if hit is None:
                hit, fb = find(f"item_accessory_{pre}6_bg"), True
            if hit:
                e = {"dir": hit[0], "frame": hit[1]}
                if fb:
                    e["fallback"] = True
                out["equipment_bg"][f"{kr}:{gi}"] = e
    for kr in ARTIFACT_PREFIX:
        for gi in range(6):
            # 원작은 아티팩트만 종류가 아니라 **등급**으로 실루엣을 고른다(`artifact%d_bg`).
            hit = find(f"item_accessory_artifact{gi + 1}_bg")
            if hit:
                out["equipment_bg"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    for kr, pre in EVENT_ICON.items():
        hit = find(f"item_accessory_{pre}_bg")
        if hit:
            out["equipment_bg"][kr] = {"dir": hit[0], "frame": hit[1]}

    # 상점 장비 가챠 버튼 아이콘 — 사용자 확정 2026-07-29(몽타주 '정체 미상' 2건의 정답):
    #   gooddeco = 다이아 가챠 / olddeco = 골드 가챠. `item/accessory` 아틀라스에 실재한다.
    for logical, frame in (("equip_gacha_diamond", "item_accessory_gooddeco"),
                           ("equip_gacha_gold", "item_accessory_olddeco")):
        hit = find(frame)
        if hit:
            out["shop"][logical] = {"dir": hit[0], "frame": hit[1]}
    return out


def main() -> None:
    print("[build_item_icons] 아틀라스 변환")
    subs = convert()
    m = build_map(subs)
    n = sum(len(m[k]) for k in ("equipment_basic", "gem", "artifact", "event", "equipment_bg", "shop"))
    if "--dry" in sys.argv:
        for sec in ("equipment_basic", "artifact", "event", "gem", "equipment_bg", "shop"):
            keys = list(m[sec])[:6]
            print(f"  {sec}: {len(m[sec])}건  예: {keys}")
        return
    OUT.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[build_item_icons] wrote %s: basic=%d artifact=%d event=%d gem=%d bg=%d shop=%d (total %d)" % (
        OUT.relative_to(REPO), len(m["equipment_basic"]), len(m["artifact"]),
        len(m["event"]), len(m["gem"]), len(m["equipment_bg"]), len(m["shop"]), n))


if __name__ == "__main__":
    main()
