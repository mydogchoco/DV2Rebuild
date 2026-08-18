class_name PartyStats
extends RefCounted

const PROB_STATS := ["cri", "evd", "blk"]

static func team_delta(party3: Array) -> Dictionary:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return {}
	return TeamBuff.typed_for_party(race_keys(party3), table)

static func race_keys(party: Array) -> Array:
	var out: Array = []
	for d in party:
		var ddef := Data.get_dragon(int((d as Dictionary).get("id", 0)))
		out.append(String(ddef.get("element", "")))
	return out

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

static func resolve(d: Dictionary, ddef: Dictionary, delta: Dictionary,
		kades: bool, field_element: String, stage_element := "") -> Dictionary:
	var base_bonus: Dictionary = (d.get("stat_bonus", {}) as Dictionary).get("base", {})
	var stats := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []), base_bonus)
	stats = Gem.apply(stats, d.get("gems", {}), Data.gems)
	stats = Equipment.apply(stats, d.get("equip", {}), Data.equipment)
	stats["artifact"] = Equipment.artifact_mods(d.get("equip", {}), Data.equipment, Data.skills)
	stats["equip_keys"] = EquipEffect.keys_of(d.get("equip", {}))
	var accb: Dictionary = d.get("accessory", {})
	for ak in ["cri", "evd", "blk"]:
		stats[ak] = int(stats.get(ak, 0)) + int(accb.get(ak, 0))
	stats = TeamBuff.apply(stats, delta)
	var drinks: Dictionary = d.get("drink_buffs", {})
	if not drinks.is_empty():
		for dk: String in ["att", "def", "hp", "crit", "dodge", "block"]:
			var sk: String = {"crit": "cri", "dodge": "evd", "block": "blk"}.get(dk, dk)
			if PROB_STATS.has(sk):
				stats[sk] = int(stats.get(sk, 0)) + ItemEffect.pct(drinks, dk)
				continue
			var m := ItemEffect.mult(drinks, dk)
			if is_equal_approx(m, 1.0):
				continue
			stats[sk] = int(round(float(int(stats.get(sk, 0))) * m))
	if kades:
		var pen := Kades.penalty_pct(Data.kades, bool(d.get("awakened", false)),
			String(ddef.get("element", "")), field_element)
		stats = Kades.apply_penalty(stats, pen)
	if stage_element != "" and String(ddef.get("element", "")) == stage_element:
		var sm := Colosseum.stage_mult()
		if not is_equal_approx(sm, 1.0):
			for sk: String in Colosseum.stage_stats():
				stats[sk] = int(round(float(int(stats.get(sk, 0))) * sm))
	var pcap := int((Data.combat.get("judge", {}) as Dictionary).get("pure_cap", 0))
	if pcap > 0 and int(stats.get("pure", 0)) > pcap:
		stats["pure"] = pcap
	var ov: Dictionary = d.get("stat_override", {})
	for k in ov:
		stats[k] = float(ov[k]) if PROB_STATS.has(String(k)) else int(round(float(ov[k])))
	var im: Dictionary = d.get("immune", {})
	if not im.is_empty():
		if im.has("skills"):
			stats["skill_immune"] = im["skills"]
		if bool(im.get("pure", false)):
			stats["immune_pure"] = true
		if bool(im.get("bonus", false)):
			stats["immune_bonus"] = true
	return stats

static func uses_drink(d: Dictionary) -> bool:
	return not (d.get("drink_buffs", {}) as Dictionary).is_empty()

static func summary(uids: Array, kades: bool, field_element: String,
		hp_state: Dictionary = {}, stage_element := "") -> Array:
	var ordered: Array = []
	for uid in uids:
		var d := UserDB.get_dragon(int(uid))
		if not d.is_empty():
			ordered.append(d)
	return summary_of(ordered, kades, field_element, hp_state, stage_element)

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
		var lvsum := 0
		var skills: Array = []
		var slot_types: Array = []
		var types: Array = Loadout.slot_types(d)
		for i in Loadout.SKILL_SLOTS:
			var e := Loadout.equipped_entry(d, i)
			if e.is_empty():
				continue
			lvsum += int(e.get("level", 1))
			skills.append(e)
			slot_types.append(String(types[i]) if i < types.size() else "star")
		var el := Icons.element_of(d)
		out.append({
			"id": int(d["id"]), "uid": int(d["uid"]), "level": int(d.get("level", 1)),
			"name": Icons.name_of(d),
			"art_id": Icons.art_id_of(d),
			"element": el,
			"stats": stats,
			"hp": clampi(hp0, 0, hpmax), "hp_max": hpmax,
			"awakened": bool(d.get("awakened", false)),
			"awaken_skill": int(d.get("awaken_skill", 0)) if bool(d.get("awakened", false)) else 0,
			"grade": float(d["grade_override"]) if d.has("grade_override") else
				Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
				d.get("gain_log", []), Data.level_curve.get("grade", {})),
			"atk_type": String(ddef.get("type", "")),
			"skill_level_sum": lvsum,
			"skills": skills, "skill_slots": slot_types,
			"stage_buff": stage_element != "" and el == stage_element,
		})
	return out

static func with_awaken(d: Dictionary, stats: Dictionary) -> Dictionary:
	var no := int(d.get("awaken_skill", 0))
	if not bool(d.get("awakened", false)) or no <= 0 or Data.skill_awaken.is_empty():
		return stats
	var ddef := Data.get_dragon(int(d.get("id", 0)))
	var st := stats.duplicate(true)
	st["awaken_no"] = no
	st["dragon_id"] = int(d.get("id", 0))
	st["atk_type"] = String(ddef.get("type", ""))
	st["grade"] = float(d["grade_override"]) if d.has("grade_override") else \
		Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))
	var lvsum := 0
	for i in Loadout.SKILL_SLOTS:
		var e := Loadout.equipped_entry(d, i)
		if not e.is_empty():
			lvsum += int(e.get("level", 1))
	st["skill_level_sum"] = lvsum
	var c := Battle.make_combatant("A0", "ally", Icons.element_of(d), st)
	var dummy := Battle.make_combatant("E0", "enemy", "", {"hp": 1, "att": 1, "def": 1})
	EquipEffect.awaken_mods([c], Data.equip_effects)
	AwakenSkill.apply_battle([c], [dummy], Data.skill_awaken, {})
	var out := stats.duplicate(true)
	out["hp"] = int(c["hp_max"])
	for k: String in ["att", "def"]:
		out[k] = Battle._eff(c, k)
	for k2: String in PROB_STATS:
		out[k2] = Battle._eff_f(c, k2)
	return out

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
		st["explore_gold_pct"] = int(ctx.get("explore_gold_pct", 0))
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
	EquipEffect.awaken_mods(pa, Data.equip_effects)
	var awoke := AwakenSkill.apply_battle(pa, [eb], Data.skill_awaken, ctx)
	var equipped := EquipEffect.apply_battle(pa, [eb], Data.equip_effects, ctx)
	for i in party.size():
		var c2: Dictionary = pa[i]
		var pd2: Dictionary = party[i]
		var old_max := int(pd2["hp_max"])
		var new_max := int(c2["hp_max"])
		if new_max != old_max:
			var ratio := float(pd2["hp"]) / maxf(1.0, float(old_max))
			pd2["hp_max"] = new_max
			pd2["hp"] = clampi(int(round(float(new_max) * ratio)), 1, new_max)
		pd2["awaken_effects"] = (c2["effects"] as Array).duplicate(true)
		pd2["awaken_gauge"] = float(c2.get("awaken_gauge", 0.0))
	return {"awaken_fired": awoke, "equip_fired": equipped}
