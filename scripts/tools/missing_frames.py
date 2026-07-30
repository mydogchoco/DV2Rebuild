#!/usr/bin/env python3
"""(C) 판정 전수 스캔 — 원작 코드가 참조하는데 **추출 에셋에 없는** 프레임을 전부 찾는다.

배경
----
CLAUDE.md §10 "에셋-코드 판본 불일치" 표는 지금까지 발견한 건만 수동으로 담았다.
그래서는 규모를 알 수 없다. 이 스크립트는 기계적으로 전수 조사한다:

  1. `docs/ref/orig_code/decomp/*.c` 에서 프레임 문자열 리터럴(`"경로/이름.png"` 등)을 전부 뽑는다.
  2. `DV2/480/**/*.img_plist` 의 `<key>…</key>` 전체 + 낱장 파일 목록을 인덱스로 만든다.
  3. (1)에 있는데 (2)에 없는 것 = **코드는 부르는데 에셋 덤프에 없는 프레임**.

주의(오탐 줄이기)
- `%d`/`%s` 가 든 포맷 문자열은 런타임 조립이라 그대로는 비교 불가 → 별도 분류.
- 확장자 없는 문자열, 아틀라스(.img_plist)·스파인(.spine_json)·사운드(.mp3)는 제외.
- 여기 나온다고 전부 "원작 후기판 추가분"은 아니다. 디컴파일 문자열 오인식도 있을 수 있으니
  **CLAUDE.md §10 표에 옮길 때는 폴더 단위로 3종 조회를 다시 돌려 확인**할 것.

사용:
    python scripts/tools/missing_frames.py                 # 요약(폴더별 집계)
    python scripts/tools/missing_frames.py --list          # 전체 목록
    python scripts/tools/missing_frames.py --md > out.md   # 마크다운 표
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"
ORIG = REPO / "DV2" / "480"

FRAME_LIT = re.compile(r'"([A-Za-z0-9_][A-Za-z0-9_/%.\-]*\.(?:png|jpg))"')
PLIST_KEY = re.compile(r"<key>([^<]+\.(?:png|jpg))</key>")


def build_asset_index() -> set[str]:
    keys: set[str] = set()
    for plist in ORIG.rglob("*.img_plist"):
        try:
            txt = plist.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        keys.update(PLIST_KEY.findall(txt))
    # 낱장 이미지(아틀라스 밖) — DV2/480 기준 상대경로
    for img in ORIG.rglob("*"):
        if img.suffix.lower() in (".png", ".jpg") and img.is_file():
            keys.add(img.relative_to(ORIG).as_posix())
    return keys


def collect_referenced() -> dict[str, set[str]]:
    """frame -> {참조한 클래스 파일명}"""
    refs: dict[str, set[str]] = defaultdict(set)
    for c in sorted(DECOMP.glob("*.c")):
        try:
            txt = c.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in FRAME_LIT.findall(txt):
            refs[m].add(c.stem)
    return refs


def main() -> None:
    args = set(sys.argv[1:])
    if not DECOMP.is_dir() or not ORIG.is_dir():
        raise SystemExit("docs/ref/orig_code/decomp 또는 DV2/480 이 없다")

    have = build_asset_index()
    # 아틀라스 키는 확장자 포함 경로. 낱장은 폴더 경로 포함. 두 형태를 모두 인덱스에 넣었다.
    refs = collect_referenced()

    fmt, missing = {}, {}
    for frame, classes in refs.items():
        if "%" in frame:
            fmt[frame] = classes
            continue
        if frame in have:
            continue
        # 낱장 파일이 하위폴더에 있을 수 있다 → 파일명만으로도 한 번 더 확인
        base = frame.split("/")[-1]
        if any(h.endswith("/" + base) or h == base for h in have):
            continue
        missing[frame] = classes

    by_dir = Counter(f.rsplit("/", 1)[0] if "/" in f else "(root)" for f in missing)

    if "--md" in args:
        print("| 폴더 | 없는 프레임 수 | 예시 | 참조 클래스(예시) |")
        print("|---|---:|---|---|")
        for d, n in by_dir.most_common():
            ex = [f for f in missing if (f.rsplit("/", 1)[0] if "/" in f else "(root)") == d][:3]
            cls = sorted(missing[ex[0]])[:3] if ex else []
            print(f"| `{d}/` | {n} | {', '.join('`'+e.split('/')[-1]+'`' for e in ex)} | {', '.join(cls)} |")
        return

    print(f"디컴파일에서 참조한 프레임 리터럴 : {len(refs)}")
    print(f"  · 포맷 문자열(%d/%s 포함, 비교 제외): {len(fmt)}")
    print(f"  · 에셋 덤프에 **없는** 프레임        : {len(missing)}")
    print()
    print("폴더별 집계(상위 25):")
    for d, n in by_dir.most_common(25):
        print(f"  {n:5d}  {d}/")
    if "--list" in args:
        print()
        for f in sorted(missing):
            print(f"  {f}   ← {', '.join(sorted(missing[f])[:3])}")


if __name__ == "__main__":
    main()
