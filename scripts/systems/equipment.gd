class_name Equipment
extends RefCounted

const PIECE_SLOTS := 3

const STATS := ["hp", "att", "def", "blk", "evd", "cri", "cri_pow",
				"pure", "depure", "accuracy", "cure", "awaken_rate", "gold", "exp"]

static func event_pool(table: Dictionary) -> Array:
	var out: Array = []
	for e in (table.get("event", []) as Array):
		if bool((e as Dictionary).get("implemented", true)):
			out.append(e)
	return out

static func catalog(table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kind in (table.get("basic", {}) as Dictionary):
		var spec: Dictionary = table["basic"][kind]
		for g in (spec.get("grades", []) as Array):
			var key := "basic:%s:%d" % [kind, int(g["grade"])]
			out[key] = {
				"key": key, "name": String(g["name"]), "group": "basic",
				"slot_class": String(spec.get("slot", "all")),
				"grade": int(g["grade"]),
				"stat_main": {String(spec["stat"]): int(g["value"])},
			}
	for e in event_pool(table):
		var key2 := "event:%s" % String(e["name"])
		out[key2] = {
			"key": key2, "name": String(e["name"]), "group": "event",
			"slot_class": _slot_of(e.get("main", {}), table),
			"stat_main": _int_dict(e.get("main", {})),
		}
	for fam in (table.get("special", {}) as Dictionary):
		var famd: Dictionary = table["special"][fam]
		if not bool(famd.get("implemented", true)):
			continue
		for it in (famd.get("items", []) as Array):
			var key3 := "special:%s:%s" % [fam, String(it["name"])]
			out[key3] = {
				"key": key3, "name": String(it["name"]), "group": "special:" + String(fam),
				"slot_class": _slot_of(it.get("main", {}), table),
				"stat_main": _int_dict(it.get("main", {})),
				"bonus": String(it.get("bonus", "")),
				"acquire": String(famd.get("acquire", "")),
			}
	for x in (table.get("exclusive", {}).get("list", []) as Array):
		var xd := x as Dictionary
		if not bool(xd.get("implemented", false)):
			continue
		var key5 := "exclusive:%s" % String(xd.get("name", ""))
		out[key5] = {
			"key": key5, "name": String(xd.get("name", "")), "group": "exclusive",
			"slot_class": "all", "stat_main": {},
			"dragon_id": int(xd.get("dragon_id", 0)),
			"dragon": String(xd.get("dragon", "")),
			"bonus": String(xd.get("effect", "")),
			"acquire": String(xd.get("acquire", "")),
		}
	var art: Dictionary = table.get("artifacts", {})
	for a in (art.get("types", []) as Array):
		for gi in (art.get("grades", []) as Array).size():
			var key4 := "artifact:%s:%d" % [String(a["name"]), gi]
			out[key4] = {
				"key": key4, "group": "artifact", "slot_class": "artifact", "grade": gi,
				"name": "%s %s" % [String((art["grades"] as Array)[gi]), String(a["name"])],
				"stat_main": {},
				"artifact_effect": String(a.get("effect", "")),
				"artifact_skills": a.get("skills", []),
			}
	return out

static func display_sort_less(a: Dictionary, b: Dictionary) -> bool:
	var aw := bool(a.get("worn", false))
	var bw := bool(b.get("worn", false))
	if aw != bw:
		return aw
	var ar := int((a.get("meta", {}) as Dictionary).get("rarity", 0))
	var br := int((b.get("meta", {}) as Dictionary).get("rarity", 0))
	if ar != br:
		return ar > br
	var ai: Dictionary = a.get("it", {})
	var bi: Dictionary = b.get("it", {})
	var ag := display_group_rank(ai)
	var bg := display_group_rank(bi)
	if ag != bg:
		return ag < bg
	var an := String(ai.get("name", ""))
	var bn := String(bi.get("name", ""))
	if an != bn:
		return an < bn
	return String(a.get("inv", a.get("cat", ""))) < String(b.get("inv", b.get("cat", "")))

static func display_group_rank(item: Dictionary) -> int:
	var group := String(item.get("group", ""))
	if group == "exclusive":
		return 0
	if group.begins_with("special:"):
		return 1
	if group == "artifact":
		return 3
	return 2

static func _slot_of(main: Dictionary, table: Dictionary) -> String:
	for s in (table.get("slots", []) as Array):
		var acc = (s as Dictionary).get("accepts", "*")
		if typeof(acc) != TYPE_ARRAY:
			continue
		for stat in main:
			if String(stat) in acc:
				return String((s as Dictionary)["id"])
	return "all"

static func _int_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[String(k)] = int(d[k])
	return out

static func can_equip(item: Dictionary, slot_id: String) -> bool:
	var cls := String(item.get("slot_class", "all"))
	if slot_id == "all":
		return cls != "artifact"
	return cls == slot_id

static func species_allows(item: Dictionary, dragon_id: int) -> bool:
	var need := int(item.get("dragon_id", 0))
	return need <= 0 or need == dragon_id

const SLOT_ORDER := ["all", "battle", "support", "artifact"]

static func slot_ids(unlocked) -> Array:
	if unlocked is Array:
		var out: Array = []
		for s in SLOT_ORDER:
			if s == "all" or (unlocked as Array).has(s):
				out.append(s)
		return out
	return SLOT_ORDER.slice(0, clampi(int(unlocked), 1, SLOT_ORDER.size()))

static func aggregate(equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var cat := catalog(table)
	var pct: Array = table.get("option", {}).get("pct_stats", [])
	var out: Dictionary = {}
	var main_max: Dictionary = {}
	for s in (equip_field.get("slots", []) as Array):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = cat.get(String(s.get("key", "")), {})
		for stat in (item.get("stat_main", {}) as Dictionary):
			var v := float(item["stat_main"][stat])
			main_max[stat] = maxf(float(main_max.get(stat, 0.0)), v)
		for o in (s.get("options", []) as Array):
			var st := String((o as Dictionary).get("stat", ""))
			if st == "":
				continue
			var key := (st + "_pct") if st in pct else st
			out[key] = float(out.get(key, 0.0)) + float((o as Dictionary).get("value", 0))
	for stat in main_max:
		out[stat] = float(out.get(stat, 0.0)) + float(main_max[stat])
	_add_piece_sets(equip_field, table, out)
	var hid := artifact_hidden(equip_field, table)
	if int(hid.get("evd", 0)) != 0:
		out["evd"] = float(out.get("evd", 0.0)) + float(hid["evd"])
	return out

static func _add_piece_sets(equip_field: Dictionary, table: Dictionary, out: Dictionary) -> void:
	if not bool((table.get("pieces", {}) as Dictionary).get("implemented", true)):
		return
	var worn: Array = equip_field.get("pieces", [])
	if worn.is_empty():
		return
	var count: Dictionary = {}
	for p in worn:
		count[String(p)] = int(count.get(String(p), 0)) + 1
	for pd in (table.get("pieces", {}).get("list", []) as Array):
		var nm := String((pd as Dictionary)["name"])
		var n := int(count.get(nm, 0))
		if n < 2:
			continue
		var eff := _parse_set_effect(String((pd as Dictionary).get("set2", "")))
		for stat in eff:
			out[stat] = float(out.get(stat, 0.0)) + float(eff[stat])

static func _parse_set_effect(text: String) -> Dictionary:
	var map := {"체력": "hp", "공격력": "att", "방어력": "def"}
	for kr in map:
		if not text.begins_with(kr):
			continue
		var rest := text.substr(kr.length()).strip_edges()
		var num := ""
		for ch in rest:
			if ch.is_valid_int():
				num += ch
			elif num != "":
				break
		if num == "":
			return {}
		var key := String(map[kr])
		return {(key + "_pct" if rest.contains("%") else key): int(num)}
	return {}

static func apply(stats: Dictionary, equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	var agg := aggregate(equip_field, table)
	for stat: String in STATS:
		if agg.has(stat):
			out[stat] = int(out.get(stat, 0)) + int(round(float(agg[stat])))
	for base: String in ["hp", "att", "def"]:
		var pk := base + "_pct"
		if agg.has(pk):
			out[base] = int(round(float(int(out.get(base, 0))) * (1.0 + float(agg[pk]) / 100.0)))
	return out

static func artifact_hidden(equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var out := {"proc_add_all": 0, "evd": 0, "skill_uses": 0}
	var arts: Dictionary = table.get("artifacts", {})
	var axes: Dictionary = arts.get("axes", {})
	var hid: Dictionary = arts.get("hidden", {})
	if axes.is_empty() or hid.is_empty():
		return out
	for sl in (equip_field.get("slots", []) as Array):
		var parts := String((sl as Dictionary).get("key", "")).split(":")
		if parts.size() < 3 or parts[0] != "artifact":
			continue
		var spec: Dictionary = hid.get(String(axes.get(String(parts[1]), "")), {})
		for f in spec:
			out[String(f)] = int(out.get(String(f), 0)) + int(spec[f])
	return out

static func artifact_mods(equip_field: Dictionary, table: Dictionary,
		skills_db: Dictionary) -> Dictionary:
	var out := {"proc_add": {}, "power_lv": {}, "foe_proc_sub": {},
				"skill_dmg_taken_pct": {}, "req_hp_relax_pct": {},
				"hidden": artifact_hidden(equip_field, table)}
	var arts: Dictionary = table.get("artifacts", {})
	var axes: Dictionary = arts.get("axes", {})
	var power: Dictionary = arts.get("power", {})
	if axes.is_empty() or power.is_empty():
		return out
	var by_name := _skill_ids_by_name(skills_db)
	for s in (equip_field.get("slots", []) as Array):
		var parts := String((s as Dictionary).get("key", "")).split(":")
		if parts.size() < 3 or parts[0] != "artifact":
			continue
		var kind := String(parts[1])
		var gi := int(parts[2])
		var axis := String(axes.get(kind, ""))
		var spec: Dictionary = power.get(axis, {})
		if axis == "" or spec.is_empty():
			continue
		var names: Array = []
		for t in (arts.get("types", []) as Array):
			if String((t as Dictionary).get("name", "")) == kind:
				names = (t as Dictionary).get("skills", [])
		for field in spec:
			var arr: Array = spec[field]
			if gi < 0 or gi >= arr.size():
				continue
			var v := int(arr[gi])
			if v == 0:
				continue
			var bucket: Dictionary = out[String(field)]
			for nm in names:
				for sid in by_name.get(_norm_skill_name(String(nm)), []):
					bucket[int(sid)] = int(bucket.get(int(sid), 0)) + v
	return out

static func _skill_ids_by_name(skills_db: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in skills_db:
		var sd: Dictionary = skills_db[k]
		var nm := _norm_skill_name(String(sd.get("name", "")))
		if nm == "":
			continue
		if not out.has(nm):
			out[nm] = []
		(out[nm] as Array).append(int(sd.get("id", int(str(k)) if str(k).is_valid_int() else 0)))
	return out

static func _norm_skill_name(nm: String) -> String:
	var s := nm.strip_edges()
	var rb := s.find("]")
	if s.begins_with("[") and rb > 0:
		s = s.substr(rb + 1)
	return s.replace(" ", "")

static func roll_rarity(source: String, rng: RandomNumberGenerator, table: Dictionary) -> int:
	var tbl: Dictionary = table.get("option", {}).get("rarity_rolls", {}).get(source, {})
	if tbl.is_empty():
		return 0
	var total := 0.0
	for g in tbl:
		total += float(tbl[g])
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	var acc := 0.0
	var last := 0
	for g in tbl:
		acc += float(tbl[g])
		last = int(str(g))
		if r < acc:
			return last
	return last

static func roll_instance(source: String, rng: RandomNumberGenerator, table: Dictionary) -> Dictionary:
	var rar := roll_rarity(source, rng, table)
	return {"rarity": rar, "options": roll_options(rar, rng, table)}

static func option_count(grade: int, table: Dictionary) -> int:
	var gs: Array = table.get("option", {}).get("grades", [])
	if grade < 0 or grade >= gs.size():
		return 0
	return int((gs[grade] as Dictionary).get("options", 0))

static func enhance_limit(grade: int, table: Dictionary) -> int:
	var per := int(table.get("option", {}).get("enhance_per_option", 5))
	return option_count(grade, table) * per

static func enhance_cap(grade: int, option_amount: int, table: Dictionary) -> int:
	var per := int(table.get("option", {}).get("enhance_per_option", 5))
	return mini(grade, option_amount) * per

static func enhance_cap_of_slot(slot: Dictionary, table: Dictionary) -> int:
	return enhance_cap(int(slot.get("grade", 0)),
		(slot.get("options", []) as Array).size(), table)

static func option_stats(table: Dictionary) -> Array:
	return (table.get("option", {}) as Dictionary).get("stats", [])

static func sanitize_options(opts: Array, table: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var pool: Array = option_stats(table)
	if pool.is_empty():
		return [opts, 0]
	var out: Array = []
	var changed := 0
	for o in opts:
		var od: Dictionary = o
		if String(od.get("stat", "")) in pool:
			out.append(od.duplicate())
			continue
		var fresh := roll_option(rng, table)
		if fresh.is_empty():
			continue
		out.append(fresh)
		changed += 1
	return [out, changed]

static func roll_option(rng: RandomNumberGenerator, table: Dictionary,
		weights: Dictionary = {}) -> Dictionary:
	var opt: Dictionary = table.get("option", {})
	var stats: Array = opt.get("stats", [])
	var ranges: Dictionary = opt.get("value_ranges", {})
	if stats.is_empty():
		return {}
	var stat := ""
	if weights.is_empty():
		stat = String(stats[rng.randi() % stats.size()])
	else:
		var total := 0.0
		for s in stats:
			total += maxf(0.0, float(weights.get(String(s), 1.0)))
		if total <= 0.0:
			return {}
		var r0 := rng.randf() * total
		var acc := 0.0
		for s in stats:
			acc += maxf(0.0, float(weights.get(String(s), 1.0)))
			stat = String(s)
			if r0 < acc:
				break
	var r: Array = ranges.get(stat, [1, 1])
	var lo := int(r[0])
	var hi := int(r[1]) if r.size() > 1 else lo
	return {"stat": stat, "value": rng.randi_range(lo, maxi(lo, hi))}

static func roll_options(grade: int, rng: RandomNumberGenerator, table: Dictionary,
		weights: Dictionary = {}) -> Array:
	var out: Array = []
	for _i in option_count(grade, table):
		var o := roll_option(rng, table, weights)
		if not o.is_empty():
			out.append(o)
	return out

static func enhance_step_of(value: int, table: Dictionary) -> int:
	var step := float(table.get("option", {}).get("enhance_step_pct", 10))
	return maxi(1, int(round(float(value) * step / 100.0)))

static func apply_enhance_steps(opts: Array, times: int, rng: RandomNumberGenerator,
		table: Dictionary) -> Array:
	var out: Array = opts.duplicate(true)
	if out.is_empty() or times <= 0:
		return out
	for _i in times:
		var od := out[rng.randi() % out.size()] as Dictionary
		var v := int(od.get("value", 0))
		od["value"] = v + enhance_step_of(v, table)
	return out

static func roll_options_at_enhance(grade: int, enhance_times: int,
		rng: RandomNumberGenerator, table: Dictionary, weights: Dictionary = {}) -> Array:
	return apply_enhance_steps(roll_options(grade, rng, table, weights),
		enhance_times, rng, table)

static func artifact_smelt_cfg(table: Dictionary) -> Dictionary:
	return (table.get("option", {}) as Dictionary).get("artifact_smelt", {})

static func artifact_smelt_weights(table: Dictionary) -> Dictionary:
	return artifact_smelt_cfg(table).get("option_weights", {})

static func reroll(equip_field: Dictionary, slot_id: String, grade: int,
		rng: RandomNumberGenerator, table: Dictionary, owner_uid: int = 0) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			continue
		if int((s as Dictionary).get("grade", 0)) != grade:
			return {}
		var times := int((s as Dictionary).get("enhance", 0))
		(s as Dictionary)["options"] = roll_options_at_enhance(grade, times, rng, table)
		if owner_uid > 0 and binds_at(grade, table):
			(s as Dictionary)["belong"] = owner_uid
		return out
	return {}

static func enhance(equip_field: Dictionary, slot_id: String, rng: RandomNumberGenerator,
		table: Dictionary) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		var sd := s as Dictionary
		if String(sd.get("slot", "")) != slot_id:
			continue
		var opts: Array = sd.get("options", [])
		if opts.is_empty():
			return {}
		if enchant_blocked(sd, table) != "":
			return {}
		var i := rng.randi() % opts.size()
		var od := opts[i] as Dictionary
		od["value"] = int(od.get("value", 0)) + enhance_step_of(int(od.get("value", 0)), table)
		sd["enhance"] = int(sd.get("enhance", 0)) + 1
		var extra := int(enchant_cfg(table).get("extra_option_pct", 0))
		if extra > 0 and opts.size() < 6 and rng.randi() % 100 < extra:
			var no := roll_option(rng, table)
			if not no.is_empty():
				opts.append(no)
		return out
	return {}

static func equip(equip_field: Dictionary, slot_id: String, key: String, table: Dictionary,
		meta: Dictionary = {}, dragon_id: int = 0) -> Dictionary:
	var cat := catalog(table)
	if not cat.has(key):
		return {}
	if not can_equip(cat[key], slot_id):
		return {}
	if dragon_id > 0 and not species_allows(cat[key], dragon_id):
		return {}
	var slots: Array = []
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			slots.append(s)
	slots.append({
		"slot": slot_id, "key": key,
		"options": (meta.get("options", []) as Array).duplicate(true),
		"grade": int(meta.get("rarity", 0)),
		"enhance": int(meta.get("enhance", 0)),
		"belong": int(meta.get("belong", 0)),
	})
	var out := equip_field.duplicate(true)
	out["slots"] = slots
	return out

static func unequip(equip_field: Dictionary, slot_id: String) -> Dictionary:
	var slots: Array = []
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) != slot_id:
			slots.append(s)
	var out := equip_field.duplicate(true)
	out["slots"] = slots
	return out

static func equipped(equip_field: Dictionary, slot_id: String, table: Dictionary) -> Dictionary:
	var cat := catalog(table)
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return cat.get(String((s as Dictionary).get("key", "")), {})
	return {}

const ITEM_PREFIX := "equip:"

const OPTION_CODE := {
	"hp": "H", "att": "A", "def": "D", "blk": "B", "exp": "E",
	"gold": "G", "pure": "P", "depure": "U", "accuracy": "C",
}

static func option_unit(stat: String, table: Dictionary) -> String:
	var lst: Array = (table.get("option", {}) as Dictionary).get("percent_display", [])
	return "%" if stat in lst else ""

static func option_text(name: String, stat: String, value, table: Dictionary,
		sep: String = " ") -> String:
	return "%s%s+%s%s" % [name, sep, str(value), option_unit(stat, table)]

static func reward_rate_pct(equip_field: Dictionary, table: Dictionary, stat: String) -> float:
	return float(aggregate(equip_field, table).get(stat, 0.0))

static func reward_mult(equip_field: Dictionary, table: Dictionary, stat: String) -> float:
	return 1.0 + reward_rate_pct(equip_field, table, stat) / 100.0

static func _code_to_stat(c: String) -> String:
	for st in OPTION_CODE:
		if String(OPTION_CODE[st]) == c:
			return String(st)
	return ""

static func item_key(catalog_key: String, meta: Dictionary = {}) -> String:
	var tok: PackedStringArray = []
	var belong := int(meta.get("belong", 0))
	var rarity := int(meta.get("rarity", 0))
	var enhance := int(meta.get("enhance", 0))
	var opts: Array = meta.get("options", [])
	if belong > 0:
		tok.append("b%d" % belong)
	if rarity > 0:
		tok.append("r%d" % rarity)
	if enhance > 0:
		tok.append("e%d" % enhance)
	if not opts.is_empty():
		var parts: PackedStringArray = []
		for o in opts:
			var st := String((o as Dictionary).get("stat", ""))
			if not OPTION_CODE.has(st):
				continue
			parts.append("%s%d" % [String(OPTION_CODE[st]), int((o as Dictionary).get("value", 0))])
		if not parts.is_empty():
			tok.append("o" + ".".join(parts))
	if tok.is_empty():
		return ITEM_PREFIX + catalog_key
	return "%s%s@%s" % [ITEM_PREFIX, ",".join(tok), catalog_key]

static func parse_item_key(key: String) -> String:
	if not key.begins_with(ITEM_PREFIX):
		return ""
	var rest := key.substr(ITEM_PREFIX.length())
	var at := rest.find("@")
	return rest.substr(at + 1) if at > 0 else rest

static func item_key_meta(key: String) -> Dictionary:
	var out := {"belong": 0, "rarity": 0, "enhance": 0, "options": []}
	if not key.begins_with(ITEM_PREFIX):
		return out
	var rest := key.substr(ITEM_PREFIX.length())
	var at := rest.find("@")
	if at <= 0:
		return out
	var meta := rest.substr(0, at)
	if meta.is_valid_int():
		out["belong"] = int(meta)
		return out
	for t in meta.split(","):
		var body := String(t).substr(1)
		match String(t).substr(0, 1):
			"b": out["belong"] = int(body) if body.is_valid_int() else 0
			"r": out["rarity"] = int(body) if body.is_valid_int() else 0
			"e": out["enhance"] = int(body) if body.is_valid_int() else 0
			"o":
				var opts: Array = []
				for p in body.split("."):
					var s := String(p)
					if s.length() < 2:
						continue
					var st := _code_to_stat(s.substr(0, 1))
					if st != "" and s.substr(1).is_valid_int():
						opts.append({"stat": st, "value": int(s.substr(1))})
				out["options"] = opts
	return out

static func item_key_belong(key: String) -> int:
	return int(item_key_meta(key).get("belong", 0))

static func slot_to_item_key(slot: Dictionary) -> String:
	return item_key(String(slot.get("key", "")), {
		"belong": int(slot.get("belong", 0)),
		"rarity": int(slot.get("grade", 0)),
		"enhance": int(slot.get("enhance", 0)),
		"options": slot.get("options", []),
	})

static func binds_at(grade: int, table: Dictionary) -> bool:
	return grade >= int(table.get("option", {}).get("bind_grade", 2))

static func belong_allows(belong: int, dragon_uid: int) -> bool:
	return belong <= 0 or belong == dragon_uid

static func slot_belong(equip_field: Dictionary, slot_id: String) -> int:
	for s in (equip_field.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return int((s as Dictionary).get("belong", 0))
	return 0

static func unbind(equip_field: Dictionary, slot_id: String) -> Dictionary:
	var out := equip_field.duplicate(true)
	for s in (out.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			if int((s as Dictionary).get("belong", 0)) <= 0:
				return {}
			(s as Dictionary)["belong"] = 0
			return out
	return {}

static func artifact_of(key: String) -> Dictionary:
	var cat := parse_item_key(key)
	if cat == "":
		cat = key
	var p := cat.split(":")
	if p.size() != 3 or String(p[0]) != "artifact":
		return {}
	return {"type": String(p[1]), "grade": int(p[2])}

static func artifact_mix_cfg(table: Dictionary) -> Dictionary:
	return (table.get("artifacts", {}) as Dictionary).get("mix", {})

static func artifact_mix_unit_cost(table: Dictionary, base_key: String) -> int:
	var a := artifact_of(base_key)
	if a.is_empty():
		return 0
	var arr: Array = artifact_mix_cfg(table).get("cost_per_material", [])
	var g := int(a["grade"])
	return int(arr[g]) if g >= 0 and g < arr.size() else 0

static func artifact_mix_cost(table: Dictionary, base_key: String, filled: int) -> int:
	return artifact_mix_unit_cost(table, base_key) * maxi(filled, 0)

static func artifact_mix_upgradable(table: Dictionary, base_key: String) -> bool:
	var a := artifact_of(base_key)
	if a.is_empty():
		return false
	var grades: Array = (table.get("artifacts", {}) as Dictionary).get("grades", [])
	return int(a["grade"]) + 1 < grades.size() \
		and artifact_mix_unit_cost(table, base_key) > 0

static func artifact_mix_material_ok(table: Dictionary, base_key: String, mat_key: String) -> bool:
	var b := artifact_of(base_key)
	var m := artifact_of(mat_key)
	if b.is_empty() or m.is_empty():
		return false
	if bool(artifact_mix_cfg(table).get("same_type_required", true)):
		if String(m["type"]) != String(b["type"]):
			return false
	if bool(artifact_mix_cfg(table).get("same_grade_required", true)):
		if int(m["grade"]) != int(b["grade"]):
			return false
	return true

static func artifact_mix_result(table: Dictionary, base_key: String) -> String:
	var a := artifact_of(base_key)
	if a.is_empty() or not artifact_mix_upgradable(table, base_key):
		return ""
	return item_key("artifact:%s:%d" % [String(a["type"]), int(a["grade"]) + 1],
		item_key_meta(base_key))

static func artifact_mix_success_pct(table: Dictionary, base_key: String) -> int:
	var a := artifact_of(base_key)
	if a.is_empty():
		return 0
	var arr: Array = artifact_mix_cfg(table).get("success_pct", [])
	var g := int(a["grade"])
	return int(arr[g]) if g >= 0 and g < arr.size() else 100

static func enchant_cfg(table: Dictionary) -> Dictionary:
	return table.get("enchant", {}) as Dictionary

static func enchant_type_level(item: Dictionary, table: Dictionary) -> int:
	var grp := String(item.get("group", ""))
	if item.has("grade"):
		return int(item["grade"]) + 1
	var by_grp: Dictionary = enchant_cfg(table).get("type_level_group", {})
	for k in by_grp:
		if grp == String(k) or grp.begins_with(String(k) + ":"):
			return int(by_grp[k])
	return 1

static func enchant_weight(item: Dictionary, rarity: int, upgrade: int,
		table: Dictionary) -> int:
	if item.is_empty():
		return 0
	return enchant_type_level(item, table) + rarity * 2 + upgrade

static func enchant_weight_of_key(key: String, table: Dictionary) -> int:
	var item: Dictionary = catalog(table).get(parse_item_key(key), {})
	if item.is_empty():
		return 0
	var m := item_key_meta(key)
	return enchant_weight(item, int(m.get("rarity", 0)), int(m.get("enhance", 0)), table)

static func enchant_weight_of_slot(slot: Dictionary, table: Dictionary) -> int:
	var item: Dictionary = catalog(table).get(String(slot.get("key", "")), {})
	if item.is_empty():
		return 0
	return enchant_weight(item, int(slot.get("grade", 0)), int(slot.get("enhance", 0)), table)

static func enchant_gold(weight: int, table: Dictionary) -> int:
	return weight * int(enchant_cfg(table).get("gold_per_weight", 500))

static func enchant_base_pct(weight: int, table: Dictionary) -> int:
	var c := enchant_cfg(table)
	var v := int(float(weight) * float(c.get("percent_per_weight", -1.5))
		+ float(c.get("base_percent", 50)))
	return maxi(0, v)

static func enchant_pct(weight: int, mat_weights: Array, table: Dictionary) -> int:
	var base := enchant_base_pct(weight, table)
	var denom := weight * int(enchant_cfg(table).get("material_denom", 5))
	var bonus := 0
	if denom != 0:
		var sum := 0
		for w in mat_weights:
			sum += int(w)
		bonus = int(sum * 100 / denom)
	var v := base + bonus
	return 100 if v > 99 else v

static func enchant_blocked(slot: Dictionary, table: Dictionary) -> String:
	if slot.is_empty():
		return "no_equip"
	var per := int(table.get("option", {}).get("enhance_per_option", 5))
	var grade := int(slot.get("grade", 0))
	var up := int(slot.get("enhance", 0))
	if grade * per <= 0:
		return "min_grade"
	if up >= grade * per:
		return "grade_max"
	if up >= (slot.get("options", []) as Array).size() * per:
		return "option_max"
	return ""
