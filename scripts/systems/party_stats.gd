class_name PartyStats
extends RefCounted

## 출전 드래곤 1마리의 **표시·전투 공용 실 능력치** 파이프라인 (logic 계층 — §8.1).
##
## 왜 따로 뺐나: 원작은 탐험과 전투가 **같은 씬(AdventureScene)** 이라 하단 파티 카드가
## 배회→조우→전투→보상까지 하나의 위젯으로 이어진다(레퍼런스 `docs/ref/adventure/4_전투시작.png`
## · `전투4.png` · `승리9.png` 가 전부 같은 카드다). 우리는 adventure ↔ battle 을 두 씬으로
## 나눠 놨기 때문에, 카드 숫자를 **두 곳에서 따로 계산하면 반드시 어긋난다**
## (실제로 탐험 카드 884 / 전투 카드 1523 처럼 벌어진다). 그래서 순서까지 포함해
## 여기 한 곳에만 둔다.
##
## ⚠️ 이 모듈은 **render 를 모른다** — 노드·씬·스프라이트를 만들지 않고 숫자만 돌려준다(§8.3).
##
## 적용 순서는 `battle.gd::_setup_party` 의 원래 순서를 그대로 옮긴 것이며, 순서가 결과를
## 바꾸므로(젬 % → 장비 → 팀버프 배수 → 드링크 배수 → 카데스 감산) 임의로 바꾸지 말 것.

## 파티 전체 구성으로 1회 산출하는 속성 조합 팀버프 델타.
## race_dim=element 는 2026-07-31 확정(`CombineElementsLayer::combine` decomp :1341-1394 의
## switch 0=earth 1=aqua 2=fire 3=wind 4=light 5=dark 6=holy 7=chaos 8=shadow).
static func team_delta(party3: Array) -> Dictionary:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return {}
	return TeamBuff.typed_for_party(race_keys(party3), table)


## 파티 구성의 속성 키 3종(조합 연출·팀버프 공용).
static func race_keys(party: Array) -> Array:
	var out: Array = []
	for d in party:
		var ddef := Data.get_dragon(int((d as Dictionary).get("id", 0)))
		out.append(String(ddef.get("element", "")))
	return out


## 드래곤 1마리의 실 능력치.
##
## `d`      = UserDB 드래곤 레코드 · `ddef` = data/dragons.json 정의
## `delta`  = `team_delta()` 결과(파티 전체에서 1회 산출해 넘긴다)
## `kades`  = 카데스의 공간 여부 · `field_element` = 던전 속성(카데스 감산 판정용)
##
## 반환: stats Dictionary (hp/att/def/cri/evd/blk … + artifact · equip_keys)
static func resolve(d: Dictionary, ddef: Dictionary, delta: Dictionary,
		kades: bool, field_element: String) -> Dictionary:
	# 실 스탯 = base + 영구base보정 + Σ레벨업 롤(gain_log). §K-1(랜덤롤 모델).
	var base_bonus: Dictionary = (d.get("stat_bonus", {}) as Dictionary).get("base", {})
	var stats := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []), base_bonus)
	# 장착 젬(최대 3슬롯) — flat 가산 → % 배수 → 부가확률(cri/evd/blk).
	stats = Gem.apply(stats, d.get("gems", {}), Data.gems)
	# 장비(전체/전투형/보조형/아티팩트) + 편린 세트.
	stats = Equipment.apply(stats, d.get("equip", {}), Data.equipment)
	# 아티팩트는 스탯이 아니라 **스킬**을 건드린다 — 스킬 id 로 키를 잡은 수정치.
	stats["artifact"] = Equipment.artifact_mods(d.get("equip", {}), Data.equipment, Data.skills)
	# 전용·특수 장비의 조건부 효과는 장착 키만 실어 보내고 전투 시작 시 심는다.
	stats["equip_keys"] = EquipEffect.keys_of(d.get("equip", {}))
	# 구형 장신구 필드(accessories.json) — 장비 시스템 이전 세이브 호환.
	var accb: Dictionary = d.get("accessory", {})
	for ak in ["cri", "evd", "blk"]:
		stats[ak] = int(stats.get(ak, 0)) + int(accb.get(ak, 0))
	# 속성 조합 팀버프(위키 §2.3.3.1 30종) — hp/att/def=배수, cri/evd/blk=%p, pure=flat.
	stats = TeamBuff.apply(stats, delta)
	# 드링크(버프 물약) — **배율**로 곱한다. 값=data/item_effects.json.
	var drinks: Dictionary = d.get("drink_buffs", {})
	if not drinks.is_empty():
		for dk: String in ["att", "def", "hp", "crit", "dodge", "block"]:
			var m := ItemEffect.mult(drinks, dk)
			if is_equal_approx(m, 1.0):
				continue
			var sk: String = {"crit": "cri", "dodge": "evd", "block": "blk"}.get(dk, dk)
			stats[sk] = int(round(float(int(stats.get(sk, 0))) * m))
	# 카데스의 공간 — **미각성 드래곤만** 감산. 혼돈/신성 35% · 동일속성 25% · 그 외 50%.
	# 여기가 마지막이어야 한다 — 젬·장비·팀버프·드링크를 반영한 **합계**에 걸린다.
	if kades:
		var pen := Kades.penalty_pct(Data.kades, bool(d.get("awakened", false)),
			String(ddef.get("element", "")), field_element)
		stats = Kades.apply_penalty(stats, pen)
	return stats


## 드링크 버프를 실제로 쓴 드래곤인지(전투가 소모 처리에 쓴다).
static func uses_drink(d: Dictionary) -> bool:
	return not (d.get("drink_buffs", {}) as Dictionary).is_empty()


## 탐험 하단 파티 카드가 필요로 하는 **표시용** 요약을 파티 단위로 만든다.
##
## ⚠️ 전투 카드와의 알려진 차이 — 여기에는 `battle.gd::_apply_awaken_skills`(각성 스킬 상시
##   특성)가 **빠져 있다**. 그 단계는 `Battle.make_combatant` + 적 정보까지 필요해서 전투
##   컨텍스트 밖에서는 못 돌린다. 따라서 **체력을 올리는 각성 스킬(57 생명의 기운 등)을 가진
##   각성 드래곤은 탐험 카드의 최대 HP 가 전투 카드보다 낮게 나온다.**
##   TODO: `_apply_awaken_skills` 를 적 없이 돌 수 있게 분리하면 이 갭이 사라진다.
##   (그 외 젬·장비·팀버프·드링크·카데스는 위 `resolve` 를 전투와 **공유**하므로 어긋나지 않는다.)
static func summary(uids: Array, kades: bool, field_element: String,
		hp_state: Dictionary = {}) -> Array:
	var ordered: Array = []
	for uid in uids:
		var d := UserDB.get_dragon(int(uid))
		if not d.is_empty():
			ordered.append(d)
	var party3: Array = ordered.slice(0, 3)
	var delta := team_delta(party3)
	var out: Array = []
	for d: Dictionary in party3:
		var ddef := Data.get_dragon(int(d["id"]))
		var stats := resolve(d, ddef, delta, kades, field_element)
		var hpmax := int(stats.get("hp", 1))
		var hp0 := int(hp_state.get(str(int(d["uid"])), hpmax)) if not hp_state.is_empty() else hpmax
		out.append({
			"id": int(d["id"]), "uid": int(d["uid"]), "level": int(d.get("level", 1)),
			"name": Icons.name_of(d),
			"element": String(ddef.get("element", "")),
			"stats": stats,
			"hp": clampi(hp0, 0, hpmax), "hp_max": hpmax,
			"awakened": bool(d.get("awakened", false)),
		})
	return out
