class_name Battle

const DEFAULT_PROC := 20.0
const LOW_HP_PROC := 66.0

static func make_combatant(name: String, side: String, element: String, stats: Dictionary, pen := 0.0, skills: Array = [], skill_slots: Array = []) -> Dictionary:
	var norm: Array = []
	var lv_sum := 0
	for s in skills:
		var sc: Dictionary = (s as Dictionary).duplicate()
		sc["id"] = int(s.get("id", 0))
		sc["level"] = int(s.get("level", 1))
		lv_sum += int(sc["level"])
		norm.append(sc)
	return {
		"name": name, "side": side, "element": element,
		"hp_max": int(stats.get("hp", 1)), "hp": int(stats.get("hp", 1)),
		"hp_base": int(stats.get("hp", 1)),
		"att": int(stats.get("att", 1)), "def": int(stats.get("def", 1)),
		"cri": float(stats.get("cri", 10)), "evd": float(stats.get("evd", 10)),
		"blk": float(stats.get("blk", 10)),
		"skill_immune": _int_ids(stats.get("skill_immune", [])),
		"immune_pure": bool(stats.get("immune_pure", false)),
		"immune_bonus": bool(stats.get("immune_bonus", false)),
		"pure": int(stats.get("pure", 0)), "depure": int(stats.get("depure", 0)),
		"cri_pow": int(stats.get("cri_pow", 0)), "accuracy": int(stats.get("accuracy", 0)),
		"cure": int(stats.get("cure", 0)),
		"pen": pen, "alive": true,
		"awaken_no": int(stats.get("awaken_no", 0)),
		"dragon_id": int(stats.get("dragon_id", 0)),
		"grade": float(stats.get("grade", 0.0)),
		"atk_type": String(stats.get("atk_type", "")),
		"explore_gold_pct": int(stats.get("explore_gold_pct", 0)),
		"skill_level_sum": int(stats.get("skill_level_sum", lv_sum)),
		"skills": norm, "skill_uses": {}, "effects": [],
		"equip_keys": (stats.get("equip_keys", []) as Array),
		"skill_slots": skill_slots,
	"artifact": (stats.get("artifact", {}) as Dictionary),
	}

static func _eff(c: Dictionary, stat: String) -> int:
	return int(round(_eff_f(c, stat)))

static func _eff_f(c: Dictionary, stat: String) -> float:
	var base := float(c.get(stat, 0))
	var pct := 0.0
	var flat := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "stat" and e.get("stat") == stat:
			if e.get("mode") == "pct": pct += float(e["value"])
			else: flat += float(e["value"])
	return base * (1.0 + pct / 100.0) + flat

static func _has_flag(c: Dictionary, flag: String) -> bool:
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			return true
	return false

static func _flag_source(c: Dictionary, flag: String) -> int:
	for e in c.get("effects", []):
		if e.get("kind") == "status" and e.get("flag") == flag:
			return int(e.get("source", 0))
	return 0

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

static func _stack_count(c: Dictionary, src: int) -> int:
	var n := 0
	for e in (c.get("effects", []) as Array):
		if int((e as Dictionary).get("source", 0)) == src:
			n += 1
	return n

static func _dmg_taken_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_taken":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

static func _dmg_deal_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_deal":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

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

static func _awaken_dmg_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if (e as Dictionary).get("kind") == "awaken_dmg":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

static func _crit_pen_pct(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "crit_pen":
			pct += float((e as Dictionary).get("pct", 0.0))
	return pct

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

static func _awaken_taken_cap(c: Dictionary) -> int:
	var cap := 0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "awaken_dmg_cap":
			var v := int((e as Dictionary).get("value", 0))
			if v > 0 and (cap == 0 or v < cap):
				cap = v
	return cap

static func _skill_dmg_taken_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "skill_dmg_taken":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

static func _dmg_taken_flat(c: Dictionary) -> float:
	var v := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_taken_flat":
			v += float(e["value"])
	return v

static func _dmg_taken_floor(c: Dictionary) -> int:
	var v := 0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "dmg_taken_flat":
			v = maxi(v, int((e as Dictionary).get("min_dmg", 0)))
	return v

static func _gauge_ref(c: Dictionary) -> Dictionary:
	var r = c.get("gauge_ref", null)
	if r is Dictionary:
		return r
	var solo := {"v": float(c.get("awaken_gauge", 0.0))}
	c["gauge_ref"] = solo
	return solo

static func gauge_of(c: Dictionary) -> float:
	return float(_gauge_ref(c)["v"])

static func _gauge_set(c: Dictionary, v: float) -> void:
	_gauge_ref(c)["v"] = v
	c["awaken_gauge"] = v

static func _gauge_bump(c: Dictionary, delta: float, cap99 := true) -> void:
	var v := gauge_of(c) + delta
	if cap99:
		v = minf(99.0, v)
	_gauge_set(c, maxf(0.0, v))

static func _bind_side_gauge(party: Array) -> Dictionary:
	var start := 0.0
	for c in party:
		start = maxf(start, float((c as Dictionary).get("awaken_gauge", 0.0)))
	var ref := {"v": start}
	for c in party:
		(c as Dictionary)["gauge_ref"] = ref
		(c as Dictionary)["awaken_gauge"] = start
	return ref

static func _side_gauge(party: Array) -> float:
	return gauge_of(party[0]) if not party.is_empty() else 0.0

static func _gauge_min_side(party: Array) -> float:
	var v := 0.0
	for c in party:
		if bool((c as Dictionary).get("alive", true)):
			v = maxf(v, _gauge_min(c))
	return v

static func _awaken_caster(party: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_att := -1
	for c in party:
		var cd := c as Dictionary
		if not bool(cd.get("alive", false)):
			continue
		var a := _eff(cd, "att")
		if a > best_att:
			best_att = a
			best = cd
	return best

static func _charge_on_hits(evs: Array, party_a: Array, party_b: Array, cfg: Dictionary) -> void:
	var per := float(cfg.get("awaken", {}).get("charge_per_hit", 0.0))
	if per <= 0.0:
		return
	for e in evs:
		var ev := e as Dictionary
		if int(ev.get("damage", 0)) <= 0:
			continue
		if String(ev.get("type", "")) == "awaken" and int(ev.get("hit", 0)) != 0:
			continue
		var dn := String(ev.get("defender", ""))
		if dn == "":
			continue
		var v := _find_by_name(party_a, dn)
		if v.is_empty():
			v = _find_by_name(party_b, dn)
		if not v.is_empty():
			_gauge_bump(v, per * _gauge_rate(v), false)

static func _find_by_name(party: Array, nm: String) -> Dictionary:
	for c in party:
		if String((c as Dictionary).get("name", "")) == nm:
			return c
	return {}

static func _gauge_rate(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "gauge_rate":
			pct += float(e["pct"])
	return maxf(0.0, 1.0 + pct / 100.0)

static func _gauge_min(c: Dictionary) -> float:
	var v := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "gauge_min":
			v = maxf(v, float(e["value"]))
	return clampf(v, 0.0, 99.0)

static func _skill_uses_bonus(c: Dictionary) -> int:
	var v := 0
	for e in c.get("effects", []):
		if e.get("kind") == "skill_uses":
			v += int(e["value"])
	return v + _art_hidden(c, "skill_uses")

static func _skill_level_bonus(c: Dictionary) -> int:
	var v := 0
	for e in c.get("effects", []):
		if e.get("kind") == "skill_level":
			v += int(e["value"])
	return v + int(c.get("_proc_level_bonus", 0))

static func _lv(c: Dictionary, s: Dictionary) -> int:
	return maxi(1, int(s["level"]) + _skill_level_bonus(c) + _art(c, "power_lv", int(s["id"]))
		+ int((c.get("_slot_lv", {}) as Dictionary).get(int(s["id"]), 0)))

static func _dmg_cap_pct(c: Dictionary) -> float:
	var best := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "dmg_cap_pct":
			var v := float(e["pct"])
			if v > 0.0 and (best <= 0.0 or v < best):
				best = v
	return best

static func _lifesteal_pct(c: Dictionary) -> float:
	var pct := 0.0
	for e in c.get("effects", []):
		if e.get("kind") == "lifesteal":
			pct += float(e["pct"])
	return pct

static func _apply_lifesteal(c: Dictionary) -> int:
	var pct := _lifesteal_pct(c)
	if pct <= 0.0 or not bool(c.get("alive", false)):
		return 0
	var before := int(c.get("hp", 0))
	var heal := maxi(0, int(round(float(_eff(c, "att")) * pct / 100.0)))
	c["hp"] = mini(int(c.get("hp_max", before)), before + heal)
	return maxi(0, int(c["hp"]) - before)

static func _is_debuff(e: Dictionary) -> bool:
	if _is_innate(e):
		return false
	var k := String(e.get("kind", ""))
	if k == "status":
		return String(e.get("flag", "")) in DEBUFF_FLAGS
	if k == "dot" or k == "timed":
		return true
	if k == "dmg_taken":
		return float(e.get("pct", 0)) > 0.0
	return k == "stat" and float(e.get("value", 0)) < 0

static func _is_innate(e: Dictionary) -> bool:
	return not e.has("source") and e.has("src")

static func _has_any_debuff(c: Dictionary) -> bool:
	for e in c.get("effects", []):
		if _is_debuff(e as Dictionary):
			return true
	return false

static func _any_debuffed(allies: Array) -> bool:
	for a in allies:
		var c := a as Dictionary
		if bool(c.get("alive", true)) and _has_any_debuff(c):
			return true
	return false

static func _cleanse(c: Dictionary) -> void:
	var keep: Array = []
	for e in c.get("effects", []):
		if not _is_debuff(e as Dictionary):
			keep.append(e)
	c["effects"] = keep

static func _add_stat(c: Dictionary, stat: String, mode: String, value: float, turns: int, src: int) -> void:
	if value < 0.0 and _has_flag(c, IMMUNE_FLAG):
		return
	c["effects"].append({"kind": "stat", "stat": stat, "mode": mode, "value": value, "turns": turns, "source": src})

static func _immune(c: Dictionary) -> bool:
	return _has_flag(c, IMMUNE_FLAG)

static func _add_flag(c: Dictionary, flag: String, turns: int, src: int) -> void:
	if flag in DEBUFF_FLAGS and _has_flag(c, IMMUNE_FLAG):
		return
	c["effects"].append({"kind": "status", "flag": flag, "turns": turns, "source": src})

static func _mark_immune(ev: Dictionary, target: Dictionary) -> Dictionary:
	if _has_flag(target, IMMUNE_FLAG):
		ev["immune"] = true
		ev.erase("debuff")
	return ev

const IMMUNE_FLAG := "status_immune"

const DEBUFF_FLAGS := ["stun", "confused", "no_evade", "no_block", "no_crit"]

static func element_mult(att_el: String, def_el: String, cfg: Dictionary) -> float:
	var e: Dictionary = cfg.get("element", {})
	if def_el in e.get("good_vs", {}).get(att_el, []):
		return float(e.get("good_mult", 1.25))
	if def_el in e.get("bad_vs", {}).get(att_el, []):
		return float(e.get("bad_mult", 0.85))
	return float(e.get("neutral_mult", 1.0))

static func hero_stat_multipliers(stage: Dictionary, variant_rules: Dictionary) -> Dictionary:
	var raw: Variant = stage.get("hero_stat_mult", variant_rules.get("hero_stat_mult", 1.0))
	if raw is Dictionary:
		var src := raw as Dictionary
		return {
			"hp": maxf(0.0, float(src.get("hp", 1.0))),
			"att": maxf(0.0, float(src.get("att", 1.0))),
			"def": maxf(0.0, float(src.get("def", 1.0))),
		}
	var common := maxf(0.0, float(raw))
	return {"hp": common, "att": common, "def": common}

static func damage(att: int, def: int, pen: float, elem_mult: float, crit_mult: float, rand_factor: float, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	var def_eff := maxf(1.0, float(def) * (1.0 - clampf(pen, 0.0, 1.0)))
	var attack_scale := maxf(0.0, float(d.get("attack_scale", 1.0)))
	var pivot := maxf(1.0, float(d.get("stat_pivot", 100.0)))
	var defense_exponent := maxf(0.01, float(d.get("defense_exponent", 1.0)))
	var guard_exponent := maxf(0.0, float(d.get("guard_exponent", 0.0)))
	var attack := maxf(1.0, float(att))
	var defense_factor := pow(pivot / (pivot + def_eff), defense_exponent)
	if def_eff > attack and guard_exponent > 0.0:
		var guard_strength := clampf(def_eff / pivot - 2.5, 0.0, 1.0)
		defense_factor *= pow(attack / def_eff, guard_exponent * guard_strength)
	var raw := attack_scale * attack * defense_factor \
		* elem_mult * crit_mult * rand_factor
	return maxi(1, int(round(raw)))

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

static func _roll(rng: RandomNumberGenerator, percent: float, cap: int) -> bool:
	return rng.randf() * 100.0 < clampf(percent, 0.0, float(cap))

static func _evade_chance(attacker: Dictionary, defender: Dictionary, cap: int) -> float:
	return maxf(0.0, clampf(_eff_f(defender, "evd"), 0.0, float(cap))
		- float(_eff(attacker, "accuracy")))

static func _block_chance(defender: Dictionary, cap: int) -> float:
	return clampf(_eff_f(defender, "blk"), 0.0, float(cap))

static func _phase_taken_mult(c: Dictionary) -> float:
	if int(c.get("phase", 1)) < 2:
		return 1.0
	return maxf(0.0, float(c.get("phase2_taken_mult", 1.0)))

static func _enter_phase2_if_needed(c: Dictionary) -> bool:
	var th := float(c.get("phase2_at", 0.0))
	if th <= 0.0 or int(c.get("phase", 1)) >= 2 or not bool(c.get("alive", true)):
		return false
	var hp_max := maxf(1.0, float(c.get("hp_max", 1)))
	if float(c.get("hp", 0)) / hp_max > th:
		return false
	c["phase"] = 2
	return true

static func _apply_dmg(defender: Dictionary, dmg: int, hit_cap_pct := 0.0) -> Dictionary:
	var scaled := float(dmg) * _dmg_taken_mult(defender) * _phase_taken_mult(defender)
	var f := maxi(1, int(round(scaled - _dmg_taken_flat(defender))))
	var floor_v := _dmg_taken_floor(defender)
	if floor_v > 0 and f < floor_v:
		f = mini(floor_v, maxi(1, int(round(scaled))))
	f = _aw_fix_damage(defender, f)
	var cap_pct := _dmg_cap_pct(defender)
	if cap_pct > 0.0:
		f = mini(f, maxi(1, int(round(float(defender["hp_max"]) * cap_pct / 100.0))))
	if hit_cap_pct > 0.0:
		f = mini(f, maxi(1, int(floor(float(defender["hp_max"]) * hit_cap_pct / 100.0))))
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

static func _crit_mult(attacker: Dictionary, cfg: Dictionary) -> float:
	var base := float(cfg.get("damage", {}).get("crit_mult", 1.5))
	return 1.0 + (base - 1.0) * (1.0 + float(_eff(attacker, "cri_pow")) / 100.0)

static func _int_ids(raw) -> Array:
	var out: Array = []
	for i in (raw as Array):
		out.append(int(i))
	return out

static func _skill_immune(c: Dictionary, skill_id: int) -> bool:
	if skill_id <= 0:
		return false
	for i in (c.get("skill_immune", []) as Array):
		if int(i) == skill_id:
			return true
	return false

static func _pure_damage(attacker: Dictionary, defender: Dictionary) -> int:
	if bool(defender.get("immune_pure", false)):
		return 0
	var p := float(_eff(attacker, "pure")) * (1.0 + float(_eff(attacker, "pure_pct")) / 100.0)
	var net := maxf(0.0, p - float(_eff(defender, "depure")))
	net *= maxf(0.0, 1.0 - float(_eff(defender, "depure_pct")) / 100.0)
	return maxi(0, int(round(net)))

static func _hit_damage(attacker: Dictionary, defender: Dictionary, crit: bool, block: bool, rng: RandomNumberGenerator, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	var em := float(cfg.get("element", {}).get("good_mult", 1.25)) 		if _has_flag(attacker, "elem_advantage") 		else element_mult(String(attacker["element"]), String(defender["element"]), cfg)
	var crit_mult := _crit_mult(attacker, cfg) if crit else 1.0
	var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
	var pen := float(attacker["pen"])
	if crit:
		pen = clampf(pen + _crit_pen_pct(attacker) / 100.0, 0.0, 0.95)
	var dmg := damage(_eff(attacker, "att"), _eff(defender, "def"), pen, em, crit_mult, rf, cfg)
	if block:
		var red := float(cfg.get("judge", {}).get("block_reduction", 0.5))
		dmg = maxi(1, int(round(float(dmg) * (1.0 - red))))
	return dmg + _pure_damage(attacker, defender)

static func _deal_attack(attacker: Dictionary, defender: Dictionary, raw_dmg: int, is_skill: bool, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary, hit_cap_pct := 0.0) -> Dictionary:
	raw_dmg = maxi(1, int(round(float(raw_dmg) * _dmg_deal_mult(attacker)
		* _dmg_deal_vs_mult(attacker, defender))))
	if is_skill and _skill_immune(defender, int(attacker.get("_cast_skill_id", 0))):
		return {"damage": 0, "dead": false, "immune": true}
	var bonus := _aw_on_attack_bonus(attacker, defender, rng, raw_dmg)
	raw_dmg += 0 if bool(defender.get("immune_bonus", false)) else bonus
	if is_skill:
		var bcap := int(cfg.get("judge", {}).get("prob_cap", 70))
		if not _has_flag(attacker, "skill_ignores_block") 				and not _has_flag(defender, "no_block") 				and _roll(rng, _block_chance(defender, bcap), bcap):
			var bred := float(cfg.get("judge", {}).get("block_reduction", 0.5))
			raw_dmg = maxi(1, int(round(float(raw_dmg) * (1.0 - bred))))
			_aw_on_block(defender, rng)
		var sdm := _skill_dmg_deal_mult(attacker)
		if not is_equal_approx(sdm, 1.0):
			raw_dmg = maxi(1, int(round(float(raw_dmg) * sdm)))
		var ded := _art(defender, "skill_dmg_taken_pct", int(attacker.get("_cast_skill_id", 0)))
		if ded > 0:
			raw_dmg = maxi(1, int(round(float(raw_dmg) * (1.0 - float(ded) / 100.0))))
		var sm := _skill_dmg_taken_mult(defender)
		if not is_equal_approx(sm, 1.0):
			raw_dmg = maxi(1, int(round(float(raw_dmg) * sm)))
	var dres := _defense_skill_onhit(defender, rng, raw_dmg, is_skill, cfg, skills_db)
	var ap := _apply_dmg(defender, int(dres["dmg"]), hit_cap_pct)
	var out := {"damage": int(ap["dmg"]), "dead": bool(ap["dead"])}
	if ap.has("phase2"):
		out["phase2"] = true
	_aw_on_hit_taken(defender, attacker, int(ap["dmg"]), rng)
	if bool(ap["dead"]):
		_aw_on_death(defender)
	if ap.has("survived"):
		out["survived"] = true
	if String(dres["fired"]) != "":
		out["def_skill"] = dres["fired"]
		out["def_skill_id"] = int(dres.get("fired_id", 0))
	var refl := int(dres.get("reflect", 0))
	if refl > 0 and _skill_immune(attacker, int(dres.get("fired_id", 0))):
		refl = 0
		out["reflect_immune"] = true
	if refl > 0 and attacker["alive"]:
		var rap := _apply_dmg(attacker, refl)
		out["reflect"] = int(rap["dmg"])
		out["reflect_dead"] = bool(rap["dead"])
	return out

static func _roll_crit(attacker: Dictionary, defender: Dictionary,
		rng: RandomNumberGenerator, cap: int, crit_cap: int) -> bool:
	if _has_flag(attacker, "no_crit"):
		return false
	if _has_flag(attacker, "crit_sure"):
		return true
	if _has_flag(attacker, "crit_sure_if_no_evade") 			and _evade_chance(attacker, defender, cap) <= 0:
		return true
	return _roll(rng, _eff_f(attacker, "cri"), crit_cap)

static func _crit_cap(cfg: Dictionary) -> int:
	var j: Dictionary = cfg.get("judge", {})
	return int(j.get("crit_cap", j.get("prob_cap", 70)))

static func resolve_attack(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}) -> Dictionary:
	var cap := int(cfg.get("judge", {}).get("prob_cap", 70))
	var ccap := _crit_cap(cfg)
	var ev := {"type": "normal", "attacker": attacker["name"], "defender": defender["name"],
		"miss": false, "block": false, "crit": false, "damage": 0, "dead": false}
	var pre_crit := -1
	var halve := _has_flag(attacker, "crit_halves_guard")
	if _has_flag(attacker, "crit_ignores_evade") or halve:
		pre_crit = 1 if _roll_crit(attacker, defender, rng, cap, ccap) else 0
	var sure_evade := _has_flag(defender, "evade_sure")
	var evd_pct := _evade_chance(attacker, defender, cap)
	var blk_pct := _block_chance(defender, cap)
	if pre_crit == 1 and halve:
		evd_pct = evd_pct / 2.0
		blk_pct = blk_pct / 2.0
	var skip_evade := pre_crit == 1 and _has_flag(attacker, "crit_ignores_evade")
	if not skip_evade and (sure_evade or (not _has_flag(defender, "no_evade") 			and _roll(rng, evd_pct, cap))):
		if sure_evade:
			_remove_flag(defender, "evade_sure")
		ev["miss"] = true
		_aw_on_evade(defender, attacker, rng)
		return ev
	var block := (not _has_flag(defender, "no_block")) and _roll(rng, blk_pct, cap)
	if block:
		_aw_on_block(defender, rng)
	var crit := (pre_crit == 1) if pre_crit >= 0 else _roll_crit(attacker, defender, rng, cap, ccap)
	ev["block"] = block
	ev["crit"] = crit
	var dmg := _hit_damage(attacker, defender, crit, block, rng, cfg)
	if crit:
		dmg += _aw_on_crit_bonus(attacker, defender)
	if not block:
		_aw_on_hit_unguarded(defender, attacker, rng)
	var res := _deal_attack(attacker, defender, dmg, false, rng, cfg, skills_db)
	_aw_on_attack_done(attacker, defender, rng, int(res.get("damage", 0)))
	for k in res:
		ev[k] = res[k]
	if not ev["miss"]:
		var heal := _apply_lifesteal(attacker)
		if heal > 0:
			ev["lifesteal"] = heal
	return ev

static func _skill_level(c: Dictionary, id: int) -> int:
	for s in c.get("skills", []):
		if int(s["id"]) == id:
			return int(s["level"])
	return 1

static func resolve_double(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}) -> Array:
	var cap := int(cfg.get("judge", {}).get("prob_cap", 70))
	var ccap := _crit_cap(cfg)
	if not skills_db.is_empty() and _uses_left(defender, 28) > 0:
		var sd28: Dictionary = skills_db.get("28", {})
		if not sd28.is_empty() and rng.randf() * 100.0 < _proc_pct(defender, sd28, _skill_level(defender, 28), cfg):
			_use(defender, 28)
			return [_merge(_double_ev(attacker, defender, 0, false, false, false, 0, false), {"def_skill": "교차막기"}),
					_merge(_double_ev(attacker, defender, 1, false, false, false, 0, false), {"def_skill": "교차막기"})]
	if not _has_flag(defender, "no_evade") and _roll(rng, _evade_chance(attacker, defender, cap), cap):
		return [_double_ev(attacker, defender, 0, true, false, false, 0, false),
				_double_ev(attacker, defender, 1, true, false, false, 0, false)]
	var block := (not _has_flag(defender, "no_block")) and _roll(rng, _block_chance(defender, cap), cap)
	var out: Array = []
	var dealt := 0
	for i in 2:
		if not defender["alive"]:
			break
		var crit := _roll_crit(attacker, defender, rng, cap, ccap)
		var dmg := _hit_damage(attacker, defender, crit, block, rng, cfg)
		dmg = maxi(1, int(round(float(dmg) * _double_dmg_mult(attacker))))
		var ap := _apply_dmg(defender, dmg)
		dealt += int(ap["dmg"])
		out.append(_double_ev(attacker, defender, i, false, block, crit, int(ap["dmg"]), bool(ap["dead"])))
	_aw_on_double(attacker, dealt)
	var heal := _apply_lifesteal(attacker)
	if heal > 0 and not out.is_empty():
		(out[out.size() - 1] as Dictionary)["lifesteal"] = heal
	return out

static func _double_dmg_mult(c: Dictionary) -> float:
	var pct := 0.0
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("kind", "")) == "double_dmg":
			pct += float((e as Dictionary).get("pct", 0.0))
	return maxf(0.0, 1.0 + pct / 100.0)

static func _double_ev(a: Dictionary, d: Dictionary, hit: int, miss: bool, block: bool, crit: bool, dmg: int, dead: bool) -> Dictionary:
	return {"type": "double", "hit": hit, "attacker": a["name"], "defender": d["name"],
		"miss": miss, "block": block, "crit": crit, "damage": dmg, "dead": dead}

static func _awaken_split(total: int, element: String, rng: RandomNumberGenerator, cfg: Dictionary) -> Array:
	var tbl: Dictionary = cfg.get("awaken", {}).get("hits_by_element", {})
	var spec: Dictionary = tbl.get(element, {})
	var out: Array = []
	var left := maxi(0, total)
	for st in (spec.get("steps", []) as Array):
		var d := st as Dictionary
		var min_total := int(d.get("min_total", 0))
		for _i in int(d.get("n", 0)):
			var part := 0
			if left > 0 and total >= min_total:
				if d.has("flat"):
					part = int(d["flat"])
				else:
					part = total / maxi(1, int(d.get("div", 1)))
					var jd := int(d.get("jitter", 0))
					if jd > 0:
						var m := total / jd - 1
						if m > 0:
							part += (rng.randi() % m) - (rng.randi() % m)
			part = clampi(part, 0, left)
			out.append(part)
			left -= part
	out.append(left)
	return out

static func resolve_awaken(attacker: Dictionary, enemies: Array, rng: RandomNumberGenerator, cfg: Dictionary) -> Array:
	var aw: Dictionary = cfg.get("awaken", {})
	var mult := float(aw.get("damage_mult", 2.0))
	var d: Dictionary = cfg.get("damage", {})
	var el := String(attacker["element"])
	var plan: Array = []
	for target in enemies:
		if not target["alive"]:
			continue
		var em := element_mult(String(attacker["element"]), String(target["element"]), cfg)
		var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
		var dmg := damage(_eff(attacker, "att"), _eff(target, "def"), float(attacker["pen"]), em, mult, rf, cfg)
		dmg = int(round(float(dmg) * _awaken_dmg_mult(attacker)))
		dmg += _pure_damage(attacker, target)
		if _has_flag(target, "awaken_taken_applies"):
			dmg = maxi(1, int(round(float(dmg) * _dmg_taken_mult(target))))
		var acap := _awaken_taken_cap(target)
		if acap > 0:
			dmg = mini(dmg, acap)
		var ap := _apply_dmg(target, dmg)
		plan.append({"target": target, "ap": ap,
			"parts": _awaken_split(int(ap["dmg"]), el, rng, cfg)})
	var volley := 0
	var max_hits := 0
	for e in plan:
		var n := (e["parts"] as Array).size()
		volley += n
		max_hits = maxi(max_hits, n)
	var out: Array = []
	var lead := true
	for i in max_hits:
		for e in plan:
			var parts: Array = e["parts"]
			if i >= parts.size():
				continue
			var ap2: Dictionary = e["ap"]
			var last := i == parts.size() - 1
			var ev := {"type": "awaken", "attacker": attacker["name"],
				"defender": (e["target"] as Dictionary)["name"],
				"miss": false, "block": false, "crit": false,
				"damage": int(parts[i]), "dead": bool(ap2["dead"]) and last,
				"hit": i, "hits": parts.size(), "volley": volley}
			if lead:
				ev["volley_lead"] = true
				lead = false
			if last:
				if bool(ap2.get("survived", false)):
					ev["survived"] = true
				if bool(ap2.get("phase2", false)):
					ev["phase2"] = true
			out.append(ev)
	if not out.is_empty():
		(out[-1] as Dictionary)["volley_last"] = true
	return out

static func _uses_left(c: Dictionary, id: int) -> int:
	return int(c.get("skill_uses", {}).get(id, 0))

static func _use(c: Dictionary, id: int) -> void:
	c["skill_uses"][id] = maxi(0, _uses_left(c, id) - 1)

static func _art_hidden(c: Dictionary, field: String) -> int:
	return int((c.get("artifact", {}) as Dictionary).get("hidden", {}).get(field, 0))

static func _art(c: Dictionary, field: String, skill_id: int) -> int:
	return int((c.get("artifact", {}) as Dictionary).get(field, {}).get(skill_id, 0))

static func _proc_chance(caster: Dictionary, sdef: Dictionary, level: int, foes: Array, cfg: Dictionary) -> float:
	var id := int(sdef.get("id", 0))
	var pct := _proc_pct(caster, sdef, level, cfg) + float(_art(caster, "proc_add", id)) \
		+ float(_art_hidden(caster, "proc_add_all"))
	var sub := 0
	for f in foes:
		if bool((f as Dictionary).get("alive", false)):
			sub = maxi(sub, _art(f, "foe_proc_sub", id))
	return maxf(0.0, pct - float(sub))

static func _hp_proc_pct(c: Dictionary, cfg: Dictionary) -> float:
	var sp: Dictionary = cfg.get("skill_proc", {})
	var base := float(sp.get("base_pct", DEFAULT_PROC))
	var low := float(sp.get("low_hp_pct", LOW_HP_PROC))
	var hp_max := maxf(1.0, float(c.get("hp_max", 1)))
	var ratio := clampf(float(c.get("hp", 0)) / hp_max, 0.0, 1.0)
	return base + (low - base) * (1.0 - ratio)

static func _proc_pct(c: Dictionary, sdef: Dictionary, level: int, cfg: Dictionary) -> float:
	if int(sdef.get("id", 0)) == 56:
		return 25.0 + 10.0 * float(level)
	return _hp_proc_pct(c, cfg)

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
	c["_skills_db"] = skills_db
	var sk: Array = c.get("skills", [])
	var slot_lv := {}
	var lv_bonus := int((cfg.get("skill_slot_match", {}) as Dictionary).get("level_bonus", 0))
	if lv_bonus > 0:
		for i in sk.size():
			var sid := int((sk[i] as Dictionary).get("id", 0))
			if slot_matched(c, sid, skills_db):
				slot_lv[sid] = lv_bonus
	c["_slot_lv"] = slot_lv
	c["_skill_limit_max"] = {}
	for i in sk.size():
		var s: Dictionary = sk[i]
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if sdef.is_empty():
			continue
		if sdef.get("active", true):
			var lim := _skill_limit(sdef, _lv(c, s))
			lim += _slot_match_use_bonus(c, sdef, cfg, skills_db)
			lim += _skill_uses_bonus(c)
			c["skill_uses"][int(s["id"])] = lim
			(c["_skill_limit_max"] as Dictionary)[int(s["id"])] = lim
		else:
			_apply_passive(c, s, sdef)

static func _slot_match_use_bonus(c: Dictionary, sdef: Dictionary, cfg: Dictionary,
		skills_db: Dictionary) -> int:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var bonus := int(m.get("heal_use_bonus", 0))
	if bonus <= 0:
		return 0
	var cats: Array = m.get("heal_categories", [])
	if not (String(sdef.get("category", "")) in cats):
		return 0
	return bonus if slot_matched(c, int(sdef.get("id", 0)), skills_db) else 0

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

static func _hp_gate_ok(c: Dictionary, skill_id: int, cfg: Dictionary,
		sdef: Dictionary = {}, allies: Array = []) -> bool:
	var g: Dictionary = cfg.get("skill_hp_gate", {})
	var ids: Array = g.get("skills", [])
	var gated := false
	for i in ids:
		if int(i) == skill_id:
			gated = true
			break
	if not gated:
		return true
	var thr := minf(100.0, float(g.get("threshold_pct", 50))
		+ float(_art(c, "req_hp_relax_pct", skill_id)))
	var scope: Array = [c]
	if String(sdef.get("target", "")) in ["ally", "ally_all", "party", "all_allies"] 			and not allies.is_empty():
		scope = allies
	for m in scope:
		var t := m as Dictionary
		if not bool(t.get("alive", true)):
			continue
		var hp_max := maxi(1, int(t.get("hp_max", 1)))
		if float(t.get("hp", 0)) / float(hp_max) * 100.0 <= thr:
			return true
	return false

static func _same_skill_effect_active(caster: Dictionary, skill_id: int, sdef: Dictionary,
		allies: Array, enemies: Array) -> bool:
	if skill_id in [23, 32]:
		return false
	var target := String(sdef.get("target", ""))
	var cat := String(sdef.get("category", ""))
	var scope: Array = [caster]
	if cat == "debuff" or target in ["single", "enemy", "enemy_all", "all_enemies"]:
		scope = enemies
	elif target in ["ally", "ally_all", "party", "all_allies"]:
		scope = allies
	for member in scope:
		for effect in (member as Dictionary).get("effects", []):
			if int((effect as Dictionary).get("source", 0)) == skill_id:
				return true
	return false

static func _eligible_attack(c: Dictionary, skills_db: Dictionary, cfg: Dictionary = {},
		allies: Array = [], enemies: Array = []) -> Array:
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
		if not _hp_gate_ok(c, int(s["id"]), cfg, sdef, allies):
			continue
		if _same_skill_effect_active(c, int(s["id"]), sdef, allies, enemies):
			continue
		if int(s["id"]) == 26 and not _any_debuffed(allies):
			continue
		out.append(s)
	return out

static func _is_free_cast(sdef: Dictionary, cfg: Dictionary) -> bool:
	var fc: Dictionary = cfg.get("free_cast", {})
	var cats: Array = fc.get("categories", ["buff", "debuff"])
	return String(sdef.get("category", "")) in cats

static func _free_cast(actor: Dictionary, pool: Array, allies: Array, enemies: Array,
		rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Array:
	if pool.is_empty():
		return []
	var s: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var sdef: Dictionary = skills_db.get(str(s["id"]), {})
	if rng.randf() * 100.0 >= _proc_chance(actor, sdef, int(s["level"]), enemies, cfg):
		return []
	var inter := _oblivion_react(actor, int(s["id"]), enemies, rng, skills_db, cfg)
	_use(actor, int(s["id"]))
	if not inter.is_empty():
		return [inter]
	_aw_on_skill_cast(actor, enemies, rng)
	actor["_proc_level_bonus"] = _roll_proc_level(actor, rng)
	var evs := _apply_skill_effect(actor, s, allies, enemies, rng, cfg, skills_db)
	actor["_proc_level_bonus"] = 0
	return evs

static func _act(actor: Dictionary, party_a: Array, party_b: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Array:
	if _has_flag(actor, "confused"):
		var d: Dictionary = cfg.get("damage", {})
		var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
		var sdmg := damage(_eff(actor, "att"), _eff(actor, "def"), float(actor["pen"]), 1.0, 1.5, rf, cfg)
		var ap := _apply_dmg(actor, sdmg)
		return [{"type": "confused", "actor": actor["name"], "damage": int(ap["dmg"]), "dead": bool(ap["dead"])}]
	var enemies: Array = party_b if actor["side"] == "ally" else party_a
	var allies: Array = party_a if actor["side"] == "ally" else party_b
	if _alive_count(enemies) == 0:
		return []
	var aw_cfg: Dictionary = cfg.get("awaken", {})
	_gauge_bump(actor, float(aw_cfg.get("charge_per_turn", 3.6)) * _gauge_rate(actor), false)
	if gauge_of(actor) >= 100.0:
		var side_party: Array = party_a if actor["side"] == "ally" else party_b
		_gauge_set(actor, _gauge_min_side(side_party))
		var caster := _awaken_caster(side_party)
		if caster.is_empty():
			return []
		return resolve_awaken(caster, enemies, rng, cfg)
	if _has_flag(actor, "no_attack"):
		return []
	var free_pool: Array = []
	var turn_pool: Array = []
	for s0 in _eligible_attack(actor, skills_db, cfg, allies, enemies):
		if _is_free_cast(skills_db.get(str((s0 as Dictionary)["id"]), {}), cfg):
			free_pool.append(s0)
		else:
			turn_pool.append(s0)
	var out: Array = _free_cast(actor, free_pool, allies, enemies, rng, cfg, skills_db)
	if not out.is_empty():
		_mark_owner_effects(actor)
	if _alive_count(enemies) == 0:
		return out
	if not turn_pool.is_empty():
		var s: Dictionary = turn_pool[rng.randi_range(0, turn_pool.size() - 1)]
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if rng.randf() * 100.0 < _proc_chance(actor, sdef, int(s["level"]), enemies, cfg):
			var inter := _oblivion_react(actor, int(s["id"]), enemies, rng, skills_db, cfg)
			_use(actor, int(s["id"]))
			if not inter.is_empty():
				out.append(inter)
				return out
			if String(sdef.get("category", "")) != "defense":
				_aw_on_skill_cast(actor, enemies, rng)
			actor["_proc_level_bonus"] = _roll_proc_level(actor, rng)
			out.append_array(_apply_skill_effect(actor, s, allies, enemies, rng, cfg, skills_db))
			actor["_proc_level_bonus"] = 0
			return out
	var t := pick_target(enemies, cfg)
	if t.is_empty():
		return out
	if _has_flag(actor, "always_double"):
		out.append_array(resolve_double(actor, t, rng, cfg, skills_db))
	else:
		out.append(resolve_attack(actor, t, rng, cfg, skills_db))
	return out

static func _roll_proc_level(c: Dictionary, rng: RandomNumberGenerator) -> int:
	for e in c.get("effects", []):
		if e.get("kind") == "skill_level_proc" and rng.randf() * 100.0 < float(e["pct"]):
			return int(e["value"])
	return 0

const OBLIVION_IMMUNE_SKILL := 36
static func _oblivion_react(caster: Dictionary, fired_id: int, enemies: Array, rng: RandomNumberGenerator, skills_db: Dictionary, cfg: Dictionary) -> Dictionary:
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
			if rng.randf() * 100.0 < _proc_pct(e, sdef, int(s["level"]), cfg):
				_use(e, int(s["id"]))
				return {"type": "skill", "skill_id": 56, "skill_name": String(skills_db.get("56", {}).get("name", "")),
					"caster": e["name"], "interrupt": true, "target": caster["name"],
					"nullified_id": fired_id, "nullified_name": String(skills_db.get(str(fired_id), {}).get("name", ""))}
	return {}

static func _oblivion_apply(caster: Dictionary, fired_id: int, owner: Dictionary, hammer: Dictionary, skills_db: Dictionary) -> Dictionary:
	_use(owner, int(hammer["id"]))
	return {"type": "skill", "skill_id": 56, "skill_name": String(skills_db.get("56", {}).get("name", "")),
		"caster": owner["name"], "interrupt": true, "target": caster["name"],
		"nullified_id": fired_id, "nullified_name": String(skills_db.get(str(fired_id), {}).get("name", ""))}

static func slot_matched(caster: Dictionary, skill_id: int, skills_db: Dictionary) -> bool:
	var slots: Array = caster.get("skill_slots", [])
	if slots.is_empty():
		return false
	var sk: Array = caster.get("skills", [])
	for i in sk.size():
		if int((sk[i] as Dictionary).get("id", 0)) != skill_id:
			continue
		if i >= slots.size():
			return false
		var ty := String(slots[i])
		return ty == "star" or ty == String(skills_db.get(str(skill_id), {}).get("slot", ""))
	return false

static func slot_match_mult(caster: Dictionary, skill_id: int, cfg: Dictionary, skills_db: Dictionary) -> float:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var pct := float(m.get("power_pct", 0.0))
	if pct <= 0.0:
		return 1.0
	return 1.0 + pct / 100.0 if slot_matched(caster, skill_id, skills_db) else 1.0

static func _skill_strike(caster: Dictionary, target: Dictionary, coeff: float, rng: RandomNumberGenerator, cfg: Dictionary) -> int:
	var d: Dictionary = cfg.get("damage", {})
	var em := element_mult(String(caster["element"]), String(target["element"]), cfg)
	var rf := rng.randf_range(float(d.get("rand_min", 0.95)), float(d.get("rand_max", 1.05)))
	var mult := coeff * float(caster.get("_slot_mult", 1.0))
	return damage(_eff(caster, "att"), _eff(target, "def"), float(caster["pen"]), em, mult, rf, cfg)

static func _apply_skill_effect(caster: Dictionary, s: Dictionary, allies: Array, enemies: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary) -> Array:
	var id := int(s["id"])
	var lv := _lv(caster, s)
	var sdef: Dictionary = skills_db.get(str(id), {})
	caster["_slot_mult"] = slot_match_mult(caster, id, cfg, skills_db)
	caster["_cast_skill_id"] = id
	var ev := {"type": "skill", "skill_id": id, "skill_name": String(sdef.get("name", "")), "caster": caster["name"]}
	if float(caster["_slot_mult"]) > 1.0:
		ev["slot_match"] = true

	match id:
		21:
			var t := pick_target(enemies, cfg)
			if t.is_empty(): return []
			var r21 := _deal_attack(caster, t, _skill_strike(caster, t, 6.0, rng, cfg), true, rng, cfg, skills_db)
			r21["target"] = t["name"]
			return [_merge(ev, r21)]
		30:
			var t30 := pick_target(enemies, cfg)
			if t30.is_empty(): return []
			var cap30 := float((cfg.get("skill_damage_cap_pct", {}) as Dictionary).get(str(id), 0.0))
			var r30 := _deal_attack(caster, t30, maxi(1, int(round(float(t30["def"]) * 1.5))), true, rng, cfg, skills_db, cap30)
			r30["target"] = t30["name"]
			return [_merge(ev, r30)]
		36:
			var t2 := pick_target(enemies, cfg)
			if t2.is_empty(): return []
			var a := _eff(caster, "att")
			var d := _eff(caster, "def")
			var raw := maxi(1, int(round(float(a) * float(d) * float(absi(a - d)) * (0.45 + 0.02 * lv))))
			var r36 := _deal_attack(caster, t2, raw, true, rng, cfg, skills_db)
			r36["target"] = t2["name"]
			return [_merge(ev, r36)]
		53:
			var t53 := pick_target(enemies, cfg)
			if t53.is_empty(): return []
			var r53 := _deal_attack(caster, t53, maxi(1, int(round(float(caster["hp"]) * float(15 + 2 * lv) / 100.0 * 0.70))), true, rng, cfg, skills_db)
			r53["target"] = t53["name"]
			return [_merge(ev, r53)]
		54:
			var t5 := pick_target(enemies, cfg)
			if t5.is_empty(): return []
			var pct := (20 if bool(s.get("dedicated", false)) else 15) + 2 * lv
			var bomb := maxi(1, int(round(float(caster["hp"]) * float(pct) / 100.0)))
			if _immune(t5):
				return [_mark_immune(_merge(ev, {"target": t5["name"]}), t5)]
			t5["effects"].append({"kind": "timed", "turns": 7, "dmg": bomb, "source": id})
			return [_merge(ev, {"target": t5["name"], "timed_turns": 7, "timed_dmg": bomb})]
		55:
			var t6 := pick_target(enemies, cfg)
			if t6.is_empty(): return []
			var rate := (0.60 if bool(s.get("dedicated", false)) else 0.50)
			var loss_c := int(float(caster["hp"]) * rate)
			var loss_t := int(float(t6["hp"]) * rate)
			var cap55 := int((cfg.get("skill_damage_cap_flat", {}) as Dictionary).get(str(id), 0))
			if cap55 > 0:
				loss_t = mini(loss_t, cap55)
			caster["hp"] = maxi(1, int(caster["hp"]) - loss_c)
			t6["hp"] = maxi(1, int(t6["hp"]) - loss_t)
			return [_merge(ev, {"target": t6["name"], "self_loss": loss_c, "target_loss": loss_t})]
		14:
			caster["effects"].append({"kind": "lifesteal", "pct": 7 + lv, "turns": 2, "source": id})
			return [_merge(ev, {"buff": "lifesteal%", "value": 7 + lv, "turns": 2})]
		25:
			var miss_pct := int(round((1.0 - float(caster["hp"]) / maxf(1.0, float(caster["hp_max"]))) * 100.0))
			_add_stat(caster, "att", "pct", miss_pct, 3, id)
			return [_merge(ev, {"buff": "att%", "value": miss_pct, "turns": 3})]
		31:
			var src := pick_target(enemies, cfg)
			if src.is_empty(): return []
			_add_stat(caster, "att", "flat", _eff(src, "att") - int(caster["att"]), 2, id)
			_add_stat(caster, "def", "flat", _eff(src, "def") - int(caster["def"]), 2, id)
			return [_merge(ev, {"buff": "copy_att_def", "from": src["name"], "turns": 2})]
		50:
			_add_stat(caster, "def", "flat", 20 + 5 * lv, 2, id)
			if not _has_flag(caster, "survive_once"):
				_add_flag(caster, "survive_once", -1, id)
			return [_merge(ev, {"buff": "def", "value": 20 + 5 * lv, "turns": 2, "survive_once": true})]
		57:
			var a3 := _eff(caster, "att")
			var d3 := _eff(caster, "def")
			_add_stat(caster, "att", "flat", d3 - int(caster["att"]), 2, id)
			_add_stat(caster, "def", "flat", a3 - int(caster["def"]), 2, id)
			return [_merge(ev, {"buff": "swap_att_def", "turns": 2})]
		60:
			_add_stat(caster, "att", "pct", 15 + 5 * lv, 2, id)
			return [_merge(ev, {"buff": "att%", "value": 15 + 5 * lv, "turns": 2})]
		70:
			_add_stat(caster, "def", "flat", 50 + 5 * lv, 2, id)
			return [_merge(ev, {"buff": "def", "value": 50 + 5 * lv, "turns": 2})]
		80:
			_add_stat(caster, "att", "pct", 7 + 3 * lv, 2, id)
			_add_stat(caster, "def", "pct", 7 + 3 * lv, 2, id)
			return [_merge(ev, {"buff": "att/def%", "value": 7 + 3 * lv, "turns": 2})]
		29:
			var evs: Array = []
			for a2 in allies:
				if not a2["alive"]: continue
				var heal := int(round(60.0 + float(a2["hp_max"]) * (0.06 + 0.01 * lv)))
				a2["hp"] = mini(int(a2["hp_max"]), int(a2["hp"]) + heal)
				evs.append(_merge(ev, {"target": a2["name"], "heal": heal}))
			return evs
		26:
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
		15:
			var t7 := pick_target(enemies, cfg)
			if t7.is_empty(): return []
			_add_flag(t7, "stun", 2, id)
			return [_mark_immune(_merge(ev, {"target": t7["name"], "debuff": "stun", "turns": 2}), t7)]
		22:
			var t8 := pick_target(enemies, cfg)
			if t8.is_empty(): return []
			_add_flag(t8, "confused", 2, id)
			return [_mark_immune(_merge(ev, {"target": t8["name"], "debuff": "confused", "turns": 2}), t8)]
		23:
			var t9 := pick_target(enemies, cfg)
			if t9.is_empty(): return []
			if _immune(t9):
				return [_mark_immune(_merge(ev, {"target": t9["name"]}), t9)]
			t9["effects"].append({"kind": "dmg_taken", "pct": 7 + 3 * lv, "turns": -1, "source": id})
			return [_merge(ev, {"target": t9["name"], "debuff": "vulnerable%", "value": 7 + 3 * lv,
				"turns": -1, "stacks": _stack_count(t9, id)})]
		32:
			var t10 := pick_target(enemies, cfg)
			if t10.is_empty(): return []
			if _immune(t10):
				return [_mark_immune(_merge(ev, {"target": t10["name"]}), t10)]
			t10["effects"].append({"kind": "dot", "pct": 3 + lv, "turns": 2, "source": id})
			return [_merge(ev, {"target": t10["name"], "debuff": "dot%", "value": 3 + lv, "turns": 2})]
		46:
			var t11 := pick_target(enemies, cfg)
			if t11.is_empty(): return []
			_add_flag(t11, "no_evade", 2, id)
			_add_flag(t11, "no_block", 2, id)
			return [_mark_immune(_merge(ev, {"target": t11["name"], "debuff": "no_evade/no_block", "turns": 2}), t11)]
		120:
			return _debuff_all(ev, enemies, [["att", -(7 + 3 * lv)]], 2, id)
		130:
			return _debuff_all(ev, enemies, [["def", -(7 + 3 * lv)]], 2, id)
		140:
			return _debuff_all(ev, enemies, [["att", -(7 + 3 * lv)], ["def", -(7 + 3 * lv)]], 2, id)
		150:
			var evs3: Array = []
			for en in enemies:
				if not en["alive"]: continue
				_add_flag(en, "no_evade", 3, id)
				evs3.append(_mark_immune(_merge(ev, {"target": en["name"], "debuff": "no_evade", "turns": 3}), en))
			caster["effects"].append({"kind": "initiative", "side": caster["side"], "turns": 2})
			return evs3
		160:
			var evs4: Array = []
			for en2 in enemies:
				if not en2["alive"]: continue
				_add_flag(en2, "no_crit", 3, id)
				_drain_one_skill(en2)
				evs4.append(_mark_immune(_merge(ev, {"target": en2["name"], "debuff": "no_crit+drain", "turns": 3}), en2))
			return evs4
		170:
			var evs5: Array = []
			for en3 in enemies:
				if not en3["alive"]: continue
				_add_flag(en3, "no_evade", 2, id)
				_add_flag(en3, "no_crit", 2, id)
				evs5.append(_mark_immune(_merge(ev, {"target": en3["name"], "debuff": "no_evade/no_crit", "turns": 2}), en3))
			return evs5
		24:
			var pool: Array = []
			for en4 in enemies:
				if not en4["alive"]: continue
				for sk in en4.get("skills", []):
					pool.append(sk)
			if pool.is_empty():
				return [_merge(ev, {"copied_id": null})]
			var picked: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			if int(picked["id"]) == 24:
				return [_merge(ev, {"copied_id": 24, "todo": true})]
			var head := _merge(ev, {"copied_id": int(picked["id"]), "copied_name": String(skills_db.get(str(picked["id"]), {}).get("name", ""))})
			return [head] + _apply_skill_effect(caster, picked, allies, enemies, rng, cfg, skills_db)
		_:
			return [_merge(ev, {"todo": true})]

static func _debuff_all(ev: Dictionary, enemies: Array, mods: Array, turns: int, src: int) -> Array:
	var out: Array = []
	for en in enemies:
		if not en["alive"]: continue
		for m in mods:
			_add_stat(en, String(m[0]), "pct", float(m[1]), turns, src)
		out.append(_mark_immune(_merge(ev, {"target": en["name"], "turns": turns,
			"debuff": "stat"}), en))
	return out

static func _drain_one_skill(c: Dictionary) -> void:
	for sk in c.get("skills", []):
		if _uses_left(c, int(sk["id"])) > 0:
			_use(c, int(sk["id"]))
			return

static func _defense_skill_onhit(defender: Dictionary, rng: RandomNumberGenerator, dmg: int, is_skill: bool, cfg: Dictionary, skills_db: Dictionary) -> Dictionary:
	var elig: Array = []
	for s in defender.get("skills", []):
		var sdef: Dictionary = skills_db.get(str(s["id"]), {})
		if sdef.is_empty() or not sdef.get("active", true):
			continue
		if String(sdef.get("category", "")) != "defense":
			continue
		if int(s["id"]) == 20 and is_skill:
			continue
		if _uses_left(defender, int(s["id"])) <= 0:
			continue
		elig.append(s)
	if elig.is_empty():
		return {"dmg": dmg, "fired": "", "reflect": 0}
	var s2: Dictionary = elig[rng.randi_range(0, elig.size() - 1)]
	var sdef2: Dictionary = skills_db.get(str(s2["id"]), {})
	if rng.randf() * 100.0 < _proc_pct(defender, sdef2, int(s2["level"]), cfg):
		_use(defender, int(s2["id"]))
		var dr := _defense_reduce(defender, s2, dmg, skills_db)
		dr["fired_id"] = int(s2["id"])
		return dr
	return {"dmg": dmg, "fired": "", "reflect": 0}

static func _defense_reduce(defender: Dictionary, s: Dictionary, dmg: int, skills_db: Dictionary) -> Dictionary:
	var id := int(s["id"])
	var lv := int(s["level"])
	var name := String(skills_db.get(str(id), {}).get("name", ""))
	match id:
		11:
			return {"dmg": maxi(1, dmg - (10 + 5 * lv)), "fired": name, "reflect": 0}
		12:
			return {"dmg": 0, "fired": name, "reflect": 0}
		13:
			var refl := mini(dmg, int(round(float(_eff(defender, "def")) * float(7 + 2 * lv) / 100.0)))
			return {"dmg": dmg, "fired": name, "reflect": maxi(0, refl)}
		20:
			return {"dmg": maxi(1, int(round(float(dmg) * 0.5))), "fired": name, "reflect": 0}
		_:
			return {"dmg": dmg, "fired": name, "reflect": 0}

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	for k in b:
		r[k] = b[k]
	return r

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

static func _consume_initiative(party_a: Array, party_b: Array) -> String:
	var side := ""
	var perm := {}
	for party in [party_a, party_b]:
		for c in party:
			var keep: Array = []
			for e in c.get("effects", []):
				if e.get("kind") == "initiative":
					side = String(e.get("side", ""))
					if int(e.get("turns", 0)) < 0:
						perm[side] = true
						keep.append(e)
					continue
				keep.append(e)
			c["effects"] = keep
	if perm.size() >= 2:
		return ""
	return side

static func _other(side: String) -> String:
	return "enemy" if side == "ally" else "ally"

static func _decide_lead(rng: RandomNumberGenerator, last_lead: String, streak: int, forced: String) -> String:
	if forced != "":
		return forced
	if last_lead != "" and streak >= 4:
		return _other(last_lead)
	return "ally" if rng.randf() < 0.5 else "enemy"

const _OWNER_TURN_MARK := "_owner_turn_mark"

static func _mark_owner_effects(c: Dictionary) -> void:
	for e in (c.get("effects", []) as Array):
		var effect := e as Dictionary
		var kind := String(effect.get("kind", ""))
		if kind in [REACT, "dyn"]:
			continue
		if kind not in ["dot", "timed"] and int(effect.get("turns", -1)) > 0:
			effect[_OWNER_TURN_MARK] = true

static func _tick_owner_effects(c: Dictionary, events: Array, round: int) -> void:
	var keep: Array = []
	var touched := {}
	for e in (c.get("effects", []) as Array):
		var effect := e as Dictionary
		if not bool(effect.get(_OWNER_TURN_MARK, false)):
			keep.append(effect)
			continue
		effect.erase(_OWNER_TURN_MARK)
		var source := int(effect.get("source", 0))
		if source > 0:
			touched[source] = true
		var turns := int(effect.get("turns", 0)) - 1
		if turns > 0:
			effect["turns"] = turns
			keep.append(effect)
	c["effects"] = keep
	for source in touched:
		var remaining := 0
		for e in keep:
			var effect := e as Dictionary
			if int(effect.get("source", 0)) == int(source) and int(effect.get("turns", -1)) > 0:
				remaining = maxi(remaining, int(effect.get("turns", 0)))
		events.append({"type": "effect_tick", "target": c["name"], "source": int(source),
			"turns": remaining, "round": round})

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
					keep.append(e)
			c["effects"] = keep

static func simulate(party_a: Array, party_b: Array, rng: RandomNumberGenerator, cfg: Dictionary, skills_db: Dictionary = {}, max_rounds := 200) -> Dictionary:
	for c in party_a: _init_combatant_skills(c, skills_db, cfg)
	for c in party_b: _init_combatant_skills(c, skills_db, cfg)
	_bind_side_gauge(party_a)
	_bind_side_gauge(party_b)
	_aw_refresh_dynamic(party_a, party_b)
	var events: Array = []
	var rounds := 0
	var last_lead := ""
	var streak := 0
	while _alive_count(party_a) > 0 and _alive_count(party_b) > 0 and rounds < max_rounds:
		rounds += 1
		var forced := _consume_initiative(party_a, party_b)
		var lead := _decide_lead(rng, last_lead, streak, forced)
		streak = streak + 1 if lead == last_lead else 1
		last_lead = lead
		var actors: Array = []
		for c in (party_a if lead == "ally" else party_b):
			if c["alive"]: actors.append(c)
		_shuffle(actors, rng)
		for actor in actors:
			if not actor["alive"]:
				continue
			_mark_owner_effects(actor)
			if _has_flag(actor, "stun"):
				events.append({"type": "status_skip", "actor": actor["name"], "round": rounds, "lead": lead,
					"source": _flag_source(actor, "stun"), "turns": _flag_turns(actor, "stun")})
				_tick_owner_effects(actor, events, rounds)
				continue
			var evs := _act(actor, party_a, party_b, rng, cfg, skills_db)
			_charge_on_hits(evs, party_a, party_b, cfg)
			for ev in evs:
				ev["round"] = rounds
				ev["lead"] = lead
				ev["gauge_ally"] = _side_gauge(party_a)
				ev["gauge_enemy"] = _side_gauge(party_b)
				events.append(ev)
			_tick_owner_effects(actor, events, rounds)
			if _alive_count(party_a) == 0 or _alive_count(party_b) == 0:
				break
		_round_end(party_a, party_b, events, rounds)
		_aw_refresh_dynamic(party_a, party_b)
	var a_alive := _alive_count(party_a)
	var b_alive := _alive_count(party_b)
	var winner := "draw"
	if a_alive > 0 and b_alive == 0:
		winner = "ally"
	elif b_alive > 0 and a_alive == 0:
		winner = "enemy"
	return {"winner": winner, "events": events, "rounds": rounds}

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

const DYN_SRC := "dyn:"

static func _aw_refresh_dynamic(party_a: Array, party_b: Array) -> void:
	var any := false
	for side in [party_a, party_b]:
		for c in side:
			if _clear_dyn(c as Dictionary):
				any = true
			elif _has_dyn(c as Dictionary):
				any = true
	if not any:
		return
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

const REACT := "react"

static func _reacts(c: Dictionary, on: String) -> Array:
	var out: Array = []
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) != REACT or String(d.get("on", "")) != on:
			continue
		if d.has("left") and int(d["left"]) <= 0:
			continue
		if d.has("when") and is_zero_approx(_dyn_scale(d["when"], c, c.get("_party", []), [])):
			continue
		out.append(d)
	return out

static func _spend(r: Dictionary) -> void:
	if r.has("left"):
		r["left"] = int(r["left"]) - 1

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
			match String(st):
				"__dmg_taken": _push(t, {"kind": "dmg_taken", "pct": add}, src)
				"__dmg_deal":  _push(t, {"kind": "dmg_deal", "pct": add}, src)
				_: _aw_add_stat(t, String(st), String(r.get("mode", "pct")), add, src)
	return true

static func _aw_on_attack_done(attacker: Dictionary, defender: Dictionary,
		_rng: RandomNumberGenerator, dealt := 0) -> void:
	if not bool(attacker.get("alive", true)):
		return
	for r in _reacts(attacker, "attack_done"):
		match String(r.get("do", "stack")):
			"heal_dealt":
				if dealt <= 0:
					continue
				var heal := int(round(float(dealt) * float(r.get("ratio", 1.0))))
				if heal > 0:
					attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + heal)
				if not (r.get("stats", []) as Array).is_empty():
					_stack_up(r, attacker, attacker.get("_party", []))
				_spend(r)
			"heal_pct":
				var h := int(round(float(attacker.get("hp_max", 0)) * float(r.get("pct", 0.0)) / 100.0))
				if h > 0:
					attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + h)
					_spend(r)
			"stack_from_target":
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
				_aw_clear_src(attacker, "react:%d" % int(r.get("no", 0)))
				for r2 in _reacts(attacker, String(r.get("reset_on", ""))):
					r2["stack"] = 0.0
			"debuff_target":
				var src := "react:%d" % int(r.get("no", 0))
				_aw_add_stat(defender, String(r.get("target_stat", "blk")), "flat",
					-float(r.get("target_value", 0.0)), src)
				_aw_add_stat(attacker, String(r.get("self_stat", "cri")), "flat",
					float(r.get("self_value", 0.0)), src)
				_spend(r)

static func _aw_on_double(attacker: Dictionary, dealt := 0) -> void:
	if not bool(attacker.get("alive", true)):
		return
	for r in _reacts(attacker, "double"):
		if String(r.get("do", "stack")) == "heal_dealt":
			if dealt <= 0:
				continue
			var heal := int(round(float(dealt) * float(r.get("ratio", 1.0))))
			attacker["hp"] = mini(int(attacker["hp_max"]), int(attacker["hp"]) + heal)
			_spend(r)
			continue
		if _stack_up(r, attacker, attacker.get("_party", [])):
			_spend(r)

static func _aw_fix_damage(defender: Dictionary, dmg: int) -> int:
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

static func _aw_clear_src(c: Dictionary, src: String) -> void:
	var keep: Array = []
	for e in (c.get("effects", []) as Array):
		if String((e as Dictionary).get("src", "")) == src:
			continue
		keep.append(e)
	c["effects"] = keep

static func _aw_on_attack_bonus(attacker: Dictionary, _defender: Dictionary,
		_rng: RandomNumberGenerator, raw_hint := 0) -> int:
	var bonus := 0
	for r in _reacts(attacker, "attack_bonus"):
		var no := int(r.get("no", 0))
		var acc := _aw_acc_get(attacker, no)
		if acc <= 0.0:
			continue
		bonus += int(round(acc * float(r.get("ratio", 1.0))))
		_aw_acc_set(attacker, no, 0.0)
		_spend(r)
	for rh in _reacts(attacker, "attack_heal"):
		var nh := int(rh.get("no", 0))
		var ah := _aw_acc_get(attacker, nh)
		if ah <= 0.0:
			continue
		attacker["hp"] = mini(int(attacker["hp_max"]),
			int(attacker["hp"]) + int(round(ah)))
		_aw_acc_set(attacker, nh, 0.0)
		_spend(rh)
	for ra in _reacts(attacker, "attack_acc"):
		var na := int(ra.get("no", 0))
		var capa := float(_eff(attacker, String(ra.get("cap_stat", "att"))))
		_aw_acc_set(attacker, na, minf(
			_aw_acc_get(attacker, na) + float(raw_hint) * float(ra.get("ratio", 1.0)), capa))
	for rt in _reacts(attacker, "attack_target_hp"):
		var add := 0.0
		match String(rt.get("do", "")):
			"cur_pct":
				add = float(_defender.get("hp", 0)) * float(rt.get("pct", 0.0)) / 100.0
			"max_pct":
				add = float(_defender.get("hp_max", 0)) * float(rt.get("pct", 0.0)) / 100.0
			"max_per_unit":
				var hm := float(_defender.get("hp_max", 0))
				add = hm * (hm * float(rt.get("per_unit_pct", 0.0))) / 100.0
		if rt.has("max"):
			add = minf(add, float(rt["max"]))
		if add >= 1.0:
			bonus += int(round(add))
			_spend(rt)
	for r2 in _reacts(attacker, "stat_gap"):
		var mine := _eff(attacker, "att") + _eff(attacker, "def")
		var theirs := _eff(_defender, "att") + _eff(_defender, "def")
		if mine > theirs:
			bonus += mini(mine - theirs, int(r2.get("max", 150)))
	return bonus

static func _aw_acc_get(c: Dictionary, no: int) -> float:
	return float((c.get("_aw_acc", {}) as Dictionary).get(no, 0.0))

static func _aw_acc_set(c: Dictionary, no: int, v: float) -> void:
	if not c.has("_aw_acc"):
		c["_aw_acc"] = {}
	(c["_aw_acc"] as Dictionary)[no] = v

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
			var lim := int((c.get("_skill_limit_max", {}) as Dictionary).get(sid, -1))
			if lim < 0:
				lim = _skill_limit(skills_db.get(str(sid), {}),
					int((sd as Dictionary).get("level", 1))) + _skill_uses_bonus(c)
			if _uses_left(c, sid) < lim:
				(c["skill_uses"] as Dictionary)[sid] = _uses_left(c, sid) + 1
				left -= 1
				any = true
	return any

static func _restore_react(owner: Dictionary, r: Dictionary) -> void:
	var want := int(r.get("target_no", 0))
	var cap := int(r.get("max", 0))
	for e in (owner.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) != REACT or int(d.get("no", -1)) != want:
			continue
		if not d.has("left"):
			continue
		if cap > 0 and int(d["left"]) >= cap:
			continue
		d["left"] = int(d["left"]) + int(r.get("value", 1))
		return

static func _aw_on_crit_bonus(_attacker: Dictionary, defender: Dictionary) -> int:
	var bonus := 0
	for r in _reacts(_attacker, "crit"):
		if String(r.get("do", "")) == "skill_restore":
			if _restore_skill_use(_attacker, r, _attacker.get("_skills_db", {})):
				_spend(r)
			continue
		var add := float(defender.get("hp_max", 0)) * float(r.get("pct", 0.0)) / 100.0
		if r.has("max"):
			add = minf(add, float(r["max"]))
		bonus += int(round(add))
		_spend(r)
	return bonus

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
				var cap := float(_eff(defender, String(r.get("cap_stat", "def"))))
				_aw_acc_set(defender, int(r.get("no", 0)),
					minf(_aw_acc_get(defender, int(r.get("no", 0))) + float(dmg), cap))

static func _aw_on_hit_unguarded(defender: Dictionary, attacker: Dictionary,
		_rng: RandomNumberGenerator) -> void:
	for r in _reacts(defender, "hit_unguarded"):
		_add_flag(attacker, "confused", int(r.get("turns", 1)), int(r.get("no", 0)))
		_spend(r)

static func _aw_on_block(defender: Dictionary, _rng: RandomNumberGenerator) -> void:
	for r in _reacts(defender, "block"):
		if String(r.get("do", "")) == "react_restore":
			_restore_react(defender, r)
			continue
		if String(r.get("do", "")) == "acc":
			var nb := int(r.get("no", 0))
			_aw_acc_set(defender, nb, _aw_acc_get(defender, nb)
				+ float(_eff(defender, String(r.get("from_stat", "def"))))
				* float(r.get("pct", 0.0)) / 100.0)
			_spend(r)
		elif r.has("gauge_pct"):
			_gauge_bump(defender, float(r["gauge_pct"]))
			_spend(r)
		elif _stack_up(r, defender, defender.get("_party", [])):
			_spend(r)

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

static func _aw_on_death(dead: Dictionary) -> void:
	for r in _reacts(dead, "death"):
		if String(r.get("do", "")) == "plant":
			for t2 in _targets(String(r.get("to", "ally")), dead, dead.get("_party", [])):
				var c2 := t2 as Dictionary
				if not bool(c2.get("alive", true)) or c2 == dead:
					continue
				var re := (r.get("plant", {}) as Dictionary).duplicate(true)
				re["kind"] = REACT
				re["no"] = int(r.get("no", 0))
				(c2["effects"] as Array).append(re)
			_spend(r)
			continue
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
		if r.has("gauge_pct"):
			_gauge_bump(dead, float(r["gauge_pct"]))
		_spend(r)

static func _aw_on_skill_cast(caster: Dictionary, targets: Array,
		rng: RandomNumberGenerator = null) -> void:
	for r in _reacts(caster, "skill_cast"):
		match String(r.get("do", "")):
			"random_debuff":
				var ch := r.get("choices", []) as Array
				if ch.is_empty() or rng == null:
					continue
				var pick := ch[rng.randi_range(0, ch.size() - 1)] as Dictionary
				for t3 in targets:
					var c3 := t3 as Dictionary
					if not bool(c3.get("alive", true)):
						continue
					if pick.has("gauge_pct"):
						_gauge_bump(c3, float(pick["gauge_pct"]), false)
					else:
						_aw_add_stat(c3, String(pick.get("stat", "")),
							String(pick.get("mode", "pct")), float(pick.get("value", 0.0)),
							"react:%d" % int(r.get("no", 0)))
					break
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

static func _dyn_scale(when, owner: Dictionary, allies: Array, enemies: Array = []) -> float:
	if when == null:
		return 1.0
	var w := when as Dictionary
	var hp_max := maxf(1.0, float(owner.get("hp_max", 1)))
	var hp_pct := float(owner.get("hp", 0)) / hp_max * 100.0
	match String(w.get("kind", "")):
		"enemy_dead_mult":
			var n2 := 1
			for c in enemies:
				if not bool((c as Dictionary).get("alive", true)):
					n2 += 1
			return float(mini(n2, int(w.get("max", 3))))
		"enemy_hp_sum":
			var s := 0.0
			for c in enemies:
				if bool((c as Dictionary).get("alive", true)):
					s += float((c as Dictionary).get("hp", 0))
			return s
		"self_hp_at_most":
			return 1.0 if hp_pct <= float(w.get("pct", 0)) else 0.0
		"self_hp_above":
			return 1.0 if hp_pct > float(w.get("pct", 0)) else 0.0
		"lost_hp_ratio":
			return clampf(1.0 - hp_pct / 100.0, 0.0, 1.0)
		"alive_ally_element":
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
		"ally_dead_any":
			for c in allies:
				if not bool((c as Dictionary).get("alive", true)):
					return 1.0
			return 0.0
		"self_alive":
			return 1.0 if bool(owner.get("alive", true)) else 0.0
		"self_dead":
			return 0.0 if bool(owner.get("alive", true)) else 1.0
		"has_debuff":
			return 1.0 if _has_debuff(owner, w.get("except_src", [])) else 0.0
	return 0.0

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
		"team_buff_active":
			return String(c.get("value", "")) in (ctx.get("team_buffs", []) as Array)
		"self_type":
			return String(owner.get("atk_type", "")) == String(c.get("value", ""))
		"self_stat_min":
			return _eff(owner, String(c.get("stat", ""))) >= int(c.get("min", 0))
		"grade_highest":
			var mine := float(owner.get("grade", 0.0))
			for c2 in allies:
				if c2 != owner and float((c2 as Dictionary).get("grade", 0.0)) > mine:
					return false
			return true
	return false

static func _count_element(party: Array, el: String) -> int:
	var n := 0
	for c in party:
		if String((c as Dictionary).get("element", "")) == el:
			n += 1
	return n

static func apply_effect_op(op: Dictionary, owner: Dictionary, allies: Array, enemies: Array,
		ctx: Dictionary, no: int, extra_scale := 1.0, src_prefix := "awaken:") -> bool:
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

	var v := 0.0
	if op.has("from"):
		var fr: Dictionary = op["from"]
		var fs := String(fr.get("stat", ""))
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
	const VALUELESS := ["absorb_top", "status_immune", "skill_level_proc", "flag", "initiative",
		"pen_share"]
	if is_zero_approx(v) and not (String(op.get("kind", "")) in VALUELESS):
		return false

	for t in targets:
		match String(op.get("kind", "stat")):
			"stat":
				if src_prefix == DYN_SRC and String(op["stat"]) == "hp":
					return false
				if String(op["stat"]) == "__dmg_deal":
					_push(t, {"kind": "dmg_deal", "pct": v}, src)
				elif String(op["stat"]) == "__dmg_taken":
					_push(t, {"kind": "dmg_taken", "pct": v}, src)
				else:
					_aw_add_stat(t, String(op["stat"]), String(op.get("mode", "flat")), v, src)
			"dmg_deal":      _push(t, {"kind": "dmg_deal", "pct": v}, src)
			"dmg_deal_vs_element":
				_push(t, {"kind": "dmg_deal_vs_element", "pct": v,
					"element": String(op.get("element", ""))}, src)
			"dmg_deal_vs_type":
				_push(t, {"kind": "dmg_deal_vs_type", "pct": v,
					"atk_type": String(op.get("atk_type", ""))}, src)
			"awaken_dmg":    _push(t, {"kind": "awaken_dmg", "pct": v}, src)
			"initiative":
				_push(t, {"kind": "initiative", "side": String(t.get("side", "ally"))}, src)
			"crit_pen":      _push(t, {"kind": "crit_pen", "pct": v}, src)
			"double_dmg":    _push(t, {"kind": "double_dmg", "pct": v}, src)
			"skill_dmg_deal":
				_push(t, {"kind": "skill_dmg_deal", "pct": v,
					"skill_id": int(op.get("skill_id", 0))}, src)
			"pen_share":
				var mine := _eff(t, "pure")
				var others := _targets("ally_others", t, allies)
				if mine > 0 and not others.is_empty():
					_aw_add_stat(t, "pure", "flat", -float(mine), src)
					var each := float(mine) / float(others.size())
					for o2 in others:
						_aw_add_stat(o2, "pure", "flat", each, src)
			"awaken_dmg_cap": _push(t, {"kind": "awaken_dmg_cap", "value": v}, src)
			"skill_dmg_taken":
				_push(t, {"kind": "skill_dmg_taken", "pct": v}, src)
			"dmg_taken":     _push(t, {"kind": "dmg_taken", "pct": v}, src)
			"dmg_taken_flat":
				_push(t, {"kind": "dmg_taken_flat", "value": v,
					"min_dmg": int(op.get("min_dmg", 0))}, src)
			"dmg_cap_pct":   _push(t, {"kind": "dmg_cap_pct", "pct": v}, src)
			"pen":
				t["pen"] = clampf(float(t.get("pen", 0.0)) + v / 100.0, 0.0, 0.95)
			"gauge_rate":    _push(t, {"kind": "gauge_rate", "pct": v}, src)
			"gauge_min":     _push(t, {"kind": "gauge_min", "value": v}, src)
			"gauge_add":
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
	d["turns"] = -1
	d["src"] = src
	(c["effects"] as Array).append(d)

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
		var base := float(_eff(top, key)) if effective else float(top.get(key, 0))
		if key == "hp":
			base = float(top.get("hp_max", 0)) if effective 				else float(top.get("hp_base", top.get("hp_max", 0)))
		var add := base * pct / 100.0
		if add >= 1.0:
			_aw_add_stat(owner, key, "flat", add, src)

static func _targets(spec: String, owner: Dictionary, allies: Array) -> Array:
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

static func _aw_add_stat(c: Dictionary, s: String, mode: String, v: float, src: String) -> void:
	if s == "hp":
		var before := int(c.get("hp_max", 0))
		var add := int(round(float(before) * v / 100.0)) if mode == "pct" else int(round(v))
		if add == 0:
			return
		c["hp_max"] = maxi(1, before + add)
		c["hp"] = mini(int(c["hp_max"]), int(c.get("hp", before)) + maxi(0, add))
		return
	(c["effects"] as Array).append({"kind": "stat", "stat": s, "mode": mode,
		"value": v, "turns": -1, "src": src})
