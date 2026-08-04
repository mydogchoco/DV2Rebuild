"""`decomp_big.py --asm-only` 산출물을 **읽을 수 있는 호출 흐름**으로 접는다.

디컴파일러가 포기한 함수는 ASM 으로만 읽히는데, 7천 줄 원본은 그대로는 못 읽는다.
이 도구가 ARM64 관용구 3가지를 사람 말로 바꿔 준다:

1. **부동소수 리터럴** — `fmov s1,0x3f900000` / `ldr s10,[…] = 0x3d088815`
   → `1.125` / `0.033333`(= 1/30, 프레임→초). 안무 수치가 전부 여기 있다.
2. **패킹된 SSO 문자열** — `mov w10,#0x7461` + `movk w10,#0x6174,LSL #16` + 길이바이트 `#0xc`
   → `"attack"`. 애니 이름·문자열 키가 이 꼴로 코드에 박혀 있다
   (`dv2-ghidra-memcmp-hex-length` 와 같은 계열의 함정 — 안 풀면 안 보인다).
3. **호출 흐름** — `bl` 만 남기고 그 앞 N줄에서 모은 상수/문자열을 인자 힌트로 붙인다.

사용:
    python scripts/tools/asm_read.py docs/ref/orig_code/probe/action_asm.c            # 호출 흐름
    python scripts/tools/asm_read.py <asm> --grep runSpine --ctx 40                   # 특정 호출 주변
    python scripts/tools/asm_read.py <asm> --floats                                   # 부동소수만 전수
    python scripts/tools/asm_read.py <asm> --strings                                  # 복원된 문자열만
"""
from __future__ import annotations
import re, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ADDR = re.compile(r"^([0-9a-f]{8})\s\s(.*?)(?:\s+;\s(.*))?$")
CALL = re.compile(r"-> ([A-Za-z0-9_:~.]+)")
# fmov sN,0x3f900000  /  ldr sN,[..] = 0x3d088815  /  mov wN,#0x3f800000
HEXF = re.compile(r"(?:fmov\s+[sd]\d+,|=\s*)0x([0-9a-f]{8})\b")
MOVI = re.compile(r"\bmov\s+(w\d+),#0x([0-9a-f]+)")
MOVK = re.compile(r"\bmovk\s+(w\d+),#0x([0-9a-f]+),\s*LSL\s*#(\d+)")


def f32(h: int) -> float:
    return struct.unpack("<f", struct.pack("<I", h))[0]


def pretty_float(v: float) -> str:
    """1/30 같은 '뻔한 분수'는 그대로 알려 준다 — 프레임레이트 환산이 자주 나온다."""
    for den in (24, 25, 30, 48, 50, 60):
        if abs(v - 1.0 / den) < 1e-6:
            return f"{v:.6g} (=1/{den})"
    return f"{v:.6g}"


def ascii_of(word: int, nbytes: int = 4) -> str:
    b = word.to_bytes(8, "little")[:nbytes]
    s = "".join(chr(c) if 32 <= c < 127 else "" for c in b)
    return s


def decode_strings(lines: list[str]) -> dict[int, str]:
    """`mov wN,#imm` (+ `movk wN,#imm,LSL#16`) 조합을 ASCII 로 되돌린다. 줄번호 → 문자열."""
    regs: dict[str, int] = {}
    out: dict[int, str] = {}
    for i, ln in enumerate(lines):
        m = MOVK.search(ln)
        if m:
            r, v, sh = m[1], int(m[2], 16), int(m[3])
            regs[r] = (regs.get(r, 0) & ~(0xFFFF << sh)) | (v << sh)
            t = ascii_of(regs[r])
            if len(t) >= 3:
                out[i] = t
            continue
        m = MOVI.search(ln)
        if m:
            r, v = m[1], int(m[2], 16)
            regs[r] = v
            t = ascii_of(v)
            if len(t) >= 3:
                out[i] = t
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = Path(sys.argv[1])
    grep = ctx = None
    mode = "flow"
    a = sys.argv[2:]
    i = 0
    while i < len(a):
        if a[i] == "--grep":
            grep = a[i + 1]; i += 2
        elif a[i] == "--ctx":
            ctx = int(a[i + 1]); i += 2
        elif a[i] == "--floats":
            mode = "floats"; i += 1
        elif a[i] == "--strings":
            mode = "strings"; i += 1
        else:
            i += 1
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    strs = decode_strings(lines)

    if mode == "floats":
        seen = {}
        for i, ln in enumerate(lines):
            for h in HEXF.findall(ln):
                v = f32(int(h, 16))
                if v == 0.0 or abs(v) > 1e7:
                    continue
                seen.setdefault(pretty_float(v), []).append(i + 1)
        for k in sorted(seen, key=lambda s: -len(seen[s])):
            print(f"{k:>22}  ×{len(seen[k]):<4} 줄 {seen[k][:12]}")
        return 0

    if mode == "strings":
        for i in sorted(strs):
            print(f"{i + 1:>6}  {strs[i]!r}   {lines[i].strip()}")
        return 0

    # 호출 흐름 — bl 줄마다 앞 `win` 줄에서 모은 상수/문자열을 인자 힌트로 붙인다.
    win = ctx or 14
    hits = []
    for i, ln in enumerate(lines):
        m = CALL.search(ln)
        if not m:
            continue
        name = m[1]
        if grep and grep.lower() not in name.lower():
            continue
        args = []
        for j in range(max(0, i - win), i):
            for h in HEXF.findall(lines[j]):
                v = f32(int(h, 16))
                if v != 0.0 and abs(v) < 1e7:
                    args.append(pretty_float(v))
            if j in strs:
                args.append(repr(strs[j]))
        addr = lines[i][:8]
        hits.append((i + 1, addr, name, args))

    for lineno, addr, name, args in hits:
        tail = ("  <- " + ", ".join(dict.fromkeys(args))) if args else ""
        print(f"{lineno:>6} {addr}  {name}{tail}")
    print(f"\n[{len(hits)}건]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
