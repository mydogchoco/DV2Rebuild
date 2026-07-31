#!/usr/bin/env python3
"""변환본 `_manifest.json` 에 **트림 오프셋**(`off`/`src`)을 채워 넣는다 — 추가만, 파괴 없음.

## 왜 필요한가 (2026-08-01 실측)

Cocos 아틀라스는 프레임의 투명 여백을 잘라내(trim) 넣고, plist 에
`offset`(트림중심 − 원본캔버스중심, y-up) 과 `sourceSize`(원본 캔버스) 를 남긴다.
원작 `CCSprite` 는 **원본 캔버스 기준**으로 배치하고 잘린 만큼 오프셋을 되돌린다.

`cocos_export.py` 는 지금은 이 두 값을 매니페스트에 쓰지만, **초기에 변환한 31개 폴더**
(common_ui · ninepatch_ui · cave_ui · worldmap_ui …)는 그 기능이 생기기 전에 만들어져
`w/h/rotated` 만 들어 있다. 그래서 그 프레임들을 "잘린 그림의 중심"에 놓게 되고,
오프셋이 큰 프레임은 **원작과 다른 위치**에 그려진다.

실측 사고: 동굴 둥지. `common/nest2`·`nest_holy2` 는 `sourceSize {184,184}` 에
`offset {-1,-37}` 이라 짚더미가 캔버스 중심보다 **37px 아래**에 있다. 오프셋을 무시하면
뒤쪽 짚더미가 알 **중턱**에 떠서 원작에 없는 노란 덩어리가 보인다
(원작 대조 실측: 알 옆 띠의 노랑 비율 원작 0.31/0.41 · 오프셋 무시 0.69/0.49 ·
오프셋 반영 0.30/0.38 — 반영본이 원작과 일치).

## 하는 일

`assets/converted/<dir>/_manifest.json` 의 키 집합을 `DV2/**/*.img_plist` 의
프레임 키 집합과 대조해 **출처 plist 를 자동으로 찾고**(추측 금지 — 키가 겹쳐야 인정),
`off`/`src` 만 추가한다. `w/h/rotated/was_rotated` 는 건드리지 않는다.
멱등이라 여러 번 돌려도 같다.

    python scripts/tools/backfill_trim_manifest.py            # 전체 스캔 + 갱신
    python scripts/tools/backfill_trim_manifest.py --dry      # 무엇이 바뀌는지만
    python scripts/tools/backfill_trim_manifest.py common_ui  # 특정 폴더만
    python scripts/tools/backfill_trim_manifest.py --force     # 이미 채워진 것도 다시 유도

읽는 쪽 = `AtlasUI.spr_cocos()`(원작 CCSprite 와 같은 배치). 이 값이 없는 프레임은
종전처럼 트림 중심 정렬로 떨어지므로, 채워 넣는 것만으로 회귀는 나지 않는다.
"""
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
    """plist → {sanitized_key: {off, src}}. 정규식 파싱 — plistlib 보다 빠르고 형식이 단순하다."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    if "<key>frames</key>" not in text:
        return {}
    out: dict[str, dict] = {}
    for m in KEY.finditer(text):
        name = m.group(1)
        # ⚠️ **반드시 `</dict>` 에서 자른다.** 고정 길이로 잘라 읽으면 다음 프레임의 dict 까지
        #    들어와 `dict(findall(...))` 이 **뒤 값으로 덮어써** 오프셋이 한 칸씩 밀린다
        #    (2026-08-01 실측: nest1 이 nest2 의 offset 을 받아 갔다).
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
    force = "--force" in sys.argv     # 이미 채워진 폴더도 plist 에서 다시 유도한다(값 수정 후 복구용)
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
        # 출처 plist = 매니페스트 키를 가장 많이 덮는 것. 절반도 못 덮으면 인정하지 않는다.
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
