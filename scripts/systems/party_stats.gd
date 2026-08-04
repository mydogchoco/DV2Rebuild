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

## 확률로 굴리는 스탯(%). 임의 스탯 지정에서 **소수점을 지켜야** 하는 것들이다 —
## 나머지 스탯은 정수다(체력 12345.6 같은 값은 뜻이 없다).
const PROB_STATS := ["cri", "evd", "blk"]

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


## 활성 팀버프 **이름** 목록 — `apply_passives` 의 조건 판정용
## (전용 장비 세로님의 전쟁보닛이 "팀버프 [흑풍]을 활성화한 경우" 로 이 값을 본다).
static func team_buff_names(uids: Array) -> Array:
	var party3: Array = []
	for uid in uids:
		var d := UserDB.get_dragon(int(uid))
		if not d.is_empty():
			party3.append(d)
		if party3.size() >= 3:
			break
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return []
	var out: Array = []
	for b in TeamBuff.active_buffs(race_keys(party3), table):
		out.append(String((b as Dictionary).get("name", "")))
	return out


## 드래곤 1마리의 실 능력치.
##
## `d`      = UserDB 드래곤 레코드 · `ddef` = data/dragons.json 정의
## `delta`  = `team_delta()` 결과(파티 전체에서 1회 산출해 넘긴다)
## `kades`  = 카데스의 공간 여부 · `field_element` = 던전 속성(카데스 감산 판정용)
##
## 반환: stats Dictionary (hp/att/def/cri/evd/blk … + artifact · equip_keys)
static func resolve(d: Dictionary, ddef: Dictionary, delta: Dictionary,
		kades: bool, field_element: String, stage_element := "") -> Dictionary:
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
	# 콜로세움 **무대 속성 보정** — 무대와 같은 속성의 드래곤만 +N%.
	#   원작 연출 = `MakeInterface::checkStageBuff` @0105f368 → `showStageBuff` @0105f4b8
	#   (양 진영 전원에 걸린다 — 내 팀 전용이 아니다). 클라는 **연출만** 하고 스탯을 안 건드리므로
	#   배수는 서버와 함께 유실 ⇒ 🟦 +10% 는 사용자 확정 2026-08-05(`data/colosseum.json` stage).
	#   `stage_element` 가 빈 문자열이면 아무 일도 없다 ⇒ 탐험 등 기존 호출부는 그대로다.
	#   카데스 감산 **뒤**에 온다: 무대 보정은 그 대결에서만 붙는 마지막 가산이다.
	if stage_element != "" and String(ddef.get("element", "")) == stage_element:
		var sm := Colosseum.stage_mult()
		if not is_equal_approx(sm, 1.0):
			for sk: String in Colosseum.stage_stats():
				stats[sk] = int(round(float(int(stats.get(sk, 0))) * sm))
	# 🟦 임의 스탯(레코드가 직접 들고 오는 값) — 콜로세움 **연승방지봇**처럼 도감·성장곡선과
	#   무관한 이벤트성 상대에 쓴다(출처 = docs/input/sheets/colosseum_guard.csv).
	#   여기가 마지막이어야 한다: 적힌 칸은 **젬·장비·팀버프·드링크를 다 계산한 뒤의 최종값**을
	#   그대로 대체한다. 적지 않은 칸은 위 계산 결과가 그대로 남는다.
	#   UserDB 드래곤에는 이 필드가 없다 — 플레이어 스탯 경로는 건드리지 않는다.
	#   ⚠️ 확률 스탯(크리/회피/막기)만 **소수점을 지킨다** — 시트가 `2.70%` 처럼 적을 수 있고
	#      전투 판정이 그 소수를 그대로 굴린다(`Battle._roll`). 나머지는 정수로 맞춘다.
	var ov: Dictionary = d.get("stat_override", {})
	for k in ov:
		stats[k] = float(ov[k]) if PROB_STATS.has(String(k)) else int(round(float(ov[k])))
	# 면역(연승방지봇의 이벤트 규칙) — 전투가 읽는 필드를 stats 에 얹어 그대로 흘려보낸다.
	#   {skills:[스킬id…] 로 받는 피해 0, pure: 관통 면역, bonus: 장비·각성 추가피해 면역}
	var im: Dictionary = d.get("immune", {})
	if not im.is_empty():
		if im.has("skills"):
			stats["skill_immune"] = im["skills"]
		if bool(im.get("pure", false)):
			stats["immune_pure"] = true
		if bool(im.get("bonus", false)):
			stats["immune_bonus"] = true
	return stats


## 드링크 버프를 실제로 쓴 드래곤인지(전투가 소모 처리에 쓴다).
static func uses_drink(d: Dictionary) -> bool:
	return not (d.get("drink_buffs", {}) as Dictionary).is_empty()


## 탐험 하단 파티 카드가 필요로 하는 **표시용** 요약을 파티 단위로 만든다.
##
## ✅ 2026-07-31 — 종전의 "각성 스킬이 빠진다" 갭은 해소됐다. `apply_passives()` 를 호출하면
##   각성 스킬·장비 조건부 효과까지 전투와 **같은 함수**로 얹힌다(호출은 선택 — 카드가 조우
##   전이라 적을 모르면 생략할 수 있다).
static func summary(uids: Array, kades: bool, field_element: String,
		hp_state: Dictionary = {}, stage_element := "") -> Array:
	var ordered: Array = []
	for uid in uids:
		var d := UserDB.get_dragon(int(uid))
		if not d.is_empty():
			ordered.append(d)
	return summary_of(ordered, kades, field_element, hp_state, stage_element)


## 같은 일을 **레코드 배열**로 한다 — 세이브에 없는 드래곤도 같은 경로를 타게 하려고 나눴다.
##
## 콜로세움 봇(`Colosseum.make_bot`)이 이 문으로 들어온다. 봇 전용 스탯 계산을 따로 만들면
## 플레이어와 밸런스가 어긋나므로, **레코드 모양만 같으면 같은 함수**가 처리한다.
## `summary(uids…)` 는 UserDB 에서 레코드를 꺼내 이걸 부르는 얇은 껍데기다.
## `stage_element` = 콜로세움 무대 속성(빈 문자열이면 보정 없음 — 탐험 경로가 이 값을 안 쓴다).
static func summary_of(records: Array, kades: bool, field_element: String,
		hp_state: Dictionary = {}, stage_element := "") -> Array:
	var party3: Array = records.slice(0, 3)
	var delta := team_delta(party3)
	var out: Array = []
	for d: Dictionary in party3:
		var ddef := Data.get_dragon(int(d["id"]))
		var stats := resolve(d, ddef, delta, kades, field_element, stage_element)
		var hpmax := int(stats.get("hp", 1))
		var hp0 := int(hp_state.get(str(int(d["uid"])), hpmax)) if not hp_state.is_empty() else hpmax
		# 각성 스킬·장비 조건부 효과(`apply_passives`)가 읽는 필드들도 같이 채운다 —
		# 전투(`battle.gd::_apply_awaken_skills`)가 쓰는 것과 같은 이름·같은 출처.
		# ⚠️ UserDB 를 거치지 않는다 — 레코드가 들고 있는 장착 정보로 직접 센다(봇 호환).
		var lvsum := 0
		for i in Loadout.SKILL_SLOTS:
			var e := Loadout.equipped_entry(d, i)
			if not e.is_empty():
				lvsum += int(e.get("level", 1))
		out.append({
			"id": int(d["id"]), "uid": int(d["uid"]), "level": int(d.get("level", 1)),
			"name": Icons.name_of(d),
			"element": String(ddef.get("element", "")),
			"stats": stats,
			"hp": clampi(hp0, 0, hpmax), "hp_max": hpmax,
			"awakened": bool(d.get("awakened", false)),
			"awaken_skill": int(d.get("awaken_skill", 0)) if bool(d.get("awakened", false)) else 0,
			# 등급도 시트가 지정하면 그 값(임의 스탯이면 계산 등급이 뜻을 잃는다).
			"grade": float(d["grade_override"]) if d.has("grade_override") else
				Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
				d.get("gain_log", []), Data.level_curve.get("grade", {})),
			"atk_type": String(ddef.get("type", "")),
			"skill_level_sum": lvsum,
			# 무대 속성 일치 여부 — render 가 버프 스파인을 붙일 대상 판정에 그대로 쓴다
			# (원작 `checkStageBuff` 의 `getRace(d) == 무대종족` 과 같은 조건).
			"stage_buff": stage_element != "" and String(ddef.get("element", "")) == stage_element,
		})
	return out


## 각성 스킬(상시 특성) + 장비 조건부 효과를 파티에 얹는다 — **전투와 탐험 카드 공용**.
##
## 원작에는 이런 분리가 없다(탐험·전투가 한 씬). 우리가 씬을 나눴기 때문에, 이 단계를
## `battle.gd` 안에만 두면 탐험 카드가 **체력을 올리는 각성 스킬**(57 생명의 기운 등)을
## 반영하지 못해 전투 카드와 최대 HP 가 달라진다. 그래서 여기(logic)로 뺐다.
##
## `party` 를 **제자리에서 수정**한다 — `hp_max`/`hp`(비율 유지) · `awaken_effects` · `awaken_gauge`.
## 반환 = `{"awaken_fired": [...], "equip_fired": [...]}`(연출용 발동 목록).
##
## `enemy` = `{element, hp}` — 원작도 이 단계에서 적은 **더미 전투원**으로만 쓴다
## (`att`/`def` 는 1 고정). 탐험 카드는 **다음 조우 몬스터**를 넣어 전투와 같은 결과를 낸다.
## `ctx` = `{field_element, enemy_boss, team_buffs(이름 배열), explore_gold_pct}`.
static func apply_passives(party: Array, enemy: Dictionary, ctx: Dictionary) -> Dictionary:
	var empty := {"awaken_fired": [], "equip_fired": []}
	if party.is_empty() or Data.skill_awaken.is_empty():
		return empty
	var pa: Array = []
	for i in party.size():
		var pd: Dictionary = party[i]
		var st: Dictionary = (pd["stats"] as Dictionary).duplicate()
		st["awaken_no"] = int(pd.get("awaken_skill", 0))
		st["grade"] = float(pd.get("grade", 0.0))
		st["dragon_id"] = int(pd.get("id", 0))
		st["atk_type"] = String(pd.get("atk_type", ""))
		# 전용 장비 다크프로스티의 무늬 — 탐험 골드 증가량만큼 자신의 공격력% 증가.
		st["explore_gold_pct"] = int(ctx.get("explore_gold_pct", 0))
		# 전용 장비 불나래의 불꽃구슬 — 장착 스킬 레벨 합.
		# 전투 파티는 `skills`(전체 스킬 레코드)를 들고 오고, 탐험 카드(`summary`)는 이미
		# 합산해 둔 `skill_level_sum` 만 들고 온다 — 둘 다 받는다.
		var lvsum := int(pd.get("skill_level_sum", 0))
		if pd.has("skills"):
			lvsum = 0
			for sd in (pd.get("skills", []) as Array):
				lvsum += int((sd as Dictionary).get("level", 1))
		st["skill_level_sum"] = lvsum
		var c := Battle.make_combatant("A%d" % i, "ally", String(pd["element"]), st)
		c["hp_max"] = int(pd["hp_max"]); c["hp"] = int(pd["hp"])
		pa.append(c)
	var eb := Battle.make_combatant("E0", "enemy", String(enemy.get("element", "")),
		{"hp": int(enemy.get("hp", 1)), "att": 1, "def": 1})
	# ⚠️ 순서가 중요하다 — 장비의 **각성스킬 수정자**를 먼저 찍어야 각성스킬이 그 값으로 심는다.
	EquipEffect.awaken_mods(pa, Data.equip_effects)
	var awoke := AwakenSkill.apply_battle(pa, [eb], Data.skill_awaken, ctx)
	var equipped := EquipEffect.apply_battle(pa, [eb], Data.equip_effects, ctx)
	# 결과를 파티로 되돌린다 — 체력은 값으로, 나머지는 효과 목록으로.
	for i in party.size():
		var c2: Dictionary = pa[i]
		var pd2: Dictionary = party[i]
		var old_max := int(pd2["hp_max"])
		var new_max := int(c2["hp_max"])
		if new_max != old_max:
			# 조우 간 이월 체력이 있으면 비율을 지킨다(1조우째면 어차피 만피).
			var ratio := float(pd2["hp"]) / maxf(1.0, float(old_max))
			pd2["hp_max"] = new_max
			pd2["hp"] = clampi(int(round(float(new_max) * ratio)), 1, new_max)
		pd2["awaken_effects"] = (c2["effects"] as Array).duplicate(true)
		pd2["awaken_gauge"] = float(c2.get("awaken_gauge", 0.0))
	return {"awaken_fired": awoke, "equip_fired": equipped}
