#!/usr/bin/env python3
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

BASIC_PREFIX = {
    "깃털": "feather",
    "발톱": "claw",
    "부적": "talisman",
    "묘안석": "catseye",
    "흑요석": "obsidian",
    "백금석": "platinum",
}

ARTIFACT_PREFIX = {
    "이그니스": "ignis_", "마리스": "maris_", "벤투스": "ventus_",
    "루멘": "lumen_", "옵스큐럼": "obscurum_", "테라": "terra_",
}

GEM_PREFIX = {
    "HP": "gem_hp", "ATT": "gem_att", "DEF": "gem_def",
    "HPATT": "gem_hp_att", "HPDEF": "gem_hp_def",
    "ATTHP": "gem_att_hp", "ATTDEF": "gem_att_def",
    "DEFHP": "gem_def_hp", "DEFATT": "gem_def_att",
    "ATTDEFHP": "gem_white",
}
SOUL_PREFIX = {"SOULATT": "att", "SOULDEF": "def", "SOULHP": "hp", "SOULALL": "all"}
SOUL_STAGES = 10

EVENT_ICON = {
    "크리스마스 별장식": "christmas_star",
    "눈사람 인형": "christmas_snow",
    "크리스마스 리본": "christmas_ribbon",
    "어린이 풍선": "children_balloon",
    "장난감 총": "children_popgun",
    "곰 인형": "children_teddy",
}

EXCLUSIVE_ALIAS = {
    "샛별의 날개장식": "루시퍼의 날개장식",
    "한울의 불꽃": "라 솔라의 불꽃",
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

def wiki_rows() -> dict:
    p = CONV / "equip_wiki" / "_rows.json"
    if not p.exists():
        print("  ! equip_wiki 없음 — 먼저 scripts/tools/extract_equip_icons.py 를 돌린다",
              file=sys.stderr)
        return {}
    return json.loads(p.read_text(encoding="utf-8")).get("rows", {})

def load_frames(sub: str) -> dict:
    p = CONV / sub / "_manifest.json"
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))

def build_map(subs: list[str]) -> dict:
    frames: dict[str, str] = {}
    for sub in subs + ["item_small_ui", "item_etc", "item_mtr", "item_egg",
                       "item_food", "item_spc", "item_doc", "item_quest",
                       "gem_soul"]:
        for k in load_frames(sub):
            frames.setdefault(k, sub)

    def find(*cands: str) -> tuple[str, str] | None:
        for c in cands:
            if c in frames:
                return frames[c], c
        return None

    out: dict = {"_source": "scripts/tools/build_item_icons.py — 원본 아틀라스 프레임명 스캔",
                 "_note": "논리키 → {dir, frame}. render 층만 이 표를 보고 AtlasTexture 를 로드한다(§8.4).",
                 "_soul_note": "소울젬 4종×10단계는 원작 후기 추가분이라 `item/gem` 아틀라스(190=10종×19티어)에 "
                               "없다. 커뮤니티 위키 PDF '사진' 열에 원본이 알파까지 실려 있어 "
                               "`extract_soul_gem_icons.py` 로 복원해 `assets/converted/gem_soul/` 에 굽는다"
                               ". 교차검증: 같은 PDF §2.2.7 꼬리 10장 ↔ 우리 `gem_white9~18` RMSE 10~11. "
                               "이전 구현의 '일반젬 최고티어 폴백'은 폐기 — 가방에서 일반젬과 같은 그림으로 보였다.",
                 "_bg_note": "equipment_bg = 아이콘 **뒤**에 깔고 희귀도 색을 입히는 흰 실루엣. "
                             "원작이 `<이름>_bg.png` 로 만들어 "
                             "rarity(2~6)에 따라 setColor 한다(1=일반은 아예 안 그림). "
                             "논리키는 equipment_basic/artifact/event 와 같다.",
                 "_wiki_note": "event(19) · special(12) · piece(6) · exclusive(95) 는 원작 후기 "
                               "업데이트분이라 아이콘 아틀라스(`item/newaccessory*` · `raidpiece_*`)가 "
                               "우리 구판 덤프에 통째로 없다. 커뮤니티 위키 PDF 표의 '사진' 열에 원본이 "
                               "알파까지 실려 있어 `extract_equip_icons.py` 로 복원해 "
                               "`assets/converted/equip_wiki/` 에 굽는다. "
                               "**원본 아틀라스에 있는 것은 항상 그쪽이 우선**이고(이벤트 6종), "
                               "위키본은 없는 것만 채운다 — 위키 이미지는 PDF 재압축을 한 번 거친다.",
                 "equipment_basic": {}, "artifact": {}, "event": {}, "gem": {},
                 "equipment_bg": {}, "shop": {},
                 "special": {}, "piece": {}, "exclusive": {}}

    for kr, pre in BASIC_PREFIX.items():
        for gi in range(7):
            hit = find(f"item_accessory_{pre}{gi + 1}", f"item_small_acc_{pre}{gi + 1}")
            if hit:
                out["equipment_basic"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    for kr, pre in ARTIFACT_PREFIX.items():
        for gi in range(6):
            hit = find(f"item_accessory_{pre}{gi + 1}", f"item_small_acc_{pre}{gi + 1}")
            if hit:
                out["artifact"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    for kr, pre in EVENT_ICON.items():
        hit = find(f"item_accessory_{pre}", f"item_small_acc_{pre}")
        if hit:
            out["event"][kr] = {"dir": hit[0], "frame": hit[1]}
    for code, pre in GEM_PREFIX.items():
        for t in range(19):
            hit = find(f"item_gem_{pre}{t}")
            if hit:
                out["gem"][f"{code}:{t}"] = {"dir": hit[0], "frame": hit[1]}
    for code, pre in SOUL_PREFIX.items():
        for t in range(SOUL_STAGES):
            hit = find(f"gem_soul_{pre}{t}")
            if hit:
                out["gem"][f"{code}:{t}"] = {"dir": hit[0], "frame": hit[1]}

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
            hit = find(f"item_accessory_artifact{gi + 1}_bg")
            if hit:
                out["equipment_bg"][f"{kr}:{gi}"] = {"dir": hit[0], "frame": hit[1]}
    for kr, pre in EVENT_ICON.items():
        hit = find(f"item_accessory_{pre}_bg")
        if hit:
            out["equipment_bg"][kr] = {"dir": hit[0], "frame": hit[1]}

    rows = wiki_rows()
    for r in rows.get("event", []):
        out["event"].setdefault(str(r["ours"]), {"dir": "equip_wiki", "frame": r["frame"],
                                                 "from_wiki": True})
    for r in rows.get("special", []):
        out["special"][str(r["ours"])] = {"dir": "equip_wiki", "frame": r["frame"],
                                          "from_wiki": True}
    for r in rows.get("piece", []):
        out["piece"][str(r["ours"])] = {"dir": "equip_wiki", "frame": r["frame"],
                                        "from_wiki": True}
    for r in rows.get("exclusive", []):
        key = re.sub(r"\[\d+\]", "", str(r["wiki_name"])).strip()
        out["exclusive"][key] = {"dir": "equip_wiki", "frame": r["frame"], "from_wiki": True}
    for dst, src in EXCLUSIVE_ALIAS.items():
        if src not in out["exclusive"]:
            print("[build_item_icons] 별칭 원본 '%s' 가 없어 '%s' 는 건너뛴다"
                  % (src, dst))
            continue
        out["exclusive"][dst] = dict(out["exclusive"][src], alias_of=src)

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
    n = sum(len(m[k]) for k in ("equipment_basic", "gem", "artifact", "event", "equipment_bg", "shop",
                             "special", "piece", "exclusive"))
    if "--dry" in sys.argv:
        for sec in ("equipment_basic", "artifact", "event", "gem", "equipment_bg", "shop",
                    "special", "piece", "exclusive"):
            keys = list(m[sec])[:6]
            print(f"  {sec}: {len(m[sec])}건  예: {keys}")
        return
    OUT.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[build_item_icons] wrote %s: basic=%d artifact=%d event=%d gem=%d bg=%d shop=%d "
          "special=%d piece=%d exclusive=%d (total %d)" % (
              OUT.relative_to(REPO), len(m["equipment_basic"]), len(m["artifact"]),
              len(m["event"]), len(m["gem"]), len(m["equipment_bg"]), len(m["shop"]),
              len(m["special"]), len(m["piece"]), len(m["exclusive"]), n))

if __name__ == "__main__":
    main()
