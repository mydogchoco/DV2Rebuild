"""libgame.so 원시 디스어셈블 덤프 — 디컴프 C 로 안 보이는 구조를 눈으로 읽는 용도.

## 왜 필요한가

`batch_decompile.py` 의 C 출력은 (a) `[skip>8000]` 으로 큰 함수를 건너뛰고,
(b) Ghidra 가 함수 꼬리를 짧게 잡으면 코드가 통째로 빠지며,
(c) switch 의 같은 본문 case 라벨을 합쳐 버린다.
**점프 테이블·비교 체인 같은 제어 구조는 C 로는 못 본다** — 명령을 직접 읽어야 한다.
`extract_switch_flow.py` 가 물린 함정(엔트리 폭 `ldrb`, 지배 cmp 방향)도 전부 이 수준에서 났다.

## 사용

    python scripts/tools/disasm.py Scenario1::setNext            # 함수 이름(부분 일치)
    python scripts/tools/disasm.py 0x1568f00 --count 400         # 주소에서 N 명령
    python scripts/tools/disasm.py 0x1568f00 --to 0x1569100      # 주소 구간
    python scripts/tools/disasm.py Scenario7::setNext --grep "0x158|0x168"   # 걸러 보기
    python scripts/tools/disasm.py 0x2244360 --data u32 --count 20           # .rodata 표 덤프

`--follow` 는 함수 진입점에서 시작하되 Ghidra 가 잡은 크기를 믿지 않고
`--count` 만큼 계속 읽는다(꼬리 절단 회피). 기본 동작이 그렇다.
"""
from __future__ import annotations
import os, re, sys
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO = Path(__file__).resolve().parents[2]
SO_PATH = REPO / "lib" / "arm64-v8a" / "libgame.so"
if not SO_PATH.exists():
    SO_PATH = REPO / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"


def parse_args(argv):
    o = {"targets": [], "count": 200, "to": None, "grep": None, "data": None, "calls": False,
         "force": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True; i += 1
        elif a == "--count":
            o["count"] = int(argv[i + 1], 0); i += 2
        elif a == "--to":
            o["to"] = int(argv[i + 1], 0); i += 2
        elif a == "--grep":
            o["grep"] = argv[i + 1]; i += 2
        elif a == "--data":
            o["data"] = argv[i + 1]; i += 2      # u8 | u16 | u32 | s32
        elif a == "--calls":
            o["calls"] = True; i += 1
        else:
            o["targets"].append(a); i += 1
    return o


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    o = parse_args(sys.argv[1:])
    if not o["targets"]:
        print(__doc__); return
    import pyghidra
    pyghidra.start()
    with pyghidra.open_program(str(SO_PATH), project_location=str(PROJECT_DIR),
                               project_name=PROJECT_NAME, analyze=False) as flat:
        prog = flat.getCurrentProgram()
        fm = prog.getFunctionManager()
        listing = prog.getListing()
        af = prog.getAddressFactory().getDefaultAddressSpace()
        mem = prog.getMemory()
        rx = re.compile(o["grep"]) if o["grep"] else None

        def resolve(q: str) -> list[tuple[int, str]]:
            if q.startswith("0x"):
                return [(int(q, 16), q)]
            ql = q.lower()
            hits = []
            for f in fm.getFunctions(True):
                if ql in f.getName(True).lower():
                    hits.append((f.getEntryPoint().getOffset(), f.getName(True)))
            return sorted(hits)

        for q in o["targets"]:
            for addr, label in resolve(q):
                print(f"\n===== {label} @ {addr:#x} =====")
                if o["data"]:
                    _dump_data(mem, af, addr, o["data"], o["count"])
                    continue
                if o["force"]:
                    _force(flat, af, addr, o["count"], o["to"])
                cur = listing.getInstructionAt(af.getAddress(addr))
                if cur is None:
                    print("  (명령 없음 — 데이터 구간이거나 미분석. --force 로 강제 해석)")
                    continue
                for _ in range(o["count"]):
                    if cur is None:
                        break
                    a = cur.getAddress().getOffset()
                    if o["to"] is not None and a > o["to"]:
                        break
                    s = re.sub(r"\s+", " ", str(cur).strip())
                    if o["calls"] and cur.getMnemonicString() == "bl":
                        fl = cur.getFlows()
                        callee = fm.getFunctionAt(fl[0]) if fl else None
                        if callee is not None:
                            s += f"   ; {callee.getName(True)}"
                    if rx is None or rx.search(s):
                        print(f"  {a:#010x}  {s}")
                    nxt = listing.getInstructionAfter(cur.getAddress())
                    # ⚠️ `getInstructionAfter` 는 미해석 바이트를 **조용히 건너뛴다** —
                    #    빠진 구간을 표시하지 않으면 없는 제어 흐름을 있다고 읽게 된다.
                    if nxt is not None and nxt.getAddress().getOffset() != a + cur.getLength():
                        print(f"  ---- 미해석 {a + cur.getLength():#x}"
                              f"~{nxt.getAddress().getOffset():#x} (--force 로 해석) ----")
                    cur = nxt


def _force(flat, af, addr: int, count: int, to: int | None) -> None:
    """미해석 바이트를 강제로 명령으로 해석한다.

    Ghidra 가 `setNext` 의 함수 꼬리를 짧게 잡으면 그 뒤 case 블록이 통째로 미해석으로 남고,
    listing 순회가 그 구간을 **조용히 건너뛴다**(없는 흐름을 있다고 읽게 된다).
    """
    end = to if to is not None else addr + count * 4
    a = addr
    while a <= end:
        try:
            flat.disassemble(af.getAddress(a))
        except Exception:                      # noqa: BLE001 — 데이터 구간이면 실패해도 무방
            pass
        a += 4


def _dump_data(mem, af, addr: int, kind: str, count: int) -> None:
    w = {"u8": 1, "u16": 2, "u32": 4, "s32": 4}[kind]
    for i in range(count):
        a = af.getAddress(addr + i * w)
        if w == 1:
            v = mem.getByte(a) & 0xFF
        elif w == 2:
            v = mem.getShort(a) & 0xFFFF
        else:
            v = mem.getInt(a)
            if kind == "u32":
                v &= 0xFFFFFFFF
        print(f"  [{i:3}] {addr + i * w:#010x}  {v:#x} ({v})")


if __name__ == "__main__":
    main()
