"""shot_fight_depth.gd 러너 — 임시 오토로드 등록 → 부팅(렌더) → 해제.

`run_shot_fight_damage.py` 와 같은 방식(--headless 는 안 쓴다 — 뷰포트 캡처가 필요하다).
⚠️ 등록 줄은 절대 커밋되면 안 된다(메모리: dv2-shothelper-autoload-gotcha).

사용:  python scripts/tools/run_shot_fight_depth.py
산출:  scratch_shots/fight_depth_before.png · fight_depth_after.png
"""
from __future__ import annotations
import subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJECT = REPO / "project.godot"
GODOT = Path(r"C:\Users\mydog\AppData\Local\Programs\Godot\Godot_v4.7-stable_win64_console.exe")
LINE = 'ShotFightDepth="*res://scripts/tools/shot_fight_depth.gd"\n'


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    original = PROJECT.read_text(encoding="utf-8")
    if "ShotFightDepth=" in original:
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
    lines.insert(last, LINE)
    try:
        PROJECT.write_text("".join(lines), encoding="utf-8")
        r = subprocess.run(
            [str(GODOT), "--path", str(REPO), "--quit-after", "1800"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        out = (r.stdout or "") + "\n" + (r.stderr or "")
        for line in out.splitlines():
            if "[write]" in line or "[shot]" in line or "[depth]" in line \
                    or "SCRIPT ERROR" in line or "Parse Error" in line:
                print(line)
        return 0 if "[write]" in out else 1
    finally:
        PROJECT.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
