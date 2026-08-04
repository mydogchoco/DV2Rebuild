"""test_colosseum.gd 러너 — 임시 오토로드 등록 → 부팅 → 해제.

왜 이렇게 도는가: Godot 의 `--script` 모드에는 **오토로드가 없다**. `Colosseum` 은
`Data`/`UserDB` 를 읽으므로 그 모드에선 컴파일조차 안 된다(메모리: dv2-godot-runtime-and-validation).
그래서 프로젝트 **부팅 경로**에 임시 오토로드로 얹어 돌린다.

⚠️ 등록 줄은 절대 커밋되면 안 된다(메모리: dv2-shothelper-autoload-gotcha) — 이 스크립트가
성공/실패/예외 어느 쪽이든 finally 에서 원본 project.godot 를 되돌린다.

사용:  python scripts/tools/run_test_colosseum.py
"""
from __future__ import annotations
import subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJECT = REPO / "project.godot"
GODOT = Path(r"C:\Users\mydog\AppData\Local\Programs\Godot\Godot_v4.7-stable_win64_console.exe")
LINE = 'TestColosseum="*res://scripts/tools/test_colosseum.gd"\n'


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if not GODOT.exists():
        print(f"Godot 실행파일 없음: {GODOT}")
        return 2
    original = PROJECT.read_text(encoding="utf-8")
    if "TestColosseum=" in original:
        print("이미 등록돼 있다 — 이전 실행이 비정상 종료했을 수 있다. 수동 확인 필요.")
        return 2
    # ⚠️ 오토로드는 **선언 순서대로** 초기화된다. 맨 앞에 넣으면 Data 보다 먼저 _ready 가
    #   돌아 Data.dragons/colosseum 이 비어 있다(실제로 그렇게 한 번 헛돌았다).
    #   그래서 [autoload] 섹션의 **끝**(다음 [섹션] 직전)에 넣는다.
    lines = original.splitlines(keepends=True)
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "[autoload]")
    except StopIteration:
        print("project.godot 에 [autoload] 섹션이 없다.")
        return 2
    end = start + 1
    last = end
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            break
        if "=" in lines[i]:
            last = i + 1
    lines.insert(last, LINE)
    patched = "".join(lines)
    try:
        PROJECT.write_text(patched, encoding="utf-8")
        r = subprocess.run(
            [str(GODOT), "--headless", "--path", str(REPO), "--quit-after", "600"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
        out = (r.stdout or "") + (r.returncode and "" or "")
        # 테스트가 찍은 줄과 진짜 에러만 남긴다(부팅 로그가 길다).
        for line in out.splitlines():
            if line.startswith("  FAIL") or "[test_colosseum]" in line \
                    or "SCRIPT ERROR" in line or "Parse Error" in line or "⚠️" in line:
                print(line)
        for line in (r.stderr or "").splitlines():
            if "SCRIPT ERROR" in line or "Parse Error" in line:
                print(line)
        if "[test_colosseum] ALL PASS" in out:
            return 0
        if "[test_colosseum]" not in out:
            print("테스트가 아예 실행되지 않았다 — 아래는 마지막 출력 20줄:")
            print("\n".join(out.splitlines()[-20:]))
        return 1
    finally:
        PROJECT.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
