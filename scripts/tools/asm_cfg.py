"""거대 함수의 **분기별 정체**를 CFG 로 특정한다.

## 왜 필요한가 (2026-08-05)

`MakeInterface::action` @01062fd4 는 점프테이블로 **53개 핸들러**에 분기하는데,
각 핸들러 입구는 `mov` 두어 줄 뒤 공통 본체로 `b` 하는 **짧은 스텁**이라
"입구~다음 입구" 로 잘라 보면 내용이 비어 있다(`asm_read.py --map` 의 한계).

그래서 **입구에서 CFG 를 따라가** 도달 가능한 호출·문자열·상수를 모으고,
**그 핸들러에서만 도달 가능한 것**(= 배타 신호)을 골라 낸다. 여러 핸들러가 공유하는
공통 본체는 자동으로 걸러진다.

## 쓰는 법

    # 점프테이블에서 핸들러 목록을 직접 뽑아 전수 추적
    python scripts/tools/asm_cfg.py <asm> --table 0x021b0708,225,0x010637a8,-54

    # 주소를 직접 주기
    python scripts/tools/asm_cfg.py <asm> --entries 0x01066ca4,0x01066ea0

    --budget N   핸들러당 방문 명령 상한(기본 6000)
    --all        배타 신호뿐 아니라 도달 전부를 출력

`--table VA,COUNT,BASE,FIRSTCODE` = `ldrh` 점프테이블 규약
(엔트리 e → 목적지 `BASE + e*4`, i 번째 엔트리의 액션코드 = `FIRSTCODE + i`).

## 한계

간접 분기(`br xN`)에서는 멈춘다. 공통 본체 안에서 다시 갈라지는 2차 테이블이 있으면
그쪽은 별도로 `--entries` 로 넣어야 한다.
"""
from __future__ import annotations
import re, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
VA_DELTA = 0x100000

LINE = re.compile(r"^([0-9a-f]{8})\s\s+(\S+)\s*(.*?)(?:\s+;\s(.*))?$")
HEX = re.compile(r"0x([0-9a-f]{4,})")
CALLN = re.compile(r"-> ([A-Za-z0-9_:~.]+)")
COND = ("cbz", "cbnz", "tbz", "tbnz")
STOP = ("ret", "br", "brk")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asm_read import f32, pretty_float, rodata_strings, decode_strings, _so_bytes  # noqa: E402


def parse(lines: list[str]):
    """주소 → (idx, mnemonic, operands, 주석). 그리고 idx 순 주소 배열."""
    ins, order = {}, []
    for i, ln in enumerate(lines):
        m = LINE.match(ln)
        if not m:
            continue
        a = int(m[1], 16)
        ins[a] = (i, m[2], m[3] or "", m[4] or "")
        order.append(a)
    return ins, order


def succs(addr: int, mn: str, ops: str, nxt: int | None) -> list[int]:
    """이 명령의 후속 주소들. `bl`(호출)은 분기가 아니다 — 함수 밖으로 나갔다 돌아온다."""
    if mn == "bl":
        return [nxt] if nxt is not None else []
    if mn in STOP:
        return []
    tgts = [int(h, 16) for h in HEX.findall(ops)]
    tgt = tgts[-1] if tgts else None
    if mn == "b":
        return [tgt] if tgt is not None else []
    if mn.startswith("b.") or mn in COND:
        out = [nxt] if nxt is not None else []
        if tgt is not None:
            out.append(tgt)
        return out
    return [nxt] if nxt is not None else []


def reach(entry: int, ins: dict, order: list[int], budget: int) -> set[int]:
    idx_of = {a: k for k, a in enumerate(order)}
    seen, stack = set(), [entry]
    while stack and len(seen) < budget:
        a = stack.pop()
        if a in seen or a not in ins:
            continue
        seen.add(a)
        k = idx_of[a]
        nxt = order[k + 1] if k + 1 < len(order) else None
        _, mn, ops, _c = ins[a]
        for s in succs(a, mn, ops, nxt):
            if s is not None and s not in seen:
                stack.append(s)
    return seen


def signals(addrs: set[int], ins: dict, lines: list[str], rod: dict, packed: dict):
    calls, strs, floats = [], [], []
    for a in addrs:
        i, _mn, _ops, note = ins[a]
        m = CALLN.search(note)
        if m:
            calls.append(m[1].split("::")[-1])
        if i in rod:
            strs.append(rod[i][1])
        if i in packed:
            strs.append(packed[i])
        for h in re.findall(r"(?:fmov\s+[sd]\d+,|=\s*)0x([0-9a-f]{8})\b", lines[i]):
            v = f32(int(h, 16))
            if v != 0.0 and abs(v) < 1e7:
                floats.append(pretty_float(v))
    return calls, strs, floats


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = Path(sys.argv[1])
    entries: dict[int, list[int]] = {}   # 주소 → 액션코드들
    budget, show_all = 6000, False
    a = sys.argv[2:]
    i = 0
    while i < len(a):
        if a[i] == "--table":
            va, cnt, base, first = a[i + 1].split(",")
            blob = (REPO / "libgame.so").read_bytes()
            off = int(va, 16) - VA_DELTA
            for k in range(int(cnt)):
                e = struct.unpack_from("<H", blob, off + k * 2)[0]
                entries.setdefault(int(base, 16) + e * 4, []).append(int(first) + k)
            i += 2
        elif a[i] == "--entries":
            for x in a[i + 1].split(","):
                entries.setdefault(int(x, 16), [])
            i += 2
        elif a[i] == "--budget":
            budget = int(a[i + 1]); i += 2
        elif a[i] == "--all":
            show_all = True; i += 1
        else:
            i += 1

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    ins, order = parse(lines)
    blob = _so_bytes()
    rod = rodata_strings(lines, blob) if blob else {}
    packed = decode_strings(lines)

    # 공통 본체(= 여러 핸들러가 도달하는 곳)를 걸러 내려면 소유자 수를 세야 한다.
    reachset = {e: reach(e, ins, order, budget) for e in entries}
    owners: dict[int, int] = {}
    for s in reachset.values():
        for a2 in s:
            owners[a2] = owners.get(a2, 0) + 1

    n = len(entries)
    print(f"핸들러 {n}개 · 명령 {len(ins)}개\n")
    for e in sorted(entries):
        codes = entries[e]
        excl = {a2 for a2 in reachset[e] if owners[a2] == 1}
        use = reachset[e] if show_all else excl
        calls, strs, floats = signals(use, ins, lines, rod, packed)
        label = ",".join(str(c) for c in codes) if codes else "-"
        print(f"== {e:08x}  code {label}   (도달 {len(reachset[e])} / 배타 {len(excl)})")
        if strs:
            print("     키   : " + ", ".join(dict.fromkeys(strs))[:300])
        if calls:
            print("     호출 : " + ", ".join(dict.fromkeys(calls))[:340])
        if floats and (strs or calls):
            print("     상수 : " + ", ".join(dict.fromkeys(floats))[:220])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
