#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "music"
DST = REPO / "assets" / "music"
SCRIPTS = REPO / "scripts"

LITERAL = re.compile(r'Bgm\.(?:sfx|loop_sfx|play)\(\s*"([a-zA-Z0-9_]+)"')
PATTERNS = [
    re.compile(r"^effect_skill_\d+$"),
    re.compile(r"^effect_critical_[a-z0-9_]+$"),
    re.compile(r"^bg_\d+$"),
    re.compile(r"^effect_(bite|scratch|headbutt)$"),
    re.compile(r"^voice\d+$"),
    re.compile(r"^effect_egg$"),
    re.compile(r"^effect_dragon_damaged_[12]$"),
]

def wanted_keys() -> set[str]:
    keys: set[str] = set()
    for gd in SCRIPTS.rglob("*.gd"):
        try:
            keys.update(LITERAL.findall(gd.read_text(encoding="utf-8", errors="replace")))
        except OSError:
            continue
    import json
    wm = json.loads((REPO / "data" / "worldmap.json").read_text(encoding="utf-8"))
    for reg in wm.get("regions", []):
        if reg.get("bgm"):
            keys.add(str(reg["bgm"]))
        for snd in reg.get("native", {}).get("sounds", []):
            if snd.get("track"):
                keys.add(str(snd["track"]))
        for fx in reg.get("native", {}).get("field_fx", []):
            if fx.get("sound"):
                keys.add(str(fx["sound"]))
    kd = json.loads((REPO / "data" / "kades.json").read_text(encoding="utf-8"))
    if kd.get("bgm_worldmap"):
        keys.add(str(kd["bgm_worldmap"]))
    sf = REPO / "data" / "scenario_flow.json"
    if sf.exists():
        for track in json.loads(sf.read_text(encoding="utf-8")).get("bgm", {}).values():
            if track:
                keys.add(str(track))
    cs = REPO / "data" / "colosseum.json"
    if cs.exists():
        bgm = json.loads(cs.read_text(encoding="utf-8")).get("bgm", {})
        if bgm.get("lobby"):
            keys.add(str(bgm["lobby"]))
        for t in bgm.get("battle", []):
            keys.add(str(t))
    for mp3 in SRC.glob("*.mp3"):
        stem = mp3.stem
        if any(p.match(stem) for p in PATTERNS):
            keys.add(stem)
    return keys

def main() -> None:
    if not SRC.is_dir():
        raise SystemExit(f"원본 음원 폴더 없음: {SRC}")
    dry = "--dry" in sys.argv
    DST.mkdir(parents=True, exist_ok=True)
    keys = wanted_keys()
    copied = skipped = missing = 0
    for k in sorted(keys):
        src = SRC / f"{k}.mp3"
        dst = DST / f"{k}.mp3"
        if not src.exists():
            missing += 1
            print(f"  (원본 없음) {k}")
            continue
        if dst.exists():
            skipped += 1
            continue
        if not dry:
            shutil.copy2(src, dst)
        copied += 1
        print(f"  + {k}")
    print(f"\n참조 키 {len(keys)} / 복사 {copied} / 기존 {skipped} / 원본없음 {missing}")
    if not dry:
        print("Godot 에디터를 한 번 열거나 `--headless --import` 로 임포트할 것.")

if __name__ == "__main__":
    main()
