"""shot_fight_damage.gd 러너 — 임시 오토로드 등록 → 부팅(렌더) → 해제.

`run_test_colosseum.py` 와 같은 방식이다. 다른 점은 **--headless 를 쓰지 않는다** —
뷰포트 캡처가 필요하다(메모리: dv2-godot-runtime-and-validation).

⚠️ 등록 줄은 절대 커밋되면 안 된다(메모리: dv2-shothelper-autoload-gotcha) —
성공/실패 어느 쪽이든 finally 에서 원본 project.godot 를 되돌린다.

사용:  python scripts/tools/run_shot_fight_damage.py
산출:  scratch_shots/fight_damage_1..3.png
"""
from __future__ import annotations
import subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJECT = REPO / "project.godot"
GODOT = Path(r"C:\Users\mydog\AppData\Local\Programs\Godot\Godot_v4.7-stable_win64_console.exe")
LINE = 'ShotFightDamage="*res://scripts/tools/shot_fight_damage.gd"\n'


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    original = PROJECT.read_text(encoding="utf-8")
    if "ShotFightDamage=" in original:
        print("이미 등록돼 있다 — 이전 실행이 비정상 종료했을 수 있다. 수동 확인 필요.")
        return 2
    lines = original.splitlines(keepends=True)
    start = next(i for i, l in enumerate(lines) if l.strip() == "[autoload]")
    last = start + 1
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("["):
            break
        if "=" in lines[i]:
            last = i + 1
    lines.insert(last, LINE)                       # 오토로드 순서상 **끝** = Data 뒤
    try:
        PROJECT.write_text("".join(lines), encoding="utf-8")
        r = subprocess.run(
            [str(GODOT), "--path", str(REPO), "--quit-after", "1800"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        out = (r.stdout or "") + "\n" + (r.stderr or "")
        for line in out.splitlines():
            if "[write]" in line or "[shot]" in line or "SCRIPT ERROR" in line \
                    or "Parse Error" in line or "push_error" in line:
                print(line)
        return 0 if "[write]" in out else 1
    finally:
        PROJECT.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
