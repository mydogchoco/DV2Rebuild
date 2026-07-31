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



# ── 각성스킬 수정자 ──────────────────────────────────────────────────────────
#
# 전용 장비의 절반 가까이가 **각성 스킬을 고치는** 물건이다.
# 그래서 장비마다 새 효과를 짜지 않고, 그 스킬의 `effect` 를 **점 경로로 패치**해서 쓴다.
# 통로 = `AwakenSkill._patched`(번역) — 자세한 문법은 그 파일의 `PATCH_FIELD` 주석.
#
# 🟦 "[스킬] 효과 +N%" 는 **퍼센트포인트 가산**으로 읽는다(사용자 확정 2026-07-31).
#    예) [공격의 날개] "데미지 20% 증가" + 발레포르의 고리 "+20%" ⇒ 40% 증가.
AWAKEN_NO: dict = {}          # 이름 → 번호. main() 이 skill_awaken.json 에서 채운다.


def awk(name, patch=None, add_ops=None, add_react=None, explore=None, patch_new=None):
    """그 각성스킬을 고치는 수정자 한 벌. 이름은 main() 이 번호로 바꾸며, 없으면 멈춘다.

    `patch`     = **이미 있는** 경로를 고친다. 빌드 때 경로 존재를 검사한다(오타 방지).
    `patch_new` = 표에 **없던 키**를 새로 넣는다(예: `ops.0.effective`). 검사에서 뺀다 —
                  대신 부모 경로는 검사하므로 인덱스 오타는 그대로 잡힌다.
    """
    d = {"skill": name}
    if patch or patch_new:
        d["patch"] = dict(patch or {})
        d["patch"].update(patch_new or {})
        d["_patch_new"] = list((patch_new or {}).keys())
    if add_ops:
        d["add_ops"] = add_ops
    if add_react:
        d["add_react"] = add_react
    if explore:
        d["explore"] = explore
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
    # ── 각성스킬을 고치는 장비 ───────────────────────────────────────────────
    "발레포르의 고리": {           # [공격의 날개](데미지 20% 증가) 효과 +20% ⇒ 40%
        "awaken_mod": awk("공격의 날개", {"ops.0.pct": "+20"})},
    "프로스티의 무늬": {           # [보호의 날개](받는 데미지 10% 감소) 효과 +10% ⇒ 20% 감소
        # 표에서는 감소가 음수(pct -10)라 "+10%p" 는 -20 이다.
        "awaken_mod": awk("보호의 날개", {"ops.0.pct": -20})},
    "프리스트의 빛나는 날개": {      # [순백의 빛](명중률 25%) 이 아군 신성/빛에게도 + 효과 +15%
        "awaken_mod": awk("순백의 빛", {
            "ops.0.to": "self|ally_element:holy|ally_element:light",
            "ops.0.value": "+15"})},
    "아틀라스의 마력 수정": {       # [대지의 기둥] 게이지 회복량 30% 증가 ⇒ 30%+30%p = 60%
        "awaken_mod": awk("대지의 기둥", {"ops.0.pct": "+30", "ops.1.pct": "+30"})},
    "금오드래곤의고대목걸이": {      # [삼족오의 후예](체/공/명중 7%) 효과 2배
        "awaken_mod": awk("삼족오의 후예", {
            "ops.0.value": "*2", "ops.1.value": "*2", "ops.2.value": "*2"})},
    "루시퍼의 날개장식": {         # [매의 눈] 방어무시 25 → 100
        "awaken_mod": awk("매의 눈", {"ops.0.value": 100}),
        "partial": "'묘안석과 중첩불가' 는 우리 엔진에 중첩 배제 규칙이 없어 미반영"},
    "살라의 화염창": {            # [푸른 화염] 으로 주는 상성 대미지 50% 증가
        # 푸른 화염은 **모든 공격**을 유리 상성으로 만든다 ⇒ 그의 피해가 곧 '상성 대미지'다.
        "awaken_mod": awk("푸른 화염", add_ops=[op("dmg_deal", pct=50)])},
    "라이오스의 바람방패": {        # [고요한 바람](받는 피해 15 감소) 효과가 방어력 100당 3씩 증가
        "awaken_mod": awk("고요한 바람", add_ops=[
            op("dmg_taken_flat", **{"from": {"stat": "def", "ratio": 0.03}})])},
    "파이썬의 갑옷": {            # [대지의 시초] 효과가 각성기에도 적용
        # 각성기는 원래 받는피해 배수를 안 탄다 — 이 플래그가 그 예외를 연다(Battle.resolve_awaken).
        "awaken_mod": awk("대지의 시초", add_ops=[
            op("flag", flag="awaken_taken_applies", to="ally_element:earth")])},
    "발칸의 푸른불꽃": {           # [지옥의 악귀] 효과에 크리티컬 파워 30% 추가
        "awaken_mod": awk("지옥의 악귀", add_ops=[
            op("stat", stat="cri_pow", mode="flat", value=30, to="ally")])},
    "헤네스의 지성의 왕관": {       # [자격을 갖춘 자](전투당 5회) 효과 3회 추가
        "awaken_mod": awk("자격을 갖춘 자", {"react.0.left": "+3"})},
    "다르고스의 파괴의 힘": {       # [파괴의 힘] 발동 시 받는 데미지를 2회 1로 고정
        # 패치는 각성스킬의 cond(아군 어둠 2명)를 통과한 뒤에 먹으므로 '발동 시' 가 지켜진다.
        "awaken_mod": awk("파괴의 힘", add_react=[{"on": "pre_damage", "fix": 1, "left": 2}])},
    "팔라곤의 권위의 투구": {       # [권위의 팔라곤] 공격력 증가량(방어력의 50%) → 150%
        "awaken_mod": awk("권위의 팔라곤", {"ops.0.from.ratio": 1.5})},
    "루키르의 바람의 날개": {       # [신뢰의 힘] 공격력 증가효과가 아군에게도 적용
        "awaken_mod": awk("신뢰의 힘", {"react.0.to": "ally"})},
    "나이트 드래곤의 기사 투구": {   # [빛의 기사] 체력 획득량 2배(상한도 함께)
        "awaken_mod": awk("빛의 기사", {"ops.0.from.ratio": "*2", "ops.0.max": "*2"})},
    "말덱의 흡수의서": {          # [흡수의 힘] 흡수 기준을 기본 → 최대(버프 포함) 능력치로
        "awaken_mod": awk("흡수의 힘", patch_new={"ops.0.effective": True})},
    "스트라의 방출의 서": {        # [방출의 힘] 각성 게이지 증가량 2배
        "awaken_mod": awk("방출의 힘", {"react.0.gauge_pct": "*2"})},
    "푸르푸르의 혼돈의 번개": {      # [절망의 번개](전투당 3회) 발동 횟수 2회 추가
        "awaken_mod": awk("절망의 번개", {"react.0.left": "+2"})},
    "사이커드래곤의 초록 번개": {    # [그림자 수호신] 받는 데미지 절반(20→10) · 아군 증뎀 10→30
        "awaken_mod": awk("그림자 수호신", {"ops.0.pct": 10, "ops.1.pct": 30})},
    "데스퍼라티오의 용암신발": {     # [잠재력] 100% 확률 발동 + 스킬 레벨 증가 +2 로 변경
        "awaken_mod": awk("잠재력", {"ops.0.pct": 100, "ops.0.value": 2})},
    "제피로스의 보석": {          # [잠재력] 발동 확률 +15%p (25 → 40)
        "awaken_mod": awk("잠재력", {"ops.0.pct": "+15"})},
    "크로우 드래곤의 해골투구": {    # 막기/회피 성공 시 [복수의 까마귀] 횟수 1회 회복(최대 4)
        "awaken_mod": awk("복수의 까마귀", add_react=[
            {"on": "block", "do": "react_restore", "target_no": 40, "max": 4},
            {"on": "evade", "do": "react_restore", "target_no": 40, "max": 4}])},
    "쏜 네일의 가시갑옷": {        # [가시와 못] 감소율·증가율을 모두 등급×2% 로
        "awaken_mod": awk("가시와 못", {"ops.0.from.ratio": -2.0, "ops.1.from.ratio": 2.0})},
    "아카이아의 성물": {          # [신성한 유대] 효과가 아군 전체에 적용
        "awaken_mod": awk("신성한 유대", {"dyn.0.ops.0.to": "ally", "dyn.0.ops.1.to": "ally"})},
    "샤마쉬의 흉갑": {           # [정의집행] 의 **추가대미지**(관통) 효과가 아군 전체에 적용
        "awaken_mod": awk("정의집행", {"ops.1.to": "ally"})},
    "샤크곤의 물안경": {          # [구드라의 가호] 아티팩트 획득 확률 100% 로 변경
        "awaken_mod": awk("구드라의 가호", explore={"artifact_chance_pct": 100})},
    "오르페우스의비석": {          # 위와 같은 문구
        "awaken_mod": awk("구드라의 가호", explore={"artifact_chance_pct": 100})},

    # ── 미구현: 기반 각성스킬이 아직 impl:false 이거나 일반 스킬을 고치는 것 ─────
    "번개고룡의 팬던트": {         # [심판의 날개](스킬 21) 사용 시 대미지 200% 증가
        "ops": [op("skill_dmg_deal", pct=200, skill_id=21)]},
    "포세이돈의 삼지창": {         # [대양의 분노](방어율 -7 · 크리 +7) 효과 2배
        "awaken_mod": awk("대양의 분노",
            {"react.0.target_value": "*2", "react.0.self_value": "*2"})},
    "블랙홀의 암흑결정체": {       # [블랙홀의 마력] 회복량 100% · 공격력 증가량 20% 로
        "awaken_mod": awk("블랙홀의 마력",
            {"react.0.ratio": 1.0, "react.0.value": 20, "react.0.max_total": 100})},
    "아루루가의 물갈퀴": {         # [물의 보호막] 효과 2회 추가 (3회 → 5회)
        "awaken_mod": awk("물의 보호막", {"react.0.plant.left": "+2"})},
    "커스리퍼의 뼈투구": {         # [뼈갑옷] 효과 2배 (감소 40→80 · 누적 10%→20%)
        "awaken_mod": awk("뼈갑옷",
            {"ops.0.value": "*2", "react.0.value": "*2"}),
        "partial": "'(감소된 최소 피해량 30)' 은 그대로 둔다 — 원문이 '효과가 2배' 라고만 해서 "
                   "바닥까지 2배인지 근거가 없다"},
    "콜테일의 헛된희망": {         # [타락한 드래곤] 증가량(기본 체력 15%)만큼 공/방도 증가
        "awaken_mod": awk("타락한 드래곤", add_ops=[
            op("stat", stat="att", mode="pct", value=15),
            op("stat", stat="def", mode="pct", value=15)])},
    "루페스의 결정화된 분노": {"impl": False, "why": "skill:복수의 거울"},
    "불나래의 불꽃구슬": {"impl": False, "why": "skill:철갑방패 · 각인 에자녹의 권능"},
    "미니드래곤 고리": {"impl": False,
        "why": "engine — [선제 공격] 발동 시 '아군 드래곤의 합으로 공격' = 합공격이라는 새 공격 형태"},
    "투탕카의 도리깨": {"impl": False,
        "why": "engine — [선제 공격] 발동 시 '공격력이 가장 높은 드래곤이 대신 공격' = 행동 주체 교체"},
    "번네스의 화염신발": {"impl": False,
        "why": "engine — '선제공격으로 발동되는 모든 적의 방어율·회피 무시' = 주도권을 가진 라운드에만 상대에게 거는 디버프 통로가 없다"},
    "홀리의 빛나는양뿔": {          # 크리티컬 공격이 상대의 회피를 무시
        # 우리 판정 순서는 회피→막기→크리라 크리가 정해질 땐 회피가 끝나 있다.
        # `crit_ignores_evade` 플래그가 있으면 Battle 이 **크리를 먼저 굴려** 회피를 건너뛴다.
        "ops": [op("flag", flag="crit_ignores_evade")]},
    "레이어스의 반석 방패": {"impl": False, "why": "skill:(각성스킬 효과 자체를 치환)"},
    "실러캔스의 물빛 투구": {"impl": False, "why": "skill:(각성스킬 효과 2배) — 방어력 조항만으로는 반쪽"},
    "카일루스의 신성 방패": {"impl": False, "why": "skill:(각성스킬 누적)"},
    "디기의 금빛장식": {"impl": False, "why": "skill:(각성스킬 추가대미지 상한)"},
    "세로님의 전쟁보닛": {"impl": False, "why": "skill:팀버프 흑풍"},
    "진의 나무비늘": {           # 아군 땅속성 수만큼 각성기 데미지 20% 증가(최대 60%)
        "ops": [op("awaken_dmg", pct=20, per="ally_element:earth", max=60)]},
    "레지아나의 빛나는 깃털": {     # 해당 드래곤 사망 시 아군 각성기 피해량 50% 증가
        "react": [{"on": "death", "do": "party_buff", "to": "ally",
                   "ops": [{"kind": "awaken_dmg", "pct": 50}]}]},
    "발로드의 갈기": {"ops": [op("awaken_dmg", pct=30)]},   # 각성기 피해량 30% 증가

    # ── 미구현: 오프라인 컷 콘텐츠 ───────────────────────────────────────────
    "청룡의 여의주": {"impl": False, "why": "cut — 토벌전(길드)"},
    # ── 컷 조항이 섞인 것 — **PvE 조항만 살린다**(🟦 사용자 확정 2026-07-31) ────────
    # 원문이 "PvP 에서도 적용되고 **효과가 30% 증가**" 처럼 컷 조항과 PvE 조항을 한 문장에
    # 담고 있다. PvP 조항은 버리고 증가분만 반영한다. 증가분은 "+N%" 규약대로 퍼센트포인트다.
    "익시아의 왕관": {           # [각성된 바람의 힘] 효과 +30%p
        "awaken_mod": awk("각성된 바람의 힘", {
            "ops.0.value": "+30", "ops.1.value": "+30", "ops.2.value": "+30"}),
        "partial": "'바람속성 필드에서 PvP 전투에도 적용' 은 오프라인에서 뺀 콘텐츠라 미반영"},
    "솔라의 불꽃구슬": {          # [각성된 빛의 힘] 효과 +30%p
        "awaken_mod": awk("각성된 빛의 힘", {
            "ops.0.value": "+30", "ops.1.value": "+30", "ops.2.value": "+30"}),
        "partial": "'PvP 에서도 적용' 은 오프라인에서 뺀 콘텐츠라 미반영"},
    "수라드래곤의고대 장식": {      # [각성된 불의 힘] 효과 +30%p
        "awaken_mod": awk("각성된 불의 힘", {
            "ops.0.value": "+30", "ops.1.value": "+30", "ops.2.value": "+30"}),
        "partial": "'PvP 에서도 적용' 은 오프라인에서 뺀 콘텐츠라 미반영"},
    "프로스트랩터의 얼음수정": {     # [각성된 어둠의 힘] 효과 +30%p
        "awaken_mod": awk("각성된 어둠의 힘", {
            "ops.0.value": "+30", "ops.1.value": "+30", "ops.2.value": "+30"}),
        "partial": "'PvP 에서도 적용' 은 오프라인에서 뺀 콘텐츠라 미반영"},
    "바리안의 백색갑옷": {"impl": False, "why": "cut — 순위쟁탈전"},
    "다크프로스티의 무늬": {       # 탐험에서 골드 획득 증가량만큼 자신의 공격력% 증가
        # 그 '증가량' 은 컷된 값이 아니라 **우리도 갖고 있는 값**이다(각성스킬의 탐험 보너스).
        # ui/battle.gd 가 전투원의 `explore_gold_pct` 에 실어 주고 여기서 파생값으로 읽는다.
        "ops": [op("stat", stat="att", mode="pct",
                   **{"from": {"stat": "explore_gold_pct", "ratio": 1.0}})]},

    # ── 미구현: 엔진에 개념이 없다 ───────────────────────────────────────────
    "엔젤 드래곤의티아라": {       # 자신의 방어 관통을 0 으로, 나머지 아군에게 공통분배
        "ops": [op("pen_share")],
        "partial": "'공통분배' 를 **똑같이 나눠 주는 것**으로 읽었다(아군마다 전액이 아니라 1/N). "
                   "원문이 갈라 주지 않아 둘 중 하나를 골라야 했다"},
    "엔투라스의 불꽃 주먹": {       # 크리티컬 발동 시 상대의 현재 방어력 절반 무시
        "ops": [op("crit_pen", pct=50)]},
    "글라시아의 왕관": {           # 상대의 회피율이 0%가 되면 반드시 크리티컬
        "ops": [op("flag", flag="crit_sure_if_no_evade")]},
    "일란의 영예의관": {           # 연속공격 피해량 50% 증가
        "ops": [op("double_dmg", pct=50)]},
    "세크라포의 어깨보호대": {      # 연속 공격 시 준 대미지만큼 회복, 전투 중 3회 한정
        "react": [{"on": "double", "do": "heal_dealt", "ratio": 1.0, "left": 3}],
        "partial": "'피의 갈증과 중첩불가' 는 우리 엔진에 중첩 배제 규칙이 없어 미반영"},
    "완숙이의 후라이팬": {         # 체력 20% 이하일 때 공격 시 체력 1% 회복 + 주는 대미지 25% 증가
        "dyn": [{"when": {"kind": "self_hp_at_most", "pct": 20},
                 "ops": [op("dmg_deal", pct=25)]}],
        "react": [{"on": "attack_done", "do": "heal_pct", "pct": 1,
                   "when": {"kind": "self_hp_at_most", "pct": 20}}],
        "partial": "'피의 갈증과 중첩 불가' 는 우리 엔진에 중첩 배제 규칙이 없어 미반영"},
    "워든의 부유검": {           # 디버프를 받는 동안 일반공격 시 타겟 최대체력 10%만큼 공격력 강화(최대 1000)
        # `when` 이 발화 시점 조건 — '상처 파악'(스킬 23)은 세지 않는다.
        "react": [{"on": "attack_done", "do": "stack_from_target", "stat": "att",
                   "pct": 10, "max_total": 1000,
                   "when": {"kind": "has_debuff", "except_src": [23]}}]},
    "모노케로스의붉은 보주": {"impl": False, "why": "engine — 피해 누적 후 방출(전투 중 1회)"},
    "발록의 전투갑주": {"impl": False, "why": "engine — 회피한 상대가 자기 턴에 반격당하는 역공 구조"},
    "쿠르파의 푸른갑주": {         # 아군 그림자 드래곤이 쓰러지면 5턴간 공격력 50% 상승
        # 죽는 쪽이 반응을 갖고 있어야 하므로 **그림자 아군에게** 심는다(plant).
        "react": [{"on": "death", "do": "party_buff", "plant": "ally_element:shadow",
                   "to": "ally", "turns": 5,
                   "ops": [{"kind": "stat", "stat": "att", "mode": "pct", "value": 50}]}]},
    "오울드라의 어둠갑옷": {        # 전투시작 시 모든 대미지를 1로 막아주는 보호막 1회 **전체** 적용
        # `plant: ally` = 아군 전원에게 각자 1회씩 심는다(각자 자기 몫의 left 를 갖는다).
        "react": [{"on": "pre_damage", "fix": 1, "left": 1, "plant": "ally"}]},
    "페이스리스의사슬": {"impl": False, "why": "engine — 등급 비례 피해 상한(등급 눈금이 원작과 다르다)"},
    "미르의 별빛방울": {           # 상대 팀 현재 체력의 10% 를 공격력에 추가(최대 1000)
        # 상대 체력은 라운드마다 변하므로 동적(dyn) 항목이다 — 라운드 경계에서 다시 계산된다.
        "dyn": [{"when": {"kind": "enemy_hp_sum"},
                 "ops": [op("stat", stat="att", mode="flat", value=0.10, max=1000)]}]},
    "타로스의 용암구슬": {         # 전투 시작 시 자신의 크리티컬 확률만큼 스킬 피해량 증가
        "ops": [op("skill_dmg_deal", **{"from": {"stat": "cri", "ratio": 1.0}})]},
    "운디네의 물방울": {           # 자신의 방어율만큼 아군 물속성 드래곤의 체력 증가(최대 30%)
        # ⚠️ `from` 은 **소유자**의 스탯을 읽고 대상에게 건다 — 원문 그대로다.
        "ops": [op("stat", stat="hp", mode="pct", to="ally_element:aqua", max=30,
                   **{"from": {"stat": "blk", "ratio": 1.0}})]},
    "현무드래곤의동방갑옷": {       # 아군 물속성 드래곤의 피해량 10% 증가
        "ops": [op("dmg_deal", pct=10, to="ally_element:aqua")]},
    "멜로우 드래곤의 부메랑": {     # 아군에 자신 제외 바람속성이 있으면 멜로우는 공격하지 않는다
        # 멜로우 자신이 바람이라 "자신을 제외하고 1마리" = 파티 바람 2마리 이상이다.
        # `no_attack` 은 각성스킬 51 빛의 환희가 쓰는 것과 같은 플래그다.
        "cond": {"kind": "party_element_count", "value": "wind", "min": 2},
        "ops": [op("flag", flag="no_attack")]},
}

# ── 특수 장비 (해골요새·발록·피오드) — 키는 "<계열>:<이름>" ──────────────────
SPECIAL = {
    "balrog:카이저 발록의 팔찌": {   # 현재 체력을 넘어서는 피해를 받아도 1 남기고 생존(1회)
        "ops": [op("flag", flag="survive_once")]},
    "balrog:카이저 발록의 보주": {   # 크리티컬 대미지 100% 증가
        "ops": [op("stat", stat="cri_pow", mode="flat", value=100)]},
    "balrog:카이저 발록의 투구": {   # 공격 시 상대 남은 체력의 5% 비례 추가 대미지(최대 300)
        "react": [{"on": "attack_target_hp", "do": "cur_pct", "pct": 5, "max": 300}]},
    "fiod:피오드의 부서진 낙인": {   # 착용한 드래곤의 스킬 효과 +1
        "ops": [op("skill_level", value=1)]},
    "fiod:피오드의 빛을 잃은 마석": {  # 각성기에 받는 대미지 1000 으로 제한
        "ops": [op("awaken_dmg_cap", value=1000)]},
    "fiod:피오드의 텅 빈 모래시계": {  # 타겟 최대 체력 1마다 0.002% 의, 타겟 최대체력 비례 추가대미지(최대 300)
        # 비율 자체가 최대 체력에 비례하므로 결과는 최대체력의 제곱에 비례한다.
        "react": [{"on": "attack_target_hp", "do": "max_per_unit",
                   "per_unit_pct": 0.002, "max": 300}]},
    # ── 해골요새 6종 — **전투 유형**(체방형/공방형 등) 두 축 ────────────────────
    # 앞 조항 = "<유형>형 드래곤을 **공격 시** 25% 추가 대미지" → `dmg_deal_vs_type`(방어자 유형)
    # 뒤 조항 = "<유형>형 드래곤이 **장착 시** …"                → cond `self_type`(착용자 유형)
    # 유형 값은 `dragons.json` 의 `type`(원작 `Dragon::getAttackType`)이라 새 데이터가 없다:
    #   atk 공격형 · hp 체력형 · def 방어형 · hd 체방형 · ha 체공형 · ad 공방형
    #
    # ⚠️ **앞 조항은 PvE 에서 걸리지 않는다.** 원문이 "…형 **드래곤**을 공격 시" 인데 오프라인
    #    전투의 상대는 몬스터이고, `monsters.json` 에는 전투 유형 열이 없다(form/size 뿐).
    #    유형을 지어내지 않고(HARD RULE 6) 기구만 정확히 두었다 — 드래곤을 상대하는 전투가
    #    생기면 그날 자동으로 걸린다. 그래서 `partial` 에 그 사실을 적는다.
    "skull:엘더 블랙퀸의 스태프": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="hd"),
                op("stat", stat="evd", mode="flat", value=10,
                   cond={"kind": "self_type", "value": "def"})],
        "partial": "앞 조항(체방형 드래곤 공격 시 +25%)은 몬스터에 전투 유형이 없어 PvE 에서 안 걸린다"},
    "skull:엘더 블랙퀸의 목걸이": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="def")],
        "impl": True,
        "partial": "'체력형이 장착 시 체력 추가 한계량 20% 증가' 는 원문의 '추가 한계량'이 "
                   "무엇의 한계인지 위키에 정의가 없어 미반영"},
    "skull:엘더 블랙퀸의 목도리": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="ad"),
                op("skill_dmg_taken", pct=-10,
                   cond={"kind": "self_type", "value": "hd"})]},
    "skull:G스컬의 은빛망토": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="ha"),
                # [신의 분노](36)가 [망각의 망치](56)의 효과를 받지 않는다 → 망각 면역 플래그.
                op("flag", flag="oblivion_immune",
                   cond={"kind": "self_type", "value": "ad"})]},
    "skull:G스컬의 붉은장갑": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="hp"),
                op("stat", stat="cri_pow", mode="flat", value=100,
                   cond={"kind": "self_type", "value": "atk"})]},
    "skull:G스컬의 영혼불길": {
        "ops": [op("dmg_deal_vs_type", pct=25, atk_type="atk"),
                op("stat", stat="hp", mode="pct", value=15,
                   cond={"kind": "self_type", "value": "ha"}),
                op("stat", stat="att", mode="pct", value=15,
                   cond={"kind": "self_type", "value": "ha"})]},
}


def normalize(tbl: dict, texts: dict) -> dict:
    """기본값 채우기 + 원문 동봉(검수용)."""
    out = {}
    for k, v in tbl.items():
        e = dict(v)
        e.setdefault("impl", True)
        e.setdefault("ops", [])
        e.setdefault("react", [])
        e.setdefault("dyn", [])       # 라운드마다 다시 계산되는 조건부 항목(각성스킬과 같은 어휘)
        e["text"] = texts.get(k, "")
        out[k] = e
    return out


def resolve_awaken_mods(tbl: dict) -> None:
    """`awaken_mod.skill`(이름) → `no`(번호). 이름이 없거나 그 스킬이 미구현이면 **멈춘다**.

    ⚠️ 조용히 넘어가면 장비가 아무 일도 안 하는 채로 `impl:true` 가 되어 가장 나쁘다.
       각성 표가 바뀌어 이름/경로가 어긋나는 순간 여기서 잡힌다.
    """
    sa = json.loads((REPO / "data" / "skill_awaken.json").read_text(encoding="utf-8"))
    by_name = {s["name"]: s for s in sa["skills"]}
    bad = []
    for key, v in tbl.items():
        mod = v.get("awaken_mod")
        if not mod:
            continue
        s = by_name.get(mod["skill"])
        if s is None:
            bad.append("%s: 각성스킬 '%s' 이 표에 없다" % (key, mod["skill"]))
            continue
        if not (s.get("effect") or {}).get("impl"):
            bad.append("%s: 각성스킬 '%s' 이 아직 impl:false" % (key, mod["skill"]))
            continue
        mod["no"] = s["no"]
        # 패치 경로가 실제로 존재하는지 확인 — 오타/표 변경으로 조용히 무효가 되는 것을 막는다.
        fresh = set(mod.pop("_patch_new", []))
        for path in (mod.get("patch") or {}):
            # 새 키는 **부모까지만** 검사한다(잎은 아직 없는 게 정상).
            probe = path.rsplit(".", 1)[0] if path in fresh and "." in path else path
            if not _path_exists(s["effect"], probe):
                bad.append("%s: 패치 경로 '%s' 가 %s 의 effect 에 없다" % (key, probe, mod["skill"]))
    if bad:
        raise SystemExit("[build_equip_effects] 각성스킬 수정자 오류:\n  " + "\n  ".join(bad))


def _path_exists(root, path: str) -> bool:
    cur = root
    for part in path.split("."):
        if isinstance(cur, list):
            i = int(part)
            if i < 0 or i >= len(cur):
                return False
            cur = cur[i]
        elif isinstance(cur, dict):
            if part not in cur:
                return False
            cur = cur[part]
        else:
            return False
    return True


def main() -> None:
    resolve_awaken_mods(EXCLUSIVE)
    resolve_awaken_mods(SPECIAL)
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
