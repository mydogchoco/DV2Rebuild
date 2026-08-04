# -*- coding: utf-8 -*-
"""
build_level_curve.py — 드래곤 레벨업 경험치 곡선 생성 → data/level_curve.json

⚠️ ASSUMPTION (서버 소실값): 원작의 레벨당 필요 경험치 테이블은 서버가 계산·보관했고
(libgame.so의 CheckLevelUp = 서버 응답 JSON 파싱일 뿐, docs/ref/design/reverse_engineering.md §Tier2),
서비스 종료로 소실됐다. 위키(docs/ref/wiki/*.pdf)에도 없다.

복원 근거(단 하나의 관측점):
  docs/ref/design/reverse_engineering.md §"샘플 드래곤 레코드" — 레벨 50 드래곤 lucifer의 exp 필드 = 1,625,625.
  레벨 50은 최대(각성)레벨이므로 이 값은 "생애 누적 경험치"로 해석 → 1→50 도달 누적 ≈ 1,625,625.

모델: req(L) = round(C * L^2)  (L→L+1 필요 경험치, 2차 곡선)
  sum_{L=1..49} L^2 = 40425 → C = 1,625,625 / 40425 ≈ 40.2131 로 누적을 관측값에 맞춤.
  2차식 선택 이유: 모바일 RPG 표준적인 완만한 가속 곡선이며 관측 누적값과 거의 정확히 일치.

이 곡선은 밸런스 노브다. data/level_curve.json을 직접 수정하거나 아래 C/지수를 바꿔 재생성하면 된다.
"""
import json
import os

CAP = 50            # 원작 최대 레벨(각성 조건도 Lv.50)
CAP_AWAKENED = 50   # 하위호환 필드: 각성 전후 상한은 동일
ANCHOR_LEVEL = 50
ANCHOR_CUM_EXP = 1_625_625   # 관측값(reverse_engineering.md)
EXPONENT = 2.0

def build():
    # C 를 앵커 누적값에 맞춰 역산: sum_{L=1..ANCHOR_LEVEL-1} L^EXPONENT
    denom = sum(L ** EXPONENT for L in range(1, ANCHOR_LEVEL))
    C = ANCHOR_CUM_EXP / denom
    # req[i] = 레벨 (i+1) → (i+2) 필요 경험치. L=1..CAP_AWAKENED-1 (=1..49).
    req = [int(round(C * (L ** EXPONENT))) for L in range(1, CAP_AWAKENED)]
    cum = []
    s = 0
    for r in req:
        s += r
        cum.append(s)
    out = {
        "_re_basis": "ASSUMPTION: exp 곡선은 서버 소실. req(L)=round(%.4f*L^%.1f), "
                     "관측 앵커=레벨%d 누적 %d (reverse_engineering.md). 밸런스 노브."
                     % (C, EXPONENT, ANCHOR_LEVEL, ANCHOR_CUM_EXP),
        "cap": CAP,
        "cap_awakened": CAP_AWAKENED,
        # req[L-1] = 레벨 L → L+1 필요 경험치 (L: 1..49)
        "req": req,
        # ---- 레벨업 스탯 롤 규칙 (레퍼런스: docs/ref/orig_image/levelup, 사용자 명세 2026-07-26) ----
        # 매 레벨 각 스탯이 [1, max] 랜덤 상승(max = stat_table growth값). 낮은 확률로 "초월맥스"(보라):
        # max + transcend(HP4/공1/방1). 트리플맥스 = 3스탯 전부 max. "능력치 다시뽑기"로 리롤,
        # 리롤마다 트리플맥스 확률 +step 누적(cap까지). 확률값=ASSUMPTION(서버소실) — 밸런스 노브.
        "roll": {
            "_re_basis": "확률=서버소실 ASSUMPTION. 레퍼런스 'MAX 확률 1.4%' 근거. 튜닝 노브.",
            "transcend": {"hp": 4, "att": 1, "def": 1},   # 초월맥스 추가 상승량(max 위에 가산)
            "transcend_chance": 0.03,                       # 스탯별 초월맥스 확률
            "triple_max_base": 0.014,                       # 트리플맥스 기본 확률(리롤0회)
            "triple_max_step": 0.002,                       # 리롤 1회당 +0.2%
            "triple_max_cap": 1.0,                          # 천장 100%
        },
    }
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    path = os.path.join(root, "data", "level_curve.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("[level_curve] C=%.4f  req(1)=%d req(44)=%d req(49)=%d" % (C, req[0], req[43], req[48]))
    print("[level_curve] 누적: →lv45=%d  →lv50=%d (앵커 %d)" % (cum[43], cum[48], ANCHOR_CUM_EXP))
    print("[level_curve] wrote %s" % path)

if __name__ == "__main__":
    build()
