"""저장된 dv2 프로젝트에서 특정 함수만 재디컴파일(진단 포함).

용도: 개별 함수를 긴 타임아웃으로 디컴파일. 재분석 없음(저장된 분석 재사용).
인자는 두 형태를 섞어 쓸 수 있다:
  - `0x00fac9d4` (16진 주소) → 그 주소의 함수
  - `showDamage` (이름 부분문자열, 소문자 비교) → 매칭되는 모든 함수(썽크/게터 제외 우선)

큰 함수(레이아웃 init 등)는 --max N 으로 상한(주소 개수) 지정 가능(기본 8000).
출력 파일은 --out 경로로 변경(기본 docs/ref/orig_code/probe/formulas_probe.c).

사용:  python scripts/tools/pyghidra_probe.py showDamage setAnimatedAttack basicAction --out docs/ref/orig_code/probe/render_probe.c
"""
from __future__ import annotations
import os, sys
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO_ROOT = Path(__file__).resolve().parents[2]
SO_PATH = REPO_ROOT / "lib" / "arm64-v8a" / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"
OUT_PATH = REPO_ROOT / "docs" / "ref" / "orig_code" / "probe" / "formulas_probe.c"


def parse_args(argv):
    out = OUT_PATH
    max_sz = 8000
    queries = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out":
            out = Path(argv[i + 1]); i += 2; continue
        if a == "--max":
            max_sz = int(argv[i + 1]); i += 2; continue
        queries.append(a); i += 1
    if not queries:
        queries = ["0x00fac9d4", "0x0100f070"]
    return queries, out, max_sz


def is_thunk_or_getter(func, size):
    # 썽크(PTR 간접호출)·단순 게터는 연출 분석에 무의미 → 작은 것 위주로 스킵
    return size <= 12


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    queries, out_path, max_sz = parse_args(sys.argv[1:])

    import pyghidra
    pyghidra.start()
    from ghidra.app.decompiler import DecompInterface
    from ghidra.app.decompiler import DecompileOptions
    from ghidra.util.task import ConsoleTaskMonitor

    with pyghidra.open_program(
        str(SO_PATH), project_location=str(PROJECT_DIR),
        project_name=PROJECT_NAME, analyze=False,   # 재분석 금지: 저장분석 사용
    ) as flat:
        program = flat.getCurrentProgram()
        af = program.getAddressFactory().getDefaultAddressSpace()
        fm = program.getFunctionManager()
        decomp = DecompInterface()
        opts = DecompileOptions()
        opts.setMaxPayloadMBytes(200)   # 큰 함수 허용
        decomp.setOptions(opts)
        decomp.openProgram(program)
        monitor = ConsoleTaskMonitor()

        # 질의 해석 → 대상 함수 집합(주소 중복 제거)
        picked = {}   # entry addr str -> func
        skipped = []  # (name, size) 상한 초과
        for q in queries:
            if q.startswith("0x"):
                addr = af.getAddress(int(q, 16))
                f = fm.getFunctionAt(addr) or fm.getFunctionContaining(addr)
                if f is None:
                    try:
                        f = flat.createFunction(addr, None)
                    except Exception:  # noqa: BLE001
                        print(f"{q}: 함수 인식 실패"); continue
                picked[f.getEntryPoint().toString()] = f
            else:
                ql = q.lower()
                qualified = "::" in q   # "Class::method" 형태면 정규화 이름으로 매칭
                for f in fm.getFunctions(True):
                    hay = f.getName(True).lower() if qualified else f.getName().lower()
                    if ql in hay:
                        picked[f.getEntryPoint().toString()] = f

        chunks = ["/* pyghidra_probe.py — 개별 함수 디컴파일. 레이아웃/연출 코드 근거. */\n"]
        done = 0
        for addr, func in sorted(picked.items(), key=lambda kv: kv[1].getName()):
            size = func.getBody().getNumAddresses()
            if is_thunk_or_getter(func, size):
                continue
            if size > max_sz:
                skipped.append((func.getName(), size, addr))
                continue
            try:
                res = decomp.decompileFunction(func, 240, monitor)
                code = (res.getDecompiledFunction().getC()
                        if res and res.decompileCompleted()
                        else f"/* 실패: {func.getName()} @ {addr} — "
                             f"{res.getErrorMessage() if res else 'no result'} */")
            except Exception as e:  # noqa: BLE001
                code = f"/* 예외: {func.getName()} @ {addr} — {e} */"
            chunks.append(f"\n/* ==== {func.getName()} @ {addr} (size={size}) ==== */\n{code}\n")
            print(f"{addr}: {func.getName()}  size={size}")
            done += 1

        if skipped:
            chunks.append("\n/* --- 상한(--max) 초과로 스킵된 큰 함수들 --- */\n")
            for n, s, a in sorted(skipped, key=lambda x: -x[1]):
                chunks.append(f"/*   {n} @ {a}  size={s} */\n")
                print(f"[skip] {n} @ {a} size={s}")

        out_path.write_text("\n".join(chunks), encoding="utf-8")
        print(f"-> {out_path}  ({done}개 디컴파일, {len(skipped)}개 스킵)")


if __name__ == "__main__":
    main()
