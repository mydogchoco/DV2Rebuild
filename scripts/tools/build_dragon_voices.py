# -*- coding: utf-8 -*-
"""드래곤 보이스 배정표 생성 → data/dragon_voices.json

⚠️ 이 표는 **유실 데이터의 재구성**이다.
원작은 드래곤마다 DB 컬럼으로 보이스 번호를 갖는다 — `Dragon::setInfo` 가
`info_dragon_v2` 의 baby/child/adult/critical voice 컬럼을 읽어
`music/voice%d.mp3` 를 만든다(docs/ref/orig_code/decomp/Dragon.c:13478-13526).
그 테이블은 서버와 함께 소실됐고 `data/dragons.json` 에도 없다.

사용자가 제공한 근거(2026-07-27):
  · 보이스 파일의 성격 구분
      성체        : 1~12, 31~40                (22개)
      해치        : 13~14, 20~22, 41~49        (44번 파일은 없음 → 13개)
      해치/해츨링 : 15~19, 23~30, 50~65        (29개)
    합 64 = 실제 파일 수(voice1..voice65 중 voice44 결번)와 일치.
  · 앵커 2개(확실히 기억): 라 솔라(id 3020) 성체 = voice4 · 루시퍼(id 3001) 성체 = voice2

검산: 드래곤을 id 순으로 세우면 루시퍼 146위, 라 솔라 165위로 **19 떨어져 있는데**
성체 풀에서 voice2→voice4 는 **2칸**이다. 즉 "1마리당 1보이스" 순차로는 두 앵커를
동시에 만족할 수 없다 ⇒ 보이스가 **연속 블록**으로 배정됐다고 본다.
두 앵커를 모두 만족하는 (블록크기 B, 오프셋)은 (8,5) (9,7) (10,9) (11,10) (15,14) 뿐이고,
그중 **B=15** 를 쓴다 — 풀을 1.1바퀴만 돌아 중복이 가장 적다.

해치/해츨링(baby/child)은 근거가 없어 **시드 고정 난수**로 배정한다(재현 가능).
사용자 확인 후 이 파일을 직접 고치거나 여기 규칙을 바꾸면 된다.

실행: python scripts/tools/build_dragon_voices.py
"""
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRAGONS = ROOT / "data" / "dragons.json"
OUT = ROOT / "data" / "dragon_voices.json"

ADULT_POOL = list(range(1, 13)) + list(range(31, 41))                 # 22
HATCH_POOL = [13, 14, 20, 21, 22] + [41, 42, 43] + list(range(45, 50))  # 13 (44 결번)
MIXED_POOL = list(range(15, 20)) + list(range(23, 31)) + list(range(50, 66))  # 29

BLOCK = 15      # 성체 블록 크기(위 검산)
OFFSET = 14     # 앵커에서 역산한 시작 오프셋
SEED = 20260727  # baby/child 난수 시드(재현용)

ANCHORS = {3020: 4, 3001: 2}   # 라 솔라 / 루시퍼 (성체)


def main() -> None:
    # ⚠️ 2026-07-31: 이 스크립트는 **임시 배정 생성기**이고, 그 자리는 이미 사용자 검수분이
    # 차지했다(dragons.csv 의 voice_해치/해츨링/성체 371종 → build_dragon_voice_sheet.py --apply).
    # 그대로 돌리면 검수분 1,113칸이 난수로 덮인다 → 덮어쓰기 전에 막는다.
    # 정말 처음부터 다시 뽑을 때만 --force. 이후 검수분은 시트에서 다시 --apply 해야 한다.
    if OUT.exists() and "--force" not in sys.argv:
        cur = json.loads(OUT.read_text(encoding="utf-8"))
        if "dragons.csv" in str(cur.get("_re_basis", "")):
            print("[build_dragon_voices] 중단 — data/dragon_voices.json 은 **사용자 검수분**이다"
                  "(dragons.csv voice_* 열). 이 스크립트는 최초 임시 배정용이라 덮으면 검수가"
                  " 날아간다.\n  · 시트를 고쳤으면: python scripts/tools/build_dragon_voice_sheet.py"
                  " --apply\n  · 정말 임시 배정으로 되돌리려면: --force")
            return
    rows = json.loads(DRAGONS.read_text(encoding="utf-8"))
    if isinstance(rows, dict):
        rows = rows.get("dragons", list(rows.values()))
    ids = sorted(int(r["id"]) for r in rows)

    rng = random.Random(SEED)
    voices = {}
    for rank, did in enumerate(ids):
        adult = ADULT_POOL[(rank // BLOCK + OFFSET) % len(ADULT_POOL)]
        voices[str(did)] = {
            # 해치 = 해치 전용 풀 + 혼용 풀에서
            "baby": rng.choice(HATCH_POOL + MIXED_POOL),
            # 해츨링 = 혼용 풀에서(해치 전용 풀은 제외)
            "child": rng.choice(MIXED_POOL),
            "adult": adult,
        }

    # 앵커 검증 — 어긋나면 즉시 실패시킨다(규칙이 조용히 깨지는 걸 막는다).
    for did, want in ANCHORS.items():
        got = voices[str(did)]["adult"]
        assert got == want, f"앵커 불일치: id {did} 성체 voice={got}, 기대={want}"

    out = {
        "_re_basis": (
            "유실(원작은 info_dragon_v2 의 voice 컬럼, Dragon.c:13478-13526). "
            "사용자 제공 풀 구분 + 앵커 2개(라 솔라 3020=4, 루시퍼 3001=2)로 재구성. "
            "성체=id순 %d마리 블록 순차(offset %d), 해치/해츨링=시드 %d 난수 → 추후 수정 대상."
            % (BLOCK, OFFSET, SEED)
        ),
        "pools": {"adult": ADULT_POOL, "hatch": HATCH_POOL, "mixed": MIXED_POOL},
        "anchors": {str(k): v for k, v in ANCHORS.items()},
        "voices": voices,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[build_dragon_voices] {len(voices)}마리 → {OUT.relative_to(ROOT)}")
    for did, want in ANCHORS.items():
        print(f"  앵커 확인 id {did} adult=voice{voices[str(did)]['adult']} (기대 {want}) OK")


if __name__ == "__main__":
    main()
