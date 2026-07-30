class_name AwakenSkill
extends RefCounted

## 각성 스킬 **효과 적용** — 순수 로직(§8.1 logic 층). 화면·에셋을 모른다.
##
## 표 = `data/skill_awaken.json` 의 `skills[].effect` (빌드: `build_awaken_effects.py`).
## 그 `effect` 는 사용자가 적어 준 `comment`(자연어 서술)를 기계가 읽는 형태로 옮긴 것이고,
## **설명 전체를 충족하는 것만 `impl:true`** 다. `impl:false` 는 아무 일도 하지 않는다 —
## 반쪽 발동(설명과 다르게 동작)이 안 하느니만 못하기 때문이다.
## 예외는 조항이 여러 개인 자작 스킬뿐이다 — 되는 조항만 걸고 나머지는 `partial` 에 적어
## 동굴 팝업이 그대로 사용자에게 보여 준다.
##
## ## 역할 분담 (한 방향)
##
##     AwakenSkill  = **번역**. data/skill_awaken.json 의 effect 를 읽어 전투원에게
##                    효과 항목(정적 결과 · `dyn` · `react`)을 심는다. 전투 시작 시 1회.
##     Battle       = **실행**. 심긴 항목을 라운드마다·사건마다 실제로 굴린다.
##
## ⚠️ 서로 참조하면 preload 순환으로 테스트가 깨진다 — Battle 은 AwakenSkill 을 부르지 않는다.
##    효과 원시연산(`Battle.apply_effect_op` · `Battle.effect_cond_ok`)도 Battle 소유다.

# ── 적용 단위 ────────────────────────────────────────────────────────────────
## 같은 각성스킬을 두 아군이 갖고 있을 때 두 번 적용할 것인가.
##   기본 = **소유자마다**(자기 대상 op 는 당연히 그래야 하고, 아군 대상도 원작에 반대 근거가 없다)
##   예외 = effect.stack == "once" — 설명이 중첩을 명시적으로 막는 스킬(예: 90 칠흑의 지배자
##          "중첩되는 각성스킬 효과에 대해서는 높은 수치만 적용됩니다")
const STACK_ONCE := "once"


## 전투 시작 시 각성 스킬을 파티에 반영한다. `allies` 를 직접 고친다(가변).
##
##   allies/enemies = Battle.make_combatant 결과 배열. 각 원소의 `awaken_no` 를 본다(0=없음).
##   table          = data/skill_awaken.json
##   ctx            = {field_element: String, enemy_boss: bool}
##
## 반환 = 실제로 발동한 것 [{no, name, owner}] — render 가 배지/로그로 쓸 수 있다.
static func apply_battle(allies: Array, enemies: Array, table: Dictionary,
		ctx: Dictionary = {}) -> Array:
	var by_no := _index(table)
	var fired: Array = []
	var used_once := {}
	# 반응 효과가 '아군 전체'를 대상으로 할 수 있어서 각 전투원이 자기 편 배열을 알아야 한다.
	# (Battle 은 반응을 부를 때 파티를 넘기지 않는다 — 사건 지점마다 인자를 늘리지 않으려고.)
	for c in allies:
		(c as Dictionary)["_party"] = allies
	for c in enemies:
		(c as Dictionary)["_party"] = enemies
	for owner in allies:
		var no := int(owner.get("awaken_no", 0))
		if no <= 0:
			continue
		var s: Dictionary = by_no.get(no, {})
		var eff: Dictionary = s.get("effect", {})
		if eff.is_empty() or not bool(eff.get("impl", false)):
			continue
		if String(eff.get("stack", "")) == STACK_ONCE:
			if used_once.has(no):
				continue
			used_once[no] = true
		if not Battle.effect_cond_ok(eff.get("cond", null), owner, allies, enemies, ctx):
			continue
		var any := false
		# 1차 패스 = 고정값 연산. `from`(파생) 은 2차로 미룬다 — 소유자의 **확정 스탯**을
		# 읽어야 하는데, 1차가 아직 스탯을 바꾸는 중이라 지금 읽으면 순서에 따라 값이 달라진다.
		for op in (eff.get("ops", []) as Array):
			if (op as Dictionary).has("from"):
				continue
			if Battle.apply_effect_op(op as Dictionary, owner, allies, enemies, ctx, no):
				any = true
		# 반응 항목도 심기만 한다 — 발화는 Battle 이 사건 지점에서 한다.
		for r in (eff.get("react", []) as Array):
			var re := (r as Dictionary).duplicate(true)
			re["kind"] = Battle.REACT
			re["no"] = no
			re["turns"] = -1
			(owner["effects"] as Array).append(re)
			any = true
		# 동적 항목은 여기서 **심기만** 한다 — 실제 계산은 라운드마다 refresh_dynamic 이 한다.
		var dyn: Array = eff.get("dyn", [])
		if not dyn.is_empty():
			for d in dyn:
				var entry := (d as Dictionary).duplicate(true)
				entry["kind"] = "dyn"
				entry["no"] = no
				entry["turns"] = -1
				(owner["effects"] as Array).append(entry)
			any = true
		if any or _has_derived(eff):
			fired.append({"no": no, "name": String(s.get("name", "")),
				"owner": String(owner.get("name", ""))})
	# 2차 패스 = 파생 연산(24 달의 비밀 · 34 물방울의 마력 · 48 빛의 기사 · 86 정의집행 …).
	for owner2 in allies:
		var no2 := int(owner2.get("awaken_no", 0))
		if no2 <= 0:
			continue
		var s2: Dictionary = by_no.get(no2, {})
		var eff2: Dictionary = s2.get("effect", {})
		if eff2.is_empty() or not bool(eff2.get("impl", false)):
			continue
		if not Battle.effect_cond_ok(eff2.get("cond", null), owner2, allies, enemies, ctx):
			continue
		for op in (eff2.get("ops", []) as Array):
			if (op as Dictionary).has("from"):
				Battle.apply_effect_op(op as Dictionary, owner2, allies, enemies, ctx, no2)
	return fired


static func _has_derived(eff: Dictionary) -> bool:
	for op in (eff.get("ops", []) as Array):
		if (op as Dictionary).has("from"):
			return true
	return false


# ── 탐험(전투 밖) ────────────────────────────────────────────────────────────
## 파티가 가진 각성 스킬의 탐험 보너스 합. 반환 {gold_pct, artifact_chance_pct}.
##   party = [{awaken_no: int}] 형태면 충분하다(전투원이 아니어도 된다).
## 같은 스킬을 여러 마리가 가지면 그만큼 합산한다(전투 쪽 기본 규칙과 같다).
static func explore_bonus(party: Array, table: Dictionary) -> Dictionary:
	var by_no := _index(table)
	var out := {"gold_pct": 0, "artifact_chance_pct": 0}
	for d in party:
		var no := int((d as Dictionary).get("awaken_no", 0))
		if no <= 0:
			continue
		var eff: Dictionary = (by_no.get(no, {}) as Dictionary).get("effect", {})
		if eff.is_empty() or not bool(eff.get("impl", false)):
			continue
		var ex: Dictionary = eff.get("explore", {})
		for k in out:
			out[k] = int(out[k]) + int(ex.get(k, 0))
	return out


## 배수로 쓰기 좋은 형태. 0% 면 1.0.
static func mult_of(bonus: Dictionary, key: String) -> float:
	return 1.0 + float(int(bonus.get(key, 0))) / 100.0


# ── 내부 ─────────────────────────────────────────────────────────────────────
static func _index(table: Dictionary) -> Dictionary:
	var out := {}
	for s in (table.get("skills", []) as Array):
		out[int((s as Dictionary).get("no", 0))] = s
	return out
