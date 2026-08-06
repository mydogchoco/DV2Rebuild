#!/usr/bin/env python3
"""콜로세움 연승 수를 세이브에 직접 박는 **개발 검증 도구**.

용도: 연승방지봇(25 누리A · 50 라온A · 75 누리B · 100 라온B · 150 라온C · **999 선대군**)을
      실제로 999판 이기지 않고 조우해 보기 위한 것. 게임 로직은 건드리지 않는다 —
      `meta.colosseum` 의 연승 필드만 고쳐 쓴다(`scripts/systems/colosseum.gd::_default_state`).

    python scripts/tools/dev_set_streak.py            # 1vs1 · 3vs3 둘 다 999
    python scripts/tools/dev_set_streak.py --streak 0 # 되돌리기(연승 초기화)
    python scripts/tools/dev_set_streak.py --mode team

⚠️ 게임을 **끈 상태**에서 돌릴 것 — 실행 중이면 게임이 들고 있는 상태가 나중에 덮어쓴다.
⚠️ 선대군(999)은 `skip_if_admin: true` 라 **관리자 모드에서는 안 나온다**
   (`UserDB.ADMIN` 상수, scripts/core/user_db.gd:21). 기본값 false 면 그대로 등장한다.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SAVE = Path(os.path.expandvars(
    r"%APPDATA%\Godot\app_userdata\DragonVillage2 Offline\save_0.json"))

# 모드 → 연승 필드. data/colosseum.json `modes[*].streak_key` 와 같은 값이며
# 파일에서 읽어 오므로 표가 바뀌면 여기도 따라간다.
def mode_keys() -> dict[str, str]:
    cfg = json.loads((REPO / "data" / "colosseum.json").read_text(encoding="utf-8"))
    return {m: v.get("streak_key", "") for m, v in cfg.get("modes", {}).items()}


def thresholds() -> list[int]:
    cfg = json.loads((REPO / "data" / "colosseum.json").read_text(encoding="utf-8"))
    return sorted(int(g.get("streak_at", 0)) for g in cfg.get("guards", []))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--streak", type=int, default=999, help="설정할 연승 수 (기본 999)")
    ap.add_argument("--mode", choices=["single", "team", "both"], default="both")
    ap.add_argument("--save", type=Path, default=SAVE)
    args = ap.parse_args()

    if not args.save.exists():
        print(f"[X] 세이브가 없다: {args.save}", file=sys.stderr)
        return 1
    data = json.loads(args.save.read_text(encoding="utf-8"))
    meta = data.setdefault("meta", {})
    st = meta.setdefault("colosseum", {})

    keys = mode_keys()
    modes = list(keys) if args.mode == "both" else [args.mode]
    ths = thresholds()
    served: dict = st.setdefault("guard_served", {})

    for m in modes:
        sk = keys.get(m, "")
        if not sk:
            print(f"[X] 모드 {m} 의 streak_key 를 못 찾았다", file=sys.stderr)
            return 1
        st[sk] = args.streak
        st[sk + "_best"] = max(int(st.get(sk + "_best", 0) or 0), args.streak)
        # 이번 연승에서 **이미 지나온** 문턱은 붙어 본 것으로 적는다(그래야 25·50… 방지봇이
        # 다시 튀어나오지 않는다). 목표 연승 그 자체는 빼 둔다 — 다음 판에 나와야 하니까.
        st["guard_served"] = served
        served[m] = [t for t in ths if t <= args.streak and t != args.streak]
        if args.streak <= 0:
            served.pop(m, None)

    shutil.copy2(args.save, args.save.with_suffix(".dev_streak.bak.json"))
    args.save.write_text(json.dumps(data, ensure_ascii=False, indent="\t"), encoding="utf-8")

    for m in modes:
        sk = keys[m]
        print(f"  {m:6s} {sk} = {st[sk]}  (best {st[sk + '_best']}, "
              f"guard_served {served.get(m, [])})")
    print(f"[OK] {args.save}  (백업 = {args.save.with_suffix('.dev_streak.bak.json').name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
