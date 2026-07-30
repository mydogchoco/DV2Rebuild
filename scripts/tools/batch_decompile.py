"""스켈레톤-우선 파이프라인 Phase 1 — 클래스 단위 일괄 디컴파일.

Ghidra 세션 오픈이 병목이므로, **여러 클래스를 한 세션에서** 디컴파일해 상각한다.
각 클래스의 모든 메서드를 디컴파일해 `docs/ref/orig_code/decomp/<Class>.c`로 저장(클래스별 1파일).
이미 있는 출력은 건너뜀(resume) — `--force`로 재생성.

클래스 목록 입력:
  --classes "WorldMapScene,CaveScene,DungeonScene"      쉼표구분
  --classlist path.txt                                   줄바꿈 구분 파일
  --from-ledger [tier]  docs/ref/design/scene_port_ledger.md 파싱해 해당 tier의 keep 클래스(기본 1)

옵션: --max N(함수 상한 주소수, 기본 8000) · --out-dir docs/ref/orig_code/decomp · --limit N(클래스 수 상한)

예:  python scripts/tools/batch_decompile.py --from-ledger 1 --limit 20
"""
from __future__ import annotations
import os, re, sys
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO_ROOT = Path(__file__).resolve().parents[2]
SO_PATH = REPO_ROOT / "lib" / "arm64-v8a" / "libgame.so"
if not SO_PATH.exists():
    SO_PATH = REPO_ROOT / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"
OUT_DIR = REPO_ROOT / "docs" / "ref" / "orig_code" / "decomp"
LEDGER = REPO_ROOT / "docs" / "ref" / "design" / "scene_port_ledger.md"


def parse_args(argv):
    classes: list[str] = []
    out_dir = OUT_DIR
    max_sz = 8000
    limit = 0
    force = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--classes":
            classes += [c.strip() for c in argv[i + 1].split(",") if c.strip()]; i += 2
        elif a == "--classlist":
            classes += [l.strip() for l in Path(argv[i + 1]).read_text(encoding="utf-8").splitlines() if l.strip()]; i += 2
        elif a == "--from-ledger":
            tier = "1"
            if i + 1 < len(argv) and argv[i + 1].isdigit():
                tier = argv[i + 1]; i += 1
            classes += ledger_classes(int(tier)); i += 1
        elif a == "--out-dir":
            out_dir = Path(argv[i + 1]); i += 2
        elif a == "--max":
            max_sz = int(argv[i + 1]); i += 2
        elif a == "--limit":
            limit = int(argv[i + 1]); i += 2
        elif a == "--force":
            force = True; i += 1
        else:
            classes.append(a); i += 1
    # 중복 제거(순서 유지)
    seen = set(); uniq = []
    for c in classes:
        if c not in seen:
            seen.add(c); uniq.append(c)
    if limit:
        uniq = uniq[:limit]
    return uniq, out_dir, max_sz, force


def ledger_classes(tier: int) -> list[str]:
    """원장 md에서 특정 tier 섹션의 `클래스` 열을 순서대로 추출."""
    if not LEDGER.exists():
        return []
    txt = LEDGER.read_text(encoding="utf-8")
    # "## Tier N" ~ 다음 "## " 사이의 `Class` 백틱 첫 열
    m = re.search(rf"## Tier {tier} .*?\n(.*?)(?:\n## |\Z)", txt, re.S)
    if not m:
        return []
    out = []
    for line in m.group(1).splitlines():
        cm = re.match(r"\|\s*`([^`]+)`\s*\|", line)
        if cm:
            out.append(cm.group(1))
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    classes, out_dir, max_sz, force = parse_args(sys.argv[1:])
    if not classes:
        print("클래스 목록이 비었음. --from-ledger 1 또는 --classes ... 지정."); return
    out_dir.mkdir(parents=True, exist_ok=True)

    # resume: 이미 있는 출력 스킵
    todo = [c for c in classes if force or not (out_dir / f"{c.replace('::','_')}.c").exists()]
    print(f"[batch] 대상 {len(classes)} · 처리 {len(todo)} (스킵 {len(classes)-len(todo)})")
    if not todo:
        print("모두 완료됨."); return

    import pyghidra
    pyghidra.start()
    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.util.task import ConsoleTaskMonitor

    with pyghidra.open_program(
        str(SO_PATH), project_location=str(PROJECT_DIR),
        project_name=PROJECT_NAME, analyze=False,
    ) as flat:
        program = flat.getCurrentProgram()
        fm = program.getFunctionManager()
        decomp = DecompInterface()
        opts = DecompileOptions(); opts.setMaxPayloadMBytes(200)
        decomp.setOptions(opts); decomp.openProgram(program)
        monitor = ConsoleTaskMonitor()

        # 클래스 → 메서드 함수들 (한 번만 전체 순회해 그룹화)
        want = {c: [] for c in todo}
        marks = {c: f"::{c}::" for c in todo}
        for f in fm.getFunctions(True):
            qual = "::" + f.getName(True)
            for c, mk in marks.items():
                if mk in qual:
                    want[c].append(f)

        for c in todo:
            funcs = want[c]
            chunks = [f"/* Phase 1 batch decompile — class {c} ({len(funcs)} methods) */\n"]
            done = skip = 0
            for f in sorted(funcs, key=lambda x: x.getName()):
                addr = f.getEntryPoint().toString()
                size = f.getBody().getNumAddresses()
                if size <= 12:  # 썽크/게터
                    continue
                if size > max_sz:
                    chunks.append(f"/*   [skip>{max_sz}] {f.getName()} @ {addr} size={size} */\n")
                    skip += 1; continue
                try:
                    res = decomp.decompileFunction(f, 240, monitor)
                    code = (res.getDecompiledFunction().getC()
                            if res and res.decompileCompleted()
                            else f"/* 실패: {f.getName()} @ {addr} */")
                except Exception as e:  # noqa: BLE001
                    code = f"/* 예외: {f.getName()} @ {addr} — {e} */"
                chunks.append(f"\n/* ==== {f.getName()} @ {addr} (size={size}) ==== */\n{code}\n")
                done += 1
            (out_dir / f"{c.replace('::','_')}.c").write_text("\n".join(chunks), encoding="utf-8")
            print(f"  {c}: {done} decompiled, {skip} skipped ({len(funcs)} methods)")

    print(f"-> {out_dir}  ({len(todo)}개 클래스)")


if __name__ == "__main__":
    main()
