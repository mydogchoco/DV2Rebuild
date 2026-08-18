#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
ORIG = REPO / "DV2"
CONV = REPO / "assets" / "converted"

NUM = re.compile(r"-?\d+")
KEY = re.compile(r"<key>([^<]+\.png)</key>")

def sanitize(name: str) -> str:
    return name.replace("/", "_").replace(".png", "")

def parse_braces(s: str) -> list[int]:
    return [int(x) for x in NUM.findall(s or "")]

def plist_frames(path: Path) -> dict[str, dict]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    if "<key>frames</key>" not in text:
        return {}
    out: dict[str, dict] = {}
    for m in KEY.finditer(text):
        name = m.group(1)
        end = text.find("</dict>", m.end())
        blk = text[m.end():end if end > 0 else m.end() + 700]
        fields = dict(re.findall(r"<key>(\w+)</key>\s*<string>([^<]*)</string>", blk))
        off = parse_braces(fields.get("offset", ""))
        src = parse_braces(fields.get("sourceSize") or fields.get("spriteSourceSize", ""))
        if len(off) == 2 and len(src) == 2:
            out[sanitize(name)] = {"off": off, "src": src}
    return out

def main() -> int:
    dry = "--dry" in sys.argv
    force = "--force" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]

    plists = [(p, plist_frames(p)) for p in sorted(ORIG.rglob("*.img_plist"))]
    plists = [(p, f) for p, f in plists if f]
    print(f"원본 plist {len(plists)}개 스캔")

    updated = skipped = unmatched = 0
    for mpath in sorted(CONV.glob("*/_manifest.json")):
        dirname = mpath.parent.name
        if only and dirname not in only:
            continue
        man = json.loads(mpath.read_text(encoding="utf-8"))
        if not man:
            continue
        if not force and all("src" in v for v in man.values() if isinstance(v, dict)):
            skipped += 1
            continue
        keys = {k for k, v in man.items() if isinstance(v, dict)}
        best, best_hit = None, 0
        for p, frames in plists:
            hit = len(keys & frames.keys())
            if hit > best_hit:
                best, best_hit = frames, hit
        if best is None or best_hit < len(keys) * 0.5:
            print(f"  ? {dirname:<18} 출처 plist 미확정 (최대 일치 {best_hit}/{len(keys)}) — 건너뜀")
            unmatched += 1
            continue
        n = 0
        for k in keys:
            if k in best and (force or "src" not in man[k]):
                man[k]["off"] = best[k]["off"]
                man[k]["src"] = best[k]["src"]
                n += 1
        if n == 0:
            continue
        trimmed = sum(1 for k in keys if man[k].get("off", [0, 0]) != [0, 0])
        print(f"  + {dirname:<18} {n}/{len(keys)} 프레임에 off/src 기입 (트림된 것 {trimmed})")
        if not dry:
            mpath.write_text(json.dumps(man, ensure_ascii=False, indent=1), encoding="utf-8")
        updated += 1
    print(f"갱신 {updated} / 이미완료 {skipped} / 미확정 {unmatched}" + ("  [--dry]" if dry else ""))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
