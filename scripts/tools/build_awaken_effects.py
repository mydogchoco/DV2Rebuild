"""각성 스킬 **효과 구조화** — 설명(자연어) → data/skill_awaken.json `effect`.

`skill_awaken.csv` 의 `설명` 은 사용자가 원작 지식으로 적어 준 **서술**이다. 전투 엔진은 문장을
못 읽으므로 여기서 기계가 읽을 형태로 옮긴다. **번역만 하고 값을 지어내지 않는다** — 설명에 없는
수치·조건은 만들지 않고, 설명 전체를 만족시키지 못하면 그 스킬은 `impl:false` 로 남긴다
(반쪽 구현 금지 — 반쪽은 "발동하는데 설명과 다르게 동작"이라 더 나쁘다).

예외는 **조항이 여러 개인 자작 스킬**(666·777)뿐이다. 한 조항이 막혔다고 나머지 대여섯 개를
통째로 죽이면 그 드래곤이 설명보다 훨씬 약해진다 → 되는 조항만 걸고, 안 되는 조항을 `partial`
목록에 적어 **동굴 각성스킬 팝업이 그대로 보여 준다**(숨기지 않는다).

## 단계

원본 102종을 이식 난이도로 나눈다(사용자 합의 2026-07-29: A+B 먼저, 그다음 C+D).

  A 탐험      전투 밖 보상/필드 조건               ✅ 완료
  B 정적      전투 시작 시 1회 계산으로 끝         ✅ 완료
  C 파생·시스템  자기 스탯 파생 · 각성게이지 · 스킬 횟수/레벨  ✅ 완료
  D 조건부·누적  전투 중 이벤트(피격·막기·회피·크리·사망·누적)에 반응  ← 남음

## 효과 스키마

    effect = {
      tier: "A"|"B"|"C"|"D",
      impl: bool,                      # 지금 엔진이 실제로 반영하는가
      why:  str,                       # impl:false 면 무엇이 막고 있는지
      cond: <조건> | null,             # 스킬 전체에 걸리는 조건
      ops:  [<연산>],                  # 전투 시작 시 1회
      dyn:  [{when, ops}],             # 라운드마다 다시 계산(D-1 조건부)
      react:[{on, ...}],               # 전투 중 사건에 반응(D-2)
      explore: {gold_pct?, artifact_chance_pct?}   # 전투 밖
    }

    조건 = {kind:"field_element", value:"<el>"}          던전 속성
         | {kind:"party_has_element", value:"<el>"}      아군에 그 속성이 있다
         | {kind:"party_element_count", value:"<el>", min:N}
         | {kind:"enemy_has_element", value:"<el>"}
         | {kind:"party_size_min", min:N}
         | {kind:"enemy_boss"}
         | {kind:"self_stat_min", stat:"def", min:500}   자기 스탯 문턱
         | {kind:"grade_highest"}                        아군 중 자기 등급이 최고

    연산 = {to:"self"|"ally"|"ally_others"|"ally_element:<el>", ...}
           · {kind:"stat",  stat, mode:"flat"|"pct", value}
           · {kind:"dmg_deal",  pct}       주는 피해 배수(%)
           · {kind:"dmg_taken", pct}       받는 피해 배수(%)
           · {kind:"dmg_taken_flat", value} 받는 피해 정액 감소
           · {kind:"gauge_rate", pct}      각성 게이지 충전율(%)
           · {kind:"gauge_min", value}     각성 게이지 최소값(발동 후 여기까지만 내려간다)
           · {kind:"gauge_add", value}     전투 시작 게이지
           · {kind:"skill_uses", value}    스킬 최대 사용횟수
           · {kind:"skill_level", value}   스킬 **효과** 레벨(발동 확률은 그대로)
           · {kind:"skill_level_proc", pct, value}  확률적으로 그 발동만 레벨 상승
           · {kind:"absorb_top", pct, stats:[...]}  아군 최고등급의 능력치를 흡수
           · per:"ally_element:<el>" 를 붙이면 그 마릿수만큼 곱해 쌓는다
           · max 를 붙이면 상한(per 로 커진 값·from 으로 파생된 값 모두에 적용)
           · from:{stat, ratio} 를 붙이면 **소유자의 그 스탯 × ratio** 가 값이 된다(2차 패스)
           · cond 를 붙이면 그 연산에만 조건이 걸린다

    ⚠️ `from` 이 붙은 연산은 **2차 패스**에서 돈다 — 1차(고정값) 연산이 스탯을 다 바꾼 뒤의
       값을 읽어야 하기 때문이다(예: 24 달의 비밀은 크리 확률을 다 더한 뒤의 값을 본다).

usage: python scripts/tools/build_awaken_effects.py [--dry]
"""
from __future__ import annotations
import json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SKILLS = REPO / "data/skill_awaken.json"

EL = {"땅": "earth", "물": "aqua", "불": "fire", "바람": "wind", "빛": "light",
      "어둠": "dark", "신성": "holy", "혼돈": "chaos", "그림자": "shadow"}


def stat(to, s, mode, v, **kw):
    d = {"to": to, "kind": "stat", "stat": s, "mode": mode, "value": v}
    d.update(kw)
    return d


def deal(to, pct, **kw):
    d = {"to": to, "kind": "dmg_deal", "pct": pct}
    d.update(kw)
    return d


def taken_flat(to, v, **kw):
    """받는 피해 **정액** 감소. `min_dmg` 를 주면 그 아래로는 못 깎는다(52 뼈갑옷)."""
    d = {"to": to, "kind": "dmg_taken_flat", "value": v}
    d.update(kw)
    return d


def taken(to, pct, **kw):
    d = {"to": to, "kind": "dmg_taken", "pct": pct}
    d.update(kw)
    return d


# ═══════════════════════════════════════════════════════════════════════════
# A — 탐험 (8종)
# ═══════════════════════════════════════════════════════════════════════════
# 4·6·7·8·9·10 "○속성 지역 탐험 시 해당 드래곤의 능력치(체력, 공격력, 방어력) 20% 상승"
#   ⇒ 던전 속성 조건이 붙은 자기 스탯 버프. 그 던전의 전투에 그대로 실린다.
A: dict[int, dict] = {}
for no, kr in [(4, "땅"), (6, "물"), (7, "바람"), (8, "불"), (9, "빛"), (10, "어둠")]:
    A[no] = {
        "tier": "A", "impl": True,
        "cond": {"kind": "field_element", "value": EL[kr]},
        "ops": [stat("self", s, "pct", 20) for s in ("hp", "att", "def")],
    }
A[42] = {  # 부유한 기운 — 탐험시 골드 획득량 50% 증가
    "tier": "A", "impl": True, "cond": None, "ops": [],
    "explore": {"gold_pct": 50},
}
A[17] = {  # 구드라의 가호 — 전설 난이도 지역에서 아티펙트 장신구 획득 확률 50% 증가
    "tier": "A", "impl": True, "cond": None, "ops": [],
    "explore": {"artifact_chance_pct": 50},
    "note": "'전설 난이도 지역' = 카데스의 공간. 아티팩트가 나오는 유일한 곳이다"
            "(위키 etc.pdf §2.2 · dungeon_1.pdf §2).",
}

# ═══════════════════════════════════════════════════════════════════════════
# B — 정적 (27종). 전투 시작 시 1회 계산으로 설명 **전체**가 충족되는 것만.
# ═══════════════════════════════════════════════════════════════════════════
B: dict[int, dict] = {
    # ── 자기 스탯 ──────────────────────────────────────────────────────────
    1:  {"ops": [stat("self", "cri", "flat", 10)]},                      # 크리 확률 10% 증가
    3:  {"ops": [stat("self", "cri_pow", "flat", 50)]},                  # 크리 파워 50% 증가
    36: {"ops": [stat("self", "evd", "flat", 10)]},                      # 회피율 10% 증가
    59: {"ops": [stat("self", "evd", "flat", 40)]},                      # 회피 확률 40% 증가
    62: {"ops": [stat("self", "accuracy", "flat", 25)]},                 # 명중률 25% 증가
    67: {"ops": [stat("self", "def", "pct", 50)]},                       # 방어력 50% 증가
    74: {"ops": [stat("self", "att", "pct", 15), stat("self", "cri", "flat", 10)]},
    32: {"ops": [stat("self", "pure", "flat", 25)]},                     # 공격 시 25 방어무시
    47: {"ops": [stat("self", "accuracy", "flat", 15)],                  # 상대 회피확률 15% 낮춤
         "note": "우리 모델에서 '상대 회피 −N%' 와 '자신 명중 +N%' 는 같은 식이다"
                 "(_evade_chance = 방어자 evd − 공격자 accuracy)."},
    # ── 자기 피해 계수 ────────────────────────────────────────────────────
    16: {"ops": [deal("self", 20)]},                                     # 입히는 데미지 20% 증가
    39: {"ops": [taken("self", -10)]},                                   # 받는 데미지 10% 감소
    76: {"ops": [taken("self", -25)]},                                   # 받는 데미지 25% 감소
    14: {"ops": [{"to": "self", "kind": "dmg_taken_flat", "value": 15}], # 받는 피해량 15 감소
         "note": "'최소 피해량 1' 은 엔진 기본값과 같다(_apply_dmg 가 이미 1 미만으로 안 내려간다)."},
    # ── 파티 정적 ─────────────────────────────────────────────────────────
    15: {"ops": [stat("ally", "att", "pct", 10)]},                       # 모든 아군 공격력 10%
    57: {"ops": [stat("ally", "hp", "pct", 10)]},                        # 모든 아군 체력 10%
    30: {"ops": [stat("ally", "depure", "flat", 30)]},                   # 아군 받는 관통 30 감소
    31: {"ops": [deal("ally", 15)]},                                     # 아군 주는 피해 15% 증가
    53: {"ops": [stat("ally_element:earth", "def", "pct", 15)]},         # 사대신룡-땅
    54: {"ops": [stat("ally_element:aqua", "hp", "pct", 15)]},           # 사대신룡-물
    55: {"ops": [stat("ally_element:fire", "att", "pct", 15)]},          # 사대신룡-불
    49: {"ops": [stat("ally_element:light", "def", "pct", 5),            # 빛의 수호자
                 stat("ally_element:light", "evd", "flat", 5)]},
    56: {"ops": [stat("ally_element:light", "hp", "pct", 7),             # 삼족오의 후예
                 stat("ally_element:light", "att", "pct", 7),
                 stat("ally_element:light", "accuracy", "flat", 7)]},
    90: {"ops": [stat("ally_element:dark", "att", "pct", 5),             # 칠흑의 지배자
                 stat("ally_element:dark", "cri", "flat", 5)],
         "note": "'중첩되는 각성스킬 효과에 대해서는 높은 수치만 적용' — 같은 no 가 파티에 둘 이상 "
                 "있어도 한 번만 적용한다(AwakenSkill 이 no 단위로 1회 적용)."},
    28: {"ops": [taken("ally_element:earth", -25)],                      # 대지의 시초
         "note": "'각성기 피해량에는 적용되지 않음' — 우리 각성기(resolve_awaken)는 아직 "
                 "dmg_taken 계수를 타지 않으므로 자연히 지켜진다."},
    68: {"ops": [taken("ally", 10), deal("ally", 20)]},                  # 아르카의 광풍
    88: {"ops": [stat("ally", "cri", "flat", 8, per="ally_element:fire")]},  # 지옥의 악귀
    # ── 조건부(전투 시작 시 1회 판정) ──────────────────────────────────────
    20: {"cond": {"kind": "party_size_min", "min": 2},                   # 그림자 수호신
         "ops": [taken("self", 20), deal("ally", 10)],
         "note": "'혼자인 경우 적용되지 않는다' → party_size_min 2. "
                 "'[공격의 날개]와 중첩 가능' 은 서로 다른 no 라 자연히 중첩된다."},
    82: {"ops": [stat("ally", "blk", "flat", 15,                         # 자외선 차단 30
                      cond={"kind": "enemy_has_element", "value": "light"}, negate=True),
                 stat("ally", "blk", "flat", 30,
                      cond={"kind": "enemy_has_element", "value": "light"})],
         "note": "'방어율' = 우리 blk(막기 확률). 상대 팀에 빛속성이 있으면 15→30."},
    19: {"cond": {"kind": "party_has_element", "value": "shadow"},       # 그림자 분신
         "ops": [stat("self", "att", "pct", 60)]},
    94: {"cond": {"kind": "party_element_count", "value": "dark", "min": 2},   # 파괴의 힘
         "ops": [stat("self", "att", "pct", 50)]},
    33: {"cond": {"kind": "enemy_boss"},                                 # 몬스터 헌터
         "ops": [deal("self", 100)],
         "note": "'보스 및 레이드 몬스터' — 레이드는 아직 없으므로 보스만 걸린다."},
}
for v in B.values():
    v.setdefault("tier", "B")
    v.setdefault("impl", True)
    v.setdefault("cond", None)

# ═══════════════════════════════════════════════════════════════════════════
# C — 파생·시스템 훅 (16종). 전투 시작 시 계산이지만 B 보다 한 겹 더 필요한 것들.
# ═══════════════════════════════════════════════════════════════════════════
def frm(to, s, mode, src, ratio, **kw):
    """소유자의 `src` 스탯 × ratio 를 값으로 쓰는 파생 연산(2차 패스)."""
    d = {"to": to, "kind": "stat", "stat": s, "mode": mode,
         "from": {"stat": src, "ratio": ratio}}
    d.update(kw)
    return d


C: dict[int, dict] = {
    # ── 각성 게이지 ────────────────────────────────────────────────────────
    22: {"ops": [{"to": "self", "kind": "gauge_rate", "pct": 15}],      # 냉철한 암흑
         "note": "'백금석과 중첩 가능' — 백금석(장비)은 아직 게이지에 배선돼 있지 않다."},
    27: {"cond": {"kind": "self_stat_min", "stat": "def", "min": 500},  # 대지의 기둥
         "ops": [{"to": "ally_element:earth", "kind": "gauge_rate", "pct": 30},
                 {"to": "ally_element:light", "kind": "gauge_rate", "pct": 30}]},
    77: {"ops": [{"to": "self", "kind": "gauge_min", "value": 15}]},    # 영원의 불길
    97: {"ops": [{"to": "ally", "kind": "gauge_add", "value": 30}],     # 하얀매의 친구
         "stack": "once", "note": "'중첩 불가' → stack:once."},
    # ── 스킬 시스템 ────────────────────────────────────────────────────────
    23: {"ops": [{"to": "ally", "kind": "skill_uses", "value": 1}]},    # 다이즈의 가호
    98: {"ops": [{"to": "self", "kind": "skill_uses", "value": 1,       # 혼돈의 절대자
                  "per": "ally_element:chaos", "max": 3}],
         "note": "'아군 혼돈 드래곤 숫자에 따라' — 대상이 자신인지 아군 전체인지 설명이 "
                 "가르지 않는다. 다른 '스킬 제한' 스킬(23)이 '모든 아군'을 명시하는 것과 "
                 "대비돼 여기는 자신으로 읽는다."},
    89: {"ops": [{"to": "ally", "kind": "skill_level", "value": 1}],    # 지혜의 별빛
         "note": "'1레벨 더 높은 **효과**' → 발동 확률(_proc_pct)에는 안 걸고 효과 계산에만."},
    83: {"ops": [{"to": "self", "kind": "skill_level_proc",             # 잠재력
                  "pct": 25, "value": 5}],
         "note": "'발동 확률에는 영향을 주지 않는다' — 확률은 원래 레벨로 굴리고, "
                 "발동이 정해진 뒤 그 한 번의 효과 레벨만 올린다."},
    # ── 자기/파티 스탯 파생 (2차 패스) ─────────────────────────────────────
    24: {"ops": [frm("self", "att", "pct", "cri", 1.0, max=100)]},      # 달의 비밀
    34: {"ops": [frm("ally", "att", "pct", "blk", 1.0, max=50)],        # 물방울의 마력
         "note": "'방어율' = 우리 blk(막기 확률)."},
    48: {"ops": [frm("self", "hp", "pct", "def", 0.1, max=50)],         # 빛의 기사
         "note": "'방어력 500에서 최대치 50% 적용' ⇒ 방어력 1당 0.1%, 상한 50%."},
    86: {"ops": [frm("self", "depure", "flat", "def", 0.1),             # 정의집행
                 frm("self", "pure", "flat", "att", 0.1)]},
    84: {"ops": [frm("ally_element:wind", "__dmg_deal", "pct", "blk", 0.5, max=30)],
         "note": "전사의 의식 — '전투 시작 시' 라 정적이다. 대상 스탯이 아니라 피해량이라 "
                 "stat 대신 __dmg_deal 로 표기한다(AwakenSkill 이 dmg_deal 로 옮긴다)."},
    18: {"cond": {"kind": "grade_highest"},                             # 권위의 팔라곤
         "ops": [frm("self", "att", "flat", "def", 0.5)],
         "note": "'1대 1에서는 무조건 발동' — 아군이 자기뿐이면 자기가 최고 등급이라 "
                 "grade_highest 가 자연히 참이다."},
    100: {"ops": [{"to": "self", "kind": "absorb_top", "pct": 30,       # 흡수의 힘
                   "stats": ["hp", "att", "def"]}]},
    # ── 마릿수 비례 (상한 있음) ────────────────────────────────────────────
    61: {"ops": [{"to": "self", "kind": "stat", "stat": s, "mode": "pct", "value": 10,
                  "per": "ally_element:earth", "max": 30} for s in ("hp", "att", "def")],
         "note": "수호의 거목 — '진'은 이 스킬을 가진 드래곤 자신이다."},
}

# ── '추가 데미지' 계열 (50·70·666·777) ──────────────────────────────────────
# 무엇이 '추가 데미지'인가가 오래 막혀 있었다. **86 정의집행이 답을 준다** — 한 문장 안에서
# 두 낱말을 함께 쓴다:
#   "자신 합계 방어력의 10% 자신의 **관통데미지 무시**, 합계 공격력의 10% 자신의 **추가데미지 증가**"
# ⇒ '추가 데미지' = 우리 `pure`(방어무시 고정 피해) · '관통데미지 무시' = 우리 `depure`.
# 그래서 비율판 두 스탯을 새로 둔다: `pure_pct`(주는 추가 데미지 %) · `depure_pct`(받는 감소 %).
# ⚠️ 추론이다(사용자 확인 대상). 틀렸다면 여기와 Battle._pure_damage 만 고치면 된다.
C[50] = {"tier": "C", "impl": True, "cond": None,          # 빛의 아버지
         "ops": [stat("self", "depure_pct", "flat", 50)]
                + [stat("ally", s, "pct", 10) for s in ("hp", "att", "def")],
         "note": "'받는 추가 데미지 50% 감소' = depure_pct 50 (근거는 86 정의집행의 낱말 대응)."}
C[70] = {"tier": "C", "impl": True, "cond": None,          # 암흑의 수호자
         "ops": [stat("ally", "depure_pct", "flat", 50),
                 stat("self", "pure_pct", "flat", 50)]}

# ═══════════════════════════════════════════════════════════════════════════
# 자작 드래곤 전용 각성스킬 — 사용자가 dragons.csv/skill_awaken.csv 에 직접 추가한 것.
# 한 스킬이 여러 조항을 갖는다. **조항 단위로** 되는 것/안 되는 것을 나눈다.
# ═══════════════════════════════════════════════════════════════════════════
CUSTOM: dict[int, dict] = {
    666: {  # 새벽을 가져오는 자 — 샛별
        "tier": "C", "impl": True, "cond": None,
        "ops": [
            stat("self", "pure", "flat", 25),        # 공격시 25의 방어무시 대미지를 추가한다
            stat("self", "depure_pct", "flat", 66),  # 자신이 받는 추가 대미지 66% 감소
            stat("ally", "hp", "pct", 6),            # 아군 전체의 체력·공격력·방어력 6% 증가
            stat("ally", "att", "pct", 6),
            stat("ally", "def", "pct", 6),
            taken("ally", -6),                       # 아군이 입는 모든 피해 6% 감소
            deal("ally", 36),                        # 아군 드래곤의 공격 대미지 36% 증가
        ],
        "react": [{"on": "evade", "turns": 1, "left": 6}],
        "note": "'자신이 공격을 회피하면 상대는 혼란 (전투당 6회)' = 96 하얀 번개와 같은 구조.",
    },
    777: {  # 성좌의 주권자 — 한울
        "tier": "C", "impl": True, "cond": None,
        "ops": [
            stat("self", "cri_pow", "flat", 50),     # 크리티컬 파워 50% 증가
            stat("self", "pure_pct", "flat", 50),    # 자신이 주는 추가대미지 50% 증가
            {"to": "self", "kind": "dmg_cap_pct", "pct": 25},
            {"to": "self", "kind": "status_immune"},  # 모든 상태이상 무시
            # 크리티컬 발동 시 상대 방어율과 회피율의 절반을 무시.
            # 🟢 2026-08-01 이식 — 종전엔 "판정 순서(회피→막기→크리)를 바꿔야 한다"며 빼 뒀는데,
            # 그 사이 93 태양의 불꽃이 같은 문구로 통로를 열었다: `crit_halves_guard` 가 있으면
            # Battle.resolve_attack 이 **크리를 먼저 굴려** 두고(홀리의 빛나는 양뿔과 같은 방식)
            # 크리일 때만 회피·막기 확률을 절반으로 본다. 순서를 바꾸지 않고도 문구가 지켜진다.
            {"to": "self", "kind": "flag", "flag": "crit_halves_guard"},
        ],
        "note": "'모든 공격에 의해 입는 피해량이 최대 체력의 25%로 제한' → dmg_cap_pct. "
                "'모든 상태이상 무시' → Battle.IMMUNE_FLAG. 막는 대상은 `Battle.DEBUFF_FLAGS` "
                "5종(stun 기절 · confused 혼란 · no_evade 회피불가 · no_block 막기불가 · "
                "no_crit 크리불가)이다. **지속피해(dot)·시한폭탄(timed)·받는피해증가"
                "(상처 파악)·능력치 감소(무언의 압박 등)는 효과 종류가 달라 막지 않는다** — "
                "'모든 상태이상' 에 그것들까지 넣을지는 사용자 확인 대상.",
    },
    600: {  # 불굴의 기상 — 도감 600(선택권으로 디자인·속성·이름을 정하는 드래곤)
        "tier": "C", "impl": True, "cond": None,
        "ops": [
            stat("self", "depure_pct", "flat", 30),  # 자신이 받는 추가 대미지 30% 감소
            stat("ally", "hp", "pct", 5),            # 아군 전체 체력·공격력·방어력 5% 증가
            stat("ally", "att", "pct", 5),
            stat("ally", "def", "pct", 5),
            taken("ally", -5),                       # 아군이 입는 모든 피해 5% 감소
            deal("ally", 50),                        # 아군 드래곤의 공격 대미지 50% 증가
        ],
        "react": [{"on": "evade", "turns": 1, "left": 4}],   # 회피 시 상대 혼란(전투당 4회)
        "note": "666 새벽을 가져오는 자와 같은 구조의 자작 스킬(수치만 다르다).",
    },
    700: {  # 각성하는 의지 — 도감 700
        "tier": "C", "impl": True, "cond": None,
        "ops": [
            stat("self", "pure_pct", "flat", 30),    # 자신이 주는 추가대미지 30% 증가
            {"to": "self", "kind": "dmg_cap_pct", "pct": 30},
            {"to": "self", "kind": "status_immune"},  # 모든 상태이상 무시
            # 크리티컬 발동 시 상대 방어율과 회피율의 절반 무시 — 777 과 같은 통로(위 주석).
            {"to": "self", "kind": "flag", "flag": "crit_halves_guard"},
        ],
        "note": "777 성좌의 주권자와 같은 구조의 자작 스킬(수치만 다르다).",
    },
    800: {  # 트릭스터 — 도감 800 로키(드빌1 에셋 이식, 🟦사용자 확정 2026-08-04)
        "tier": "C", "impl": True, "cond": None,
        "ops": [
            stat("self", "depure_pct", "flat", 50),  # 자신이 받는 추가 대미지 50% 감소
            stat("ally", "hp", "pct", 10),           # 아군 전체 체력·공격력·방어력 10% 증가
            stat("ally", "att", "pct", 10),
            stat("ally", "def", "pct", 10),
            taken("ally", -10),                      # 아군이 입는 모든 피해 10% 감소
            deal("ally", 50),                        # 아군 드래곤의 공격 대미지 50% 증가
        ],
        "react": [{"on": "evade", "turns": 1, "left": 5}],   # 회피 시 상대 혼란(전투당 5회)
        "note": "600 불굴의 기상과 **조항 구조가 같고 수치만 크다**(30→50 · 5→10 · 4회→5회). "
                "따라서 같은 번역을 그대로 쓴다 — 새 연산 종류를 만들 필요가 없었다.",
    },
}
C.update(CUSTOM)

for v in C.values():
    v.setdefault("tier", "C")
    v.setdefault("impl", True)
    v.setdefault("cond", None)


# ═══════════════════════════════════════════════════════════════════════════
# D-1 — **동적 조건** (매 라운드 다시 계산). `dyn` 에 담는다.
#
#   dyn = [{when:<조건>, ops:[<연산>]}]
#   when = self_hp_at_most{pct} / self_hp_above{pct} / lost_hp_ratio /
#          alive_ally_element{value, exclude_self?} / ally_dead_any /
#          self_alive / self_dead / has_debuff{except_src[]}
#   조건은 **배수**를 돌려준다 — lost_hp_ratio(0~1) · alive_ally_element(마릿수) 처럼
#   조건이 곧 크기인 스킬이 있어서다. 그 배수를 값에 곱하고 `max` 로 자른다.
#
#   ⚠️ dyn 에서 `hp` 는 못 쓴다(라운드마다 최대체력이 불어난다) — 체력 조항은 정적으로.
# ═══════════════════════════════════════════════════════════════════════════
def dyn(when, ops):
    return {"when": when, "ops": ops}


HP_AT_MOST = lambda p: {"kind": "self_hp_at_most", "pct": p}
HP_ABOVE = lambda p: {"kind": "self_hp_above", "pct": p}

# 등급 기반 계수 — "(드래곤 등급 * N)%".
# ⚠️ 눈금이 원작과 다르다: 우리 등급은 7.0 기준(Growth.compute_grade), 원작은 0~6(위키
#   '최대 한계는 6.0등급'). 값 자체는 설명 그대로 쓰되 이 차이를 문서에 남긴다 — `ratio` 가 노브.
def grade(to, s, mode, ratio, **kw):
    d = {"to": to, "kind": "stat", "stat": s, "mode": mode,
         "from": {"stat": "grade", "ratio": ratio}}
    d.update(kw)
    return d


GRADE_NOTE = ("'드래곤 등급' 의 눈금이 원작과 다르다 — 우리 등급은 7.0 기준"
              "(Growth.compute_grade), 원작은 0~6(위키 '최대 한계는 6.0등급'). "
              "계수는 설명 그대로 쓰되 결과 크기는 그만큼 차이날 수 있다. "
              "노브 = build_awaken_effects.py 의 grade() ratio.")

D: dict[int, dict] = {
    5: {  # 각성된 맹수의 발톱
        "dyn": [dyn(HP_AT_MOST(50), [{"to": "self", "kind": "flag", "flag": "crit_sure"}])],
        "note": "'크리티컬 확률 100% 고정' — 확률 상한(prob_cap 70)을 우회해야 '고정'이 되므로 "
                "확률이 아니라 플래그(crit_sure)로 표현한다.",
    },
    11: {  # 감시자의 눈
        "dyn": [dyn({"kind": "has_debuff", "except_src": [23]},
                    [taken("ally", -25)])],
        "note": "'[상처 파악]을 제외한' → except_src=[23] (상처 파악 = skills.json id 23).",
    },
    12: {  # 게으름의 화신
        "ops": [stat("self", "att", "pct", -20), stat("self", "hp", "pct", 50)],
        "dyn": [dyn({"kind": "lost_hp_ratio"}, [stat("self", "att", "pct", 200)])],
        "note": "실제 공격력 = (기본+추가) × (1 + 잃은체력/최대체력 × 2) ⇒ 잃은 비율 × 200%. "
                "체력 +50% 는 라운드마다 불어나면 안 되므로 정적(ops).",
    },
    13: {  # 격류
        "dyn": [dyn(HP_ABOVE(50), [grade("ally", "__dmg_taken", "pct", -0.5)]),
                dyn(HP_AT_MOST(50), [grade("ally", "__dmg_deal", "pct", 0.5)])],
        "note": GRADE_NOTE,
    },
    37: {  # 반항심
        "dyn": [dyn({"kind": "ally_dead_any"},
                    [stat("self", "att", "pct", 30), stat("self", "evd", "flat", 10)])],
    },
    58: {  # 생명의 빛
        "dyn": [dyn({"kind": "alive_ally_element", "value": "light"},
                    [stat("self", "att", "pct", 20, max=60)])],
    },
    66: {  # 신성한 유대
        "dyn": [dyn({"kind": "alive_ally_element", "value": "holy"},
                    [stat("self", "att", "pct", 20),
                     stat("ally_others", "def", "pct", 20)])],
    },
    72: {  # 어둠 속의 빛
        "dyn": [dyn({"kind": "self_alive"}, [taken("ally", -10)]),
                dyn({"kind": "self_dead"}, [taken("ally", -20)])],
        "note": "'자신이 사망 시 효과량이 2배' → 살아 있을 때 −10%, 죽으면 −20%. "
                "'같은 종류의 효과와 중첩 불가' 는 아직 못 지킨다(효과 종류 식별 체계 필요).",
    },
    92: {  # 타오르는 바위
        "ops": [grade("self", "__dmg_deal", "pct", 2.0),
                grade("self", "__dmg_taken", "pct", 1.0)],
        "note": GRADE_NOTE,
    },
    99: {  # 혼돈의 힘
        "dyn": [dyn(HP_AT_MOST(50), [deal("self", 50)])],
    },
    102: {  # 가시와 못
        "ops": [grade("self", "__dmg_taken", "pct", -1.0),
                grade("ally_others", "__dmg_deal", "pct", 1.0)],
        "note": GRADE_NOTE + " '쏜 네일의 드래곤 등급' = 이 스킬을 가진 드래곤 자신의 등급.",
    },
}

# ═══════════════════════════════════════════════════════════════════════════
# D-2 — **반응**(전투 중 사건). `react` 에 담는다.
#
#   react = [{on:"<사건>", ...}]
#   사건: attack_done · attack_bonus · hit_taken · hit_unguarded · block · evade ·
#         crit · death · skill_cast
#   left:N 을 붙이면 "최대 N회" · "전투당 N회". 누적형은 value/max_total/stats/mode.
# ═══════════════════════════════════════════════════════════════════════════
def stack_react(on, stats, value, max_total, to="self", mode="pct"):
    return {"on": on, "do": "stack", "stats": stats, "value": value,
            "max_total": max_total, "to": to, "mode": mode}


D.update({
    2: {"react": [{"on": "crit", "pct": 5}],                      # 각성된 드래곤의 영혼
        "note": "크리 시 상대 **최대 체력**의 5% 를 추가 피해로 더한다."},
    44: {"ops": [stat("self", "cri", "flat", 5)],                 # 불의 원조
         "react": [{"on": "crit", "pct": 3}]},
    21: {"react": [stack_react("hit_taken", ["def"], 5, 50)]},    # 깨어난 방어 감각
    63: {"react": [stack_react("attack_done", ["att"], 10, 100)]},  # 신뢰의 힘
    64: {"react": [stack_react("block", ["att", "def"], 2, 30, to="ally")]},  # 신비한 보호
    40: {"react": [{"on": "hit_unguarded", "turns": 1, "left": 2}]},  # 복수의 까마귀
    96: {"react": [{"on": "evade", "turns": 1, "left": 4}]},      # 하얀 번개
    85: {"react": [{"on": "skill_cast", "do": "confuse_target",   # 절망의 번개
                    "turns": 1, "left": 3}]},
    81: {"react": [{"on": "skill_cast", "do": "self_flag",        # 자격을 갖춘 자
                    "flag": "evade_sure", "left": 5}]},
    45: {"react": [{"on": "hit_taken", "do": "acc", "cap_stat": "def"},   # 불타는 날개
                   {"on": "attack_bonus", "ratio": 1.0 / 3.0}],
         "note": "받은 피해를 방어력만큼 누적했다가 공격 시 1/3 을 얹고 초기화한다."},
    101: {"react": [{"on": "death", "gauge_pct": 50}]},           # 희생과 복수
})

D.update({
    38: {"react": [{"on": "block", "gauge_pct": 5}]},             # 방출의 힘
    80: {"react": [stack_react("double", ["att"], 30, 120)]},     # 원투박치기
    71: {"react": [{"on": "stat_gap", "max": 150}],               # 약점 공략
         "note": "'일반공격·연속공격·치명 공격에서' — 우리 엔진의 평타/연속/스킬이 모두 "
                 "같은 피해 경로(_deal_attack)를 지나므로 한 곳에서 걸린다."},
    95: {"ops": [{"to": "self", "kind": "flag", "flag": "elem_advantage"}],   # 푸른 화염
         "note": "'방어에는 영향 없음' — 우리도 공격자 쪽 배수만 바꾼다(_hit_damage)."},
    87: {"react": [{"on": "pre_damage", "chance": 25, "fix": 1, "left": 5}]},  # 즈믄의 친구
    51: {"cond": {"kind": "party_has_element", "value": "holy"},  # 빛의 환희
         "ops": [{"to": "self", "kind": "flag", "flag": "no_attack"}],
         "note": "'아군에 [신성] 속성 드래곤이 있으면' — 조건은 전투 시작 시 1회 판정."},
    29: {"ops": [stat("ally_dragon:4023", "hp", "pct", 25),       # 대폭렬의 힘
                 stat("ally_dragon:4023", "att", "pct", 25)],
         "note": "'아군 다르고스' = 도감 id 4023. '[파괴의 힘]과 중첩 가능' 은 서로 다른 no 라 "
                 "자연히 중첩된다."},
    73: {"ops": [stat("self", "att", "pct", 20, per="ally_element:wind"),     # 어둠 습격자
                 {"to": "self", "kind": "pen", "value": 20,
                  "per": "ally_element:dark", "max": 95}],
         "note": "'공격 시 대상의 방어력 20% 무시' → damage() 의 pen. 둘 다 마릿수 비례라 "
                 "전투 시작 시 1회로 끝난다."},
    43: {"ops": [deal("ally", 10),                                # 불같은 성격
                 deal("ally", 15, cond={"kind": "enemy_has_element", "value": "earth"})],
         "note": "'땅속성 적에 대한 아군 전체의 데미지 15% 추가 증가' — 우리 PvE 는 적이 "
                 "한 마리라 '상대에 땅속성이 있나' 와 '그 적이 땅속성인가' 가 같다. "
                 "다대다가 생기면 대상별 판정으로 옮겨야 한다."},
})

for v in D.values():
    v.setdefault("tier", "D")
    v.setdefault("impl", True)
    v.setdefault("cond", None)
    v.setdefault("ops", [])


# ═══════════════════════════════════════════════════════════════════════════
# 2026-07-31 — 종전 C_WHY/D_WHY 로 미뤄 두었던 14종. 훅을 열어 이식했다.
# 남는 것은 46 의 '일부'(수치가 원문에 없어 사용자 확정) 뿐이다.
# ═══════════════════════════════════════════════════════════════════════════
D.update({
    25: {"react": [{"on": "attack_done", "do": "debuff_target",     # 대양의 분노
                    "target_stat": "blk", "target_value": 7,
                    "self_stat": "cri", "self_value": 7, "left": 3}]},
    26: {"react": [{"on": "pre_damage", "fix": 1, "left": 3,        # 대장군 완숙이
                    "when": HP_AT_MOST(20)}],
         "partial": "'전투 당 1회 발동' 은 체력이 20% 위로 회복됐다가 다시 내려가면 남은 "
                    "횟수가 이어진다(재발동이 아니라 이어짐). 전투당 총 3회를 넘지는 않는다."},
    35: {"react": [{"on": "death", "do": "plant",                   # 물의 보호막
                    "to": "ally_element:aqua",
                    "plant": {"on": "pre_damage", "fix": 1, "left": 3}}],
         "note": "'각성기로 입는 피해는 1명당 1회' 는 pre_damage 가 각성기에도 걸리므로 "
                 "자연히 각자 자기 몫에서 소모된다. '전투 중 동일 효과 1회' = death 반응이 "
                 "한 번뿐이라 자연히 지켜진다."},
    41: {"react": [{"on": "skill_cast", "do": "random_debuff",      # 봉인의 힘
                    "choices": [{"gauge_pct": -10},
                                {"stat": "def", "mode": "pct", "value": -10},
                                {"stat": "att", "mode": "pct", "value": -10}]}]},
    46: {"react": [{"on": "attack_done", "do": "heal_dealt",        # 블랙홀의 마력
                    "ratio": 0.5, "left": 5, "when": HP_AT_MOST(50),
                    "stats": ["att"], "value": 10, "mode": "pct", "max_total": 50}],
         "partial": "'[피의 갈증]과 중첩 불가' 는 우리 엔진에 중첩 배제 규칙이 없어 미반영",
         "note": "🟦 원문의 '피해량의 **일부**' 와 공격력 상승폭이 위키에 없다 → 사용자 확정 "
                 "2026-07-31: **회복 50% · 공격력 +10%**(전용 장비 '블랙홀의 암흑결정체' 가 "
                 "각각 100%/20% '로 증가' 라고 해서 그 절반을 기본값으로 잡았다). "
                 "# ASSUMPTION — 근거가 생기면 이 두 값만 고치면 된다."},
    52: {"ops": [taken_flat("self", 40, min_dmg=30)],               # 뼈갑옷
         "react": [{"on": "hit_taken", "do": "stack", "stats": ["__dmg_taken"],
                    "mode": "pct", "value": 10, "max_total": 0},
                   {"on": "attack_done", "do": "reset", "reset_on": "hit_taken"}]},
    60: {"ops": [{"to": "self", "kind": "initiative"}],
         "note": "'상대방이 동일한 스킬을 보유 시 무효화' — 양쪽 다 이 플래그를 가지면 "
                 "Battle._decide_lead 가 둘 다 무시한다(원래 규칙으로 돌아간다)."},
    65: {"react": [{"on": "block", "do": "acc", "from_stat": "def", "pct": 5, "left": 5},
                   {"on": "attack_heal"}],
         "partial": "'[피의 갈증]과 중첩 불가' 는 우리 엔진에 중첩 배제 규칙이 없어 미반영"},
    69: {"dyn": [dyn({"kind": "enemy_dead_mult", "max": 3},         # 암흑 마법
                     [grade("ally", "__dmg_deal", "pct", 1.0),
                      deal("ally", 1)])],
         "note": "'(드래곤 등급+1)%' 를 등급 파생분 + 상수 1 두 조항으로 나눠 적었다. "
                 "'상대 사망마다 배율 증가(최대 3)' 가 dyn 의 배수라 두 조항에 함께 걸린다."},
    75: {"react": [{"on": "attack_acc", "ratio": 0.3333, "cap_stat": "att"},
                   {"on": "defend_release"}]},
    78: {"ops": [{"to": "self", "kind": "flag", "flag": "skill_ignores_block"}],
         "note": "🟦 사용자 확정 2026-07-31 — 이 스킬이 존재한다는 것 자체가 원작에서 "
                 "**스킬도 막혔다**는 근거다 ⇒ 스킬 공격에도 막기를 적용하고(Battle._deal_attack) "
                 "이 플래그가 그 면제다."},
    79: {"ops": [{"to": "self", "kind": "flag", "flag": "always_double"},
                 deal("ally_element:wind", 10)]},
    91: {"ops": [stat("self", "hp", "pct", 15)],                    # 타락한 드래곤
         "partial": "'상대 팀 각성 스킬 [다이즈의 가호] 무효화' 는 오프라인 PvE 의 상대가 "
                    "몬스터라 각성스킬을 갖지 않아 걸릴 일이 없다(기구를 만들어도 무효과)."},
    93: {"ops": [{"to": "self", "kind": "flag", "flag": "crit_halves_guard"}],
         "note": "크리 발동 시 방어율·회피율의 절반 무시. 우리 판정 순서가 회피→막기→크리라 "
                 "크리를 **먼저 굴려** 두고(홀리의 빛나는 양뿔과 같은 통로) 그 결과로 "
                 "회피·막기 확률을 절반으로 본다."},
})

for _no in (25, 26, 35, 41, 46, 52, 60, 65, 69, 75, 78, 79, 91, 93):
    D[_no].setdefault("tier", "D")
    D[_no].setdefault("impl", True)
    D[_no].setdefault("cond", None)
    D[_no].setdefault("ops", [])

# ═══════════════════════════════════════════════════════════════════════════
# C·D 미이식 — **왜** 못 하는지 한 줄씩 남긴다(다음 작업의 입력).
# ═══════════════════════════════════════════════════════════════════════════
C_WHY = {
}
D_WHY = {
}


def main() -> int:
    dry = "--dry" in sys.argv
    doc = json.loads(SKILLS.read_text(encoding="utf-8"))
    n = {"A": 0, "B": 0, "C": 0, "D": 0}
    for s in doc["skills"]:
        no = int(s["no"])
        if no in A:
            s["effect"] = A[no]
        elif no in B:
            s["effect"] = B[no]
        elif no in C:
            s["effect"] = C[no]
        elif no in D:
            s["effect"] = D[no]
        elif no in C_WHY:
            s["effect"] = {"tier": "C", "impl": False, "why": C_WHY[no]}
        elif no in D_WHY:
            s["effect"] = {"tier": "D", "impl": False, "why": D_WHY[no]}
        else:
            raise SystemExit("분류 안 된 각성스킬 no=%d (%s)" % (no, s["name"]))
        n[s["effect"]["tier"]] += 1

    doc["_effect_basis"] = (
        "각 스킬의 `effect` = `comment`(사용자가 적은 서술)를 기계가 읽는 형태로 옮긴 것. "
        "빌드: scripts/tools/build_awaken_effects.py (분류·번역이 전부 그 파일에 있다). "
        "**번역만 하고 값을 지어내지 않는다** — 설명 전체를 충족하지 못하면 impl:false 로 두고 "
        "`why` 에 무엇이 막고 있는지 적는다. 반쪽 구현은 '발동하는데 설명과 다르게 동작'이라 "
        "안 하느니만 못하다. 판정 = scripts/systems/awaken_skill.gd (순수 로직)."
    )
    doc["_effect_schema"] = {
        "tier": "A 탐험 · B 정적 · C 파생/시스템훅 · D 조건부/누적",
        "impl": "bool — 지금 엔진이 실제로 반영하는가",
        "why": "impl:false 일 때 무엇이 막고 있는지(다음 작업의 입력)",
        "partial": "impl:true 지만 **일부 조항이 아직 안 도는** 경우 그 조항들(자작 다중조항 스킬). "
                   "동굴 각성스킬 팝업이 이 목록을 그대로 보여 준다",
        "cond": "스킬 전체 조건. field_element / party_has_element / party_element_count / "
                "enemy_has_element / party_size_min / enemy_boss",
        "ops": "전투 시작 시 적용할 연산. to = self|ally|ally_element:<el>, "
               "kind = stat|dmg_deal|dmg_taken|dmg_taken_flat. "
               "per 를 붙이면 마릿수만큼 배수, cond 를 붙이면 그 연산만 조건부",
        "explore": "전투 밖 — gold_pct(탐험 골드) / artifact_chance_pct(아티팩트 확률)",
    }
    impl = sum(1 for s in doc["skills"] if bool(s["effect"].get("impl", False)))
    part = sum(1 for s in doc["skills"] if s["effect"].get("partial"))
    total = sum(n.values())
    doc["_effect_progress"] = {
        "A_탐험": n["A"], "B_정적": n["B"], "C_파생시스템": n["C"], "D_조건부누적": n["D"],
        "_impl": impl, "_partial": part, "_total": total,
        "_note": "_impl = 효과가 실제로 도는 스킬 수. _partial 은 그중 **일부 조항만** 도는 것"
                 "(자작 다중조항 스킬) — 각 스킬의 `partial` 에 무엇이 아직 안 되는지 적혀 있다.",
    }

    if dry:
        print("(dry)", n, "impl=%d partial=%d" % (impl, part))
        return 0
    SKILLS.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print("티어별: A %d · B %d · C %d · D %d   (전체 %d)" % (n["A"], n["B"], n["C"], n["D"], total))
    print("효과가 도는 스킬: %d / %d   (그중 일부 조항만 도는 것 %d)" % (impl, total, part))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
