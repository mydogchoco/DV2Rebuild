"""test_sundaegun_npc.gd 러너 — 임시 오토로드 등록 → 부팅 → 해제.

`run_test_colosseum.py` 와 같은 패턴(그 파일 주석 참조): `--script` 모드에는 오토로드가
없어 `NpcPortrait`(Data/Design 참조)가 컴파일되지 않으므로 부팅 경로에 임시로 얹는다.
등록 줄은 finally 에서 반드시 되돌린다(메모리: dv2-shothelper-autoload-gotcha).

사용:  python scripts/tools/run_test_sundaegun.py
"""
from __future__ import annotations
import subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJECT = REPO / "project.godot"
GODOT = Path(r"C:\Users\mydog\AppData\Local\Programs\Godot\Godot_v4.7-stable_win64_console.exe")
LINE = 'TestSundaegun="*res://scripts/tools/test_sundaegun_npc.gd"\n'
MARK = "[test_sundaegun]"


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if not GODOT.exists():
        print(f"Godot 실행파일 없음: {GODOT}")
        return 2
    original = PROJECT.read_text(encoding="utf-8")
    if "TestSundaegun=" in original:
        print("이미 등록돼 있다 — 이전 실행이 비정상 종료했을 수 있다. 수동 확인 필요.")
        return 2
    # 오토로드는 선언 순서대로 초기화 — Data 뒤에 오도록 [autoload] 섹션 끝에 넣는다.
    lines = original.splitlines(keepends=True)
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "[autoload]")
    except StopIteration:
        print("project.godot 에 [autoload] 섹션이 없다.")
        return 2
    last = start + 1
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            break
        if "=" in lines[i]:
            last = i + 1
    lines.insert(last, LINE)
    try:
        PROJECT.write_text("".join(lines), encoding="utf-8")
        r = subprocess.run(
            [str(GODOT), "--headless", "--path", str(REPO), "--quit-after", "600"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
        out = (r.stdout or "")
        for line in out.splitlines():
            if line.startswith("  ") or MARK in line or "SCRIPT ERROR" in line or "Parse Error" in line:
                print(line)
        for line in (r.stderr or "").splitlines():
            if "SCRIPT ERROR" in line or "Parse Error" in line:
                print(line)
        if MARK + " ALL PASS" in out:
            return 0
        if MARK not in out:
            print("테스트가 아예 실행되지 않았다 — 아래는 마지막 출력 20줄:")
            print("\n".join(out.splitlines()[-20:]))
        return 1
    finally:
        PROJECT.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
