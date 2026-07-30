#!/usr/bin/env python3
"""장비 조건부 효과 → 전투 반영표 `data/equip_effects.json`.

## 무엇을 하는가

`data/equipment.json` 의 **전용 장비 95종 `effect`** 와 **특수 장비 12종 `bonus`** 는 위키
원문(자연어)이다. 그걸 전투 엔진이 읽는 형태로 옮긴 것이 이 표다.

어휘는 **각성 스킬과 완전히 같다**(`data/skill_awaken.json` `skills[].effect`) —
`Battle.apply_effect_op` 의 op 종류와 `Battle.effect_cond_ok` 의 cond, 그리고 `react` 항목.
새 문법을 만들지 않았다. 실행도 각성 스킬과 같은 규약이다:

    EquipEffect = **번역**(전투 시작 시 1회 효과를 심는다)   ·   Battle = **실행**

## 규칙 (각성 스킬 표와 동일)

**설명 전체를 충족하는 것만 `impl: true`.** 반쪽 발동은 안 하느니만 못하다.
조항이 여러 개인데 일부만 되는 경우에만 되는 조항을 걸고 `partial` 에 남은 조항을 적는다.
`impl: false` 는 아무 일도 하지 않으며 `why` 에 이유를 적는다.

`why` 의 분류:
  · `skill:<이름>`  — 특정 스킬/각성스킬의 효과를 고치는 조항. 그 스킬 구현과 함께 다뤄야 한다.
  · `cut`          — PvP·토벌전·순위쟁탈전·탐험 등 오프라인 재구현에서 뺀 콘텐츠(CLAUDE.md §2-1).
  · `engine`       — 지금 전투 엔진에 그 개념 자체가 없다(연출/타이밍 구조가 필요).

usage: python scripts/tools/build_equip_effects.py
"""
from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EQ = REPO / "data" / "equipment.json"
OUT = REPO / "data" / "equip_effects.json"


def op(kind, **kw):
    d = {"kind": kind}
    d.update(kw)
    return d


# ── 전용 장비 (equipment.json exclusive.list[].name 키) ──────────────────────
#
# 값 = {ops: [...], react: [...], cond: {...}, impl: bool, partial: str, why: str}
# ops/react/cond 어휘는 Battle 소유다(위 docstring 참조).
EXCLUSIVE = {
    # ── 스탯 상수 ────────────────────────────────────────────────────────────
    "고대신룡의 금관": {          # 받는 방어관통 대미지 50 무시
        "ops": [op("stat", stat="depure", mode="flat", value=50)]},
    "다크닉스의 구슬": {          # 방어 관통 대미지 50 증가
        "ops": [op("stat", stat="pure", mode="flat", value=50)]},
    "에메랄드 드래곤의 보석 왕관": {  # 받는 방어관통 데미지 40 감소
        "ops": [op("stat", stat="depure", mode="flat", value=40)]},
    "루너스의 달빛불꽃": {         # 크리티컬 파워 150% 증가
        "ops": [op("stat", stat="cri_pow", mode="flat", value=150)]},
    "루미네스의 빙결신발": {        # 입히는 대미지 30% 증가
        "ops": [op("dmg_deal", pct=30)]},
    "아가레스의 투구": {          # 체력 -10% 대신 공/방 +30%
        "ops": [op("stat", stat="hp", mode="pct", value=-10),
                op("stat", stat="att", mode="pct", value=30),
                op("stat", stat="def", mode="pct", value=30)]},
    "트로페우스의얼음결정": {       # 크리티컬 확률만큼 체력% 증가
        "ops": [op("stat", stat="hp", mode="pct", **{"from": {"stat": "cri", "ratio": 1.0}})]},

    # ── 스킬 사용 횟수 ───────────────────────────────────────────────────────
    "라 솔라의 불꽃": {"ops": [op("skill_uses", value=2)]},
    "팡팡드래곤의풍선": {"ops": [op("skill_uses", value=2)]},
    "섬머샤인의 선글라스": {"ops": [op("skill_uses", value=2)]},
    "소라게 드래곤의 마법의 소라": {"ops": [op("skill_uses", value=2)]},

    # ── 피해 상한 / 정액 감소 ────────────────────────────────────────────────
    "노웨마의 갈기": {            # 받는 피해 최대 체력 30% 제한 + 아군 대미지 10% 증가
        "ops": [op("dmg_cap_pct", pct=30),
                op("dmg_deal", pct=10, to="ally")]},
    "설리반의 가면": {            # 아군에 신성 속성이 있으면 한 번에 입는 피해 최대 체력 30% 제한
        "cond": {"kind": "party_has_element", "value": "holy"},
        "ops": [op("dmg_cap_pct", pct=30)]},
    "가오론의 뿔갑옷": {           # 가오론과 다르고스가 받는 피해량 20 고정감소
        "ops": [op("dmg_taken_flat", value=20)],
        "partial": "'가오론과 다르고스' 중 **장착자 본인**에게만 건다. "
                   "아군의 특정 종을 지목하는 대상 표기가 아직 없다."},

    # ── 속성 지정 대미지 ─────────────────────────────────────────────────────
    "빙하고룡의 칼날": {          # 불 속성 드래곤에게 주는 대미지 50% 증가
        "ops": [op("dmg_deal_vs_element", pct=50, element="fire")]},
    "파워드래곤의장갑": {          # 물속성 드래곤에게 주는 대미지 50% 증가
        "ops": [op("dmg_deal_vs_element", pct=50, element="aqua")]},
    "즈믄의 빛나는갑주": {         # 신성·빛속성 드래곤 대상 피해량 100% 증가
        "ops": [op("dmg_deal_vs_element", pct=100, element="holy"),
                op("dmg_deal_vs_element", pct=100, element="light")]},

    # ── 사건 반응(react) ─────────────────────────────────────────────────────
    "백룡의 보주": {             # 회피 발동 시 스킬 사용 횟수 1회 회복
        "react": [{"on": "evade", "do": "skill_restore", "value": 1}]},
    "네시의 머리장식": {           # 위와 같은 문구
        "react": [{"on": "evade", "do": "skill_restore", "value": 1}]},
    "흑룡의 보주": {             # 크리티컬 발동 시 스킬 사용 횟수 1회 회복
        "react": [{"on": "crit", "do": "skill_restore", "value": 1}]},
    "시타엘의 신성한 뿔": {         # 회피 발동 시 **아군**의 스킬 사용횟수 1회 회복
        "react": [{"on": "evade", "do": "skill_restore", "value": 1, "to": "ally"}]},
    "저네르의 정기": {            # 크리 시 상대 최대 체력 10% 추가 피해(최대 300)
        "react": [{"on": "crit", "pct": 10, "max": 300}]},
    "다크나이트의투구": {          # 1회 피격마다 방어율 2% 증가(누적 최대 20%)
        "react": [{"on": "hit_taken", "do": "stack", "stats": ["blk"],
                   "mode": "flat", "value": 2, "max_total": 20}]},
    "레드와이번의뿔": {           # 죽음에 이르는 피해를 입으면 죽지 않고 1회 생존
        "ops": [op("flag", flag="survive_once")]},

    # ── 미구현: 특정 스킬/각성스킬을 고치는 조항 ─────────────────────────────
    "번개고룡의 팬던트": {"impl": False, "why": "skill:심판의 날개"},
    "발레포르의 고리": {"impl": False, "why": "skill:공격의 날개"},
    "루시퍼의 날개장식": {"impl": False, "why": "skill:매의눈"},
    "프로스티의 무늬": {"impl": False, "why": "skill:보호의 날개"},
    "샤크곤의 물안경": {"impl": False, "why": "skill:구드라의 가호"},
    "라이오스의 바람방패": {"impl": False, "why": "skill:고요한 바람"},
    "포세이돈의 삼지창": {"impl": False, "why": "skill:대양의 분노"},
    "프리스트의 빛나는 날개": {"impl": False, "why": "skill:순백의 빛"},
    "파이썬의 갑옷": {"impl": False, "why": "skill:대지의 시초"},
    "발칸의 푸른불꽃": {"impl": False, "why": "skill:지옥의 악귀"},
    "금오드래곤의고대목걸이": {"impl": False, "why": "skill:삼족오의 후예"},
    "블랙홀의 암흑결정체": {"impl": False, "why": "skill:블랙홀의 마력"},
    "헤네스의 지성의 왕관": {"impl": False, "why": "skill:자격을 갖춘 자"},
    "아루루가의 물갈퀴": {"impl": False, "why": "skill:물의보호막"},
    "아틀라스의 마력 수정": {"impl": False, "why": "skill:대지의 기둥"},
    "다르고스의 파괴의 힘": {"impl": False, "why": "skill:파괴의 힘"},
    "커스리퍼의 뼈투구": {"impl": False, "why": "skill:뼈갑옷"},
    "살라의 화염창": {"impl": False, "why": "skill:푸른화염"},
    "팔라곤의 권위의 투구": {"impl": False, "why": "skill:권위의 팔라곤"},
    "루키르의 바람의 날개": {"impl": False, "why": "skill:신뢰의 힘"},
    "나이트 드래곤의 기사 투구": {"impl": False, "why": "skill:빛의 기사"},
    "말덱의 흡수의서": {"impl": False, "why": "skill:흡수의 힘"},
    "스트라의 방출의 서": {"impl": False, "why": "skill:방출의 힘"},
    "푸르푸르의 혼돈의 번개": {"impl": False, "why": "skill:절망의 번개"},
    "사이커드래곤의 초록 번개": {"impl": False, "why": "skill:그림자 수호신"},
    "오르페우스의비석": {"impl": False, "why": "skill:구드라의 가호"},
    "데스퍼라티오의 용암신발": {"impl": False, "why": "skill:잠재력"},
    "제피로스의 보석": {"impl": False, "why": "skill:잠재력"},
    "콜테일의 헛된희망": {"impl": False, "why": "skill:타락한 드래곤"},
    "루페스의 결정화된 분노": {"impl": False, "why": "skill:복수의 거울"},
    "크로우 드래곤의 해골투구": {"impl": False, "why": "skill:복수의 까마귀"},
    "쏜 네일의 가시갑옷": {"impl": False, "why": "skill:가시와 못"},
    "아카이아의 성물": {"impl": False, "why": "skill:신성한 유대"},
    "샤마쉬의 흉갑": {"impl": False, "why": "skill:정의집행"},
    "불나래의 불꽃구슬": {"impl": False, "why": "skill:철갑방패 · 각인 에자녹의 권능"},
    "미니드래곤 고리": {"impl": False, "why": "skill:선제 공격"},
    "투탕카의 도리깨": {"impl": False, "why": "skill:선제 공격"},
    "번네스의 화염신발": {"impl": False, "why": "skill:선제공격"},
    "홀리의 빛나는양뿔": {"impl": False, "why": "engine — 크리 공격만 회피를 무시하는 분기가 없다"},
    "레이어스의 반석 방패": {"impl": False, "why": "skill:(각성스킬 효과 자체를 치환)"},
    "실러캔스의 물빛 투구": {"impl": False, "why": "skill:(각성스킬 효과 2배) — 방어력 조항만으로는 반쪽"},
    "카일루스의 신성 방패": {"impl": False, "why": "skill:(각성스킬 누적)"},
    "디기의 금빛장식": {"impl": False, "why": "skill:(각성스킬 추가대미지 상한)"},
    "세로님의 전쟁보닛": {"impl": False, "why": "skill:팀버프 흑풍"},
    "진의 나무비늘": {"impl": False, "why": "skill:(각성기 대미지) — awaken_dmg 는 있으나 '아군 땅속성 수만큼'의 per 대상이 각성기 배수와 맞물려야 한다"},
    "레지아나의 빛나는 깃털": {"impl": False, "why": "skill:(사망 시 아군 각성기 강화)"},
    "발로드의 갈기": {"ops": [op("awaken_dmg", pct=30)]},   # 각성기 피해량 30% 증가

    # ── 미구현: 오프라인 컷 콘텐츠 ───────────────────────────────────────────
    "청룡의 여의주": {"impl": False, "why": "cut — 토벌전(길드)"},
    "익시아의 왕관": {"impl": False, "why": "cut — PvP"},
    "솔라의 불꽃구슬": {"impl": False, "why": "cut — PvP"},
    "수라드래곤의고대 장식": {"impl": False, "why": "cut — PvP"},
    "프로스트랩터의 얼음수정": {"impl": False, "why": "cut — PvP"},
    "바리안의 백색갑옷": {"impl": False, "why": "cut — 순위쟁탈전"},
    "다크프로스티의 무늬": {"impl": False, "why": "cut — 탐험 골드 획득 증가량 참조"},

    # ── 미구현: 엔진에 개념이 없다 ───────────────────────────────────────────
    "엔젤 드래곤의티아라": {"impl": False, "why": "engine — 자기 관통을 아군에게 '공통분배'하는 대상 연산이 없다"},
    "엔투라스의 불꽃 주먹": {"impl": False, "why": "engine — 크리 시에만 방어력 절반 무시(pen 은 상시값이다)"},
    "글라시아의 왕관": {"impl": False, "why": "engine — '상대 회피율 0%면 반드시 크리' 조건부 확정 크리"},
    "일란의 영예의관": {"impl": False, "why": "engine — 연속공격(double)에만 걸리는 피해 배수"},
    "세크라포의 어깨보호대": {"impl": False, "why": "engine — 연속공격 시 준 피해만큼 회복(횟수 제한)"},
    "완숙이의 후라이팬": {"impl": False, "why": "engine — 체력 20% 이하 조건부 회복+증뎀"},
    "워든의 부유검": {"impl": False, "why": "engine — 디버프 피격 중 공격력 누적 강화"},
    "모노케로스의붉은 보주": {"impl": False, "why": "engine — 피해 누적 후 방출(전투 중 1회)"},
    "발록의 전투갑주": {"impl": False, "why": "engine — 회피한 상대가 자기 턴에 반격당하는 역공 구조"},
    "쿠르파의 푸른갑주": {"impl": False, "why": "engine — 아군 사망 트리거 + 5턴 한정 버프"},
    "오울드라의 어둠갑옷": {"impl": False, "why": "engine — 전투 시작 시 전체 1회 피해 1 보호막"},
    "페이스리스의사슬": {"impl": False, "why": "engine — 등급 비례 피해 상한(등급 눈금이 원작과 다르다)"},
    "미르의 별빛방울": {"impl": False, "why": "engine — 상대 팀 현재 체력 비례 공격력 가산"},
    "타로스의 용암구슬": {"impl": False, "why": "engine — 스킬 피해량만 따로 올리는 통로가 없다"},
    "운디네의 물방울": {"impl": False, "why": "engine — 아군 중 특정 속성만 대상으로 하는 표기가 없다"},
    "현무드래곤의동방갑옷": {"impl": False, "why": "engine — 아군 중 특정 속성만 대상으로 하는 표기가 없다"},
    "멜로우 드래곤의 부메랑": {"impl": False, "why": "engine — 조건부로 '공격하지 않는다'(행동 자체를 막는 규칙)"},
}

# ── 특수 장비 (해골요새·발록·피오드) — 키는 "<계열>:<이름>" ──────────────────
SPECIAL = {
    "balrog:카이저 발록의 팔찌": {   # 현재 체력을 넘어서는 피해를 받아도 1 남기고 생존(1회)
        "ops": [op("flag", flag="survive_once")]},
    "balrog:카이저 발록의 보주": {   # 크리티컬 대미지 100% 증가
        "ops": [op("stat", stat="cri_pow", mode="flat", value=100)]},
    "balrog:카이저 발록의 투구": {
        "impl": False, "why": "engine — 상대 남은 체력 비례 추가 피해(최대 300)"},
    "fiod:피오드의 부서진 낙인": {"impl": False, "why": "skill:(착용자 스킬 효과 +1)"},
    "fiod:피오드의 빛을 잃은 마석": {"impl": False, "why": "engine — 각성기 피격 피해 상한(고정값)"},
    "fiod:피오드의 텅 빈 모래시계": {
        "impl": False, "why": "engine — 타겟 최대 체력 비례 추가 피해(최대 300)"},
    # 해골요새 6종은 전부 "<유형>형 드래곤을 공격 시 25% 추가 대미지" + "<유형>형이 장착 시 …" 라
    # **전투 유형(체방형/공방형 등)** 을 봐야 한다. 우리 전투원은 속성만 알고 유형을 모른다.
    "skull:엘더 블랙퀸의 스태프": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
    "skull:엘더 블랙퀸의 목걸이": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
    "skull:엘더 블랙퀸의 목도리": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
    "skull:G스컬의 은빛망토": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
    "skull:G스컬의 붉은장갑": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
    "skull:G스컬의 영혼불길": {"impl": False, "why": "engine — 상대/자신의 전투 유형 참조"},
}


def normalize(tbl: dict, texts: dict) -> dict:
    """기본값 채우기 + 원문 동봉(검수용)."""
    out = {}
    for k, v in tbl.items():
        e = dict(v)
        e.setdefault("impl", True)
        e.setdefault("ops", [])
        e.setdefault("react", [])
        e["text"] = texts.get(k, "")
        out[k] = e
    return out


def main() -> None:
    eq = json.loads(EQ.read_text(encoding="utf-8"))
    ex_text = {x["name"]: x.get("effect", "") for x in eq["exclusive"]["list"]}
    sp_text = {}
    for fam, v in eq["special"].items():
        for it in v["items"]:
            sp_text["%s:%s" % (fam, it["name"])] = it.get("bonus", "")

    ex = normalize(EXCLUSIVE, ex_text)
    sp = normalize(SPECIAL, sp_text)

    # 누락 검사 — equipment.json 에 있는데 표에 없는 장비가 있으면 조용히 무효과가 된다.
    miss_ex = [k for k in ex_text if k not in ex]
    miss_sp = [k for k in sp_text if k not in sp]
    ghost_ex = [k for k in ex if k not in ex_text]
    ghost_sp = [k for k in sp if k not in sp_text]
    for label, arr in (("전용 누락", miss_ex), ("특수 누락", miss_sp),
                       ("전용 유령(장비에 없음)", ghost_ex), ("특수 유령", ghost_sp)):
        if arr:
            print("  ! %s %d건: %s" % (label, len(arr), arr[:6]))

    on_ex = sum(1 for v in ex.values() if v["impl"])
    on_sp = sum(1 for v in sp.values() if v["impl"])
    doc = {
        "_source": "scripts/tools/build_equip_effects.py — 위키 원문(equipment.json effect/bonus)을 "
                   "전투 어휘로 옮긴 표.",
        "_vocab": "ops/react/cond 는 **각성 스킬과 같은 어휘**다(Battle.apply_effect_op · "
                  "Battle.effect_cond_ok · react). 새 문법을 만들지 않았다.",
        "_rule": "설명 전체를 충족하는 것만 impl:true. 일부만 되면 되는 조항만 걸고 partial 에 "
                 "남은 조항을 적는다. impl:false 는 아무 일도 하지 않고 why 에 이유를 적는다 "
                 "(skill:<이름> / cut / engine).",
        "_runner": "EquipEffect.apply_battle 이 전투 시작 시 1회 심고, 실행은 Battle 이 한다.",
        "exclusive": ex,
        "special": sp,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[build_equip_effects] wrote %s: 전용 %d/%d 구현 · 특수 %d/%d 구현"
          % (OUT.relative_to(REPO), on_ex, len(ex), on_sp, len(sp)))


if __name__ == "__main__":
    main()
