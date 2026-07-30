"""데이터 트랙 — 나무위키 장비 PDF → data/equipment.json.

유실된 서버 데이터(장비 종류·주능력 수치·옵션 규칙)를 위키에서 복원한다.
  docs/ref/wiki/equipment_0.pdf  장비 본편(일반/이벤트/특수/아티팩트/옵션/편린)
  docs/ref/wiki/equipment_1.pdf  전용 장비 목록(드래곤별 고유 효과)

원작 클라 근거(값이 아니라 *스키마*):
  - 장비 옵션 테이블 = `info_item_acc`. 컬럼이 디컴프에 그대로 있다:
        select hp, atk, def, blk, gold, exp, pure, depure, accuracy from info_item_acc where no=%d
      (docs/ref/orig_code/decomp/OptionSelectLayer.c:2343)
    ⇒ 옵션 스탯은 **9종**이다. 위키 §2.6은 7종만 적었는데(공/방/생/방어율/골드/경험치/관통)
      클라에는 depure(관통 감소)·accuracy(명중)가 더 있다. 스키마는 클라가 이긴다.
  - 편린 세트 옵션 테이블 = `info_item_setacc`, 컬럼 13개:
        select h,i,j,a,b,c,d,e,f,k,l,m,n from info_item_setacc where no=%d
      (docs/ref/orig_code/decomp/RaidpieceItem.c:2128) — 위키 §3.1의 "무려 13가지"와 개수가 일치.
  - 장비 부가 버프 = `info_item_buf`: select hp,att,def,cri,evd,blk (Dragon.c/Item.c).
  - 장비 슬롯 = `Dragon::getDragonEquipSlot(int)` / 편린 슬롯 = `getDragonPieceSlot(int)`.

⚠️ 유실 & 미확정(HARD RULE 6):
  일반 장비(깃털/발톱/부적/묘안석/흑요석/백금석)의 **등급별 수치**는 위키가 서술형
  ("미약하게/조금/크게/대폭")이라 숫자가 없다. 아래 BASIC 의 values 는 ASSUMPTION이며,
  위키에 숫자가 명시된 이벤트·특수 장비를 앵커로 삼아 그 아래에 오도록 잡았다.
  앵커는 각 항목의 "_anchors" 에 적어 두었다 — 사용자 검수 대상
  (docs/input/review/equipment_sheet.md).

사용:  python scripts/tools/build_equipment.py
       python scripts/tools/build_equipment.py --dry
"""
from __future__ import annotations
import re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WIKI = REPO / "docs" / "ref" / "wiki"
OUT = REPO / "data" / "equipment.json"
ICON_MAP = REPO / "data" / "icon_map.json"

# ── 스탯 어휘 ────────────────────────────────────────────────────────────────
# 우리 엔진 키 ← 원작 info_item_acc 컬럼 / 위키 표기
STAT_KEYS = {
    "hp":       "생명력(flat)",
    "att":      "공격력(flat)",            # 원작 컬럼명 atk
    "def":      "방어력(flat)",
    "blk":      "방어(막기)율 %",
    "evd":      "상대공격 회피 확률 %",
    "cri":      "크리티컬 확률 %",
    "cri_pow":  "크리티컬 파워 %",          # 크리 배수 가산
    "pure":     "방어 관통 대미지(flat, 방어 무시 고정 피해)",
    "depure":   "받는 방어 관통 대미지 감소(flat)",
    "accuracy": "명중률 %",
    "cure":     "행동불능 치유 확률 %",
    "awaken_rate": "각성기 게이지 상승률 %",
    "gold":     "골드 획득 %",
    "exp":      "경험치 획득 %",
}

# 위키 §2 슬롯 표 — 주 능력에 따라 붙일 수 있는 칸이 갈린다.
SLOTS = [
    {"id": "all", "name": "모든 장비", "accepts": "*",
     "_source": "위키 §2 '전용장비를 포함한 말 그대로 모든 장비'"},
    {"id": "battle", "name": "전투형 장비", "accepts": ["cri", "pure", "cri_pow", "accuracy"],
     "_source": "위키 §2 '크리티컬 확률/방어 관통 대미지/크리티컬 파워/명중률 증가형'"},
    {"id": "support", "name": "보조형 장비", "accepts": ["evd", "cure", "awaken_rate", "depure"],
     "_source": "위키 §2 '회피율/행동불능 치유 확률/각성기 게이지 상승률/방어 관통 대미지 감소형'"},
    {"id": "artifact", "name": "아티팩트 장비", "accepts": ["artifact"],
     "_source": "위키 §2 '모든 아티팩트'"},
]

# ── 일반 장비 6종 (위키 §2.1) ───────────────────────────────────────────────
# grades = 등급명 목록(위키 표기 그대로), values = ASSUMPTION 수치(앵커 근거는 _anchors).
#
# ⚠️ 최고등급(아만타) 표기 정정 — 2026-07-27:
#   위키 §2.1 등급표 헤더는 "아만타의 **조갑/금우**" 이고, **부적 행의 아만타 칸은 `-`(없음)** 이다.
#   추출 아틀라스도 이와 일치한다: `item/accessory/feather1..7` `claw1..7` 은 7종이지만
#   `talisman1..6` 은 6종뿐(`asset_index.py --grep talisman`).
#   ⇒ 이전 산출물의 "아만타의 부적"(7등급)은 실재하지 않는 자작 항목이었다. 6등급으로 정정.
#   ⇒ 깃털/발톱의 최고등급 이름도 "아만타의 깃털/발톱" 이 아니라 금우/조갑 이다(top_name).
GRADES_ACC = ["허름한", "용의", "고룡의", "전설의", "룬의 수호자의", "태고의 수호자의", "아만타의"]
GRADES_STONE = ["작은", "깨진", "", "세공", "고급", "전설의"]   # 3번째는 접두어 없음(위키 '~')

BASIC = {
    "깃털": {
        "stat": "evd", "slot": "support", "grade_names": GRADES_ACC,
        "top_name": "아만타의 금우",      # 위키 §2.1 등급표 헤더 "아만타의 조갑/금우"
        "values": [2, 3, 4, 5, 6, 8, 10],
        "_anchors": "발록 팔찌 13% · 눈사람 인형/온화한 호박반지 13% · 유타칸의 바람 11% · 허리케인 뱃지 10%. "
                    "일반 최고등급(아만타의 금우)은 이벤트·특수 장비보다 아래여야 하므로 10에서 끝냄. ASSUMPTION.",
    },
    "발톱": {
        "stat": "cri", "slot": "battle", "grade_names": GRADES_ACC,
        "top_name": "아만타의 조갑",      # 위키 §2.1 등급표 헤더 "아만타의 조갑/금우"
        "values": [2, 3, 4, 5, 6, 8, 10],
        "_anchors": "발록 보주 13% · 크리스마스 별장식/사악한 호박반지 13% · 어린이 풍선 12% · "
                    "유타칸의 별빛/붉은 달의 조각 11% · 발록의 뱃지 10%. ASSUMPTION.",
    },
    "부적": {
        # 아만타 등급 없음(위키 등급표 `-` + 아틀라스 talisman1..6) → 6등급.
        "stat": "cure", "slot": "support", "grade_names": GRADES_ACC[:6],
        "values": [10, 16, 24, 32, 40, 50],
        "_anchors": "크리스마스 리본/곰 인형 69% · 팔라곤의 뱃지 50%. 최고등급(태고의 수호자의 부적)을 "
                    "뱃지급(50)에 맞춤 — 아만타 부적은 원작에 없다. ASSUMPTION. "
                    "⚠️위키 설명문은 부적을 '패배 시 부활 확률'로 적지만 §2.1 효과표는 '행동불능 치유 확률'이다 — 효과표를 따랐다.",
    },
    "묘안석": {
        "stat": "pure", "slot": "battle", "grade_names": GRADES_STONE,
        "values": [5, 10, 15, 20, 25, 30],
        "_anchors": "발록 투구/피오드 낙인·잠뜰의 모자/할로윈 바구니 40 · 멋진 선글라스 35 · 포세이돈 뱃지 25. "
                    "최고등급(전설의 묘안석)을 특수장비(40) 아래인 30으로. ASSUMPTION.",
    },
    "흑요석": {
        "stat": "cri_pow", "slot": "battle", "grade_names": GRADES_STONE,
        "values": [10, 20, 30, 40, 50, 60],
        "_anchors": "오색 비치볼/유타칸의 햇빛 60% · 다르고스의 뱃지 45% · 발록 보주 부가효과 100%. "
                    "위키 §2.3.2: '메인 효과가 크리티컬 데미지인 대부분의 아이템이 60%를 넘지 못한다' → 60에서 끝냄.",
    },
    "백금석": {
        "stat": "awaken_rate", "slot": "support", "grade_names": GRADES_STONE,
        "values": [5, 10, 15, 20, 25, 30],
        "_anchors": "크리스마스 종 40% · 시원한 밀짚모자 35% · 그라노스의 뱃지 25%. ASSUMPTION.",
    },
}

# ── 특수 장비 (위키 §2.3) — 주 능력은 숫자가 명시돼 있다. 부가 능력은 원문 보존. ──
SPECIAL = {
    "skull": {
        "name": "해골요새 장비",
        "_source": "위키 §2.3.1. '모든 장비의 주 능력이 방어 관통 대미지 +40'.",
        "items": [
            {"name": "엘더 블랙퀸의 스태프", "main": {"pure": 40},
             "bonus": "체방형 드래곤을 공격 시 25% 추가 대미지, 방어형 드래곤이 장착 시 회피율 10% 상승"},
            {"name": "엘더 블랙퀸의 목걸이", "main": {"pure": 40},
             "bonus": "방어형 드래곤을 공격 시 25% 추가 대미지, 체력형 드래곤이 장착 시 체력 추가 한계량 20% 증가"},
            {"name": "G스컬의 은빛망토", "main": {"pure": 40},
             "bonus": "체공형 드래곤을 공격 시 25% 추가 대미지, 공방형 드래곤이 장착 시 [신의 분노]가 [망각의 망치] 효과를 받지 않음"},
            {"name": "G스컬의 붉은장갑", "main": {"pure": 40},
             "bonus": "체력형 드래곤을 공격 시 25% 추가 대미지, 공격형 드래곤이 장착 시 크리티컬 파워 100% 상승"},
            {"name": "G스컬의 영혼불길", "main": {"pure": 40},
             "bonus": "공격형 드래곤을 공격 시 25% 추가 대미지, 체공형 드래곤이 장착 시 전투 중 체력·공격력 15% 증가"},
            {"name": "엘더 블랙퀸의 목도리", "main": {"pure": 40},
             "bonus": "공방형 드래곤 공격 시 25% 추가 대미지, 체방형 드래곤이 장착 시 스킬에 입는 피해 10% 감소"},
        ],
    },
    "balrog": {
        "name": "발록 장비",
        "_source": "위키 §2.3.2.",
        "items": [
            {"name": "카이저 발록의 투구", "main": {"pure": 40},
             "bonus": "공격 시 상대 드래곤 남은 체력의 5%에 비례하는 추가 대미지(최대 300)"},
            {"name": "카이저 발록의 팔찌", "main": {"evd": 13},
             "bonus": "현재 체력을 넘어서는 대미지를 받았을 때 체력 1을 남기고 생존(1회)"},
            {"name": "카이저 발록의 보주", "main": {"cri": 13},
             "bonus": "크리티컬 대미지 100% 증가"},
        ],
    },
    "fiod": {
        "name": "피오드 장비",
        "_source": "위키 §2.3.3. 2020 크리스마스 업데이트.",
        "items": [
            {"name": "피오드의 부서진 낙인", "main": {"evd": 13},
             "bonus": "착용한 드래곤의 스킬 효과 +1"},
            {"name": "피오드의 빛을 잃은 마석", "main": {"accuracy": 13},
             "bonus": "착용 드래곤이 각성기에 받는 대미지 1000으로 제한"},
            {"name": "피오드의 텅 빈 모래시계", "main": {"depure": 20},
             "bonus": "공격 시 타겟의 최대 체력 1마다 0.002%의 타겟 최대 체력 비례 추가대미지(최대 300)"},
        ],
    },
}

# ── 아티팩트 (위키 §2.4) ────────────────────────────────────────────────────
ARTIFACT_GRADES = ["파손된", "작은", "신비한", "빛나는", "위대한", "전설의"]

# 아티팩트 6종 ↔ 원작 `Item::getTypeDetail()` 축(§docs/ref/porting/EquipBelongOption.md §3).
# 짝은 libgame.so 문자열 테이블에서 `CaveItemEquipComentN` 과 1:1로 붙어 확정된 것이다.
ARTIFACT_AXES = {
    "이그니스": "BOOST",     # CaveItemEquipComent7  스킬효과 +N
    "마리스": "REQHP",       # Coment8   스킬발동 요구체력 +N%
    "테라": "BNR",           # Coment9   스킬발동 확률 및 효과 +N
    "벤투스": "DEDMG",       # Coment10  받는 스킬 대미지 -N%
    "루멘": "INRATE",        # Coment11  스킬발동확률 +N%
    "옵스큐럼": "DERATE",     # Coment12  상대스킬발동확률 -N%
}

# 축별 등급 6단(파손된→전설의) 세기. ⚠️ 전부 자작 — 원작 수치는 서버(info_item_acc 계열) 유실.
#   · BOOST/BNR 의 "효과 강화" 는 우리 엔진에서 **스킬 효과 레벨 가산**으로 준다
#     (배틀의 기존 통로 `_skill_level_bonus` 와 같은 축이라 모든 스킬 효과에 균일하게 먹는다).
#   · 나머지는 퍼센트포인트.
#   · 앵커: 각성스킬 83 '잠재력'이 레벨 +5 를 주므로 아티팩트 최고 등급은 그 아래(+3)로 뒀다.
#     확률계는 스킬 기본 발동률 20%(Battle.DEFAULT_PROC) 대비 최고 +12%p(=1.6배)를 상한으로.
ARTIFACT_POWER = {
    "BOOST":  {"power_lv": [1, 1, 2, 2, 3, 3]},
    "BNR":    {"power_lv": [1, 1, 1, 2, 2, 2], "proc_add": [2, 3, 5, 6, 8, 9]},
    "INRATE": {"proc_add": [3, 5, 7, 9, 11, 12]},
    "DERATE": {"foe_proc_sub": [3, 5, 7, 9, 11, 12]},
    "DEDMG":  {"skill_dmg_taken_pct": [5, 8, 11, 15, 19, 22]},
    "REQHP":  {"req_hp_relax_pct": [5, 8, 11, 15, 19, 22]},
}
# 아티팩트 **히든 옵션** — 표에 안 적힌 상시 효과. 사용자 확정 2026-07-29(위키 §2.4 각주 [42][43][44]).
#   ⚠️ 우리 위키 PDF 추출본에는 각주 **본문이 안 담겨 있다**(마커만 있음) → 사용자 제공값이 근거다.
#   등급과 무관한 고정값이고, 위 power(대상 스킬 한정)와 달리 **모든 스킬/상시**에 걸린다.
ARTIFACT_HIDDEN = {
    "REQHP":  {"proc_add_all": 5},   # 마리스  — 스킬 발동 확률 +5%
    "DEDMG":  {"evd": 5},            # 벤투스  — 회피율 +5%
    "BNR":    {"skill_uses": 1},     # 테라    — 스킬 발동 횟수 +1
}
ARTIFACT_HIDDEN_NOTE = (
    "히든 옵션 = 아티팩트를 끼우기만 하면 붙는 상시 효과(등급 무관 고정값). "
    "마리스 = 스킬 발동 확률 +5%(대상 스킬 한정 아님, 전 스킬) · 벤투스 = 회피율 +5% · "
    "테라 = 스킬 발동 횟수 +1. 출처: 사용자 확정 2026-07-29(나무위키 §2.4 각주). "
    "⚠️ 우리 PDF 추출본에는 각주 본문이 없어 재확인 불가 — 값이 바뀌면 여기만 고치면 된다."
)
ARTIFACT_POWER_NOTE = (
    "⚠️ 자작(HARD RULE 6 예외) — 원작 아티팩트 수치는 서버 유실. 배열 = 등급 6단(파손된→전설의). "
    "power_lv = 스킬 효과 레벨 가산(각성스킬 83 '잠재력' +5 를 상한 앵커로 그 아래 +3). "
    "proc_add/foe_proc_sub = 발동 확률 퍼센트포인트(기본 발동률 20% 대비 최고 +12%p). "
    "skill_dmg_taken_pct = 받는 스킬 피해 감소 %. "
    "req_hp_relax_pct = 스킬 발동 체력 조건 완화 % — ⚠️ 우리 전투 엔진에 체력 게이트가 아직 "
    "없어 **현재 무효**다(데이터만 보유). 튜닝 노브 = build_equipment.py ARTIFACT_POWER."
)
ARTIFACTS = [
    {"name": "이그니스", "effect": "스킬 효과 강화",
     "skills": ["[카데스]철갑방패", "복수의 거울", "피의 갈증", "상처파악", "치유의 빛", "신경독소",
                "바위방어술", "거신의 돌격", "시한폭탄", "야수의 본능", "자연의 수호", "약점파악",
                "[베르나]돌격지시", "신속이동", "맹수의 감각", "고속이동", "무언의 압박", "살기표출"]},
    {"name": "마리스", "effect": "스킬 발동 체력 조건 완화",
     "skills": ["분노의 일격", "치유의 빛", "아수라 일섬", "신의 분노"]},
    {"name": "벤투스", "effect": "상대 스킬 대미지 감소",
     "skills": ["신경독소", "시한폭탄", "거신의 돌격", "복수의 거울", "신의 분노"]},
    {"name": "루멘", "effect": "스킬 발동 확률 증가",
     "skills": ["철갑방패", "신의 결계", "복수의 거울", "암흑의 사슬", "심판의 날개", "환각효과",
                "상처파악", "뼈 부수기", "어둠의 손길", "망각의망치"]},
    {"name": "옵스큐럼", "effect": "상대 스킬 발동 확률 감소",
     "skills": ["철갑방패", "신의 결계", "복수의 거울", "암흑의 사슬", "심판의 날개", "환각효과",
                "상처파악", "어둠의 손길", "뼈 부수기", "망각의망치"]},
    {"name": "테라", "effect": "스킬 효과 강화 및 발동 확률 증가",
     "skills": ["철갑방패", "복수의 거울", "상처파악", "피의 갈증", "바위방어술", "거신의 돌격",
                "시한폭탄", "야수의 본능", "자연의 수호", "약점파악"]},
]

# ── 옵션 (위키 §2.6 + 원작 info_item_acc) ───────────────────────────────────
OPTION = {
    "_source": "위키 §2.6(등급별 옵션 수·강화 횟수) + 원작 info_item_acc 컬럼(OptionSelectLayer.c:2343).",
    "grades": [
        {"name": "일반",  "options": 0},
        {"name": "매직",  "options": 1},
        {"name": "레어",  "options": 2},
        {"name": "유니크", "options": 3},
        {"name": "에픽",  "options": 4},
        {"name": "초월",  "options": 5},
    ],
    "stats": ["hp", "att", "def", "blk", "gold", "exp", "pure", "depure", "accuracy"],
    "_stats_note": "위키 §2.6은 7종(공/방/생/방어율/골드/경험치/관통)만 적었으나 원작 컬럼은 9종 — "
                   "depure(관통 감소)·accuracy(명중)가 더 있다. 스키마는 클라가 이긴다.",
    "enhance_per_option": 5,
    "_enhance_note": "위키 §2.6 표: 옵션 1개=5번 … 6개=30번. 즉 옵션 수 × 5.",
    "extra_option_possible": True,
    # ── 단위: 어느 옵션이 "기본 스탯의 %" 인가 ────────────────────────────────────
    # 원작 확정(2026-07-29, Dragon.c): hp/att/def 만 기본값에 곱한다.
    #   getAttAdd  : fVar22 += Equip::getAtk()/100.0  →  base_att * fVar22   (Dragon.c:1508)
    #   getDefAdd/getHpAdd 도 같은 꼴
    #   getBlk/getAccuracy/getExp/getGold 는 `fVar += 값` 으로 **그냥 더한다**(퍼센트포인트)
    #   pure/depure 는 원래 flat
    "pct_stats": ["hp", "att", "def"],
    "_pct_stats_re_basis": (
        "원작 근거 확정 — `Dragon::getAttAdd`(Dragon.c:1508) 가 `Equip::getAtk()/100.0` 을 "
        "기본 공격력에 곱한다. def/hp 동일. 반면 `Equip::getBlk`(Dragon.c:2372) 등은 "
        "`fVar14 = fVar14 + fVar15` 로 가산 → 퍼센트포인트다. "
        "즉 hp/att/def 옵션만 배수, 나머지는 가산. 상세 = docs/ref/porting/EquipBelongOption.md §2-2."
    ),
    # ── 옵션 1롤당 수치 범위 — 자작(HARD RULE 6 예외, 사용자 승인 2026-07-27) ──────────
    # 원작 롤 범위는 서버 유실. 위키에 숫자가 있는 장비를 상한 앵커로 삼아 균형을 맞췄다:
    #   관통은 특수장비 주 능력이 40 → 옵션은 그보다 훨씬 낮은 1~12
    #   확률계(방어율)는 이벤트 장비가 10~13% → 옵션은 1~5%
    #   골드/경험치는 배율성이라 1~10%
    # 등급이 높을수록 붙는 옵션 **개수**가 늘 뿐(위키 §2.6), 1롤 범위는 동일하다.
    #
    # ⚠️ 2026-07-29 hp/att/def 를 flat → **%** 로 바꿨다(위 pct_stats). 종전 flat 범위
    #    (hp 10~120 · att/def 3~30)를 "레벨 40 전후 드래곤 기준 몇 %였나"로 환산해 옮겼다:
    #    그 구간 실스탯이 대략 hp 1,200 / att 300 / def 300 이므로 hp 1~10% · att/def 1~10%.
    #    초월(5옵션)이 전부 att 로 몰려도 +50% 로, 종전 flat 상한(+150 ≒ +50%)과 같은 자리다.
    "value_ranges": {
        "hp":       [1, 10],
        "att":      [1, 10],
        "def":      [1, 10],
        "blk":      [1, 5],
        "gold":     [1, 10],
        "exp":      [1, 10],
        "pure":     [1, 12],
        "depure":   [1, 8],
        "accuracy": [1, 5],
    },
    "_value_ranges_authored": (
        "⚠️ 자작(HARD RULE 6 예외, 사용자 승인 2026-07-27, 2026-07-29 단위 정정). 원작 롤 범위는 서버 유실. "
        "위키 확인값(특수장비 관통 40 · 이벤트 확률계 10~13%)을 상한 앵커로 잡고 그 아래로 정했다. "
        "hp/att/def 는 %(pct_stats)라 종전 flat 범위를 Lv40 전후 실스탯 기준으로 환산했다. "
        "튜닝 노브 = scripts/tools/build_equipment.py OPTION.value_ranges."
    ),
    # ── 귀속(belong) ──────────────────────────────────────────────────────────
    "bind_grade": 2,
    "_bind_re_basis": (
        "원작 모델 = `Equip::get/setBelong`(드래곤 tag). 미귀속 = 0 또는 -1, "
        "장착 판정은 `belong==-1 || belong==0 || belong==현재 드래곤`(BagTableViewCell.c:671). "
        "**레어 등급 이상부터 귀속**은 위키 item.pdf(구드라의 지혜 항목) — 그래서 bind_grade=2(레어). "
        "해제 아이템 = 구드라의 지혜(items.json `item_disconnect`, 원작 20다이아)."
    ),
    "unbind_item": "item_disconnect",
    # 옵션 재설정 소모품 — 원작은 장비와 **등급이 같은** 기누의 동전을 쓴다(위키 item.pdf).
    # 초월 동전은 우리 items.json 에 없다 → 초월 재설정은 현재 불가(없는 아이템은 만들지 않는다).
    "reroll_items": {"2": "ginu_coin_green", "3": "ginu_coin_yellow", "4": "ginu_coin_red"},
    "_reroll_items_note": (
        "키 = 등급 인덱스(2=레어 3=유니크 4=에픽). 원작 `ItemEquipSelectPopup::requestRegenEquip`. "
        "5(초월) 동전은 추출 아이템 목록에 없어 비워 둔다."
    ),
    # ── 획득 시 희귀도 분포 (사용자 확정 2026-07-29) ──────────────────────────────
    # 원작은 서버가 장비 레코드에 `rarity` 를 실어 보냈다(AccountManager 파싱 키) — 값은 유실.
    # 키 = 등급 인덱스(0 일반 / 1 매직 / 2 레어 / 3 유니크 / 4 에픽 / 5 초월), 값 = 확률 %.
    #   · 매직(1)·초월(5)은 어느 경로에도 없다 — 사용자 지정 그대로다.
    #   · 초월은 원작에서도 '초월' 재료로 올리는 것이지 뽑히는 등급이 아니다(위키 §2.6).
    "rarity_rolls": {
        "drop":       {"0": 70, "2": 20, "3": 8, "4": 2},
        "shop_gold":  {"0": 100},
        "shop_gacha": {"2": 60, "3": 30, "4": 10},
    },
    "_rarity_rolls_source": (
        "사용자 확정 2026-07-29 — 드롭 일반70:레어20:유니크8:에픽2 / 상점 골드구매 일반100 / "
        "상점 가챠 레어60:유니크30:에픽10. 원작 값은 서버 유실이라 이 표가 정답이다."
    ),
    # 희귀도 실루엣 색 — 원작 `Equip::getGradeImageSmallSprite` 의 setColor 값 그대로.
    # 인덱스 = 등급 인덱스(0=일반 … 5=초월). 일반은 원작이 실루엣을 아예 안 그린다 → null.
    "rarity_colors": [None, "E6E6E6", "7AF04C", "FFF600", "FF3924", "00FFEA"],
    "_rarity_colors_re_basis": (
        "원작 확정 — `Equip::getGradeImageSmallSprite` 가 rarity(1~6)로 setColor 한다. "
        "rarity 1(일반)은 스프라이트 자체를 만들지 않는다. 초월은 추가로 스파인 "
        "`scene/worldmap/trancendence_bg_spine` 을 얹는데 그 스파인은 추출 에셋에 없다."
    ),
    # 강화 1회당 기존 옵션이 오르는 양(자작). 위키 §2.6은 횟수만 알려 준다.
    "enhance_step_pct": 10,
    "_enhance_step_authored": "⚠️ 자작: 강화 1회 = 해당 옵션 값 +10%(최소 +1). 튜닝 노브.",
}

# ── 편린 (위키 §3) ──────────────────────────────────────────────────────────
PIECES = {
    "_source": "위키 §3(7주년, 4세대 레이드). 세트 2/3 효과.",
    "_re_basis": "세트 옵션 테이블 = 원작 info_item_setacc, 컬럼 13개(RaidpieceItem.c:2128) — 위키 '13가지'와 일치.",
    "slots": 3,
    "option_stats": ["att", "def", "hp", "att_plus", "def_plus", "hp_plus", "blk",
                     "att_cap", "def_cap", "hp_cap", "evd", "cri_pow", "cri"],
    "_option_stats_note": "위키 §3.1의 13종을 우리 키로. 원작 컬럼(h,i,j,a,b,c,d,e,f,k,l,m,n)과 개수 일치하나 "
                          "컬럼↔스탯 대응은 유실 — 순서는 ASSUMPTION.",
    "grades": ["일반", "매직", "레어", "유니크"],
    "list": [
        {"name": "모험가의 편린", "source": "원소문어", "set2": "체력 10% 증가",
         "set3": "체력 추가 상승량 한계 10% 증가"},
        {"name": "신비의 편린", "source": "원소문어", "set2": "체력 80 증가",
         "set3": "회피를 2회 성공할 때마다 받는 추가 대미지 1 감소(최대 50)"},
        {"name": "수호자의 편린", "source": "고대의 사서", "set2": "방어력 10% 증가",
         "set3": "방어력 추가 상승량 한계 10% 증가"},
        {"name": "요새의 편린", "source": "고대의 사서", "set2": "방어력 20 증가",
         "set3": "방어(블로킹)를 2회 성공할 때마다 기본 대미지 1 강화(최대 50)"},
        {"name": "정복자의 편린", "source": "상처입은 늑대", "set2": "공격력 10% 증가",
         "set3": "공격력 추가 상승량 한계 10% 증가"},
        {"name": "단죄의 편린", "source": "상처입은 늑대", "set2": "공격력 20 증가",
         "set3": "치명타를 성공할 때마다 추가 대미지 1 증가(최대 100)"},
    ],
}

# ── 이벤트 장비 파싱 (위키 §2.1.1) ──────────────────────────────────────────
# 표가 "이름 / 효과 / 최초 등장 이벤트" 3줄 반복으로 평탄화돼 있다.
EFFECT_MAP = [
    (re.compile(r"크리티컬 (?:공격 )?확률 \+(\d+)%?(\[\d+\])?"), "cri"),
    (re.compile(r"상대\s?공격 회피 확률 \+(\d+)%?(\[\d+\])?"), "evd"),
    (re.compile(r"행동불능 치유 확률 \+(\d+)%?(\[\d+\])?"), "cure"),
    (re.compile(r"각성기 게이지 상승률 \+(\d+)%?(\[\d+\])?"), "awaken_rate"),
    (re.compile(r"크리티컬 파워 증가 \+(\d+)%?(\[\d+\])?"), "cri_pow"),
    (re.compile(r"방어 관통 대미지 \+(\d+)%?(\[\d+\])?"), "pure"),
]


def read_pdf(name: str) -> list[str]:
    import fitz
    doc = fitz.open(WIKI / f"{name}.pdf")
    return [ln.strip() for ln in "\n".join(p.get_text() for p in doc).splitlines()]


def parse_event_equipment(lines: list[str]) -> list[dict]:
    """§2.1.1 거래가능/거래불가 표를 (이름, 효과, 이벤트) 로 복원."""
    out: list[dict] = []
    # '효과' 줄을 앵커로 잡고 직전 줄=이름, 직후 줄=이벤트.
    for i, ln in enumerate(lines):
        stat = value = None
        for rx, key in EFFECT_MAP:
            m = rx.fullmatch(ln)
            if m:
                stat, value = key, int(m.group(1))
                break
        if stat is None:
            continue
        # 각주 마커([19] 등)는 위키 표기라 제거한다.
        name = re.sub(r"\[\d+\]", "", lines[i - 1]).strip()
        event = re.sub(r"\[\d+\]", "", lines[i + 1]).strip() if i + 1 < len(lines) else ""
        if not name or name.startswith("효과") or "이벤트" in name and "이름" in name:
            continue
        out.append({"name": name, "main": {stat: value}, "event": event})
    # 중복(펼치기 설명 블록 등) 제거 — 이름 기준 첫 등장만.
    seen, uniq = set(), []
    for e in out:
        if e["name"] in seen:
            continue
        seen.add(e["name"])
        uniq.append(e)
    return uniq


def parse_exclusive(lines: list[str]) -> list[dict]:
    """전용 장비 목록: '장비' 헤더 … '평가' 사이 블록에서 이름/사용자/효과를 복원.

    표가 줄바꿈으로 잘게 쪼개져 있어 완벽 분리는 불가능하다. 블록 원문을 raw 로 보존하고,
    효과문(마지막 문장군)만 best-effort 로 뽑는다. ⇒ 전용장비는 데이터로만 보관하고
    전투 반영은 하지 않는다(effect 별 개별 로직 필요, implemented=false).
    """
    out: list[dict] = []
    idx = [i for i, ln in enumerate(lines) if ln == "장비"]
    for i in idx:
        j = next((k for k in range(i + 1, len(lines)) if lines[k] == "평가"), None)
        if j is None:
            continue
        block = [ln for ln in lines[i + 1:j] if ln and ln != "분류:드래곤빌리지2"]
        if len(block) < 3:
            continue
        # 효과문 = '자신' / '장착' / '[' 로 시작하는 첫 줄부터 끝까지.
        s = next((k for k, ln in enumerate(block)
                  if ln.startswith(("자신", "장착", "[", "전투", "각성스킬"))), None)
        if s is None or s == 0:
            out.append({"raw": " ".join(block), "implemented": False})
            continue
        head = block[:s]
        effect = " ".join(block[s:])
        # head = [이름조각…, 사용자조각…] — 사용자는 보통 마지막 1~2조각.
        out.append({
            "name_raw": " ".join(head),
            "effect": re.sub(r"\[\d+\]", "", effect).strip(),
            "implemented": False,
        })
    return out


def icon_names(section: str) -> set[str]:
    """`data/icon_map.json` 의 그 섹션이 실제로 프레임을 가진 논리키 집합.

    icon_map 은 `build_item_icons.py` 가 **변환 산출물의 매니페스트를 스캔해** 만든다 —
    즉 여기 이름이 있다 = 원본 아틀라스에 아이콘 프레임이 실재한다. 추측이 아니다.
    """
    if not ICON_MAP.exists():
        return set()
    return set(json.loads(ICON_MAP.read_text(encoding="utf-8")).get(section, {}))


# 아이콘 프레임이 없는 장비는 **구현 대상에서 뺀다**(사용자 확정 2026-07-30).
# 판정은 `data/icon_map.json` 조회로 자동이므로, **아이콘을 확보하면 그대로 다시 켜진다.**
#
# 🟢 2026-07-31: 실제로 다시 켰다. 이벤트 19 · 특수 12 · 편린 6 의 아이콘이 커뮤니티 위키
#    PDF 표의 '사진' 열에 원본(PNG + SMask 알파)으로 실려 있어 `extract_equip_icons.py` 가
#    행 순서로 복원해 `assets/converted/equip_wiki/` 에 굽고, `build_item_icons.py` 가
#    icon_map 의 event/special/piece/exclusive 섹션을 채운다. 개수·이름이 이 파일이 만드는
#    배열과 1:1 로 대조된다(추출기 `--check`).
#
# ⚠️ 전용 장비(exclusive)만 여전히 꺼져 있다 — **아이콘이 아니라 수치가 없어서**다.
#    위키 표에 주 능력치 열 자체가 없고 조건부 효과 문구뿐이라(`effect`) 장착해도 붙일 스탯이
#    없다. 아이콘은 icon_map `exclusive` 에 95장 다 들어 있으니, 효과 규칙이 정해지면
#    데이터만 채우면 된다.
IMPL_NOTE = ("아이콘 프레임 미보유 ⇒ 구현 제외. 판정은 build_item_icons.py 가 만든 "
             "data/icon_map.json 조회로 자동이라, 아이콘을 확보하면 그대로 다시 켜진다.")
EXCLUSIVE_NOTE = ("전용 장비는 **아이콘이 아니라 수치가 없어서** 미구현이다(2026-07-31 갱신). "
                  "위키 표에 주 능력치 열이 없고 드래곤별 조건부 효과 문구(effect)뿐이라 "
                  "장착해도 붙일 스탯이 없다. 아이콘은 위키에서 복원해 icon_map `exclusive` 에 "
                  "95장 실려 있다(행 번호 키) — 효과 규칙이 정해지면 데이터만 채우면 된다.")
# 편린 아이콘을 못 찾았을 때만 쓰는 문구(2026-07-31 이전 상태로 되돌아간 경우).
PIECES_IMPL_NOTE = (
    "아이콘 폴더(`raidpiece_acc/` · `raidpiece_cave/`)가 추출 에셋에 없고 프레임명이 서버 "
    "res key 라 원본 덤프만으로는 복원 근거가 없다 ⇒ 구현 제외. 위키 PDF 표(equipment_0 p11)에 "
    "원본 6장이 실려 있으므로 `extract_equip_icons.py` 를 돌리면 다시 켜진다.")


def mark_implemented(events: list[dict], special: dict, pieces: dict) -> tuple[int, int]:
    """아이콘 보유 여부로 `implemented` 플래그를 박는다. 반환 = (켠 이벤트 수, 끈 이벤트 수)."""
    have = icon_names("event")
    on = off = 0
    for e in events:
        ok = e["name"] in have
        e["implemented"] = ok
        if ok:
            on += 1
            e.pop("_impl_basis", None)
        else:
            e["_impl_basis"] = IMPL_NOTE
            off += 1
    # 특수 장비(해골요새·발록·피오드) — icon_map `special` 은 "<계열>:<이름>" 키다.
    sp_have = icon_names("special")
    for fam, v in special.items():
        ok = all("%s:%s" % (fam, it["name"]) in sp_have for it in v.get("items", []))
        v["implemented"] = ok
        if ok:
            v.pop("_impl_basis", None)
        else:
            v["_impl_basis"] = IMPL_NOTE
    # 레이드 편린 — icon_map `piece` 는 편린 이름 키.
    pc_have = icon_names("piece")
    pieces["implemented"] = all(p["name"] in pc_have for p in pieces.get("list", []))
    if pieces["implemented"]:
        pieces.pop("_impl_basis", None)
        pieces["_impl_note"] = (
            "아이콘은 위키에서 복원해 배선했다(icon_map `piece`). 남은 것은 **획득·장착 경로**로, "
            "원작 레이드(4세대) 산출물이라 솔로 재설계 대상이다 — 에셋 문제가 아니다. "
            "세트 효과는 Equipment._add_piece_sets 가 그대로 합산한다.")
    else:
        pieces["_impl_basis"] = PIECES_IMPL_NOTE
    return on, off


def build() -> dict:
    eq0 = read_pdf("equipment_0")
    eq1 = read_pdf("equipment_1")
    events = parse_event_equipment(eq0)
    exclusive = parse_exclusive(eq1)
    print(f"  이벤트 장비 {len(events)}종 / 전용 장비 {len(exclusive)}종 파싱")
    special = json.loads(json.dumps(SPECIAL, ensure_ascii=False))   # 상수 원본을 건드리지 않는다
    pieces = json.loads(json.dumps(PIECES, ensure_ascii=False))
    on, off = mark_implemented(events, special, pieces)
    sp_on = sum(1 for v in special.values() if v.get("implemented"))
    print(f"  아이콘 판정 — 이벤트 {on}구현/{off}제외 · 특수 계열 {sp_on}/{len(special)} 구현"
          f" · 편린 {'구현' if pieces.get('implemented') else '제외'}"
          f" · 전용 {len(exclusive)}종은 수치 부재로 제외(아이콘은 보유)")

    basic = {}
    for name, spec in BASIC.items():
        grades = []
        last = len(spec["grade_names"]) - 1
        for gi, gname in enumerate(spec["grade_names"]):
            label = (gname + " " + name).strip() if gname else name
            if gi == last and spec.get("top_name"):
                label = spec["top_name"]      # 아만타 등급은 이름이 바뀐다(조갑/금우)
            grades.append({"grade": gi, "name": label, "value": spec["values"][gi]})
        basic[name] = {
            "stat": spec["stat"], "slot": spec["slot"], "grades": grades,
            "_values": ("자작 확정 기본값(사용자 승인 2026-07-27, HARD RULE 6 예외). "
                        "위키가 서술형이라 숫자가 없고, 아래 앵커 아래로 오도록 정했다. "
                        "튜닝 노브 = build_equipment.py BASIC[*].values. 앵커: " + spec["_anchors"]),
            "_authored": True,
        }

    return {
        "_source": "나무위키 equipment_0.pdf(장비) + equipment_1.pdf(전용 장비). scripts/tools/build_equipment.py.",
        "_re_basis": (
            "옵션 스탯 9종 = 원작 info_item_acc 컬럼(hp,atk,def,blk,gold,exp,pure,depure,accuracy; "
            "OptionSelectLayer.c:2343). 편린 세트 옵션 13종 = info_item_setacc(RaidpieceItem.c:2128). "
            "장비 부가버프 = info_item_buf(hp,att,def,cri,evd,blk). 슬롯 = Dragon::getDragonEquipSlot/getDragonPieceSlot. "
            "행값(수치)은 서버 유실 → 위키 + ASSUMPTION."
        ),
        "_offline_cuts": (
            "피오드 장비는 원작에서 원정 상점(ExpeditionShopScene) 전용 — 원정=온라인 CUT(CLAUDE.md §1). "
            "발록 장비는 길드 토벌전 산출 — 길드 CUT. 두 계열은 데이터로 두되 획득처는 솔로 레이드 재설계 대상."
        ),
        "stat_keys": STAT_KEYS,
        "slots": SLOTS,
        "basic": basic,
        "_impl_rule": ("`implemented: false` = 아이콘 프레임 미보유로 구현에서 뺀 항목"
                       "(사용자 확정 2026-07-30). 판정은 build_equipment.py 가 data/icon_map.json 을"
                       " 조회해 자동으로 박는다. 읽는 곳 = Equipment.catalog()/event_pool()."),
        "event": events,
        "special": special,
        "artifacts": {"grades": ARTIFACT_GRADES, "types": ARTIFACTS,
                      "_note": "아티팩트는 스킬 발동확률/효과를 건드린다 — 스탯 장비와 계층이 다르다.",
                      "axes": ARTIFACT_AXES, "power": ARTIFACT_POWER,
                      "_power_authored": ARTIFACT_POWER_NOTE,
                      "hidden": ARTIFACT_HIDDEN, "_hidden_source": ARTIFACT_HIDDEN_NOTE},
        "option": OPTION,
        "pieces": pieces,
        "exclusive": {
            "_note": "전용 장비는 드래곤별 고유 효과라 개별 전투 로직이 필요하다. 현재는 데이터 보관만 "
                     "(implemented=false) — 전투 미반영. 위키 표가 줄단위로 쪼개져 name_raw 는 이름+사용자가 섞여 있다.",
            "_impl_basis": EXCLUSIVE_NOTE,
            "_icons": "아이콘 95장은 위키에서 복원해 icon_map `exclusive` 에 **행 번호 키**로 실려 있다"
                      "(`extract_equip_icons.py`). 이 배열의 인덱스와 같은 순서다 — 깨끗한 이름은 "
                      "icon_map 쪽 `name` 필드에 있다.",
            "list": exclusive,
        },
    }


def main() -> None:
    data = build()
    if "--dry" in sys.argv:
        print(json.dumps(data, ensure_ascii=False, indent=2)[:3000])
        return
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[build_equipment] wrote {OUT.relative_to(REPO)}: "
          f"basic={len(data['basic'])} event={len(data['event'])} "
          f"special={sum(len(v['items']) for v in data['special'].values())} "
          f"artifacts={len(data['artifacts']['types'])} pieces={len(data['pieces']['list'])} "
          f"exclusive={len(data['exclusive']['list'])}")


if __name__ == "__main__":
    main()
