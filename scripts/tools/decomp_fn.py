"""디컴프 `.c` 에서 **함수 하나의 본문만** 정확히 잘라 낸다.

왜 필요한가: `awk '/==== name @/,/^}$/'` 로 자르면 Ghidra 출력에서 종료 `}` 를 못 만나
**파일 끝까지 새어 나온다**(2026-07-31 실측 — setFightPass 를 뽑았더니 fountain·guild 프레임까지
딸려 나와 "원작이 쓴다"고 오판할 뻔했다). 블록 경계는 항상 다음 `/* ==== <name> @ <addr> ... */`
헤더이므로 그걸로 자르는 게 정확하다.

사용:
    python scripts/tools/decomp_fn.py <Class> <fn>            # 본문 출력(잡음 제거)
    python scripts/tools/decomp_fn.py <Class> <fn> --raw      # 원문 그대로
    python scripts/tools/decomp_fn.py <Class> <fn> --assets   # 그 함수가 쓰는 리터럴만
    python scripts/tools/decomp_fn.py <Class> --list          # 함수 목록(크기순)
"""
from __future__ import annotations
import re, sys
from pathlib import Path

# 콘솔이 cp949 라 '—' 같은 글자에서 죽는다(윈도우 기본). 출력만 UTF-8 로 강제한다.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"

HEAD = re.compile(r"^/\* ==== (?P<name>[A-Za-z_0-9~]+) @ (?P<addr>[0-9a-fA-Fx]+) \(size=(?P<size>\d+)\) ==== \*/")
# Ghidra 주석 잡음 — 읽을 때 방해만 된다.
NOISE = re.compile(r"^\s*(/\* )?(catch\(\)|try \{ // try|WARNING:|\*/)")
ASSET = re.compile(r'"([a-zA-Z0-9_/%.\-]+\.(?:png|jpg|jpeg|mp3|spine_json|fnt|plist|ccz))"')


def blocks(path: Path):
    """[(name, addr, size, [줄...]), ...] — 헤더 기준으로 자른다."""
    out, cur = [], None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = HEAD.match(line)
        if m:
            if cur:
                out.append(cur)
            cur = [m["name"], m["addr"], int(m["size"]), []]
        elif cur:
            cur[3].append(line)
    if cur:
        out.append(cur)
    return out


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    cls, fn = sys.argv[1], sys.argv[2]
    path = DECOMP / f"{cls}.c"
    if not path.exists():
        print(f"! {path} 없음 — batch_decompile.py 로 먼저 생성", file=sys.stderr)
        return 1
    bs = blocks(path)
    if fn == "--where":
        # 리터럴(또는 임의 문자열)이 **어느 함수 안에** 있는지. 프레임 소유자 특정용.
        needle = sys.argv[3]
        for name, addr, size, body in bs:
            for i, line in enumerate(body):
                if needle in line:
                    print(f"{name} @ {addr} (size={size})  |  {line.strip()[:110]}")
                    break
        return 0
    if fn == "--list":
        for name, addr, size, _ in sorted(bs, key=lambda b: -b[2]):
            print(f"{size:7d}  {name} @ {addr}")
        return 0
    hits = [b for b in bs if b[0] == fn]
    if not hits:
        print(f"! {cls}::{fn} 없음. 후보: " +
              ", ".join(sorted({b[0] for b in bs if fn.lower() in b[0].lower()})[:10]), file=sys.stderr)
        return 1
    # 같은 이름이 여럿이면(썽크 + 본체) **가장 큰 것**이 본체다.
    name, addr, size, body = max(hits, key=lambda b: b[2])
    raw = "--raw" in sys.argv
    if "--assets" in sys.argv:
        found = sorted({m for line in body for m in ASSET.findall(line)})
        print(f"=== {cls}::{name} @ {addr} (size={size}) — 리터럴 {len(found)} ===")
        for f in found:
            print(" ", f)
        return 0
    print(f"=== {cls}::{name} @ {addr} (size={size}) ===")
    for line in body:
        if raw or not NOISE.match(line):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
