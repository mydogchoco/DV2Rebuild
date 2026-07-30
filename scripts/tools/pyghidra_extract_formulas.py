"""libgame.so 공식 함수 디컴파일 (PyGhidra / CPython).

Ghidra 12는 Jython을 제거하고 PyGhidra(CPython)만 지원한다. 이 스크립트는 헤드리스
postScript가 아니라 **독립 실행 CPython**으로 pyghidra를 구동한다:
  1) 영구 Ghidra 프로젝트에 libgame.so를 임포트+자동분석(최초 1회, ~25분) 후 저장
  2) TARGETS에 매칭되는 함수를 디컴파일해 의사코드를 docs/ref/orig_code/probe/formulas_decompiled.c 로 덤프
재실행 시 저장된 분석을 재사용하므로 재분석이 없다(디컴파일만 수 초).

사전: pip install <ghidra>/Ghidra/Features/PyGhidra/pypkg/dist/pyghidra-*.whl
사용:  python scripts/tools/pyghidra_extract_formulas.py
"""
from __future__ import annotations
import os
import sys
from pathlib import Path

# --- 환경 (설치 경로) ---
os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO_ROOT = Path(__file__).resolve().parents[2]
SO_PATH = REPO_ROOT / "lib" / "arm64-v8a" / "libgame.so"
OUT_PATH = REPO_ROOT / "docs" / "ref" / "orig_code" / "probe" / "formulas_decompiled.c"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"

# 목표 함수(부분문자열, 소문자 비교). _symbol_map.md에서 선정.
TARGETS = [
    "calculatedamage",          # MapAttackLayer / UltimateLayer 데미지 진입점
    "gethealthvariation",       # FightManager 체력 변화
    "getbombdamage", "getpoisondamage", "getreflectdamage",
    "checklevelup",             # 레벨업 스탯 성장
    "getcontinuecost",          # 이어하기 비용 곡선
    "getduelscore", "getdueladdrankpoint", "getduelbaserankpoint",
    "getcurawakengage",         # 각성 게이지
    "initjsondragonhp", "initjsondragonaddvalue",  # 드래곤 스탯 JSON 파싱(필드순서 확정)
    "increaserapturestack",
]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    if not SO_PATH.exists():
        sys.exit(f"libgame.so 없음: {SO_PATH}")
    PROJECT_DIR.mkdir(parents=True, exist_ok=True)

    import pyghidra
    pyghidra.start()  # JVM 부팅

    from ghidra.app.decompiler import DecompInterface
    from ghidra.util.task import ConsoleTaskMonitor

    print(f"[pyghidra] 프로젝트={PROJECT_DIR}\\{PROJECT_NAME}  (최초 분석은 오래 걸림)")
    targets = [t.lower() for t in TARGETS]

    with pyghidra.open_program(
        str(SO_PATH),
        project_location=str(PROJECT_DIR),
        project_name=PROJECT_NAME,
        analyze=True,
    ) as flat:
        program = flat.getCurrentProgram()
        decomp = DecompInterface()
        decomp.openProgram(program)
        monitor = ConsoleTaskMonitor()
        fm = program.getFunctionManager()

        # 함수명 매칭(디맹글된 이름 기준). 중복 주소 방지.
        picked = {}
        for func in fm.getFunctions(True):
            low = func.getName().lower()
            if any(t in low for t in targets):
                picked[func.getEntryPoint().toString()] = func

        chunks = [
            "/* 자동생성: pyghidra_extract_formulas.py — libgame.so 공식 함수 디컴파일.\n"
            "   의사코드다(컴파일용 아님). 공식/상수 추출용 참고자료. */\n"
        ]
        for addr, func in sorted(picked.items(), key=lambda kv: kv[1].getName()):
            try:
                res = decomp.decompileFunction(func, 90, monitor)
                code = (res.getDecompiledFunction().getC()
                        if res and res.decompileCompleted()
                        else f"/* 디컴파일 실패: {func.getName()} */")
            except Exception as e:  # noqa: BLE001
                code = f"/* 예외: {func.getName()} ({e}) */"
            full = func.getName()
            chunks.append(f"\n/* ==== {full} @ {addr} ==== */\n{code}\n")
            print(f"[pyghidra] decompiled: {full} @ {addr}")

        OUT_PATH.write_text("\n".join(chunks), encoding="utf-8")
        print(f"[pyghidra] {len(picked)}개 함수 -> {OUT_PATH}")


if __name__ == "__main__":
    main()
