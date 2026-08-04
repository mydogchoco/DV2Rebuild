"""디컴파일러가 **포기하는 거대 함수**를 읽어 내는 우회 도구.

## 왜 필요한가 (2026-08-04)

`MakeInterface::action` @01062fd4 (28,968B) = 콜로세움/탐험 전투의 **안무 마스터 디스패처**.
`batch_decompile.py --max 20000` 도 `pyghidra_probe.py --max 40000` 도 실패했고, 실패 사유는
크기 상한이 아니라 **디컴파일러 프로세스 타임아웃**이었다:

    /* 실패: action @ 01062fd4 — Exception while decompiling 01062fd4: process: timeout */

즉 `--max` 를 아무리 올려도 안 된다 — 올려야 하는 건 **디컴파일 타임아웃**이고,
그래도 안 되면 C 로 복원하는 것 자체를 포기하고 **디스어셈블리에서 읽어야** 한다.

## 이 도구가 하는 일 (순서대로 시도)

1. `--timeout N` (기본 1800초) 로 정식 디컴파일.
2. 실패하면 **간이 정규화 스타일**(`normalize`)로 재시도 — 구조화(루프/if 복원)를 건너뛰므로
   훨씬 빨리 끝난다. 변수명은 흉하지만 **상수와 호출 순서**는 그대로 나온다.
3. 그래도 실패하면 **주석 붙은 디스어셈블리**를 뽑는다. 이건 절대 실패하지 않는다 —
   호출 대상 이름 · 문자열/데이터 참조 · 부동소수 리터럴을 각 줄에 붙여 준다.
   우리가 안무에서 원하는 것(`CCMoveBy::create(0.05, (x,y))` 같은 **수치**)은 여기서 읽힌다.

## ⚠️ 실측 결론 (2026-08-05, `action` @01062fd4 기준)

**타임아웃을 올려도 소용없다.** 240초 → 300초 → 2700초로 올려 봤더니 증상이 바뀐다:
`process: timeout` 메시지조차 못 남기고 **파이썬 프로세스가 통째로 조용히 죽는다**
(exit 0, 출력·산출 파일 없음). `normalize` 스타일도 같다. 즉 디컴파일러 네이티브 프로세스가
죽으면서 pyghidra 를 같이 끌고 내려간다 ⇒ 이 함수는 **C 로 복원할 수 없다.**

⇒ 이런 함수는 처음부터 `--asm-only` 로 가고, 결과를 `asm_read.py` 로 접어서 읽는다.
   실제로 `action` 의 기본 공격 안무(스파인 이름·재생속도 1.125·타격 프레임 ÷30·
   ScaleTo 3단 1.25/1.05 → 0.90/0.95 → 1.00/1.00)는 전부 그 경로로 복원했다.
   교훈: **"디컴프에 없다" ≠ "바이너리에 없다"** — `dv2-decomp-skip-trap` 의 세 번째 함정이다.

## 사용

    python scripts/tools/decomp_big.py 0x01062fd4 --out docs/ref/orig_code/probe/action_probe.c
    python scripts/tools/decomp_big.py 0x01062fd4 --asm-only        # 디컴파일 건너뛰고 ASM 만
    python scripts/tools/decomp_big.py 0x01062fd4 --timeout 3600

⚠️ 저장된 Ghidra 분석을 **읽기만** 한다(`analyze=False`, 함수 생성·분할 없음).
   프로젝트 DB 를 건드리면 `batch_decompile.py` 산출물과 어긋나므로 변형은 하지 않는다.
"""
from __future__ import annotations
import os, sys, time
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
SO_PATH = REPO / "libgame.so"
if not SO_PATH.exists():
    SO_PATH = REPO / "lib" / "arm64-v8a" / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"
DEFAULT_OUT = REPO / "docs" / "ref" / "orig_code" / "probe" / "big_fn_probe.c"


def parse_args(argv):
    out, timeout, asm_only, targets, rng = DEFAULT_OUT, 1800, False, [], None
    disasm_table = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out":
            out = Path(argv[i + 1]); i += 2
        elif a == "--timeout":
            timeout = int(argv[i + 1]); i += 2
        elif a == "--asm-only":
            asm_only = True; i += 1
        elif a == "--range":
            lo, hi = argv[i + 1].split(","); rng = (int(lo, 16), int(hi, 16)); i += 2
        elif a == "--disasm-table":
            disasm_table = argv[i + 1]; i += 2
        else:
            targets.append(a); i += 1
    return targets, out, timeout, asm_only, rng, disasm_table


def annotate(flat, program, body) -> list[str]:
    """주석 붙은 디스어셈블리 — 호출 대상 이름 · 데이터 참조값을 각 줄에 단다.

    `body` = AddressSetView 또는 (시작, 끝) 주소쌍.
    ⚠️ 함수 본체(`func.getBody()`)만 뜨면 **간접 분기(`br xN`) 목적지 블록이 빠진다** —
       Ghidra 가 점프테이블을 못 풀면 그 블록들을 함수에 귀속시키지 않기 때문이다.
       실측(action @01062fd4): 본체 덤프에 **구멍 16군데**, 핸들러 53개 중 52개가 누락.
       그래서 분기 정체를 볼 때는 `--range` 로 **주소 구간**을 떠야 한다.
    """
    listing = program.getListing()
    fm = program.getFunctionManager()
    out = []
    it = listing.getInstructions(body, True)
    while it.hasNext():
        ins = it.next()
        line = f"{ins.getAddress()}  {ins}"
        notes = []
        for ref in ins.getReferencesFrom():
            to = ref.getToAddress()
            if to is None:
                continue
            callee = fm.getFunctionAt(to)
            if callee is not None:
                notes.append(f"-> {callee.getName(True)}")
                continue
            d = listing.getDataAt(to)
            if d is not None:
                v = d.getValue()
                if v is not None:
                    # 문자열·부동소수 리터럴이 여기서 잡힌다(안무 수치의 출처).
                    notes.append(f"[{to}] = {v!s}")
        # 즉시값(mov/movz/fmov)도 그대로 보이지만, 스칼라를 10진으로 한 번 더 적어 준다.
        for k in range(ins.getNumOperands()):
            sc = ins.getScalar(k)
            if sc is not None and abs(sc.getValue()) > 9:
                notes.append(f"#{sc.getValue()}=0x{sc.getUnsignedValue():x}")
        if notes:
            line += "    ; " + "  ".join(notes)
        out.append(line)
    return out


def main() -> int:
    targets, out_path, timeout, asm_only, rng, disasm_table = parse_args(sys.argv[1:])
    if not targets and rng is None:
        print(__doc__)
        return 2

    import pyghidra
    pyghidra.start()
    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.util.task import ConsoleTaskMonitor

    with pyghidra.open_program(
        str(SO_PATH), project_location=str(PROJECT_DIR),
        project_name=PROJECT_NAME, analyze=False,
    ) as flat:
        program = flat.getCurrentProgram()
        af = program.getAddressFactory().getDefaultAddressSpace()
        fm = program.getFunctionManager()
        monitor = ConsoleTaskMonitor()

        chunks = ["/* decomp_big.py — 디컴파일러가 포기한 거대 함수. "
                  "①정식 ②normalize ③주석 디스어셈블리 순으로 시도. */\n"]

        # `--disasm-table VA,COUNT,BASE,STRIDE` — 점프테이블 목적지를 **직접 디스어셈블**한다.
        # ⚠️ 이건 Ghidra 프로젝트 DB 를 **수정한다**(유일한 쓰기 경로).
        #   간접 분기를 못 푼 Ghidra 가 목적지 블록을 미정의 바이트로 남겨 두기 때문에,
        #   그 자리를 코드로 인식시키지 않으면 분기 정체를 볼 방법이 없다.
        #   원본 `libgame.so` 와 `DV2/` 는 건드리지 않는다 — 손상돼도 재임포트로 복구된다.
        if disasm_table:
            import struct as _st
            va, cnt, base, stride = disasm_table.split(",")
            blob = SO_PATH.read_bytes()
            o = int(va, 16) - 0x100000
            tgts = sorted({int(base, 16) + _st.unpack_from("<H", blob, o + k * 2)[0] * int(stride)
                           for k in range(int(cnt))})
            tx = program.startTransaction("asm_cfg disassemble")
            ok = 0
            try:
                for t in tgts:
                    try:
                        if flat.disassemble(af.getAddress(t)):
                            ok += 1
                    except Exception:  # noqa: BLE001,PERF203
                        pass
            finally:
                program.endTransaction(tx, True)
            print(f"점프테이블 목적지 {len(tgts)}개 중 {ok}개 디스어셈블")

        # `--range` — 함수 귀속과 무관하게 **주소 구간**을 통째로 뜬다.
        # 간접 분기(`br xN`) 목적지 블록은 함수 본체에 안 들어가므로 이 모드가 필요하다.
        if rng is not None:
            from ghidra.program.model.address import AddressSet
            lo, hi = rng
            aset = AddressSet(af.getAddress(lo), af.getAddress(hi))
            body = annotate(flat, program, aset)
            print(f"range {lo:08x}..{hi:08x} — 명령 {len(body)}개")
            chunks.append(f"\n/* ==== RANGE {lo:08x}..{hi:08x} ==== */\n")
            chunks.append("\n".join(body) + "\n")
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text("\n".join(chunks), encoding="utf-8")
            print(f"-> {out_path}")
            return 0

        for q in targets:
            func = None
            if q.startswith("0x"):
                addr = af.getAddress(int(q, 16))
                func = fm.getFunctionAt(addr) or fm.getFunctionContaining(addr)
            else:
                for f in fm.getFunctions(True):
                    if q.lower() in f.getName(True).lower():
                        func = f
                        break
            if func is None:
                print(f"! {q}: 함수 못 찾음")
                continue
            addr = func.getEntryPoint().toString()
            size = func.getBody().getNumAddresses()
            print(f"{addr}: {func.getName()}  size={size}")

            code = None
            if not asm_only:
                for style in ("decompile", "normalize"):
                    decomp = DecompInterface()
                    opts = DecompileOptions()
                    opts.setMaxPayloadMBytes(512)
                    decomp.setOptions(opts)
                    decomp.toggleCCode(True)
                    decomp.toggleSyntaxTree(True)
                    decomp.setSimplificationStyle(style)
                    decomp.openProgram(program)
                    t0 = time.time()
                    try:
                        res = decomp.decompileFunction(func, timeout, monitor)
                        ok = res is not None and res.decompileCompleted()
                        msg = "" if ok else (res.getErrorMessage() if res else "no result")
                    except Exception as e:  # noqa: BLE001
                        ok, msg = False, str(e)
                    dt = time.time() - t0
                    print(f"  [{style}] {'OK' if ok else 'FAIL'} ({dt:.0f}s) {msg}")
                    decomp.dispose()
                    if ok:
                        code = (f"/* 디컴파일 성공 — style={style}, {dt:.0f}s */\n"
                                + res.getDecompiledFunction().getC())
                        break

            chunks.append(f"\n/* ==== {func.getName()} @ {addr} (size={size}) ==== */\n")
            if code:
                chunks.append(code + "\n")
            else:
                print("  → 주석 디스어셈블리로 대체")
                chunks.append("/* 디컴파일 실패 — 주석 붙은 디스어셈블리 (호출대상·데이터참조·스칼라) */\n")
                chunks.append("\n".join(annotate(flat, program, func)) + "\n")

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(chunks), encoding="utf-8")
        print(f"-> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
