class_name Battle
## logic 층: 턴제 전투 + 스킬 엔진. (CLAUDE.md §10, 출처 §K-2~K-6/§B + 사용자 스킬규칙)
## 순수 정적 — Node·render·에셋·오토로드 비의존. 결과(이벤트 로그+승패)만 반환, 연출 안 함(§10.3).
## 전투 상수(cfg=data/combat.json)·스킬 정의(skills_db=data/skills.json)·시드 RNG는 인자로 받는다(재현 가능).

const DEFAULT_PROC := 20.0   # 스킬 기본 발동 확률(%) — notes 미명시 시

## compute_stats 결과를 전투 엔티티(가변)로. skills=[{id,level,dedicated}], pen=관통(§K-2).
static func make_combatant(name: String, side: String, element: String, stats: Dictionary, pen := 0.0, skills: Array = [], skill_slots: Array = []) -> Dictionary:
	# ⚠️ 스킬 id 정규화: 로드아웃/세이브의 id는 JSON 경유로 float(30.0)이 되기 쉬운데,
	# skills_db는 "30" 문자열 키라 str(30.0)="30.0"이면 조회 실패 → 스킬이 전혀 발동 안 함.
	# 여기서 int로 정규화해 str(id)가 항상 "30"이 되게 한다(원본 배열은 건드리지 않음).
	var norm: Array = []
	for s in skills:
		var sc: Dictionary = (s as Dictionary).duplicate()
		sc["id"] = int(s.get("id", 0))
		sc["level"] = int(s.get("level", 1))
		norm.append(sc)
	return {
		"name": name, "side": side, "element": element,
		"hp_max": int(stats.get("hp", 1)), "hp": int(stats.get("hp", 1)),
		# 버프가 얹히기 **전**의 최대 체력. 100 흡수의 힘이 '기본 능력치'를 읽을 때 쓴다
		# (다른 스탯은 원시 필드가 그대로 남아 있지만 hp_max 는 _aw_add_stat 가 직접 고친다).
		"hp_base": int(stats.get("hp", 1)),
		"att": int(stats.get("att", 1)), "def": int(stats.get("def", 1)),
		"cri": int(stats.get("cri", 10)), "evd": int(stats.get("evd", 10)), "blk": int(stats.get("blk", 10)),
		# 장비 스탯(원작 info_item_acc 컬럼). 전부 0 기본 = 장비 없으면 종전과 완전히 동일한 전투.
		#   pure     방어 관통 대미지(flat). "방어 무시 고정 대미지"라 방어력·막기와 무관하게 더해진다.
		#   depure   받는 pure 감소(flat). 피오드 모래시계 주 능력.
		#   cri_pow  크리티컬 파워 %. 크리 배수를 (1 + cri_pow/100) 배로 키운다.
		#   accuracy 명중률 %. 상대 회피 확률에서 차감한다.
		#   cure     행동불능(패배 후 지속 상태) **회피** 확률 %. 전투 중에는 쓰지 않는다 —
		#            전투 종료 후 render 가 `Incapacitation.avoids` 로 판정한다(사용자 확정 2026-07-29).
		"pure": int(stats.get("pure", 0)), "depure": int(stats.get("depure", 0)),
		"cri_pow": int(stats.get("cri_pow", 0)), "accuracy": int(stats.get("accuracy", 0)),
		"cure": int(stats.get("cure", 0)),
		"pen": pen, "alive": true,
		# 각성 스킬 번호(data/skill_awaken.json). 0 = 미각성이거나 배정 없음.
		# 효과는 Battle 이 아니라 `AwakenSkill.apply_battle` 이 전투 시작 전에 얹는다 —
		# 각성스킬은 '스킬'이 아니라 상시 특성이라 이 엔진의 skill_uses 흐름을 타지 않는다.
		"awaken_no": int(stats.get("awaken_no", 0)),
		# 도감 id — 특정 드래곤을 지목하는 각성스킬(29 대폭렬의 힘 "아군 다르고스")용.
		"dragon_id": int(stats.get("dragon_id", 0)),
		# 개체 등급(Growth.compute_grade). 각성스킬 18·100 이 아군끼리 **비교**할 때만 쓴다.
		# ⚠️ 절대 눈금은 원작과 다르다(우리 7.0 기준 / 원작 0~6) — 절대값을 쓰는 스킬은 미이식.
		"grade": float(stats.get("grade", 0.0)),
		# 전투 유형(원작 `Dragon::getAttackType`) — `dragons.json` 의 `type`.
		#   atk 공격형 · hp 체력형 · def 방어형 · hd 체방형 · ha 체공형 · ad 공방형
		# 해골요새 특수 장비가 "체방형 드래곤을 공격 시 25% 추가 대미지" 처럼 **양쪽 유형**을 본다.
		# 스탯 곡선(stat_table)의 축과 같은 값이라 별도 표가 필요 없다.
		"atk_type": String(stats.get("atk_type", "")),
		# 이 파티의 **탐험 골드 증가량(%)**. 전투 계수가 아니라 참조값이다 —
		# 전용 장비 다크프로스티의 무늬가 "그 증가량만큼 공격력% 증가" 라고 이 값을 읽는다.
		"explore_gold_pct": int(stats.get("explore_gold_pct", 0)),
		"skills": norm, "skill_uses": {}, "effects": [],
		# 장착 중인 장비의 카탈로그 키(EquipEffect.keys_of). 조건부 효과를 심을 때만 쓰고,
		# 스탯은 이미 Equipment.apply 로 stats 에 반영돼 들어온다.
		"equip_keys": (stats.get("equip_keys", []) as Array),
		# 스킬 칸 타입(원작 Dragon::getSkillType 0△1□2○3☆). 스킬 자체 타입과 일치하면 추가효과.
		"skill_slots": skill_slots,
	# 아티팩트 수정치(Equipment.artifact_mods) — 스킬 id → 값. 비어 있으면 아무 영향 없다.
	#   proc_add/foe_proc_sub = 발동 확률 %p · power_lv = 효과 레벨 · skill_dmg_taken_pct = 받는 스킬피해 %
	"artifact": (stats.get("artifact", {}) as Dictionary),
	}

# ============================================================ 상태효과 프레임워크
## 효과 반영 최종 스탯(stat 버프/디버프 pct/flat).
static func _eff(c: Dictionary, stat: String) -> int:
	var base := float(c.get(stat, 0))
	var pct := 0.0
	var flat := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "stat" and e.get("stat") == stat:
			if e.get("mode") == "pct": pct += float(e["value"])
			else: flat += float(e["value"])
	return int(round(base * (1.0 + pct / 100.0) + flat))

static func _has_flag(c: Dictionary, flag: String) -> bool:
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			return true
	return false

## 그 상태를 건 **스킬 id**. render 가 원작 Bicon(= `skill/%d.png` 아이콘)을 그릴 때 쓴다 —
## 원작은 버프 아이콘이 곧 스킬 아이콘이라 출처가 있어야 그릴 수 있다. 없으면 0.
static func _flag_source(c: Dictionary, flag: String) -> int:
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			return int(e.get("source", 0))
	return 0

## 그 상태의 **남은 턴**. 원작 `Bicon::setTurnCount` 가 아이콘 위에 이 숫자를 찍는다.
static func _flag_turns(c: Dictionary, flag: String) -> int:
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			return maxi(0, int(e.get("turns", 0)))
	return 0

static func _remove_flag(c: Dictionary, flag: String) -> void:
	var keep: Array = []
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			continue
		keep.append(e)
	c["effects"] = keep

## 받는 피해 배수(취약 23 등 dmg_taken 합산).
static func _dmg_taken_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_taken":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

## 주는 피해 배수 — 각성스킬의 "입히는/주는 데미지 N% 증가" 계열(16·31·68·20·33 …).
## `_deal_attack` 한 곳에서 곱하므로 **평타·스킬 공격 모두** 같은 규칙을 탄다.
## # ASSUMPTION: 방어 무시 고정 피해(pure)에도 함께 걸린다 — 설명이 "입히는 데미지"라고만 해서
##   갈라 볼 근거가 없다. 갈라야 할 근거가 생기면 `_hit_damage` 쪽으로 옮기면 된다.
static func _dmg_deal_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_deal":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

## **상대를 보고** 걸리는 주는 피해 배수 — 두 축이 있다.
##   `dmg_deal_vs_element` 방어자의 **속성** ("불 속성 드래곤에게 주는 대미지 50% 증가")
##   `dmg_deal_vs_type`    방어자의 **전투 유형** ("체방형 드래곤을 공격 시 25% 추가 대미지")
## 상시값인 `dmg_deal` 과 달리 방어자를 봐야 해서 별도 통로다.
## 여러 개면 **곱이 아니라 합**으로 본다(같은 축의 증가율이라 dmg_deal 과 같은 규약).
static func _dmg_deal_vs_mult(attacker: Dictionary, defender: Dictionary) -> float:
	var el := String(defender.get("element", ""))
	var ty := String(defender.get("atk_type", ""))
	var pct := 0.0
	for e in (attacker.get("effects", []) as Array):
		var d := e as Dictionary
		match String(d.get("kind", "")):
			"dmg_deal_vs_element":
				if el != "" and String(d.get("element", "")) == el:
					pct += float(d.get("pct", 0.0))
			"dmg_deal_vs_type":
				if ty != "" and String(d.get("atk_type", "")) == ty:
					pct += float(d.get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

## 각성기 피해 배수 — "자신의 각성기 피해량 30% 증가"(발로드의 갈기) 계열.
## 평타·스킬이 지나는 `dmg_deal` 과 통로가 다르다(각성기는 resolve_awaken 이 따로 굴린다).
static func _awaken_dmg_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if (e as Dictionary).get("kind") == "awaken_dmg":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

## 크리 전용 방어 관통(%) — "크리티컬 발동 시 상대의 현재 방어력 절반 무시"(엔투라스의 불꽃 주먹).
static func _crit_pen_pct(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "crit_pen":
			pct += float((e as Dictionary).get("pct", 0.0))
	return pct


## **스킬 피해에만** 걸리는 **주는** 피해 배수 — "스킬 피해량 증가"(타로스의 용암구슬).
## 평타·각성기가 지나는 `dmg_deal` 과 통로가 다르다.
## `skill_id` 를 붙이면 **그 스킬을 쓸 때만** 걸린다("[심판의 날개] 사용 시 대미지 200% 증가"
## — 번개고룡의 팬던트). 안 붙이면 모든 스킬에 걸린다(타로스의 용암구슬).
static func _skill_dmg_deal_mult(c: Dictionary) -> float:
	var now := int(c.get("_cast_skill_id", 0))
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) != "skill_dmg_deal":
			continue
		var only := int(d.get("skill_id", 0))
		if only > 0 and only != now:
			continue
		pct += float(d.get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)


## 각성기에 **받는** 피해 상한(정액) — "각성기에 받는 대미지 1000으로 제한"(피오드의 마석).
## 0 = 상한 없음. 여러 개면 가장 낮은 값이 이긴다.
static func _awaken_taken_cap(c: Dictionary) -> int:
	var cap := 0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "awaken_dmg_cap":
			var v := int((e as Dictionary).get("value", 0))
			if v > 0 and (cap == 0 or v < cap):
				cap = v
	return cap


## **스킬 피해에만** 걸리는 받는 피해 배수 — "스킬에 입는 피해 10% 감소"(엘더 블랙퀸의 목도리).
## 상시 `dmg_taken` 과 통로가 다르다(평타에는 안 걸린다). 음수 pct 가 감소다.
static func _skill_dmg_taken_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "skill_dmg_taken":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

## 받는 피해 정액 감소 — "받는 피해량 15 감소 (최소 피해량 1)"(14 고요한 바람) 계열.
## 배수(dmg_taken)를 먹인 **뒤에** 뺀다.
static func _dmg_taken_flat(c: Dictionary) -> float:
	var v := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_taken_flat":
			v += float(e["value"])
	return v

## 정액 감소의 **바닥** — "(감소된 최소 피해량 30)"(52 뼈갑옷). 0 = 바닥 없음.
## 여러 개면 가장 높은 값이 이긴다(더 강한 보호가 이기는 다른 규칙들과 같은 규약).
static func _dmg_taken_floor(c: Dictionary) -> int:
	var v := 0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "dmg_taken_flat":
			v = maxi(v, int((e as Dictionary).get("min_dmg", 0)))
	return v


## 각성 게이지 충전율 배수 — `gauge_rate` 효과(%)의 합. 기본 1.0.
static func _gauge_rate(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "gauge_rate":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

## 각성기 발동 후 게이지가 내려가는 바닥값. 기본 0. 여러 개면 가장 높은 것.
static func _gauge_min(c: Dictionary) -> float:
	var v := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "gauge_min":
			v = maxf(v, float(e["value"]))
	return clampf(v, 0.0, 99.0)

## 스킬 최대 사용횟수 보너스(23 다이즈의 가호 · 98 혼돈의 절대자).
static func _skill_uses_bonus(c: Dictionary) -> int:
	var v := 0
	for e in c.get("effects", []):
		if e.get("kind") == "skill_uses":
			v += int(e["value"])
	return v + _art_hidden(c, "skill_uses")

## 스킬 **효과** 레벨 보너스(89 지혜의 별빛 + 83 잠재력의 한 발동 한정 보너스).
## ⚠️ 발동 확률(_proc_pct)에는 걸지 않는다 — 83 이 "발동 확률에는 영향을 주지 않는다" 라고
##    못박고, 89 도 "1레벨 더 높은 **효과**" 라고만 한다.
static func _skill_level_bonus(c: Dictionary) -> int:
	var v := 0
	for e in c.get("effects", []):
		if e.get("kind") == "skill_level":
			v += int(e["value"])
	return v + int(c.get("_proc_level_bonus", 0))

## 이 발동 건의 스킬 효과 레벨.
static func _lv(c: Dictionary, s: Dictionary) -> int:
	# 아티팩트 BOOST(이그니스)·BNR(테라) = "스킬 효과 강화" → 효과 레벨 가산.
	return maxi(1, int(s["level"]) + _skill_level_bonus(c) + _art(c, "power_lv", int(s["id"])))

## 1회 피해 상한(최대 체력의 %). 0 = 상한 없음. 여러 개면 **가장 낮은 것**이 이긴다.
static func _dmg_cap_pct(c: Dictionary) -> float:
	var best := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_cap_pct":
			var v := float(e["pct"])
			if v > 0.0 and (best <= 0.0 or v < best):
				best = v
	return best

## 흡혈(14) 합산 %.
static func _lifesteal_pct(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "lifesteal":
			pct += float(e["pct"])
	return pct

## 해로운 효과 전부 제거(정화 26). 이로운 효과(양수 stat·lifesteal·survive_once·패시브)는 유지.
static func _cleanse(c: Dictionary) -> void:
	var keep: Array = []
	for e in c.get("effects", []):
		var k := String(e.get("kind", ""))
		if k == "status" or k == "dot" or k == "dmg_taken" or k == "timed":
			continue
		if k == "stat" and float(e.get("value", 0)) < 0:
			continue
		keep.append(e)
	c["effects"] = keep

static func _add_stat(c: Dictionary, stat: String, mode: String, value: float, turns: int, src: int) -> void:
	c["effects"].append({"kind": "stat", "stat": stat, "mode": mode, "value": value, "turns": turns, "source": src})

static func _add_flag(c: Dictionary, flag: String, turns: int, src: int) -> void:
	# 상태이상 면역(각성스킬 777 성좌의 주권자 · 700 각성하는 의지 "모든 상태이상 무시").
	# ⚠️ **해로운 플래그만** 막는다. 종전에는 `status_immune` 이 아닌 플래그를 전부 막아서
	#    자기 자신에게 거는 이로운 플래그(50 필살 방어의 `survive_once` ·
	#    각성스킬 81 자격을 갖춘 자의 `evade_sure` · 5 각성된 맹수의 발톱의 `crit_sure`)까지
	#    조용히 사라졌다 — 면역이 오히려 손해가 되던 버그(2026-07-29 수정).
	if flag in DEBUFF_FLAGS and _has_flag(c, IMMUNE_FLAG):
		return
	c["effects"].append({"kind": "status", "flag": flag, "turns": turns, "source": src})

## '모든 상태이상 무시' 를 나타내는 플래그. AwakenSkill 이 얹고, `_add_flag` 가 이걸 보고 막는다.
const IMMUNE_FLAG := "status_immune"

## **해로운** 상태 플래그 — '상태이상 무시' 가 막는 대상. 이로운 플래그는 여기 넣지 않는다.
##
##   stun      행동 불가        — 스킬 15 암흑의 사슬
##   confused  자기 자신을 공격 — 스킬 22 환각 효과 · 각성 40·85·96·600·666
##   no_evade  회피 불가        — 스킬 46 뼈 부수기 · 150 빙결의 표식 · 170 시간의 역행
##   no_block  막기 불가        — 스킬 46 뼈 부수기
##   no_crit   크리 불가        — 스킬 160 마비의 구름 · 170 시간의 역행
##
## ⚠️ 경계: 이 목록은 **플래그형 상태이상**만이다. 지속피해(`dot` 32 신경독소) ·
##   시한폭탄(`timed` 54) · 받는피해 증가(`dmg_taken` 23 상처 파악) ·
##   능력치 감소(음수 `stat` — 120 무언의 압박 · 130 약점파악 · 140 살기표출)는
##   효과 종류가 달라 `_add_flag` 를 지나지 않으므로 **면역이 막지 않는다**.
##   '모든 상태이상' 에 그것들까지 넣을지는 사용자 확인 대상(2026-07-29).
const DEBUFF_FLAGS := ["stun", "confused", "no_evade", "no_block", "no_crit"]

# ============================================================ 데미지/판정 (§K-2~K-4)
static func element_mult(att_el: String, def_el: String, cfg: Dictionary) -> float:
	var e: Dictionary = cfg.get("element", {})
	if def_el in e.get("good_vs", {}).get(att_el, []):
		return float(e.get("good_mult", 1.25))
	if def_el in e.get("bad_vs", {}).get(att_el, []):
		return float(e.get("bad_mult", 0.85))
	return float(e.get("neutral_mult", 1.0))

## 데미지(§K-2). def_eff=max(1, def*(1-관통)).
static func damage(att: int, def: int, pen: float, elem_mult: float, crit_mult: float, rand_factor: float, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	var base := float(d.get("base", 30))
	var def_eff := maxf(1.0, float(def) * (1.0 - clampf(pen, 0.0, 1.0)))   # ASSUMPTION: 0 division 방지 최소 1
	var raw := (base * float(att) / def_eff) * elem_mult * crit_mult * rand_factor
	return maxi(1, int(round(raw)))   # ASSUMPTION: 최소 1 데미지

## 타겟팅(§K-6): 적 생존자 중 (hp_max/4)+def 최대.
static func pick_target(enemies: Array, _cfg: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for c in enemies:
		if not c["alive"]:
			continue
		var score := float(c["hp_max"]) / 4.0 + float(c["def"])
		if score > best_score:
			best_score = score
			best = c
	return best

static func _roll(rng: RandomNumberGenerator, percent: int, cap: int) -> bool:
	return rng.randf() * 100.0 < float(clampi(percent, 0, cap))

## 실효 회피 확률 = 방어자 회피 − 공격자 명중률(장비 accuracy). 장비 없으면 종전과 동일.
## 원작 근거: 명중률은 info_item_acc 의 accuracy 컬럼이자 피오드 마석의 주 능력(+13%).
static func _evade_chance(attacker: Dictionary, defender: Dictionary) -> int:
	return maxi(0, _eff(defender, "evd") - _eff(attacker, "accuracy"))

## 피해 적용: 취약(dmg_taken) 배수 + 1회 생존(survive_once 50). 반환 {dmg(실피해), dead, survived?}.
## ── 보스 2페이즈 (혼돈의 틈새) ──────────────────────────────────────────────────
## 원작에는 이 규칙의 **수치가 남아 있지 않다** — 전투가 서버 계산이라
## (`attack_darknix.hb` 요청 → 클라는 `change%d` 델타만 재생) 조건·계수가 유실됐다.
## 문자열·심볼·`getIsDarknixMode` 분기 17곳 전수 조회에도 배리어/피해감소 코드가 없다
## (근거 = docs/ref/porting/ChaosRiftDarknix.md §4-A).
## ⇒ 🟦 사용자 확정 2026-07-31: **잔여 HP 33% 이하로 떨어지는 즉시 2페이즈**,
##    그 뒤로 **받는 피해 50%**. 회복 찬스 턴은 구현하지 않는다(사용자 결정).
## 값은 코드가 아니라 `data/stages.json` 의 `summon.phase2` 에 있다(§2-6 튜닝 노브).
##
## 전환을 만든 그 타격 자체는 **감면되지 않는다** — "임계 진입 즉시 전환"이라 감면은
## 다음 타격부터다. 전환된 턴에 `phase2: true` 를 결과에 실어 render 가 연출하게 한다.
static func _phase_taken_mult(c: Dictionary) -> float:
	if int(c.get("phase", 1)) < 2:
		return 1.0
	return maxf(0.0, float(c.get("phase2_taken_mult", 1.0)))

## 피해를 넣은 뒤 임계를 넘었는지 본다. 방금 2페이즈가 됐으면 true.
static func _enter_phase2_if_needed(c: Dictionary) -> bool:
	var th := float(c.get("phase2_at", 0.0))
	if th <= 0.0 or int(c.get("phase", 1)) >= 2 or not bool(c.get("alive", true)):
		return false
	var hp_max := maxf(1.0, float(c.get("hp_max", 1)))
	if float(c.get("hp", 0)) / hp_max > th:
		return false
	c["phase"] = 2
	return true

static func _apply_dmg(defender: Dictionary, dmg: int) -> Dictionary:
	var scaled := float(dmg) * _dmg_taken_mult(defender) * _phase_taken_mult(defender)
	var f := maxi(1, int(round(scaled - _dmg_taken_flat(defender))))
	# 52 뼈갑옷 "(감소된 최소 피해량 30)" — 정액 감소는 이 바닥 아래로 못 깎는다.
	# 원래 피해가 그보다 작으면 그대로 둔다(감소가 피해를 **늘리면** 안 되므로).
	var floor_v := _dmg_taken_floor(defender)
	if floor_v > 0 and f < floor_v:
		f = mini(floor_v, maxi(1, int(round(scaled))))
	# 확률적 피해 고정 — 87 즈믄의 친구. 상한보다 먼저 본다(더 강한 효과라서).
	f = _aw_fix_damage(defender, f)
	# 피해 상한 — 각성스킬 777 "모든 공격에 의해 입는 피해량이 최대 체력의 25%로 제한".
	var cap_pct := _dmg_cap_pct(defender)
	if cap_pct > 0.0:
		f = mini(f, maxi(1, int(round(float(defender["hp_max"]) * cap_pct / 100.0))))
	if f >= int(defender["hp"]) and _has_flag(defender, "survive_once"):
		var taken := maxi(0, int(defender["hp"]) - 1)
		defender["hp"] = 1
		_remove_flag(defender, "survive_once")
		var sp := _enter_phase2_if_needed(defender)
		var sout := {"dmg": taken, "dead": false, "survived": true}
		if sp: sout["phase2"] = true
		return sout
	defender["hp"] = maxi(0, int(defender["hp"]) - f)
	var dead := int(defender["hp"]) <= 0
	if dead:
		defender["alive"] = false
	var out2 := {"dmg": f, "dead": dead}
	if _enter_phase2_if_needed(defender):
		out2["phase2"] = true
	return out2

## 크리티컬 배수 — 장비 크리티컬 파워(cri_pow %)를 곱한다. 장비 없으면 cfg 기본값 그대로.
## ASSUMPTION: 위키 "크리티컬 대미지 100% 증가"(발록 보주) = 크리 배수 ×2 로 해석.
static func _crit_mult(attacker: Dictionary, cfg: Dictionary) -> float:
	var base := float(cfg.get("damage", {}).get("crit_mult", 1.5))
	return base * (1.0 + float(_eff(attacker, "cri_pow")) / 100.0)

## 방어 관통 고정 피해(pure) — 방어력·막기를 무시하고 더해지는 flat 피해.
## 원작 위키: 묘안석 "방어 무시 고정 대미지", 피오드 모래시계 "관통 대미지 감소 20"(=depure).
## ASSUMPTION: 속성 상성·크리 배수의 영향을 받지 않고, 막기 감산 뒤에 더한다.
##
## 각성스킬이 이 값을 **비율로** 키우고 줄인다 — `pure_pct`(주는 추가 데미지 %) ·
## `depure_pct`(받는 추가 데미지 감소 %).
## 근거: 각성스킬 86 정의집행이 한 문장 안에서 두 낱말을 함께 쓴다 —
##   "자신 합계 방어력의 10% 자신의 **관통데미지 무시**, 합계 공격력의 10% 자신의 **추가데미지 증가**"
##   ⇒ '추가 데미지' = 우리 `pure`(방어무시 고정 피해) · '관통데미지 무시' = 우리 `depure`.
##   이 대응으로 50·70·666·777 의 '추가 데미지' 조항이 전부 해석된다.
##   ⚠️ 사용자 확인 대상(추론이다) — 틀렸다면 이 함수와 build_awaken_effects.py 만 고치면 된다.
static func _pure_damage(attacker: Dictionary, defender: Dictionary) -> int:
	var p := float(_eff(attacker, "pure")) * (1.0 + float(_eff(attacker, "pure_pct")) / 100.0)
	var net := maxf(0.0, p - float(_eff(defender, "depure")))
	net *= maxf(0.0, 1.0 - float(_eff(defender, "depure_pct")) / 100.0)
	return maxi(0, int(round(net)))

static func _hit_damage(attacker: Dictionary, defender: Dictionary, crit: bool, block: bool, rng: RandomNumberGenerator, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	# 95 푸른 화염 "공격이 항상 유리한 상성으로 적용 (방어에는 영향 없음)".
	var em := float(cfg.get("element", {}).get("good_mult", 1.25)) 		if _has_flag(attacker, "elem_advantage") 		else element_mult(String(attacker["element"]), String(defender["element"]), cfg)
	var crit_mult := _crit_mult(attacker, cfg) if crit else 1.0
	var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
	# `crit_pen` = 전용 장비 엔투라스의 불꽃 주먹 "크리티컬 발동 시 상대의 현재 방어력 절반 무시".
	# 상시값인 `pen` 과 달리 **크리일 때만** 더한다.
	var pen := float(attacker["pen"])
	if crit:
		pen = clampf(pen + _crit_pen_pct(attacker) / 100.0, 0.0, 0.95)
	var dmg := damage(_eff(attacker, "att"), _eff(defender, "def"), pen, em, crit_mult, rf, cfg)
	if block:
		var red := float(cfg.get("judge", {}).get("block_reduction", 0.5))
		dmg = maxi(1, int(round(float(dmg) * (1.0 - red))))
	return dmg + _pure_damage(attacker, defender)

## 공격 1회의 피해 적용(평타·스킬공격 공통): 피격 방어스킬(is_skill 구분) + 취약/생존 + 반사.
## 반환 이벤트 조각 {damage, dead, [def_skill], [survived], [reflect], [reflect_dead]}.
static func _deal_attack(attacker: Dictionary, defender: Dictionary, raw_dmg: int, is_skill: bool, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Dictionary:
	# 주는 피해 배수(각성스킬 "입히는 데미지 N% 증가")는 평타·스킬이 공통으로 지나는 여기서 곱한다.
	raw_dmg = maxi(1, int(round(float(raw_dmg) * _dmg_deal_mult(attacker)
		* _dmg_deal_vs_mult(attacker, defender))))
	# 각성스킬 반응 — 공격 직전(누적 방출 45 불타는 날개 등)에 추가 피해를 얹는다.
	raw_dmg += _aw_on_attack_bonus(attacker, defender, rng, raw_dmg)
	# 아티팩트 DEDMG(벤투스) = "상대 스킬 대미지 감소". 스킬 피해에만, 방어측 기준으로 깎는다.
	if is_skill:
		# 🟦 스킬 공격에도 **막기**를 적용한다(사용자 확정 2026-07-31).
		#    근거: 각성스킬 78 [용암의 노련함] "자신의 스킬이 상대 방어율을 100% 무시" 가
		#    존재한다는 것 자체가 원작에서 스킬도 막혔다는 뜻이다. 그 스킬이 면제 플래그다.
		#    ⚠️ 방어 스킬 20 [보호의 장막]이 스킬 피해에 안 걸리는 것과는 다른 축이다.
		if not _has_flag(attacker, "skill_ignores_block") 				and not _has_flag(defender, "no_block") 				and _roll(rng, _eff(defender, "blk"),
					int(cfg.get("judge", {}).get("prob_cap", 70))):
			var bred := float(cfg.get("judge", {}).get("block_reduction", 0.5))
			raw_dmg = maxi(1, int(round(float(raw_dmg) * (1.0 - bred))))
			_aw_on_block(defender, rng)            # 64 신비한 보호 · 65 신성 방패 · 38 방출의 힘
		# 주는 쪽 — "자신의 크리티컬 확률만큼 스킬 피해량 증가"(타로스의 용암구슬).
		var sdm := _skill_dmg_deal_mult(attacker)
		if not is_equal_approx(sdm, 1.0):
			raw_dmg = maxi(1, int(round(float(raw_dmg) * sdm)))
		var ded := _art(defender, "skill_dmg_taken_pct", int(attacker.get("_cast_skill_id", 0)))
		if ded > 0:
			raw_dmg = maxi(1, int(round(float(raw_dmg) * (1.0 - float(ded) / 100.0))))
		# 장비/각성스킬의 "스킬에 입는 피해 N% 감소" — `dmg_taken` 과 같은 규약으로 **음수가 감소**다.
		var sm := _skill_dmg_taken_mult(defender)
		if not is_equal_approx(sm, 1.0):
			raw_dmg = maxi(1, int(round(float(raw_dmg) * sm)))
	var dres := _defense_skill_onhit(defender, rng, raw_dmg, is_skill, cfg, skills_db)
	var ap := _apply_dmg(defender, int(dres["dmg"]))
	var out := {"damage": int(ap["dmg"]), "dead": bool(ap["dead"])}
	if ap.has("phase2"):
		out["phase2"] = true          # 이 타격으로 보스가 2페이즈에 들어갔다(render 가 연출)
	# 각성스킬 반응 — 피격/사망. 누적기(21 깨어난 방어 감각 등)가 여기서 자란다.
	_aw_on_hit_taken(defender, attacker, int(ap["dmg"]), rng)
	if bool(ap["dead"]):
		_aw_on_death(defender)
	if ap.has("survived"):
		out["survived"] = true
	if String(dres["fired"]) != "":
		out["def_skill"] = dres["fired"]
	var refl := int(dres.get("reflect", 0))
	if refl > 0 and attacker["alive"]:
		var rap := _apply_dmg(attacker, refl)
		out["reflect"] = int(rap["dmg"])
		out["reflect_dead"] = bool(rap["dead"])
	return out

## 크리티컬 판정 한 곳 — 평타·연속공격이 같은 규칙을 쓰도록 모았다.
##   `crit_sure`              각성스킬 5 각성된 맹수의 발톱 "크리티컬 확률 100% 고정".
##                            확률 상한(prob_cap 70)을 우회해야 '고정'이라 확률이 아니라 플래그다.
##   `crit_sure_if_no_evade`  전용 장비 글라시아의 왕관 "상대의 회피율이 0%가 되면 반드시 크리".
##                            회피율은 명중률·디버프가 깎은 **최종 확률**로 본다(`_evade_chance`).
static func _roll_crit(attacker: Dictionary, defender: Dictionary,
		rng: RandomNumberGenerator, cap: int) -> bool:
	if _has_flag(attacker, "no_crit"):
		return false
	if _has_flag(attacker, "crit_sure"):
		return true
	if _has_flag(attacker, "crit_sure_if_no_evade") 			and _evade_chance(attacker, defender) <= 0:
		return true
	return _roll(rng, _eff(attacker, "cri"), cap)


## 평타 1회(§K-4): 회피→방어율→크리. 상태이상·피격 방어스킬·반사·흡혈 반영.
static func resolve_attack(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}) -> Dictionary:
	var cap := int(cfg.get("judge", {}).get("prob_cap", 70))
	var ev := {"type": "normal", "attacker": attacker["name"], "defender": defender["name"],
		"miss": false, "block": false, "crit": false, "damage": 0, "dead": false}
	# 전용 장비 홀리의 빛나는 양뿔 — "크리티컬 공격이 상대의 회피를 무시".
	# ⚠️ 우리 판정 순서는 **회피 → 막기 → 크리**라, 크리가 정해질 땐 이미 회피가 끝나 있다.
	#    그래서 이 플래그가 있을 때**만** 크리를 먼저 굴려 두고(`pre_crit`), 크리면 회피를
	#    건너뛴다. 굴린 결과는 아래에서 그대로 쓰므로 난수 소비 횟수는 그대로다.
	# 93 태양의 불꽃도 같은 통로다 — "크리티컬 발동 시 상대 방어율과 회피율의 절반을 무시".
	var pre_crit := -1
	var halve := _has_flag(attacker, "crit_halves_guard")
	if _has_flag(attacker, "crit_ignores_evade") or halve:
		pre_crit = 1 if _roll_crit(attacker, defender, rng, cap) else 0
	# `evade_sure` = 각성스킬 81 자격을 갖춘 자 "다음 공격 무조건 회피".
	var sure_evade := _has_flag(defender, "evade_sure")
	var evd_pct := _evade_chance(attacker, defender)
	var blk_pct := _eff(defender, "blk")
	if pre_crit == 1 and halve:                    # 크리일 때만 절반으로 본다
		evd_pct = int(evd_pct / 2)
		blk_pct = int(blk_pct / 2)
	# `crit_ignores_evade`(홀리) 는 회피를 통째로 건너뛴다 — 93 과 달리 절반이 아니다.
	var skip_evade := pre_crit == 1 and _has_flag(attacker, "crit_ignores_evade")
	if not skip_evade and (sure_evade or (not _has_flag(defender, "no_evade") 			and _roll(rng, evd_pct, cap))):
		if sure_evade:
			_remove_flag(defender, "evade_sure")
		ev["miss"] = true
		_aw_on_evade(defender, attacker, rng)      # 96 하얀 번개 · 666 샛별
		return ev
	var block := (not _has_flag(defender, "no_block")) and _roll(rng, blk_pct, cap)
	if block:
		_aw_on_block(defender, rng)                # 64 신비한 보호 · 65 신성 방패
	var crit := (pre_crit == 1) if pre_crit >= 0 else _roll_crit(attacker, defender, rng, cap)
	ev["block"] = block
	ev["crit"] = crit
	var dmg := _hit_damage(attacker, defender, crit, block, rng, cfg)
	if crit:
		# 크리 발동 반응 — 2 각성된 드래곤의 영혼 · 44 불의 원조(상대 최대체력 비례 추가 피해).
		dmg += _aw_on_crit_bonus(attacker, defender)
	if not block:
		# '막기 혹은 회피에 실패' — 40 복수의 까마귀. 여기까지 왔으면 둘 다 실패한 것이다.
		_aw_on_hit_unguarded(defender, attacker, rng)
	var res := _deal_attack(attacker, defender, dmg, false, rng, cfg, skills_db)
	# 63 신뢰의 힘 · 25 대양의 분노 · 46 블랙홀의 마력(준 피해만큼 흡혈)
	_aw_on_attack_done(attacker, defender, rng, int(res.get("damage", 0)))
	for k in res:
		ev[k] = res[k]
	# 흡혈(피의 갈증 14)
	var ls := _lifesteal_pct(attacker)
	if ls > 0.0 and not ev["miss"] and attacker["alive"]:
		var heal := maxi(0, int(round(float(_eff(attacker, "att")) * ls / 100.0)))
		if heal > 0:
			attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + heal)
			ev["lifesteal"] = heal
	return ev

static func _skill_level(c: Dictionary, id: int) -> int:
	for s in c.get("skills", []):
		if int(s["id"]) == id:
			return int(s["level"])
	return 1

## 더블공격: 평타 2회. 회피·방어 일괄, 크리 독립. 교차막기(28) 무효 반응 포함.
## TODO: "두 턴 연속 공격 시 발동"은 턴 이력 상태 필요 → 현재는 더블평타 무효만.
static func resolve_double(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}) -> Array:
	var cap := int(cfg.get("judge", {}).get("prob_cap", 70))
	# 교차막기(28): 상대 더블평타를 무효(데미지 0)
	if not skills_db.is_empty() and _uses_left(defender, 28) > 0:
		var sd28: Dictionary = skills_db.get("28", {})
		if not sd28.is_empty() and rng.randf() * 100.0 < _proc_pct(sd28, _skill_level(defender, 28)):
			_use(defender, 28)
			return [_merge(_double_ev(attacker, defender, 0, false, false, false, 0, false), {"def_skill": "교차막기"}),
					_merge(_double_ev(attacker, defender, 1, false, false, false, 0, false), {"def_skill": "교차막기"})]
	if not _has_flag(defender, "no_evade") and _roll(rng, _evade_chance(attacker, defender), cap):
		return [_double_ev(attacker, defender, 0, true, false, false, 0, false),
				_double_ev(attacker, defender, 1, true, false, false, 0, false)]
	var block := (not _has_flag(defender, "no_block")) and _roll(rng, _eff(defender, "blk"), cap)
	var out: Array = []
	var dealt := 0                   # 이번 연속공격으로 실제로 준 피해 합(회복형 반응용)
	for i in 2:
		if not defender["alive"]:
			break
		var crit := _roll_crit(attacker, defender, rng, cap)
		var dmg := _hit_damage(attacker, defender, crit, block, rng, cfg)
		# 전용 장비 일란의 영예의관 "연속공격 피해량 50% 증가" — 평타에는 안 걸리는 별도 통로.
		dmg = maxi(1, int(round(float(dmg) * _double_dmg_mult(attacker))))
		var ap := _apply_dmg(defender, dmg)
		dealt += int(ap["dmg"])
		out.append(_double_ev(attacker, defender, i, false, block, crit, int(ap["dmg"]), bool(ap["dead"])))
	_aw_on_double(attacker, dealt)   # 80 원투박치기 · 세크라포의 어깨보호대(준 피해만큼 회복)
	return out


## 연속공격 전용 피해 배수 — "연속공격 피해량 50% 증가"(일란의 영예의관).
static func _double_dmg_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "double_dmg":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

static func _double_ev(a: Dictionary, d: Dictionary, hit: int, miss: bool, block: bool, crit: bool, dmg: int, dead: bool) -> Dictionary:
	return {"type": "double", "hit": hit, "attacker": a["name"], "defender": d["name"],
		"miss": miss, "block": block, "crit": crit, "damage": dmg, "dead": dead}

## 각성기(§K-5): 적 전체, 회피·방어 무시 확정, ×2.
static func resolve_awaken(attacker: Dictionary, enemies: Array, rng: RandomNumberGenerator, cfg: Dictionary) -> Array:
	var aw: Dictionary = cfg.get("awaken", {})
	var mult := float(aw.get("damage_mult", 2.0))
	var d: Dictionary = cfg.get("damage", {})
	var out: Array = []
	for target in enemies:
		if not target["alive"]:
			continue
		var em := element_mult(String(attacker["element"]), String(target["element"]), cfg)
		var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
		var dmg := damage(_eff(attacker, "att"), _eff(target, "def"), float(attacker["pen"]), em, mult, rf, cfg)
		# 각성기 전용 피해 배수(전용 장비 "각성기 피해량 N% 증가"). 관통을 더하기 **전에** 곱한다 —
		# 관통은 방어 무시 고정 피해라 각성기 배수의 대상이 아니다.
		dmg = int(round(float(dmg) * _awaken_dmg_mult(attacker)))
		dmg += _pure_damage(attacker, target)   # 관통 고정 피해는 각성기에도 더해진다
		# 각성기는 원래 `dmg_taken`(받는 피해 배수)을 타지 않는다 — 28 대지의 시초의
		# "각성기 피해량에는 적용되지 않음" 이 그래서 저절로 지켜진다.
		# 전용 장비 파이썬의 갑옷이 그 예외를 연다("[대지의 시초]효과가 각성기에도 적용").
		if _has_flag(target, "awaken_taken_applies"):
			dmg = maxi(1, int(round(float(dmg) * _dmg_taken_mult(target))))
		# 받는 쪽 상한 — "각성기에 받는 대미지 1000으로 제한"(피오드의 빛을 잃은 마석).
		var acap := _awaken_taken_cap(target)
		if acap > 0:
			dmg = mini(dmg, acap)
		var ap := _apply_dmg(target, dmg)
		out.append({"type": "awaken", "attacker": attacker["name"], "defender": target["name"],
			"miss": false, "block": false, "crit": false, "damage": int(ap["dmg"]), "dead": bool(ap["dead"])})
	return out

# ============================================================ 스킬 엔진
static func _uses_left(c: Dictionary, id: int) -> int:
	return int(c.get("skill_uses", {}).get(id, 0))

static func _use(c: Dictionary, id: int) -> void:
	c["skill_uses"][id] = maxi(0, _uses_left(c, id) - 1)

## 아티팩트 수정치 조회 — c["artifact"][field][skill_id]. 없으면 0.
## 원작 typeDetail BOOST/BNR/INRATE/DERATE/DEDMG 를 우리 전투 통로에 얹은 것(§EquipBelongOption.md §3).
## 아티팩트 히든 옵션(등급·대상 스킬 무관 상시값).
static func _art_hidden(c: Dictionary, field: String) -> int:
	return int((c.get("artifact", {}) as Dictionary).get("hidden", {}).get(field, 0))

static func _art(c: Dictionary, field: String, skill_id: int) -> int:
	return int((c.get("artifact", {}) as Dictionary).get(field, {}).get(skill_id, 0))

## 이 스킬이 실제로 굴릴 발동 확률(%). 루멘/테라가 올리고, **상대**의 옵스큐럼이 깎는다.
static func _proc_chance(caster: Dictionary, sdef: Dictionary, level: int, foes: Array) -> float:
	var id := int(sdef.get("id", 0))
	# 히든 옵션(마리스)은 대상 스킬 제한 없이 전 스킬에 붙는다.
	var pct := _proc_pct(sdef, level) + float(_art(caster, "proc_add", id)) \
		+ float(_art_hidden(caster, "proc_add_all"))
	var sub := 0
	for f in foes:
		if bool((f as Dictionary).get("alive", false)):
			sub = maxi(sub, _art(f, "foe_proc_sub", id))   # 여럿이면 가장 센 것 하나만
	return maxf(0.0, pct - float(sub))

static func _proc_pct(sdef: Dictionary, level: int) -> float:
	if int(sdef.get("id", 0)) == 56:
		return 25.0 + 10.0 * float(level)   # 망각의 망치 (notes)
	return DEFAULT_PROC

static func _skill_limit(sdef: Dictionary, level: int) -> int:
	var lim = sdef.get("number_limit", null)
	if lim != null:
		return int(lim)
	var raw := String(sdef.get("number_limit_raw", "")).strip_edges()
	if raw == "" or raw.to_lower() == "n/a":
		return 9999
	var parts := raw.split("+")
	if parts.size() >= 2 and parts[0].strip_edges().is_valid_int():
		var base := int(parts[0].strip_edges())
		var per := 1
		if "*" in parts[1]:
			var m := parts[1].split("*")[1].strip_edges()
			if m.is_valid_int(): per = int(m)
		return base + per * level
	return 9999

static func _init_combatant_skills(c: Dictionary, skills_db: Dictionary, cfg: Dictionary = {}) -> void:
	if not c.has("effects"): c["effects"] = []
	c["skill_uses"] = {}
	# 사건 반응이 스킬 한도를 다시 계산해야 할 때가 있다(`skill_restore` — 회피/크리 시
	# 스킬 사용 횟수 1회 회복). 반응 지점에는 skills_db 가 안 넘어오므로 여기서 실어 둔다.
	c["_skills_db"] = skills_db
	var sk: Array = c.get("skills", [])
	for i in sk.size():
		var s: Dictionary = sk[i]
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if sdef.is_empty():
			continue
		if sdef.get("active", true):
			var lim := _skill_limit(sdef, _lv(c, s))
			lim += _slot_match_use_bonus(c, i, sdef, cfg)
			lim += _skill_uses_bonus(c)          # 23 다이즈의 가호 · 98 혼돈의 절대자
			c["skill_uses"][int(s["id"])] = lim
		else:
			_apply_passive(c, s, sdef)

## 칸 타입이 일치할 때 **회복 계열** 스킬이 받는 최대 사용횟수 보너스.
##
## 사용자 확정(2026-07-29, docs/input/sheets/open_questions.csv):
##   "assumption대로 유지, 회복 계열 스킬들은 최대 사용횟수 1 증가"
##   → 종전의 `power_pct`(스킬 피해 +15%)는 그대로 두고, 피해가 의미 없는 회복·해제 계열에는
##     **사용횟수 +1** 을 추가효과로 준다.
## 대상 계열·증가량은 `data/combat.json` `skill_slot_match.heal_use_bonus` / `heal_categories`.
## ☆칸은 원작 툴팁대로 모든 스킬의 추가효과를 발생시킨다(`<ToolTipDragonSkillExplain>`).
static func _slot_match_use_bonus(c: Dictionary, idx: int, sdef: Dictionary,
		cfg: Dictionary) -> int:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var bonus := int(m.get("heal_use_bonus", 0))
	if bonus <= 0:
		return 0
	var cats: Array = m.get("heal_categories", [])
	if not (String(sdef.get("category", "")) in cats):
		return 0
	var slots: Array = c.get("skill_slots", [])
	if idx < 0 or idx >= slots.size():
		return 0
	var ty := String(slots[idx])
	if ty == "star" or ty == String(sdef.get("slot", "")):
		return bonus
	return 0

## 패시브(전투 내내, turns=-1). 90/100/110.
static func _apply_passive(c: Dictionary, s: Dictionary, sdef: Dictionary) -> void:
	var lv := _lv(c, s)
	var ded := bool(s.get("dedicated", false))
	match int(sdef["id"]):
		90:
			_add_stat(c, "evd", "flat", (9 if ded else 7) + lv, -1, 90)
		100:
			_add_stat(c, "cri", "flat", (7 if ded else 4) + lv, -1, 100)
			_add_stat(c, "att", "pct", (10 if ded else 5), -1, 100)
		110:
			_add_stat(c, "cri", "flat", (4 if ded else 3) + lv, -1, 110)
			_add_stat(c, "evd", "flat", (5 if ded else 4) + lv, -1, 110)
			_add_stat(c, "att", "pct", (6 if ded else 3), -1, 110)

## 스킬 **체력 조건**(원작). 그 스킬을 지금 쓸 수 있는가 = 현재 체력% <= 문턱.
##
## 근거: 원작 아티팩트 **마리스**의 효과가 "스킬 발동 체력 조건 완화"이고, 위키 §2.4 표가
##   그 대상으로 분노의 일격·치유의 빛·아수라 일섬·신의 분노 4종을 적는다 ⇒ 이 4종이
##   원작의 체력 조건 스킬이다. 목록은 위키 확정, **문턱값은 서버 유실 → 자작**
##   (data/combat.json `skill_hp_gate`).
## 마리스를 끼면 문턱이 relax %p 만큼 올라가 더 일찍(체력이 덜 닳아도) 터진다.
static func _hp_gate_ok(c: Dictionary, skill_id: int, cfg: Dictionary) -> bool:
	var g: Dictionary = cfg.get("skill_hp_gate", {})
	var ids: Array = g.get("skills", [])
	# ⚠️ JSON 숫자는 float 로 들어온다 — `ids.has(25)` 는 25.0 과 안 맞아 **조용히 실패**한다.
	#    (같은 함정을 뽑기 알 제외목록에서 이미 밟았다) → int 로 비교한다.
	var gated := false
	for i in ids:
		if int(i) == skill_id:
			gated = true
			break
	if not gated:
		return true
	var hp_max := maxi(1, int(c.get("hp_max", 1)))
	var hp_pct := float(c.get("hp", 0)) / float(hp_max) * 100.0
	var thr := float(g.get("threshold_pct", 50)) + float(_art(c, "req_hp_relax_pct", skill_id))
	return hp_pct <= minf(100.0, thr)

static func _eligible_attack(c: Dictionary, skills_db: Dictionary, cfg: Dictionary = {}) -> Array:
	var out: Array = []
	for s in c.get("skills", []):
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if sdef.is_empty() or not sdef.get("active", true) or not sdef.get("usable", true):
			continue
		var cat := String(sdef.get("category", ""))
		if cat == "defense" or cat == "interrupt":
			continue
		if _uses_left(c, int(s["id"])) <= 0:
			continue
		# 체력 조건 스킬은 체력이 문턱 아래로 내려가야 후보가 된다(마리스가 문턱을 올려 준다).
		if not _hp_gate_ok(c, int(s["id"]), cfg):
			continue
		out.append(s)
	return out

## 한 드래곤의 턴 행동 → 이벤트 배열. 혼란→자해, 아니면 스킬(확률·둘중랜덤) 또는 평타. 망각 반응 포함.
static func _act(actor: Dictionary, party_a: Array, party_b: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Array:
	if _has_flag(actor, "confused"):   # 환각(22): 자기 자신을 150% 공격
		var d: Dictionary = cfg.get("damage", {})
		var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
		var sdmg := damage(_eff(actor, "att"), _eff(actor, "def"), float(actor["pen"]), 1.0, 1.5, rf, cfg)
		var ap := _apply_dmg(actor, sdmg)
		return [{"type": "confused", "actor": actor["name"], "damage": int(ap["dmg"]), "dead": bool(ap["dead"])}]
	var enemies: Array = party_b if actor["side"] == "ally" else party_a
	var allies: Array = party_a if actor["side"] == "ally" else party_b
	if _alive_count(enemies) == 0:
		return []
	# 각성기 게이지(§K-5): 행동마다 충전, 만충 시 각성기(적 전체·회피/방어 무시·×2) 발동 후 리셋.
	# ⚠️ 원작 발동조건(충전율)=미확정 → 행동당 고정 충전(ASSUMPTION). resolve_awaken 배선.
	# 충전량은 `data/combat.json awaken.charge_per_turn`(만충=100). 사용자 지시(2026-07-27)로
	# 종전 18 → **3.6 = 5배 느리게**. 소수 충전이 잘리지 않게 게이지는 float 로 누적한다.
	var aw_cfg: Dictionary = cfg.get("awaken", {})
	# 각성스킬이 충전율(22 냉철한 암흑 · 27 대지의 기둥)과 최소값(77 영원의 불길)을 바꾼다.
	var gauge := float(actor.get("awaken_gauge", 0.0)) 		+ float(aw_cfg.get("charge_per_turn", 3.6)) * _gauge_rate(actor)
	if gauge >= 100.0:
		actor["awaken_gauge"] = _gauge_min(actor)
		return resolve_awaken(actor, enemies, rng, cfg)
	actor["awaken_gauge"] = gauge
	# 51 빛의 환희 "아군에 [신성] 속성 드래곤이 있으면, 자신은 공격을 하지 않는다".
	if _has_flag(actor, "no_attack"):
		return []
	var elig := _eligible_attack(actor, skills_db, cfg)
	if not elig.is_empty():
		var s: Dictionary = elig[rng.randi_range(0, elig.size() - 1)]   # 다중 보유 시 둘 중 랜덤
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if rng.randf() * 100.0 < _proc_chance(actor, sdef, int(s["level"]), enemies):
			var inter := _oblivion_react(actor, int(s["id"]), enemies, rng, skills_db, cfg)
			_use(actor, int(s["id"]))   # 시전 시도 → 무효화돼도 소모
			if not inter.is_empty():
				return [inter]
			# 각성스킬 반응 — 81 자격을 갖춘 자 · 85 절망의 번개는 '공격 스킬 발동 시' 터진다.
			if String(sdef.get("category", "")) != "defense":
				_aw_on_skill_cast(actor, enemies, rng)
			# 83 잠재력 — 발동이 정해진 **뒤에** 굴린다(확률에는 영향 없음).
			actor["_proc_level_bonus"] = _roll_proc_level(actor, rng)
			var out5 := _apply_skill_effect(actor, s, allies, enemies, rng, cfg, skills_db)
			actor["_proc_level_bonus"] = 0
			return out5
	var t := pick_target(enemies, cfg)
	if t.is_empty():
		return []
	# 79 우아한 날개짓 "자신의 모든 공격이 연속공격이 된다".
	if _has_flag(actor, "always_double"):
		return resolve_double(actor, t, rng, cfg, skills_db)
	return [resolve_attack(actor, t, rng, cfg, skills_db)]

## 83 잠재력 — "전투 중에 스킬 사용시 25% 확률로 스킬 레벨+5 된 효과로 발동".
## 반환 = 이번 발동에만 얹을 레벨 보너스(0 = 안 터짐).
static func _roll_proc_level(c: Dictionary, rng: RandomNumberGenerator) -> int:
	for e in c.get("effects", []):
		if e.get("kind") == "skill_level_proc" and rng.randf() * 100.0 < float(e["pct"]):
			return int(e["value"])
	return 0

## 망각의 망치(56) 반응. 적 보유자 롤 성공 시 무효화 이벤트(아니면 {}).
## `oblivion_immune` = 해골요새 장비 "G스컬의 은빛망토" — 공방형이 장착하면 [신의 분노](36)가
## [망각의 망치](56) 효과를 받지 않는다. 원문이 36 만 지목하므로 **그 스킬에만** 면제한다.
const OBLIVION_IMMUNE_SKILL := 36
static func _oblivion_react(caster: Dictionary, fired_id: int, enemies: Array, rng: RandomNumberGenerator, skills_db: Dictionary, _cfg: Dictionary) -> Dictionary:
	if fired_id == OBLIVION_IMMUNE_SKILL and _has_flag(caster, "oblivion_immune"):
		return {}
	for e in enemies:
		if not e["alive"]:
			continue
		for s in e.get("skills", []):
			var sdef: Dictionary = skills_db.get(str(s["id"]), {})
			if String(sdef.get("category", "")) != "interrupt":
				continue
			if _uses_left(e, int(s["id"])) <= 0:
				continue
			if rng.randf() * 100.0 < _proc_pct(sdef, int(s["level"])):
				_use(e, int(s["id"]))
				return {"type": "skill", "skill_id": 56, "skill_name": String(skills_db.get("56", {}).get("name", "")),
					"caster": e["name"], "interrupt": true, "target": caster["name"],
					"nullified_id": fired_id, "nullified_name": String(skills_db.get(str(fired_id), {}).get("name", ""))}
	return {}

## 망각 적용(테스트/직접용): 보유자 횟수 차감 + 무효화 이벤트.
static func _oblivion_apply(caster: Dictionary, fired_id: int, owner: Dictionary, hammer: Dictionary, skills_db: Dictionary) -> Dictionary:
	_use(owner, int(hammer["id"]))
	return {"type": "skill", "skill_id": 56, "skill_name": String(skills_db.get("56", {}).get("name", "")),
		"caster": owner["name"], "interrupt": true, "target": caster["name"],
		"nullified_id": fired_id, "nullified_name": String(skills_db.get(str(fired_id), {}).get("name", ""))}

## 스킬 칸 타입 일치 보너스 배수.
## 원작 근거 `<ToolTipDragonSkillExplain>`: "같은 스킬이라도 스킬과 슬롯의 타입이 일치하는 경우
##   추가 효과가 발생합니다. … 별 타입의 특수 슬롯이 존재하는데 모든 스킬의 추가 효과를 발생 시킵니다."
## ⚠️ "추가 효과"의 **정체와 수치는 서버 유실**. ASSUMPTION: 스킬 피해 +N%(combat.json
##   `skill_slot_match.power_pct`, 기본 15)로 대체한다. 회복·버프량에는 아직 걸지 않는다.
##   장착 제약은 없다(사용자 확인 2026-07-27) — 안 맞는 모양에도 장착되고 보너스만 없다.
static func slot_match_mult(caster: Dictionary, skill_id: int, cfg: Dictionary, skills_db: Dictionary) -> float:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var pct := float(m.get("power_pct", 0.0))
	if pct <= 0.0:
		return 1.0
	var slots: Array = caster.get("skill_slots", [])
	if slots.is_empty():
		return 1.0
	# 그 스킬이 꽂힌 칸을 찾는다(skills 배열 순서 = 칸 순서).
	var idx := -1
	var sk: Array = caster.get("skills", [])
	for i in sk.size():
		if int((sk[i] as Dictionary).get("id", 0)) == skill_id:
			idx = i
			break
	if idx < 0 or idx >= slots.size():
		return 1.0
	var ty := String(slots[idx])
	if ty == "star":
		return 1.0 + pct / 100.0        # ☆칸은 모든 스킬에 추가효과
	return 1.0 + pct / 100.0 if String(skills_db.get(str(skill_id), {}).get("slot", "")) == ty else 1.0

## 스킬 공격: 평타식 × 계수(§K-2). 크리 없음(평타 전용).
## `caster["_slot_mult"]` = 슬롯 타입 일치 보너스(_apply_skill_effect 가 발동 스킬 기준으로 설정).
static func _skill_strike(caster: Dictionary, target: Dictionary, coeff: float, rng: RandomNumberGenerator, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	var em := element_mult(String(caster["element"]), String(target["element"]), cfg)
	var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
	var mult := coeff * float(caster.get("_slot_mult", 1.0))
	return damage(_eff(caster, "att"), _eff(target, "def"), float(caster["pen"]), em, mult, rf, cfg)

## 스킬 효과 적용(발동 확정 후). effect_text(사용자 복원)대로. 수치 누락분은 스텁.
static func _apply_skill_effect(caster: Dictionary, s: Dictionary, allies: Array, enemies: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Array:
	var id := int(s["id"])
	var lv := _lv(caster, s)      # 89 지혜의 별빛 · 83 잠재력이 여기서만 레벨을 올린다
	var sdef: Dictionary = skills_db.get(str(id), {})
	# 슬롯 타입 일치 보너스를 이 발동 건에만 적용(_skill_strike 가 읽는다).
	caster["_slot_mult"] = slot_match_mult(caster, id, cfg, skills_db)
	# 지금 시전 중인 스킬 id — 방어측 아티팩트(벤투스 DEDMG)가 어떤 스킬인지 알아야 한다.
	caster["_cast_skill_id"] = id
	var ev := {"type": "skill", "skill_id": id, "skill_name": String(sdef.get("name", "")), "caster": caster["name"]}
	if float(caster["_slot_mult"]) > 1.0:
		ev["slot_match"] = true       # render 가 "타입 일치" 배지를 띄울 수 있게

	match id:
		# ---- 공격 ----
		21:  # 심판의 날개: 평타식 × 6
			var t := pick_target(enemies, cfg)
			if t.is_empty(): return []
			var r21 := _deal_attack(caster, t, _skill_strike(caster, t, 6.0, rng, cfg), true, rng, cfg, skills_db)
			r21["target"] = t["name"]
			return [_merge(ev, r21)]
		30:  # 아수라일섬: 상대 순수(base) 방어력 × 1.5 고정 피해
			var t30 := pick_target(enemies, cfg)
			if t30.is_empty(): return []
			var r30 := _deal_attack(caster, t30, maxi(1, int(round(float(t30["def"]) * 1.5))), true, rng, cfg, skills_db)
			r30["target"] = t30["name"]
			return [_merge(ev, r30)]
		36:  # 신의 분노: 공×방×|공-방|×(0.45+0.02L)  (사용자 공식)
			var t2 := pick_target(enemies, cfg)
			if t2.is_empty(): return []
			var a := _eff(caster, "att")
			var d := _eff(caster, "def")
			var raw := maxi(1, int(round(float(a) * float(d) * float(absi(a - d)) * (0.45 + 0.02 * lv))))
			var r36 := _deal_attack(caster, t2, raw, true, rng, cfg, skills_db)
			r36["target"] = t2["name"]
			return [_merge(ev, r36)]
		53:  # 거신의 돌격: caster 체력 × (15+2L)% × 0.70 (시한폭탄 계수의 70%)
			var t53 := pick_target(enemies, cfg)
			if t53.is_empty(): return []
			var r53 := _deal_attack(caster, t53, maxi(1, int(round(float(caster["hp"]) * float(15 + 2 * lv) / 100.0 * 0.70))), true, rng, cfg, skills_db)
			r53["target"] = t53["name"]
			return [_merge(ev, r53)]
		54:  # 시한폭탄: 7턴 후 caster 체력의 (15+2L)% (전용 20+2L%) 만큼 피해
			var t5 := pick_target(enemies, cfg)
			if t5.is_empty(): return []
			var pct := (20 if bool(s.get("dedicated", false)) else 15) + 2 * lv
			var bomb := maxi(1, int(round(float(caster["hp"]) * float(pct) / 100.0)))
			t5["effects"].append({"kind": "timed", "turns": 7, "dmg": bomb, "source": id})
			return [_merge(ev, {"target": t5["name"], "timed_turns": 7, "timed_dmg": bomb})]
		55:  # 이판사판: 자신과 상대 현재 체력 50%(전용 60%) 감소
			var t6 := pick_target(enemies, cfg)
			if t6.is_empty(): return []
			var rate := (0.60 if bool(s.get("dedicated", false)) else 0.50)
			var loss_c := int(float(caster["hp"]) * rate)
			var loss_t := int(float(t6["hp"]) * rate)
			caster["hp"] = maxi(1, int(caster["hp"]) - loss_c)
			t6["hp"] = maxi(1, int(t6["hp"]) - loss_t)
			return [_merge(ev, {"target": t6["name"], "self_loss": loss_c, "target_loss": loss_t})]
		# ---- 자버프 ----
		14:  # 피의 갈증: 흡혈 att×(7+1L)% (공격 시), 2턴
			caster["effects"].append({"kind": "lifesteal", "pct": 7 + lv, "turns": 2, "source": id})
			return [_merge(ev, {"buff": "lifesteal%", "value": 7 + lv, "turns": 2})]
		25:  # 분노의 일격: 잃은 체력 비례 공 증가, 3턴. ASSUMPTION: 잃은체력% = 공 +%
			var miss_pct := int(round((1.0 - float(caster["hp"]) / maxf(1.0, float(caster["hp_max"]))) * 100.0))
			_add_stat(caster, "att", "pct", miss_pct, 3, id)
			return [_merge(ev, {"buff": "att%", "value": miss_pct, "turns": 3})]
		31:  # 최후의 수단: 2턴간 적 공·방 복사. ASSUMPTION: 타겟 적의 실효 공/방으로 일치
			var src := pick_target(enemies, cfg)
			if src.is_empty(): return []
			_add_stat(caster, "att", "flat", _eff(src, "att") - int(caster["att"]), 2, id)
			_add_stat(caster, "def", "flat", _eff(src, "def") - int(caster["def"]), 2, id)
			return [_merge(ev, {"buff": "copy_att_def", "from": src["name"], "turns": 2})]
		50:  # 필살 방어: 방 +20+5L (2턴) + 1회 생존(중첩 불가)
			_add_stat(caster, "def", "flat", 20 + 5 * lv, 2, id)
			if not _has_flag(caster, "survive_once"):
				_add_flag(caster, "survive_once", -1, id)
			return [_merge(ev, {"buff": "def", "value": 20 + 5 * lv, "turns": 2, "survive_once": true})]
		57:  # 야누스의 계략: 공↔방 변환, 2턴
			var a3 := _eff(caster, "att")
			var d3 := _eff(caster, "def")
			_add_stat(caster, "att", "flat", d3 - int(caster["att"]), 2, id)
			_add_stat(caster, "def", "flat", a3 - int(caster["def"]), 2, id)
			return [_merge(ev, {"buff": "swap_att_def", "turns": 2})]
		60:  # 야수의 본능: 공 +%(15+5L), 2턴
			_add_stat(caster, "att", "pct", 15 + 5 * lv, 2, id)
			return [_merge(ev, {"buff": "att%", "value": 15 + 5 * lv, "turns": 2})]
		70:  # 자연의 수호: 방 +flat(50+5L), 2턴
			_add_stat(caster, "def", "flat", 50 + 5 * lv, 2, id)
			return [_merge(ev, {"buff": "def", "value": 50 + 5 * lv, "turns": 2})]
		80:  # 돌격지시: 공·방 +%(7+3L), 2턴
			_add_stat(caster, "att", "pct", 7 + 3 * lv, 2, id)
			_add_stat(caster, "def", "pct", 7 + 3 * lv, 2, id)
			return [_merge(ev, {"buff": "att/def%", "value": 7 + 3 * lv, "turns": 2})]
		# ---- 회복/정화 ----
		29:  # 치유의 빛: 아군 전체 60+최대체력*(0.06+0.01L)
			var evs: Array = []
			for a2 in allies:
				if not a2["alive"]: continue
				var heal := int(round(60.0 + float(a2["hp_max"]) * (0.06 + 0.01 * lv)))
				a2["hp"] = mini(int(a2["hp_max"]), int(a2["hp"]) + heal)
				evs.append(_merge(ev, {"target": a2["name"], "heal": heal}))
			return evs
		26:  # 빛의 정화: 아군 전체 해로운 효과 제거 + caster 스킬(자신 제외) 사용횟수 +1
			var evs2: Array = []
			for a4 in allies:
				if not a4["alive"]: continue
				_cleanse(a4)
				evs2.append(_merge(ev, {"target": a4["name"], "cleanse": true}))
			for sk in caster.get("skills", []):
				if int(sk["id"]) == 26: continue
				if caster["skill_uses"].has(int(sk["id"])):
					caster["skill_uses"][int(sk["id"])] = _uses_left(caster, int(sk["id"])) + 1
			return evs2
		# ---- 디버프 ----
		15:  # 암흑의 사슬: 상대 턴 무시(stun), 2턴(ASSUMPTION)
			var t7 := pick_target(enemies, cfg)
			if t7.is_empty(): return []
			_add_flag(t7, "stun", 2, id)
			return [_merge(ev, {"target": t7["name"], "debuff": "stun", "turns": 2})]
		22:  # 환각 효과: 상대 자기 자신을 150% 공격(confused), 2턴
			var t8 := pick_target(enemies, cfg)
			if t8.is_empty(): return []
			_add_flag(t8, "confused", 2, id)
			return [_merge(ev, {"target": t8["name"], "debuff": "confused", "turns": 2})]
		23:  # 상처 파악: 영구 취약 +(7+3L)% 받는 피해
			var t9 := pick_target(enemies, cfg)
			if t9.is_empty(): return []
			t9["effects"].append({"kind": "dmg_taken", "pct": 7 + 3 * lv, "turns": -1, "source": id})
			return [_merge(ev, {"target": t9["name"], "debuff": "vulnerable%", "value": 7 + 3 * lv, "turns": -1})]
		32:  # 신경독소: 2턴 DoT, 최대체력의 (3+1L)%
			var t10 := pick_target(enemies, cfg)
			if t10.is_empty(): return []
			t10["effects"].append({"kind": "dot", "pct": 3 + lv, "turns": 2, "source": id})
			return [_merge(ev, {"target": t10["name"], "debuff": "dot%", "value": 3 + lv, "turns": 2})]
		46:  # 뼈 부수기: 단일 방어·회피 불가, 2턴
			var t11 := pick_target(enemies, cfg)
			if t11.is_empty(): return []
			_add_flag(t11, "no_evade", 2, id)
			_add_flag(t11, "no_block", 2, id)
			return [_merge(ev, {"target": t11["name"], "debuff": "no_evade/no_block", "turns": 2})]
		120: # 무언의 압박: 적 전체 공 -%. ASSUMPTION 수치(7+3L%, 살기표출 계열) — 효과식 수치 미명시
			return _debuff_all(ev, enemies, [["att", -(7 + 3 * lv)]], 2, id)
		130: # 약점 파악: 적 전체 방 -%. ASSUMPTION 수치(7+3L%)
			return _debuff_all(ev, enemies, [["def", -(7 + 3 * lv)]], 2, id)
		140: # 살기표출: 적 전체 공·방 -%(7+3L), 2턴(ASSUMPTION 지속)
			return _debuff_all(ev, enemies, [["att", -(7 + 3 * lv)], ["def", -(7 + 3 * lv)]], 2, id)
		150: # 빙결의 표식: 적 전체 3턴 회피 불가 + 다음 턴 아군 주도권 100%(initiative)
			var evs3: Array = []
			for en in enemies:
				if not en["alive"]: continue
				_add_flag(en, "no_evade", 3, id)
				evs3.append(_merge(ev, {"target": en["name"], "debuff": "no_evade", "turns": 3}))
			caster["effects"].append({"kind": "initiative", "side": caster["side"], "turns": 2})
			return evs3
		160: # 마비의 구름: 적 전체 3턴 크리 불가 + 스킬 사용횟수 1 차감
			var evs4: Array = []
			for en2 in enemies:
				if not en2["alive"]: continue
				_add_flag(en2, "no_crit", 3, id)
				_drain_one_skill(en2)
				evs4.append(_merge(ev, {"target": en2["name"], "debuff": "no_crit+drain", "turns": 3}))
			return evs4
		170: # 시간의 역행: 적 전체 2턴 회피·크리 불가
			var evs5: Array = []
			for en3 in enemies:
				if not en3["alive"]: continue
				_add_flag(en3, "no_evade", 2, id)
				_add_flag(en3, "no_crit", 2, id)
				evs5.append(_merge(ev, {"target": en3["name"], "debuff": "no_evade/no_crit", "turns": 2}))
			return evs5
		24:  # 어둠의 손길: 상대 장착 스킬 중 무작위 1개를 caster가 주체로 발동
			var pool: Array = []
			for en4 in enemies:
				if not en4["alive"]: continue
				for sk in en4.get("skills", []):
					pool.append(sk)
			if pool.is_empty():
				return [_merge(ev, {"copied_id": null})]
			var picked: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			if int(picked["id"]) == 24:   # 자기참조 방지
				return [_merge(ev, {"copied_id": 24, "todo": true})]
			var head := _merge(ev, {"copied_id": int(picked["id"]), "copied_name": String(skills_db.get(str(picked["id"]), {}).get("name", ""))})
			return [head] + _apply_skill_effect(caster, picked, allies, enemies, rng, cfg, skills_db)
		_:
			# 미구현/미정 스킬 폴백(발동·횟수·이벤트만).
			return [_merge(ev, {"todo": true})]

static func _debuff_all(ev: Dictionary, enemies: Array, mods: Array, turns: int, src: int) -> Array:
	var out: Array = []
	for en in enemies:
		if not en["alive"]: continue
		for m in mods:
			_add_stat(en, String(m[0]), "pct", float(m[1]), turns, src)
		out.append(_merge(ev, {"target": en["name"], "turns": turns}))
	return out

## 대상의 액티브 스킬 중 하나의 남은 횟수 1 차감(마비의 구름 160).
static func _drain_one_skill(c: Dictionary) -> void:
	for sk in c.get("skills", []):
		if _uses_left(c, int(sk["id"])) > 0:
			_use(c, int(sk["id"]))
			return

## 피격 방어 스킬(확률 발동, 정상 방어와 동시). is_skill=스킬공격 피격 여부. {dmg, fired, reflect}.
static func _defense_skill_onhit(defender: Dictionary, rng: RandomNumberGenerator, dmg: int, is_skill: bool, _cfg: Dictionary, skills_db: Dictionary) -> Dictionary:
	var elig: Array = []
	for s in defender.get("skills", []):
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if sdef.is_empty() or not sdef.get("active", true):
			continue
		if String(sdef.get("category", "")) != "defense":
			continue
		if int(s["id"]) == 20 and is_skill:   # 보호의 장막은 스킬 피해엔 미적용
			continue
		if _uses_left(defender, int(s["id"])) <= 0:
			continue
		elig.append(s)
	if elig.is_empty():
		return {"dmg": dmg, "fired": "", "reflect": 0}
	var s2: Dictionary = elig[rng.randi_range(0, elig.size() - 1)]
	var sdef2: Dictionary = skills_db.get(str(s2["id"]), {})
	if rng.randf() * 100.0 < _proc_pct(sdef2, int(s2["level"])):
		_use(defender, int(s2["id"]))
		return _defense_reduce(defender, s2, dmg, skills_db)
	return {"dmg": dmg, "fired": "", "reflect": 0}

## 방어 스킬 피해 변환(발동 확정 후). {dmg, fired, reflect}.
static func _defense_reduce(defender: Dictionary, s: Dictionary, dmg: int, skills_db: Dictionary) -> Dictionary:
	var id := int(s["id"])
	var lv := int(s["level"])
	var name := String(skills_db.get(str(id), {}).get("name", ""))
	match id:
		11:  # 철갑방패: 피해감소(고정) 10+5L
			return {"dmg": maxi(1, dmg - (10 + 5 * lv)), "fired": name, "reflect": 0}
		12:  # 신의 결계: 모든 공격 무효화
			return {"dmg": 0, "fired": name, "reflect": 0}
		13:  # 복수의 거울: 방어력의 (7+2L)% 만큼 반사(피해량 한도)
			var refl := mini(dmg, int(round(float(_eff(defender, "def")) * float(7 + 2 * lv) / 100.0)))
			return {"dmg": dmg, "fired": name, "reflect": maxi(0, refl)}
		20:  # 보호의 장막: 평타 피해 50% 감소(스킬 피해엔 미적용 — onhit에서 제외)
			return {"dmg": maxi(1, int(round(float(dmg) * 0.5))), "fired": name, "reflect": 0}
		_:
			# TODO 스텁: 28 교차막기는 resolve_double에서 처리(여기 아님)
			return {"dmg": dmg, "fired": name, "reflect": 0}

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	for k in b:
		r[k] = b[k]
	return r

# ============================================================ 시뮬레이션
static func _alive_count(party: Array) -> int:
	var n := 0
	for c in party:
		if c["alive"]:
			n += 1
	return n

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]; arr[i] = arr[j]; arr[j] = t

## 주도권 마커(initiative) 소비 → 우선 행동할 side("ally"/"enemy") 또는 "". 마커 제거.
static func _consume_initiative(party_a: Array, party_b: Array) -> String:
	var side := ""
	var perm := {}          # 상시 주도권을 가진 진영들 — 양쪽 다면 서로 무효화된다
	for party in [party_a, party_b]:
		for c in party:
			var keep: Array = []
			for e in c.get("effects", []):
				if e.get("kind") == "initiative":
					side = String(e.get("side", ""))
					# 각성스킬 60 선제 공격은 **상시**다(turns=-1) → 소모하지 않고 남긴다.
					# 스킬 150 빙결의 표식이 거는 것(turns>0)은 1회용이라 여기서 사라진다.
					if int(e.get("turns", 0)) < 0:
						perm[side] = true
						keep.append(e)
					continue
				keep.append(e)
			c["effects"] = keep
	# 60 선제 공격 "상대방이 동일한 스킬을 보유 시 무효화된다".
	if perm.size() >= 2:
		return ""
	return side

static func _other(side: String) -> String:
	return "enemy" if side == "ally" else "ally"

## 이번 턴 공격 주도 진영(§K-6 기본 메커니즘): forced(150) 우선 → 같은 진영 4연속이면 강제 교체 → 그 외 50% 난수.
static func _decide_lead(rng: RandomNumberGenerator, last_lead: String, streak: int, forced: String) -> String:
	if forced != "":
		return forced
	if last_lead != "" and streak >= 4:
		return _other(last_lead)
	return "ally" if rng.randf() < 0.5 else "enemy"

## 라운드 끝 처리: DoT·지연폭탄(timed) 발동 + 지속턴 1 감소(영구 -1 제외).
## ASSUMPTION: 원작은 공격 시 지속차감이나 v1은 라운드 단위.
static func _round_end(party_a: Array, party_b: Array, events: Array, round: int) -> void:
	for side in [party_a, party_b]:
		for c in side:
			var keep: Array = []
			for e in c.get("effects", []):
				var k := String(e.get("kind", ""))
				if k == "dot":
					if c["alive"]:
						var dmg := maxi(1, int(round(float(c["hp_max"]) * float(e["pct"]) / 100.0)))
						c["hp"] = maxi(0, int(c["hp"]) - dmg)
						var dead := int(c["hp"]) <= 0
						if dead: c["alive"] = false
						events.append({"type": "dot", "target": c["name"], "damage": dmg, "dead": dead, "round": round, "source": e.get("source", 0), "turns": maxi(0, int(e.get("turns", 1)) - 1)})
					var t := int(e["turns"]) - 1
					if t > 0 and c["alive"]:
						e["turns"] = t; keep.append(e)
				elif k == "timed":
					var t2 := int(e["turns"]) - 1
					if t2 <= 0:
						if c["alive"]:
							var dmg2 := int(e["dmg"])
							c["hp"] = maxi(0, int(c["hp"]) - dmg2)
							var dead2 := int(c["hp"]) <= 0
							if dead2: c["alive"] = false
							events.append({"type": "timed", "target": c["name"], "damage": dmg2, "dead": dead2, "round": round, "source": e.get("source", 0), "turns": 0})
					else:
						e["turns"] = t2; keep.append(e)
				else:
					var tt := int(e.get("turns", -1))
					if tt < 0:
						keep.append(e)
					else:
						tt -= 1
						if tt > 0:
							e["turns"] = tt; keep.append(e)
			c["effects"] = keep

## 전투 시뮬레이션. party_a/b = make_combatant 배열(가변). skills_db=data/skills.json.
static func simulate(party_a: Array, party_b: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}, max_rounds := 200) -> Dictionary:
	for c in party_a: _init_combatant_skills(c, skills_db, cfg)
	for c in party_b: _init_combatant_skills(c, skills_db, cfg)
	_aw_refresh_dynamic(party_a, party_b)   # 1라운드 시작 전 초기 상태로 한 번
	var events: Array = []
	var rounds := 0
	var last_lead := ""   # 직전 주도 진영
	var streak := 0       # 같은 진영 연속 주도 횟수
	while _alive_count(party_a) > 0 and _alive_count(party_b) > 0 and rounds < max_rounds:
		rounds += 1
		# 매 턴: 한 진영이 공격 주도(반대는 수동 수비). 50% 난수 + 4연속 시 강제 교체. 150은 forced로 개입.
		var forced := _consume_initiative(party_a, party_b)
		var lead := _decide_lead(rng, last_lead, streak, forced)
		streak = streak + 1 if lead == last_lead else 1
		last_lead = lead
		var actors: Array = []
		for c in (party_a if lead == "ally" else party_b):
			if c["alive"]: actors.append(c)
		_shuffle(actors, rng)
		for actor in actors:   # 주도 진영만 행동, 상대는 피격(방어스킬은 _deal_attack에서)
			if not actor["alive"]:
				continue
			if _has_flag(actor, "stun"):   # 행동불가(암흑의 사슬 등) → 턴 소모
				# 🔴 2026-07-29 정정: 여기서 장비 `cure`(부적)로 stun 을 풀고 있었다.
				#   사용자 확정(open_questions.csv)에 따르면 부적의 '행동불능 치유 확률'은
				#   **던전 패배 시 지속 행동불능(Dragon::cureTime)에 걸리지 않을 확률**이지
				#   전투 중 스킬 기절(`AdventureSkillStop`)과는 무관하다.
				#   → 그쪽은 `Incapacitation` + `battle.gd::_apply_defeat_incapacitation` 담당.
				events.append({"type": "status_skip", "actor": actor["name"], "round": rounds, "lead": lead,
					"source": _flag_source(actor, "stun"), "turns": _flag_turns(actor, "stun")})   # 원작 Bicon 아이콘용 출처 스킬
				continue
			var evs := _act(actor, party_a, party_b, rng, cfg, skills_db)
			for ev in evs:
				ev["round"] = rounds
				ev["lead"] = lead
				events.append(ev)
			if _alive_count(party_a) == 0 or _alive_count(party_b) == 0:
				break
		_round_end(party_a, party_b, events, rounds)
		# 각성스킬 **동적** 효과(체력 비율·생존 수 등 매 순간 달라지는 조건)를 다시 계산한다.
		# 라운드 경계에서만 갱신한다 — 근거는 `AwakenSkill.refresh_dynamic` 주석.
		_aw_refresh_dynamic(party_a, party_b)
	var a_alive := _alive_count(party_a)
	var b_alive := _alive_count(party_b)
	var winner := "draw"
	if a_alive > 0 and b_alive == 0:
		winner = "ally"
	elif b_alive > 0 and a_alive == 0:
		winner = "enemy"
	return {"winner": winner, "events": events, "rounds": rounds}


# ─────────────────────────────────────────────────────────────────────────────
# 전투 통계(원작 FightStats) — 전투원별 스코어보드. 순수 로직(§10): 이벤트 로그 환원.
# 근거: docs/ref/orig_code/decomp/FightStats.c — 필드 {tag, dmg(가한피해), taken(받은피해), heal, kill,
#   block, evade} (getDmg/getTaken/getKill/getBlock/getEvade + init(tag)). 원작은 전투 중
#   FightManager가 누적(BattleScene.c:2143 initFightStats); 우리는 simulate 이벤트에서 등가 환원.
# ⚠️ ASSUMPTION(heal): getHeal이 '가한/받은 회복' 중 무엇인지는 FightManager(미디컴파일) 소관
#   → 회복 발생 대상(lifesteal=시전자, 스킬힐=대상)에 귀속. dmg/taken/kill/block/evade는 필드명대로.
static func fight_stats(events: Array) -> Dictionary:
	var stats: Dictionary = {}
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var dealer := String(ev.get("attacker", ev.get("actor", "")))
		var victim := String(ev.get("defender", ev.get("target", "")))
		var dmg := int(ev.get("damage", 0))
		if dmg > 0:
			if dealer != "":
				_fs_at(stats, dealer)["dmg"] += dmg
			if victim != "" and victim != dealer:
				_fs_at(stats, victim)["taken"] += dmg
			if bool(ev.get("dead", false)) and dealer != "" and victim != "":
				_fs_at(stats, dealer)["kill"] += 1
		if bool(ev.get("block", false)) and victim != "":
			_fs_at(stats, victim)["block"] += 1
		if bool(ev.get("miss", false)) and victim != "":
			_fs_at(stats, victim)["evade"] += 1
		if ev.has("lifesteal") and dealer != "":
			_fs_at(stats, dealer)["heal"] += int(ev.get("lifesteal", 0))
		if ev.has("heal"):
			var healed := String(ev.get("target", ev.get("attacker", "")))
			if healed != "":
				_fs_at(stats, healed)["heal"] += int(ev.get("heal", 0))
	return stats

static func _fs_at(stats: Dictionary, name: String) -> Dictionary:
	if not stats.has(name):
		stats[name] = {"tag": name, "dmg": 0, "taken": 0, "heal": 0, "kill": 0, "block": 0, "evade": 0}
	return stats[name]


# ═════════════════════════════════════════════════════════════════════════════
# 각성스킬 런타임 — 동적(조건부) · 반응(사건) 효과 + 효과 원시연산
#
# ⚠️ 왜 여기 있나: 이 코드는 처음에 `AwakenSkill` 에 있었는데, 그러면 Battle↔AwakenSkill 이
#    **서로를 참조**하게 되어 `preload()` 로 두 스크립트를 함께 불러오는 테스트가 통째로
#    깨졌다(순환 참조). 지금은 **한 방향**이다:
#        AwakenSkill(번역: data → 효과 항목)  →  Battle(실행: 효과를 실제로 굴린다)
#    Battle 은 전투원에 심긴 `dyn`/`react` 항목을 스스로 읽어 돌린다 — AwakenSkill 을 모른다.
#
# 효과 항목의 뜻과 각 스킬의 대응은 `scripts/tools/build_awaken_effects.py` 에 있다.
# ═════════════════════════════════════════════════════════════════════════════
# ── 동적 효과(D 조건부) ──────────────────────────────────────────────────────
## 매 순간 달라지는 조건(체력 비율 · 생존 아군 수 · 디버프 보유 · 사망 여부)에 걸린 효과를
## **라운드 경계마다 다시 계산**한다. `Battle.simulate` 이 라운드 끝에서 부른다.
##
## ⚠️ 왜 라운드 단위인가 — 원작이 이걸 매 타격마다 재평가하는지 라운드마다 하는지는
##   서버·클라 어디에도 남아 있지 않다. 우리는 **라운드 경계**로 고정한다:
##     · 한 라운드 안에서 스탯이 요동치지 않아 전투 로그가 읽힌다
##     · "체력 50% 이하일 때" 류가 같은 라운드 안에서 켜졌다 꺼졌다 하지 않는다
##   더 잘게 갱신할 근거가 생기면 이 함수를 부르는 곳만 늘리면 된다.
##
## 구현: 소유자에게 심어 둔 `{kind:"dyn"}` 항목을 읽어, 조건을 만족하면 그 결과를
## `src` 가 `dyn:` 으로 시작하는 일반 효과로 다시 깐다. 갱신 = **전부 지우고 다시 깔기**.
const DYN_SRC := "dyn:"

static func _aw_refresh_dynamic(party_a: Array, party_b: Array) -> void:
	# ① 먼저 양쪽 전부에서 지난 라운드의 동적 효과를 걷어낸다.
	#    (한 드래곤의 dyn 이 아군 전체를 대상으로 할 수 있으므로 적용 전에 모두 비워야 한다.)
	var any := false
	for side in [party_a, party_b]:
		for c in side:
			if _clear_dyn(c as Dictionary):
				any = true
			elif _has_dyn(c as Dictionary):
				any = true
	if not any:
		return
	# ② 다시 깐다.
	for i in 2:
		var allies: Array = party_a if i == 0 else party_b
		var enemies: Array = party_b if i == 0 else party_a
		for owner in allies:
			for e in (owner.get("effects", []) as Array):
				if String((e as Dictionary).get("kind", "")) != "dyn":
					continue
				var d := e as Dictionary
				var scale := _dyn_scale(d.get("when", null), owner, allies, enemies)
				if is_zero_approx(scale):
					continue
				for op in (d.get("ops", []) as Array):
					apply_effect_op(op as Dictionary, owner, allies, enemies, {},
						int(d.get("no", 0)), scale, DYN_SRC)


# ── 반응 효과(D 이벤트) ──────────────────────────────────────────────────────
## 전투 도중 사건에 반응하는 각성스킬. 설치는 `apply_battle` 이 `react` 항목으로 하고,
## 발화는 `Battle` 이 각 사건 지점에서 아래 함수들을 부른다.
##
## 항목 = {kind:"react", on:"<사건>", left:N(남은 횟수, 없으면 무제한), ...}
##   사건: attack_done(공격 성사) · hit_taken(피격) · hit_unguarded(막기·회피 둘 다 실패) ·
##         block(막기 성공) · evade(회피 성공) · crit(크리 발동) · death(사망) ·
##         attack_bonus(공격 직전 추가 피해)
##
## `left` 가 있으면 발동할 때마다 줄고 0 이 되면 더 안 터진다(설명의 "최대 N회" · "전투당 N회").
## 누적형은 `stack` 에 현재 누적치를 들고 다니며 `max_total` 로 자른다.
const REACT := "react"

static func _reacts(c: Dictionary, on: String) -> Array:
	var out: Array = []
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) != REACT or String(d.get("on", "")) != on:
			continue
		if d.has("left") and int(d["left"]) <= 0:
			continue
		# `when` = 발화 **시점**의 조건(동적 효과와 같은 어휘). 전용 장비 완숙이의 후라이팬
		# "자신의 체력 20% 이하일 때 공격 시 …" 처럼 상시가 아니라 그때그때 봐야 하는 것들.
		# 없으면 종전대로 무조건 발화한다.
		if d.has("when") and is_zero_approx(_dyn_scale(d["when"], c, c.get("_party", []), [])):
			continue
		out.append(d)
	return out


## 남은 횟수 소모. 무제한이면 아무 일도 안 한다.
static func _spend(r: Dictionary) -> void:
	if r.has("left"):
		r["left"] = int(r["left"]) - 1


## 누적형 버프 — 발동할 때마다 조금씩 쌓고 상한에서 멈춘다.
## (21 깨어난 방어 감각 · 63 신뢰의 힘 · 64 신비한 보호 · 80 원투박치기)
static func _stack_up(r: Dictionary, owner: Dictionary, party: Array) -> bool:
	var step := float(r.get("value", 0.0))
	var cur := float(r.get("stack", 0.0))
	var cap := float(r.get("max_total", 0.0))
	if cap > 0.0 and cur >= cap:
		return false
	var add := step if cap <= 0.0 else minf(step, cap - cur)
	if add <= 0.0:
		return false
	r["stack"] = cur + add
	var targets: Array = party if String(r.get("to", "self")) == "ally" else [owner]
	var src := "react:%d" % int(r.get("no", 0))
	for t in targets:
		for st in (r.get("stats", []) as Array):
			# `__dmg_taken`/`__dmg_deal` 은 스탯이 아니라 **피해 계수**를 뜻하는 표기다
			# (52 뼈갑옷 "피해를 입을 때 마다 다음 피해를 10%만큼 증가"). apply_effect_op 와 같은 규약.
			match String(st):
				"__dmg_taken": _push(t, {"kind": "dmg_taken", "pct": add}, src)
				"__dmg_deal":  _push(t, {"kind": "dmg_deal", "pct": add}, src)
				_: _aw_add_stat(t, String(st), String(r.get("mode", "pct")), add, src)
	return true


## 공격이 성사됐다 — 누적형 공격 버프(63) · 횟수제 디버프(25) · 흡혈(46).
## `dealt` = 이번 공격으로 실제로 준 피해(흡혈형이 쓴다).
static func _aw_on_attack_done(attacker: Dictionary, defender: Dictionary,
		_rng: RandomNumberGenerator, dealt := 0) -> void:
	if not bool(attacker.get("alive", true)):
		return
	for r in _reacts(attacker, "attack_done"):
		match String(r.get("do", "stack")):
			"heal_dealt":
				# 46 블랙홀의 마력 — "입힌 피해량의 일부를 흡수하여 체력 회복 **및 공격력 상승**".
				# 회복과 누적 버프를 한 항목이 함께 한다(`stats` 가 있으면 누적도 같이).
				if dealt <= 0:
					continue
				var heal := int(round(float(dealt) * float(r.get("ratio", 1.0))))
				if heal > 0:
					attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + heal)
				if not (r.get("stats", []) as Array).is_empty():
					_stack_up(r, attacker, attacker.get("_party", []))
				_spend(r)
			"heal_pct":
				# "자신의 체력 20% 이하일 때 공격 시, 체력 1% 회복"(완숙이의 후라이팬).
				# 조건은 항목의 `when` 이 이미 걸렀다(`_reacts`).
				var h := int(round(float(attacker.get("hp_max", 0)) * float(r.get("pct", 0.0)) / 100.0))
				if h > 0:
					attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + h)
					_spend(r)
			"stack_from_target":
				# 워든의 부유검 — "타겟 **최대 체력의 10%** 만큼 공격력 강화(최대 1000)".
				# 누적 크기가 상대에게서 오므로 `_stack_up` 의 고정 value 대신 여기서 계산한다.
				# 조건("디버프의 영향을 받는 동안")은 항목의 `when` 이 이미 걸렀다.
				var step := float(defender.get("hp_max", 0)) * float(r.get("pct", 0.0)) / 100.0
				var cur := float(r.get("stack", 0.0))
				var cap2 := float(r.get("max_total", 0.0))
				if cap2 > 0.0:
					step = minf(step, cap2 - cur)
				if step >= 1.0:
					r["stack"] = cur + step
					_aw_add_stat(attacker, String(r.get("stat", "att")), "flat", step,
						"react:%d" % int(r.get("no", 0)))
					_spend(r)
			"stack":
				if _stack_up(r, attacker, attacker.get("_party", [])):
					_spend(r)
			"reset":
				# 52 뼈갑옷 "공격 시, 피해량 증가 효과가 초기화된다"
				_aw_clear_src(attacker, "react:%d" % int(r.get("no", 0)))
				for r2 in _reacts(attacker, String(r.get("reset_on", ""))):
					r2["stack"] = 0.0
			"debuff_target":
				# 25 대양의 분노 "공격 적중 시 마다, 3회에 한하여 상대 방어율을 7% 감소시키고,
				#   자신의 크리티컬 확률을 7% 증가"
				var src := "react:%d" % int(r.get("no", 0))
				_aw_add_stat(defender, String(r.get("target_stat", "blk")), "flat",
					-float(r.get("target_value", 0.0)), src)
				_aw_add_stat(attacker, String(r.get("self_stat", "cri")), "flat",
					float(r.get("self_value", 0.0)), src)
				_spend(r)


## 연속공격이 끝났다 — 80 원투박치기 · 세크라포의 어깨보호대.
## `dealt` = 이번 연속공격으로 실제로 준 피해 합.
static func _aw_on_double(attacker: Dictionary, dealt := 0) -> void:
	if not bool(attacker.get("alive", true)):
		return
	for r in _reacts(attacker, "double"):
		if String(r.get("do", "stack")) == "heal_dealt":
			# "연속 공격 시 자신이 준 대미지만큼 자신의 체력 회복, 전투 중 3회 한정"
			if dealt <= 0:
				continue
			var heal := int(round(float(dealt) * float(r.get("ratio", 1.0))))
			attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + heal)
			_spend(r)
			continue
		if _stack_up(r, attacker, attacker.get("_party", [])):
			_spend(r)


## 확률적 피해 고정(87 즈믄의 친구). 반환 = 고쳐진 피해.
static func _aw_fix_damage(defender: Dictionary, dmg: int) -> int:
	# 75 얼어붙은 날개 — "방어 시 누적된 수치만큼 데미지를 감소하고 누적 수치를 초기화"
	for rr in _reacts(defender, "defend_release"):
		var nr := int(rr.get("no", 0))
		var acc := _aw_acc_get(defender, nr)
		if acc > 0.0:
			dmg = maxi(1, dmg - int(round(acc)))
			_aw_acc_set(defender, nr, 0.0)
	for r in _reacts(defender, "pre_damage"):
		var chance := float(r.get("chance", 100.0))
		if chance < 100.0 and randf() * 100.0 >= chance:
			continue
		_spend(r)
		return maxi(1, int(r.get("fix", 1)))
	return dmg


## 주어진 출처(src)의 효과를 전부 걷어낸다.
static func _aw_clear_src(c: Dictionary, src: String) -> void:
	var keep: Array = []
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("src", "")) == src:
			continue
		keep.append(e)
	c["effects"] = keep


## 공격 직전 추가 피해(누적 방출형). 반환 = 이번 타격에 더할 피해.
static func _aw_on_attack_bonus(attacker: Dictionary, _defender: Dictionary,
		_rng: RandomNumberGenerator, raw_hint := 0) -> int:
	var bonus := 0
	for r in _reacts(attacker, "attack_bonus"):
		var no := int(r.get("no", 0))
		var acc := _aw_acc_get(attacker, no)
		if acc <= 0.0:
			continue
		bonus += int(round(acc * float(r.get("ratio", 1.0))))
		_aw_acc_set(attacker, no, 0.0)      # "누적 수치를 초기화"
		_spend(r)
	# 65 신성 방패 — "공격 시 누적된 수치만큼 체력을 회복하고 누적 수치를 초기화"
	for rh in _reacts(attacker, "attack_heal"):
		var nh := int(rh.get("no", 0))
		var ah := _aw_acc_get(attacker, nh)
		if ah <= 0.0:
			continue
		attacker["hp"] = mini(int(attacker["hp_max"]),
			int(attacker["hp"]) + int(round(ah)))
		_aw_acc_set(attacker, nh, 0.0)
		_spend(rh)
	# 75 얼어붙은 날개 — 준 피해의 1/3 을 누적(최대 자신의 공격력만큼)
	for ra in _reacts(attacker, "attack_acc"):
		var na := int(ra.get("no", 0))
		var capa := float(_eff(attacker, String(ra.get("cap_stat", "att"))))
		_aw_acc_set(attacker, na, minf(
			_aw_acc_get(attacker, na) + float(raw_hint) * float(ra.get("ratio", 1.0)), capa))
	# 특수 장비 — 타겟의 체력에 비례하는 추가 피해. 상한(`max`)은 원문의 "(최대 300)".
	for rt in _reacts(attacker, "attack_target_hp"):
		var add := 0.0
		match String(rt.get("do", "")):
			"cur_pct":
				# "상대 드래곤 남은 체력의 5%에 비례"(카이저 발록의 투구)
				add = float(_defender.get("hp", 0)) * float(rt.get("pct", 0.0)) / 100.0
			"max_pct":
				add = float(_defender.get("hp_max", 0)) * float(rt.get("pct", 0.0)) / 100.0
			"max_per_unit":
				# "타겟의 최대 체력 **1마다** 0.002% 의, 타겟 최대 체력 비례 추가대미지"
				# (피오드의 텅 빈 모래시계) ⇒ 비율 자체가 최대 체력에 비례한다 = 최대체력²
				# 비율(%) = 최대체력 × 0.002 · 추가피해 = 최대체력 × 그 비율 / 100
				#   ⇒ 최대체력 3,000 이면 6% → 180. 상한 300 은 최대체력 약 3,873 에서 닿는다.
				var hm := float(_defender.get("hp_max", 0))
				add = hm * (hm * float(rt.get("per_unit_pct", 0.0))) / 100.0
		if rt.has("max"):
			add = minf(add, float(rt["max"]))
		if add >= 1.0:
			bonus += int(round(add))
			_spend(rt)
	# 71 약점 공략 — "상대의 공격력 방어력 합이 자신보다 낮은 경우 그 차이만큼 (최대 150)"
	for r2 in _reacts(attacker, "stat_gap"):
		var mine := _eff(attacker, "att") + _eff(attacker, "def")
		var theirs := _eff(_defender, "att") + _eff(_defender, "def")
		if mine > theirs:
			bonus += mini(mine - theirs, int(r2.get("max", 150)))
	return bonus


## 각성스킬 누적치 — 스킬 번호별로 전투원에 붙여 둔다(쌓는 항목과 쓰는 항목이 다르므로).
static func _aw_acc_get(c: Dictionary, no: int) -> float:
	return float((c.get("_aw_acc", {}) as Dictionary).get(no, 0.0))


static func _aw_acc_set(c: Dictionary, no: int, v: float) -> void:
	if not c.has("_aw_acc"):
		c["_aw_acc"] = {}
	(c["_aw_acc"] as Dictionary)[no] = v


## 스킬 사용 **횟수 회복** — 전용 장비 "회피/크리티컬 발동 시 스킬 사용 횟수 1회 회복"
## (백룡·흑룡의 보주 · 네시의 머리장식 · 시타엘의 신성한 뿔).
## 남은 횟수가 **한도보다 적은** 스킬 중 앞쪽 것부터 채운다 — 이미 가득이면 아무 일도 없다.
## to == "ally" 면 아군 전체(시타엘)에 건다.
static func _restore_skill_use(owner: Dictionary, r: Dictionary, skills_db: Dictionary) -> bool:
	var targets: Array = [owner]
	if String(r.get("to", "self")) == "ally":
		targets = owner.get("_party", [owner])
	var n := int(r.get("value", 1))
	var any := false
	for t in targets:
		var c := t as Dictionary
		if not bool(c.get("alive", true)):
			continue
		var left := n
		for sd in (c.get("skills", []) as Array):
			if left <= 0:
				break
			var sid := int((sd as Dictionary).get("id", 0))
			var lim := _skill_limit(skills_db.get(str(sid), {}), int((sd as Dictionary).get("level", 1)))
			lim += _skill_uses_bonus(c)
			if _uses_left(c, sid) < lim:
				(c["skill_uses"] as Dictionary)[sid] = _uses_left(c, sid) + 1
				left -= 1
				any = true
	return any


## **다른 반응의 남은 횟수**를 되살린다 — 전용 장비 크로우 드래곤의 해골투구
## ("막기 혹은 회피에 성공하면 각성스킬 [복수의 까마귀] 횟수를 1회 회복, 최대 4회").
## `target_no` = 되살릴 반응의 각성스킬 번호 · `max` = 그 반응의 횟수 상한.
static func _restore_react(owner: Dictionary, r: Dictionary) -> void:
	var want := int(r.get("target_no", 0))
	var cap := int(r.get("max", 0))
	for e in (owner.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) != REACT or int(d.get("no", -1)) != want:
			continue
		if not d.has("left"):
			continue                       # 무제한이면 되살릴 것이 없다
		if cap > 0 and int(d["left"]) >= cap:
			continue
		d["left"] = int(d["left"]) + int(r.get("value", 1))
		return


## 크리티컬이 터졌다 — 상대 최대 체력 비례 추가 피해(2 · 44).
static func _aw_on_crit_bonus(_attacker: Dictionary, defender: Dictionary) -> int:
	var bonus := 0
	for r in _reacts(_attacker, "crit"):
		if String(r.get("do", "")) == "skill_restore":
			if _restore_skill_use(_attacker, r, _attacker.get("_skills_db", {})):
				_spend(r)
			continue
		var add := float(defender.get("hp_max", 0)) * float(r.get("pct", 0.0)) / 100.0
		if r.has("max"):
			add = minf(add, float(r["max"]))     # "(최대 300)" — 전용 장비 저네르의 정기
		bonus += int(round(add))
		_spend(r)
	return bonus


## 피격했다 — 누적형 방어 버프(21) · 받은 피해 누적(45).
static func _aw_on_hit_taken(defender: Dictionary, _attacker: Dictionary, dmg: int,
		_rng: RandomNumberGenerator) -> void:
	if not bool(defender.get("alive", true)):
		return
	for r in _reacts(defender, "hit_taken"):
		match String(r.get("do", "stack")):
			"stack":
				if _stack_up(r, defender, defender.get("_party", [])):
					_spend(r)
			"acc":
				# "받은 데미지를 누적 (최대 자신의 방어력만큼)" — 45 불타는 날개
				# ⚠️ 누적치는 **전투원**에 둔다. 쌓는 항목(hit_taken)과 방출하는 항목
				#    (attack_bonus)이 서로 다른 react 항목이라 항목에 두면 공유가 안 된다.
				var cap := float(_eff(defender, String(r.get("cap_stat", "def"))))
				_aw_acc_set(defender, int(r.get("no", 0)),
					minf(_aw_acc_get(defender, int(r.get("no", 0))) + float(dmg), cap))
				# 누적은 횟수를 쓰지 않는다(방출할 때 쓴다)


## 막기·회피에 **둘 다** 실패해 맞았다 — 40 복수의 까마귀(상대를 혼란에 빠뜨린다).
static func _aw_on_hit_unguarded(defender: Dictionary, attacker: Dictionary,
		_rng: RandomNumberGenerator) -> void:
	for r in _reacts(defender, "hit_unguarded"):
		_add_flag(attacker, "confused", int(r.get("turns", 1)), int(r.get("no", 0)))
		_spend(r)


## 막기에 성공했다 — 64 신비한 보호(아군 버프 누적).
static func _aw_on_block(defender: Dictionary, _rng: RandomNumberGenerator) -> void:
	for r in _reacts(defender, "block"):
		if String(r.get("do", "")) == "react_restore":
			_restore_react(defender, r)
			continue
		if String(r.get("do", "")) == "acc":
			# 65 신성 방패 "막기에 성공할 때 마다 자신의 합계 방어력 5%를 누적"
			var nb := int(r.get("no", 0))
			_aw_acc_set(defender, nb, _aw_acc_get(defender, nb)
				+ float(_eff(defender, String(r.get("from_stat", "def"))))
				* float(r.get("pct", 0.0)) / 100.0)
			_spend(r)
		elif r.has("gauge_pct"):
			# 38 방출의 힘 "막기 발동시 아군 각성 게이지가 5% 증가한다"
			for t in (defender.get("_party", []) as Array):
				var c := t as Dictionary
				if bool(c.get("alive", true)):
					c["awaken_gauge"] = minf(99.0,
						float(c.get("awaken_gauge", 0.0)) + float(r["gauge_pct"]))
			_spend(r)
		elif _stack_up(r, defender, defender.get("_party", [])):
			_spend(r)


## 회피에 성공했다 — 96 하얀 번개 · 666 샛별(상대를 혼란에 빠뜨린다).
static func _aw_on_evade(defender: Dictionary, attacker: Dictionary,
		_rng: RandomNumberGenerator) -> void:
	for r in _reacts(defender, "evade"):
		if String(r.get("do", "")) == "react_restore":
			_restore_react(defender, r)
			continue
		if String(r.get("do", "")) == "skill_restore":
			if _restore_skill_use(defender, r, defender.get("_skills_db", {})):
				_spend(r)
			continue
		_add_flag(attacker, "confused", int(r.get("turns", 1)), int(r.get("no", 0)))
		_spend(r)


## 쓰러졌다 — 101 희생과 복수(아군 각성 게이지 회복) 등.
static func _aw_on_death(dead: Dictionary) -> void:
	for r in _reacts(dead, "death"):
		# 35 물의 보호막 — "사망 시 아군 물속성 드래곤들이 다음 3회 받는 데미지가 1로 고정".
		# 죽는 순간 **살아 있는 대상에게 반응을 심는다**(각자 자기 몫의 횟수를 갖는다).
		if String(r.get("do", "")) == "plant":
			for t2 in _targets(String(r.get("to", "ally")), dead, dead.get("_party", [])):
				var c2 := t2 as Dictionary
				if not bool(c2.get("alive", true)) or c2 == dead:
					continue
				var re := (r.get("plant", {}) as Dictionary).duplicate(true)
				re["kind"] = REACT
				re["no"] = int(r.get("no", 0))
				re["turns"] = -1
				(c2["effects"] as Array).append(re)
			_spend(r)
			continue
		# 아군 사망을 계기로 **살아남은 편에게 효과를 건다** — 전용 장비 쿠르파의 푸른갑주
		# ("아군 그림자 드래곤이 쓰러지면 5턴간 공격력 50% 상승") · 레지아나의 빛나는 깃털
		# ("사망 시 아군 각성기 피해량 50% 증가"). `turns` 를 주면 한시 효과다.
		if String(r.get("do", "")) == "party_buff":
			for t4 in _targets(String(r.get("to", "ally")), dead, dead.get("_party", [])):
				var c4 := t4 as Dictionary
				if not bool(c4.get("alive", true)) or c4 == dead:
					continue
				for o in (r.get("ops", []) as Array):
					var e4 := (o as Dictionary).duplicate(true)
					e4["turns"] = int(r.get("turns", -1))
					e4["src"] = "death:%d" % int(r.get("no", 0))
					(c4["effects"] as Array).append(e4)
			_spend(r)
			continue
		for t in (dead.get("_party", []) as Array):
			var c := t as Dictionary
			if not bool(c.get("alive", true)):
				continue
			if r.has("gauge_pct"):
				c["awaken_gauge"] = minf(99.0,
					float(c.get("awaken_gauge", 0.0)) + float(r["gauge_pct"]))
		_spend(r)


## 스킬을 시전했다 — 81 자격을 갖춘 자(다음 공격 무조건 회피) · 85 절망의 번개(상대 혼란).
static func _aw_on_skill_cast(caster: Dictionary, targets: Array,
		rng: RandomNumberGenerator = null) -> void:
	for r in _reacts(caster, "skill_cast"):
		match String(r.get("do", "")):
			"random_debuff":
				# 41 봉인의 힘 — "무작위 효과: 게이지 10% 감소 / 방어력 10% 감소 / 공격력 10% 감소"
				var ch := r.get("choices", []) as Array
				if ch.is_empty() or rng == null:
					continue
				var pick := ch[rng.randi_range(0, ch.size() - 1)] as Dictionary
				for t3 in targets:
					var c3 := t3 as Dictionary
					if not bool(c3.get("alive", true)):
						continue
					if pick.has("gauge_pct"):
						c3["awaken_gauge"] = maxf(0.0,
							float(c3.get("awaken_gauge", 0.0)) + float(pick["gauge_pct"]))
					else:
						_aw_add_stat(c3, String(pick.get("stat", "")),
							String(pick.get("mode", "pct")), float(pick.get("value", 0.0)),
							"react:%d" % int(r.get("no", 0)))
					break                    # 대상 하나(우리 PvE 는 적이 한 마리다)
			"self_flag":
				_add_flag(caster, String(r.get("flag", "")), -1, int(r.get("no", 0)))
			"confuse_target":
				for t in targets:
					var c := t as Dictionary
					if bool(c.get("alive", true)):
						_add_flag(c, "confused", int(r.get("turns", 1)),
							int(r.get("no", 0)))
						break
		_spend(r)


static func _has_dyn(c: Dictionary) -> bool:
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "dyn":
			return true
	return false


## 지난 라운드의 동적 효과 제거. 뭔가 지웠으면 true.
static func _clear_dyn(c: Dictionary) -> bool:
	var keep: Array = []
	var removed := false
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("src", "")).begins_with(DYN_SRC):
			removed = true
			continue
		keep.append(e)
	if removed:
		c["effects"] = keep
	return removed


## 조건 평가 → **배수**. 0 이면 미발동, 1 이면 그대로, 그 밖이면 값에 곱한다.
## 배수를 쓰는 이유: "잃은 체력에 비례"(12) · "생존 아군 1마리당"(58·66) 처럼
## 조건이 곧 크기인 스킬이 있어서다.
static func _dyn_scale(when, owner: Dictionary, allies: Array, enemies: Array = []) -> float:
	if when == null:
		return 1.0
	var w := when as Dictionary
	var hp_max := maxf(1.0, float(owner.get("hp_max", 1)))
	var hp_pct := float(owner.get("hp", 0)) / hp_max * 100.0
	match String(w.get("kind", "")):
		"enemy_dead_mult":            # 69 암흑 마법 — 상대가 죽을 때마다 배율 +1 (최대 max)
			var n2 := 1
			for c in enemies:
				if not bool((c as Dictionary).get("alive", true)):
					n2 += 1
			return float(mini(n2, int(w.get("max", 3))))
		"enemy_hp_sum":               # 상대 팀 **현재 체력의 합** 자체가 크기 (미르의 별빛방울)
			var s := 0.0
			for c in enemies:
				if bool((c as Dictionary).get("alive", true)):
					s += float((c as Dictionary).get("hp", 0))
			return s
		"self_hp_at_most":            # "체력이 N% 이하일 때"
			return 1.0 if hp_pct <= float(w.get("pct", 0)) else 0.0
		"self_hp_above":              # "체력이 N% 초과 시"
			return 1.0 if hp_pct > float(w.get("pct", 0)) else 0.0
		"lost_hp_ratio":              # 잃은 체력 비율(0~1) 자체가 크기 (12 게으름의 화신)
			return clampf(1.0 - hp_pct / 100.0, 0.0, 1.0)
		"alive_ally_element":         # 생존한 그 속성 아군 마릿수 (58 생명의 빛 · 66 신성한 유대)
			var n := 0
			for c in allies:
				if bool((c as Dictionary).get("alive", true)) \
						and String((c as Dictionary).get("element", "")) == String(w.get("value", "")):
					n += 1
			if bool(w.get("exclude_self", false)) \
					and String(owner.get("element", "")) == String(w.get("value", "")) \
					and bool(owner.get("alive", true)):
				n -= 1
			return float(maxi(0, n))
		"ally_dead_any":              # 아군이 하나라도 쓰러졌나 (37 반항심)
			for c in allies:
				if not bool((c as Dictionary).get("alive", true)):
					return 1.0
			return 0.0
		"self_alive":
			return 1.0 if bool(owner.get("alive", true)) else 0.0
		"self_dead":
			return 0.0 if bool(owner.get("alive", true)) else 1.0
		"has_debuff":                 # 해로운 효과를 받고 있나 (11 감시자의 눈)
			return 1.0 if _has_debuff(owner, w.get("except_src", [])) else 0.0
	return 0.0                        # 모르는 조건은 발동하지 않는다


## '디버프를 받고 있다' 의 판정 — 상태이상 · 지속피해 · 받는피해 증가 · 음수 스탯.
## `except_src` 에 든 스킬 id 가 원인인 것은 세지 않는다(11 이 [상처 파악]을 제외한다).
static func _has_debuff(c: Dictionary, except_src: Array) -> bool:
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if int(d.get("source", -1)) in except_src:
			continue
		match String(d.get("kind", "")):
			"status":
				if String(d.get("flag", "")) != IMMUNE_FLAG:
					return true
			"dot", "timed":
				return true
			"dmg_taken":
				if float(d.get("pct", 0.0)) > 0.0:
					return true
			"stat":
				if float(d.get("value", 0.0)) < 0.0:
					return true
	return false


static func effect_cond_ok(cond, owner: Dictionary, allies: Array, enemies: Array,
		ctx: Dictionary) -> bool:
	if cond == null or (cond is Dictionary and (cond as Dictionary).is_empty()):
		return true
	var c := cond as Dictionary
	match String(c.get("kind", "")):
		"field_element":
			return String(ctx.get("field_element", "")) == String(c.get("value", ""))
		"party_has_element":
			return _count_element(allies, String(c.get("value", ""))) > 0
		"party_element_count":
			return _count_element(allies, String(c.get("value", ""))) >= int(c.get("min", 1))
		"enemy_has_element":
			return _count_element(enemies, String(c.get("value", ""))) > 0
		"party_size_min":
			return allies.size() >= int(c.get("min", 1))
		"enemy_boss":
			return bool(ctx.get("enemy_boss", false))
		"self_type":
			# 해골요새 장비의 후반 조항 — "방어형 드래곤이 장착 시 회피율 10% 상승".
			# 값은 `dragons.json` 의 `type`(atk/hp/def/hd/ha/ad) 그대로다.
			return String(owner.get("atk_type", "")) == String(c.get("value", ""))
		"self_stat_min":
			# 27 대지의 기둥 "자신의 방어력이 500 이상이면". 전투 시작 시점의 확정 스탯으로 본다.
			return _eff(owner, String(c.get("stat", ""))) >= int(c.get("min", 0))
		"grade_highest":
			# 18 권위의 팔라곤 "아군 드래곤 중 자신의 등급이 가장 높으면
			#   (1대 1에서는 무조건 발동)". 아군이 자기뿐이면 자연히 참이다.
			# ⚠️ 비교만 하므로 등급의 **절대 눈금**은 문제되지 않는다(우리 grade 는 7.0 기준,
			#   원작은 0~6 이라 스케일이 다르다 — 절대값을 쓰는 스킬은 아직 미이식).
			var mine := float(owner.get("grade", 0.0))
			for c2 in allies:
				if c2 != owner and float((c2 as Dictionary).get("grade", 0.0)) > mine:
					return false
			return true
	return false                      # 모르는 조건은 **발동하지 않는다**(안전 쪽)


static func _count_element(party: Array, el: String) -> int:
	var n := 0
	for c in party:
		if String((c as Dictionary).get("element", "")) == el:
			n += 1
	return n


## op 하나 적용. 실제로 뭔가 걸었으면 true.
## extra_scale = 동적 조건이 준 배수(1.0 = 평범). src_prefix = "awaken:" 또는 "dyn:".
static func apply_effect_op(op: Dictionary, owner: Dictionary, allies: Array, enemies: Array,
		ctx: Dictionary, no: int, extra_scale := 1.0, src_prefix := "awaken:") -> bool:
	# op 자체에 조건이 붙어 있으면(예: 82 자외선 차단 30) 여기서 가른다.
	if op.has("cond"):
		var ok := effect_cond_ok(op["cond"], owner, allies, enemies, ctx)
		if bool(op.get("negate", false)):
			ok = not ok
		if not ok:
			return false
	var targets := _targets(String(op.get("to", "self")), owner, allies)
	if targets.is_empty():
		return false
	var src := "%s%d" % [src_prefix, no]

	# 값 = 고정값 × per 배수, 또는 소유자의 스탯에서 파생(from). 둘 다 max 로 자른다.
	var v := 0.0
	if op.has("from"):
		var fr: Dictionary = op["from"]
		var fs := String(fr.get("stat", ""))
		# `grade`(개체 등급)는 소수라 _eff 의 정수 반올림을 거치면 안 된다.
		# ⚠️ 눈금 주의: 우리 등급은 7.0 기준(Growth.compute_grade), 원작은 0~6 이다.
		#    "(드래곤 등급 × N)%" 류는 이 차이만큼 원작과 다를 수 있다 — `ratio` 가 조절 노브다.
		var base := float(owner.get("grade", 0.0)) if fs == "grade" 			else float(_eff(owner, fs))
		v = base * float(fr.get("ratio", 1.0))
	else:
		v = float(op.get("value", op.get("pct", 0.0)))
		if op.has("per"):
			var n := _targets(String(op["per"]), owner, allies).size()
			if n <= 0:
				return false
			v *= float(n)
	v *= extra_scale
	if op.has("max"):
		v = minf(v, float(op["max"]))
	# 값이 없는 연산(면역 부여·흡수)은 0 이어도 정상이다.
	const VALUELESS := ["absorb_top", "status_immune", "skill_level_proc", "flag", "initiative",
		"pen_share"]
	if is_zero_approx(v) and not (String(op.get("kind", "")) in VALUELESS):
		return false

	for t in targets:
		match String(op.get("kind", "stat")):
			"stat":
				# ⚠️ 동적 효과가 hp 를 건드리면 라운드마다 최대체력이 불어난다
				#    (_add_stat 의 hp 는 효과가 아니라 hp_max 를 직접 고치기 때문).
				#    체력을 바꾸는 조항은 반드시 정적(ops)으로 둘 것.
				if src_prefix == DYN_SRC and String(op["stat"]) == "hp":
					return false
				# `__dmg_deal`/`__dmg_taken` 은 '스탯이 아니라 피해량'을 뜻하는 표기 —
				# from(파생)·per(마릿수) 문법을 피해 계수에도 그대로 쓰려고 둔 것이다
				# (84 전사의 의식 · 13 격류 · 92 타오르는 바위 · 102 가시와 못).
				if String(op["stat"]) == "__dmg_deal":
					_push(t, {"kind": "dmg_deal", "pct": v}, src)
				elif String(op["stat"]) == "__dmg_taken":
					_push(t, {"kind": "dmg_taken", "pct": v}, src)
				else:
					_aw_add_stat(t, String(op["stat"]), String(op.get("mode", "flat")), v, src)
			"dmg_deal":      _push(t, {"kind": "dmg_deal", "pct": v}, src)
			"dmg_deal_vs_element":
				# 전용 장비 "불 속성 드래곤에게 주는 대미지 50% 증가" 계열 —
				# 방어자의 속성을 봐야 하므로 대상 속성을 항목에 함께 싣는다.
				_push(t, {"kind": "dmg_deal_vs_element", "pct": v,
					"element": String(op.get("element", ""))}, src)
			"dmg_deal_vs_type":
				# 해골요새 장비 "체방형 드래곤을 공격 시 25% 추가 대미지" —
				# 방어자의 **전투 유형**을 봐야 하므로 대상 유형을 항목에 함께 싣는다.
				_push(t, {"kind": "dmg_deal_vs_type", "pct": v,
					"atk_type": String(op.get("atk_type", ""))}, src)
			"awaken_dmg":    _push(t, {"kind": "awaken_dmg", "pct": v}, src)
			"initiative":
				# 60 선제 공격 "전투 시에 아군이 항상 먼저 공격하도록 만든다".
				# 상시(turns=-1)라 소모되지 않는다 — 스킬 150 빙결의 표식이 거는 1회용과 구분된다.
				_push(t, {"kind": "initiative", "side": String(t.get("side", "ally"))}, src)
			"crit_pen":      _push(t, {"kind": "crit_pen", "pct": v}, src)
			"double_dmg":    _push(t, {"kind": "double_dmg", "pct": v}, src)
			"skill_dmg_deal":
				_push(t, {"kind": "skill_dmg_deal", "pct": v,
					"skill_id": int(op.get("skill_id", 0))}, src)
			"pen_share":
				# 엔젤 드래곤의티아라 — "자신의 방어 관통을 0으로 감소, 나머지 아군에게 공통분배".
				var mine := _eff(t, "pure")
				var others := _targets("ally_others", t, allies)
				if mine > 0 and not others.is_empty():
					_aw_add_stat(t, "pure", "flat", -float(mine), src)
					var each := float(mine) / float(others.size())
					for o2 in others:
						_aw_add_stat(o2, "pure", "flat", each, src)
			"awaken_dmg_cap": _push(t, {"kind": "awaken_dmg_cap", "value": v}, src)
			"skill_dmg_taken":
				# "스킬에 입는 피해 10% 감소"(엘더 블랙퀸의 목도리). 음수 = 감소.
				# 아티팩트의 `skill_dmg_taken_pct` 와 같은 지점에서 곱해진다.
				_push(t, {"kind": "skill_dmg_taken", "pct": v}, src)
			"dmg_taken":     _push(t, {"kind": "dmg_taken", "pct": v}, src)
			"dmg_taken_flat":
				_push(t, {"kind": "dmg_taken_flat", "value": v,
					"min_dmg": int(op.get("min_dmg", 0))}, src)
			"dmg_cap_pct":   _push(t, {"kind": "dmg_cap_pct", "pct": v}, src)
			"pen":
				# 73 어둠 습격자 "공격 시 대상의 방어력 N% 무시" — damage() 의 pen(0~1).
				t["pen"] = clampf(float(t.get("pen", 0.0)) + v / 100.0, 0.0, 0.95)
			"gauge_rate":    _push(t, {"kind": "gauge_rate", "pct": v}, src)
			"gauge_min":     _push(t, {"kind": "gauge_min", "value": v}, src)
			"gauge_add":
				# 전투 시작 게이지(97 하얀매의 친구). 효과가 아니라 값이라 직접 올린다.
				t["awaken_gauge"] = minf(99.0, float(t.get("awaken_gauge", 0.0)) + v)
			"skill_uses":    _push(t, {"kind": "skill_uses", "value": v}, src)
			"skill_level":   _push(t, {"kind": "skill_level", "value": v}, src)
			"skill_level_proc":
				_push(t, {"kind": "skill_level_proc", "pct": float(op["pct"]),
					"value": float(op["value"])}, src)
			"status_immune":
				_push(t, {"kind": "status", "flag": IMMUNE_FLAG}, src)
			"flag":
				_push(t, {"kind": "status", "flag": String(op["flag"])}, src)
			"absorb_top":
				_absorb_top(t, allies, float(op.get("pct", 0.0)),
					op.get("stats", ["hp", "att", "def"]), src,
					bool(op.get("effective", false)))
			_:
				return false
	return true


static func _push(c: Dictionary, e: Dictionary, src: String) -> void:
	var d := e.duplicate()
	d["turns"] = -1          # 각성스킬은 상시 특성 — 턴으로 사라지지 않는다
	d["src"] = src
	(c["effects"] as Array).append(d)


## 100 흡수의 힘 — "아군 드래곤 중 가장 등급이 높은 드래곤의 능력치를 30% 흡수해서
## 자신의 체/공/방에 합친다." 자기 자신이 최고 등급이면 자기 값을 흡수한다(설명이 제외하지 않는다).
##
## `effective` = **무엇을 흡수하는가**. 원작이 둘을 구분한다(전용 장비 말덱의 흡수의서가
## "대상의 **기본** 능력치가 아니라 대상의 **최대** 능력치로 변경(아이템/스킬로 인한 변화량 포함)"
## 이라고 못 박는다) ⇒ 기본값은 **기본 능력치**(버프 전)이고, 그 장비가 켜야 최종값을 읽는다.
## 🟦 사용자 확정 2026-07-31 — 종전에는 늘 최종값을 읽어서 그 장비가 무효과였다.
static func _absorb_top(owner: Dictionary, allies: Array, pct: float, stats: Array,
		src: String, effective := false) -> void:
	var top: Dictionary = {}
	var best := -INF
	for c in allies:
		var g := float((c as Dictionary).get("grade", 0.0))
		if g > best:
			best = g
			top = c
	if top.is_empty() or pct <= 0.0:
		return
	for s in stats:
		var key := String(s)
		# 기본 = 전투원의 원시 스탯 필드(효과 목록을 타지 않는다) · 최종 = `_eff`(버프 포함)
		var base := float(_eff(top, key)) if effective else float(top.get(key, 0))
		if key == "hp":
			# 체력은 `_eff` 를 안 쓰므로 기본/최종 모두 hp_max 다 — 다만 최종은 버프가 이미
			# 얹힌 hp_max 이고, 기본은 전투 시작 시점의 원시 최대체력(`hp_base`)이다.
			base = float(top.get("hp_max", 0)) if effective 				else float(top.get("hp_base", top.get("hp_max", 0)))
		var add := base * pct / 100.0
		if add >= 1.0:
			_aw_add_stat(owner, key, "flat", add, src)


static func _targets(spec: String, owner: Dictionary, allies: Array) -> Array:
	# 여러 대상을 `|` 로 이어 쓸 수 있다 — "자신의 스킬이 아군 신성/빛 드래곤에게도 적용"
	# (프리스트의 빛나는 날개). 중복은 제거한다(자신이 신성이면 두 번 걸리면 안 된다).
	if spec.contains("|"):
		var uniq: Array = []
		for part in spec.split("|"):
			for t in _targets(String(part).strip_edges(), owner, allies):
				if not uniq.has(t):
					uniq.append(t)
		return uniq
	if spec == "self":
		return [owner]
	if spec == "ally":
		return allies.duplicate()
	if spec == "ally_others":
		var o: Array = []
		for c in allies:
			if c != owner:
				o.append(c)
		return o
	if spec.begins_with("ally_dragon:"):
		# 특정 드래곤을 지목한다(29 대폭렬의 힘 "아군 다르고스").
		var did := int(spec.substr(12))
		var od: Array = []
		for c in allies:
			if int((c as Dictionary).get("dragon_id", 0)) == did:
				od.append(c)
		return od
	if spec.begins_with("ally_element:"):
		var el := spec.substr(13)
		var o2: Array = []
		for c in allies:
			if String((c as Dictionary).get("element", "")) == el:
				o2.append(c)
		return o2
	return []


## 스탯 가감. ⚠️ `hp` 만 특수하다 — `Battle._eff` 는 hp 를 안 쓰고 전투는 `hp_max`/`hp` 필드를
## 직접 읽으므로, 효과 목록에 넣어 봐야 아무 일도 일어나지 않는다. 그래서 hp 는 **여기서 직접**
## 최대체력과 현재체력에 반영한다(전투 시작 시점이라 비율이 보존된다).
static func _aw_add_stat(c: Dictionary, s: String, mode: String, v: float, src: String) -> void:
	if s == "hp":
		var before := int(c.get("hp_max", 0))
		var add := int(round(float(before) * v / 100.0)) if mode == "pct" else int(round(v))
		if add == 0:
			return
		c["hp_max"] = maxi(1, before + add)
		# 현재 체력도 같은 만큼 올린다(전투 시작 전이라 만피 상태가 정상).
		c["hp"] = mini(int(c["hp_max"]), int(c.get("hp", before)) + maxi(0, add))
		return
	(c["effects"] as Array).append({"kind": "stat", "stat": s, "mode": mode,
		"value": v, "turns": -1, "src": src})
