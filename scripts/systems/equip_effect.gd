# EquipEffect — 장비 조건부 효과의 **전투 반영**. 순수 로직(§8.1), 화면·에셋을 모른다.
#
# 표 = `data/equip_effects.json` (빌드: `scripts/tools/build_equip_effects.py`).
# 그 표는 위키 원문(`equipment.json` 의 전용 `effect` · 특수 `bonus`)을 기계가 읽는 형태로
# 옮긴 것이고, **설명 전체를 충족하는 것만 `impl: true`** 다 — 반쪽 발동은 안 하느니만 못하다.
# 조항이 여러 개인데 일부만 되는 경우에만 되는 조항을 걸고 `partial` 에 남은 조항을 적는다.
#
# ## 역할 분담 (각성 스킬과 완전히 같은 규약 — [[AwakenSkill]])
#
#     EquipEffect = **번역**. 표를 읽어 전투원에게 효과 항목(ops·react)을 심는다. 전투 시작 시 1회.
#     Battle      = **실행**. 심긴 항목을 라운드마다·사건마다 굴린다.
#
# 어휘도 그대로 재사용한다(`Battle.apply_effect_op` · `Battle.effect_cond_ok` · react) —
# 장비 전용 문법을 새로 만들지 않았다. 새로 문 훅은 셋뿐이다:
#   · `dmg_deal_vs_element`  특정 속성 상대에게만 걸리는 피해 배수
#   · `awaken_dmg`           각성기 전용 피해 배수
#   · react `do: skill_restore`  회피/크리 시 스킬 사용 횟수 회복
#
# ⚠️ Battle 을 참조하지만 Battle 은 이 파일을 부르지 않는다(preload 순환 방지 — AwakenSkill 과 동일).
class_name EquipEffect
extends RefCounted

## 효과 src 접두어. 각성스킬("awaken:")과 구분해 디버그·정화 규칙에서 갈라 볼 수 있게 한다.
const SRC := "equip:"


## 전투 시작 시 장비 효과를 파티에 반영한다. `allies` 를 직접 고친다(가변).
##
##   allies/enemies = Battle.make_combatant 결과 배열.
##                    각 원소의 `equip_keys`(장착 중인 카탈로그 키 배열)를 본다.
##   table          = data/equip_effects.json
##   ctx            = {field_element: String, enemy_boss: bool} — cond 판정용
##
## 반환 = 실제로 발동한 것 [{key, name, owner}] — render 가 배지·로그로 쓸 수 있다.
static func apply_battle(allies: Array, enemies: Array, table: Dictionary,
		ctx: Dictionary = {}) -> Array:
	var fired: Array = []
	# 반응 효과가 '아군 전체'를 대상으로 할 수 있어서 각 전투원이 자기 편 배열을 알아야 한다
	# (AwakenSkill 이 이미 심어 두지만, 장비만 쓰는 호출에서도 성립해야 한다).
	for c in allies:
		if not (c as Dictionary).has("_party"):
			(c as Dictionary)["_party"] = allies
	for c in enemies:
		if not (c as Dictionary).has("_party"):
			(c as Dictionary)["_party"] = enemies

	for owner in allies:
		for key in ((owner as Dictionary).get("equip_keys", []) as Array):
			var spec := rule_for(String(key), table)
			if spec.is_empty() or not bool(spec.get("impl", false)):
				continue
			if not Battle.effect_cond_ok(spec.get("cond", null), owner, allies, enemies, ctx):
				continue
			var any := false
			for o in (spec.get("ops", []) as Array):
				# `no` 는 각성스킬의 번호 자리다 — 장비는 번호가 없어 0 을 넣고 src 로 구분한다.
				if Battle.apply_effect_op(o as Dictionary, owner, allies, enemies, ctx, 0,
						1.0, SRC):
					any = true
			for r in (spec.get("react", []) as Array):
				# `plant: "ally"` = 반응을 **아군 전원에게 각자** 심는다("모든 대미지를 1로
				# 막아주는 보호막 1회 **전체** 적용" — 오울드라의 어둠갑옷). 각자 자기 몫의
				# 횟수(`left`)를 갖는다. 기본은 착용자 자신에게만.
				var plant: Array = allies if String((r as Dictionary).get("plant", "")) == "ally" 					else [owner]
				for who in plant:
					var re := (r as Dictionary).duplicate(true)
					re.erase("plant")
					re["kind"] = Battle.REACT
					re["no"] = 0
					re["turns"] = -1
					((who as Dictionary)["effects"] as Array).append(re)
				any = true
			# 동적 항목 — 여기서는 **심기만** 한다. 실제 계산은 라운드마다 Battle 이 한다
			# (상대 팀 체력 · 자신의 체력 비율처럼 전투 중에 변하는 조건).
			for d in (spec.get("dyn", []) as Array):
				var de := (d as Dictionary).duplicate(true)
				de["kind"] = "dyn"
				de["no"] = 0
				de["turns"] = -1
				((owner as Dictionary)["effects"] as Array).append(de)
				any = true
			if any:
				fired.append({"key": String(key), "name": _name_of(String(key)),
					"owner": String((owner as Dictionary).get("name", ""))})
	return fired


## 카탈로그 키 → 효과 표 항목. 없으면 {}.
##   "exclusive:<이름>"        → table.exclusive[<이름>]
##   "special:<계열>:<이름>"   → table.special["<계열>:<이름>"]
## 그 밖(일반·이벤트·아티팩트)은 조건부 효과가 없다 — 주 능력치로 이미 반영돼 있다.
static func rule_for(key: String, table: Dictionary) -> Dictionary:
	if key.begins_with("exclusive:"):
		return (table.get("exclusive", {}) as Dictionary).get(key.substr(10), {})
	if key.begins_with("special:"):
		return (table.get("special", {}) as Dictionary).get(key.substr(8), {})
	return {}


static func _name_of(key: String) -> String:
	var parts := key.split(":")
	return String(parts[parts.size() - 1])


## 그 장비가 전투에 반영되는가(= 표에 impl:true 로 있는가). 동굴·상태창 표시용.
static func implemented(key: String, table: Dictionary) -> bool:
	return bool(rule_for(key, table).get("impl", false))


## 사용자에게 보여 줄 반영 상태 문구. 반영되면 "" (원문만 보이면 된다).
## 미반영이면 왜 안 되는지, 일부만 되면 남은 조항을 돌려준다.
static func status_text(key: String, table: Dictionary) -> String:
	var spec := rule_for(key, table)
	if spec.is_empty():
		return ""
	if not bool(spec.get("impl", false)):
		var why := String(spec.get("why", ""))
		if why.begins_with("cut"):
			return "(오프라인 재구현에서 빠진 콘텐츠라 전투에 반영되지 않습니다)"
		if why.begins_with("skill:"):
			return "(해당 스킬이 아직 구현되지 않아 전투에 반영되지 않습니다)"
		return "(아직 전투에 반영되지 않습니다)"
	var partial := String(spec.get("partial", ""))
	return "(일부만 반영됩니다)" if partial != "" else ""


## 장착 슬롯 → 카탈로그 키 배열. `Battle.make_combatant` 에 넘길 `equip_keys` 를 만든다.
static func keys_of(equip_field: Dictionary) -> Array:
	var out: Array = []
	for s in (equip_field.get("slots", []) as Array):
		var k := String((s as Dictionary).get("key", ""))
		if k != "":
			out.append(k)
	return out
