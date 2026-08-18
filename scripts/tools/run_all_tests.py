#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TOOLS = REPO / "scripts" / "tools"
CHECKER = "res://scripts/tools/check_scripts.gd"

SAVE_DIR = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "DragonVillage2 Offline"
TEST_SAVE_DIR = SAVE_DIR / "test_save"

TIMEOUT = 180

def find_godot() -> str:
    env = os.environ.get("GODOT")
    if env and Path(env).exists():
        return env
    for c in (shutil.which("godot"), shutil.which("godot.exe")):
        if c:
            return c
    winget = (Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Packages")
    for p in winget.glob("GodotEngine.GodotEngine_*/Godot_v4.*_win64_console.exe"):
        return str(p)
    for p in winget.glob("GodotEngine.GodotEngine_*/Godot_v4.*_win64.exe"):
        return str(p)
    raise SystemExit("Godot 실행 파일을 못 찾았다. 환경변수 GODOT 에 경로를 넣어 줄 것.")

def scene_tree_tests() -> list[Path]:
    out = []
    for p in sorted(TOOLS.glob("test_*.gd")):
        head = p.read_text(encoding="utf-8", errors="ignore").lstrip().splitlines()
        if head and head[0].strip() == "extends SceneTree":
            out.append(p)
    return out

def node_tests() -> list[Path]:
    out = []
    for p in sorted(TOOLS.glob("test_*.gd")):
        head = p.read_text(encoding="utf-8", errors="ignore").lstrip().splitlines()
        if head and head[0].strip() != "extends SceneTree":
            out.append(p)
    return out

def save_fingerprint() -> dict[str, tuple[int, str]]:
    out: dict[str, tuple[int, str]] = {}
    for p in sorted(SAVE_DIR.glob("*.json")):
        b = p.read_bytes()
        out[p.name] = (len(b), hashlib.sha1(b).hexdigest())
    return out

def run_one(godot: str, res_path: str) -> tuple[bool, str, float]:
    t0 = time.time()
    env = dict(os.environ, DV2_TEST_SAVE="1")
    try:
        r = subprocess.run(
            [godot, "--headless", "--path", str(REPO), "--script", res_path],
            capture_output=True, timeout=TIMEOUT, env=env,
        )
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT (%ds)" % TIMEOUT, time.time() - t0
    out = (r.stdout or b"").decode("utf-8", "replace") + (r.stderr or b"").decode("utf-8", "replace")
    dt = time.time() - t0

    if r.returncode != 0:
        return False, "exit %d" % r.returncode, dt
    bad = re.search(r"^\s*(FAIL|✗)\b|\bFAIL\b\s*$|=== \d+ FAIL", out, re.M)
    if bad:
        return False, "출력에 FAIL", dt
    if "SCRIPT ERROR" in out or "Parse Error" in out:
        return False, "스크립트 오류", dt
    return True, "", dt

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[], help="이름에 이 말이 든 테스트만")
    ap.add_argument("--no-compile", action="store_true", help="컴파일 게이트 건너뛰기")
    ap.add_argument("--list", action="store_true", help="목록만 출력")
    ap.add_argument("--keep-going", action="store_true", help="컴파일 게이트가 실패해도 계속")
    args = ap.parse_args()

    godot = find_godot()
    tests = scene_tree_tests()
    if args.only:
        tests = [t for t in tests if any(k in t.name for k in args.only)]

    if args.list:
        print("SceneTree 테스트 %d개:" % len(tests))
        for t in tests:
            print("   ", t.name)
        print("\n씬이 필요한 테스트 %d개(여기서 안 돌린다):" % len(node_tests()))
        for t in node_tests():
            print("   ", t.name)
        return 0

    shutil.rmtree(TEST_SAVE_DIR, ignore_errors=True)
    before = save_fingerprint()

    failed: list[tuple[str, str]] = []
    try:
        if not args.no_compile:
            print("\n── 컴파일 게이트 ──")
            ok, why, dt = run_one(godot, CHECKER)
            print("  %s  전체 스크립트 로드  (%.1fs)%s"
                  % ("PASS" if ok else "FAIL", dt, "" if ok else "  ← " + why))
            if not ok:
                failed.append(("check_scripts.gd", why))
                if not args.keep_going:
                    print("\n컴파일이 깨졌다 ― 테스트를 돌려도 의미가 없어 여기서 멈춘다.")
                    print("자세한 내용: %s --headless --path . --script %s" % (godot, CHECKER))
                    return 1

        print("\n── 테스트 %d건 ──" % len(tests))
        for i, t in enumerate(tests, 1):
            res = "res://scripts/tools/%s" % t.name
            ok, why, dt = run_one(godot, res)
            print("  [%2d/%2d] %-34s %s  (%.1fs)%s"
                  % (i, len(tests), t.name, "PASS" if ok else "FAIL", dt,
                     "" if ok else "  ← " + why))
            if not ok:
                failed.append((t.name, why))
    finally:
        after = save_fingerprint()
        touched = sorted(set(before) | set(after))
        touched = [n for n in touched if before.get(n) != after.get(n)]
        if touched:
            print("\n[!] 실세이브가 변했다: %s" % ", ".join(touched))
            print("   SaveSystem 을 우회해 user:// 에 직접 쓰는 테스트가 있다는 뜻이다.")
            print("   해당 테스트를 찾아 SaveSystem/UserDB 경유로 고칠 것 ― %s" % SAVE_DIR)
            failed.append(("<실세이브 오염>", ", ".join(touched)))
        else:
            print("\n세이브 무사(실세이브 미접근, 테스트는 %s)" % TEST_SAVE_DIR.name)

    print("\n=== %d/%d PASS ===" % (len(tests) - len([f for f in failed if f[0] != 'check_scripts.gd']),
                                   len(tests)))
    if failed:
        print("실패:")
        for name, why in failed:
            print("   %-34s %s" % (name, why))
        print("\n개별 재현: %s --headless --path . --script res://scripts/tools/<이름>" % godot)
        return 1
    print("\n씬이 필요한 테스트 %d건은 이 러너 밖이다. run_test_*.py 참고." % len(node_tests()))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
