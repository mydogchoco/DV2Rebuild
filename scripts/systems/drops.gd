class_name Drops
extends RefCounted

const SOURCE_NORMAL := "normal"
const SOURCE_CHEST := "chest"
const SOURCE_BOSS := "boss"

const ELEMENT_ALIAS := {"ground": "earth", "water": "aqua"}

static func normalize_element(element) -> String:
	if typeof(element) != TYPE_STRING:
		return ""
	return String(ELEMENT_ALIAS.get(element, element))

static func food_pool(item_defs: Dictionary, stage_element) -> Array:
	var want := normalize_element(stage_element)
	if want == "" or want == "none":
		return []
	var out: Array = []
	for k in item_defs:
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("category", "")) != "food":
			continue
		if normalize_element(v.get("element", "")) == want:
			out.append(String(k))
	out.sort()
	return out

static func roll_food(item_defs: Dictionary, stage_element,
		rng: RandomNumberGenerator) -> String:
	var pool := food_pool(item_defs, stage_element)
	if pool.is_empty():
		return ""
	return String(pool[rng.randi() % pool.size()])

static func essence_of(item_defs: Dictionary, stage_element) -> String:
	var want := normalize_element(stage_element)
	if want == "" or want == "none":
		return ""
	for k in item_defs:
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("subcategory", "")) != "essence":
			continue
		if normalize_element(v.get("element", "")) == want:
			return String(k)
	return ""

static func roll_essence(table: Dictionary, item_defs: Dictionary, stage_element,
		source: String, rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("essence", {})
	if cfg.is_empty():
		return {}
	if rng.randf() >= float((cfg.get("chance", {}) as Dictionary).get(source, 0.0)):
		return {}
	var key := essence_of(item_defs, stage_element)
	if key == "":
		return {}
	var c: Dictionary = cfg.get("count", {})
	var lo := int(c.get("min", 1))
	return {"key": key, "count": rng.randi_range(lo, maxi(lo, int(c.get("max", 1))))}

static func rare_element_allowed(table: Dictionary, mode: String, boss: bool) -> bool:
	var cfg: Dictionary = table.get("rare_element", {})
	if cfg.is_empty():
		return false
	match String((cfg.get("modes", {}) as Dictionary).get(mode, "")):
		"any": return true
		"boss": return boss
	return false

static func roll_rare_element(table: Dictionary, mode: String, boss: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	if not rare_element_allowed(table, mode, boss):
		return {}
	var cfg: Dictionary = table.get("rare_element", {})
	var pool: Array = cfg.get("pool", [])
	if pool.is_empty():
		return {}
	if rng.randf() >= float(cfg.get("chance", 0.0)):
		return {}
	var row: Dictionary = pool[rng.randi() % pool.size()]
	var lo := int(row.get("min", 1))
	return {"key": String(row.get("key", "")),
		"count": rng.randi_range(lo, maxi(lo, int(row.get("max", 1))))}

static func drink_pool(table: Dictionary, item_defs: Dictionary) -> Array:
	var cfg: Dictionary = table.get("drink", {})
	if cfg.is_empty():
		return []
	var tiers: Array = cfg.get("tiers", [])
	var out: Array = []
	for k in item_defs:
		if typeof(item_defs[k]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = item_defs[k]
		if String(v.get("subcategory", "")) != "drink":
			continue
		if not v.has("tier"):
			continue
		for t in tiers:
			if int(t) == int(v.get("tier", 0)):
				out.append(String(k))
				break
	out.sort()
	return out

static func roll_drink(table: Dictionary, item_defs: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("drink", {})
	if cfg.is_empty():
		return {}
	if rng.randf() >= float(cfg.get("chance", 0.0)):
		return {}
	var pool := drink_pool(table, item_defs)
	if pool.is_empty():
		return {}
	var c: Dictionary = cfg.get("count", {})
	var lo := int(c.get("min", 1))
	return {"key": String(pool[rng.randi() % pool.size()]),
		"count": rng.randi_range(lo, maxi(lo, int(c.get("max", 1))))}

const MODE_NORMAL := "normal"
const MODE_HERO := "hero"
const MODE_NIGHT := "night"
const MODE_KADES := "kades"

static func mode_of(hero: bool, night: bool, kades: bool) -> String:
	if kades: return MODE_KADES
	if night: return MODE_NIGHT
	if hero: return MODE_HERO
	return MODE_NORMAL

static func special_table(stage: Dictionary, mode: String) -> Array:
	var d = stage.get("drops", [])
	if typeof(d) == TYPE_ARRAY:
		return d as Array
	var dd: Dictionary = d
	if mode == MODE_NIGHT:
		return (dd.get(MODE_NIGHT, []) as Array)
	if dd.has(mode):
		return dd[mode] as Array
	return (dd.get(MODE_NORMAL, []) as Array)

static func roll_special(stage: Dictionary, rng: RandomNumberGenerator,
		mode := MODE_NORMAL, is_boss := true) -> Array:
	var legacy := typeof(stage.get("drops", [])) == TYPE_ARRAY
	var out: Array = []
	for d in special_table(stage, mode):
		var dp: Dictionary = d
		if bool(dp.get("boss_only", false)) and not is_boss:
			continue
		var pct := float(dp.get("chance", dp.get("rate", 100)))
		if rng.randf() * 100.0 >= pct:
			continue
		match String(dp.get("kind", "item")):
			"skill_scroll":
				var sid := int(dp.get("skill", 0))
				if sid <= 0:
					continue
				var lv := _pick_level(dp, rng)
				if lv > 0:
					out.append({"kind": "item", "key": Loadout.item_key(sid, lv), "count": 1})
			_:
				var key := String(dp.get("item", dp.get("key", "")))
				if key == "":
					continue
				var lo := int(dp.get("min", 1))
				var hi := int(dp.get("max", 1))
				if legacy and mode == MODE_HERO and dp.has("hero_min"):
					lo = int(dp["hero_min"])
					hi = int(dp.get("hero_max", dp["hero_min"]))
				var qty := rng.randi_range(mini(lo, hi), maxi(lo, hi))
				if qty > 0:
					out.append({"kind": "item", "key": key, "count": qty})
	return out

static func _pick_level(row: Dictionary, rng: RandomNumberGenerator) -> int:
	var lw: Array = row.get("level_weights", [1])
	var levels: Array = row.get("levels", [])
	var i := _weighted_index(lw, rng)
	if levels.is_empty():
		return i + 1
	return int(levels[clampi(i, 0, levels.size() - 1)])

static func monster_table(table: Dictionary, monster_id: int) -> Array:
	if monster_id <= 0:
		return []
	return ((table.get("drops", {}) as Dictionary).get(str(monster_id), []) as Array)

static func roll_monster(table: Dictionary, monster_id: int,
		rng: RandomNumberGenerator) -> Array:
	var rows := monster_table(table, monster_id)
	if rows.is_empty():
		return []
	var by_kind: Dictionary = {}
	for r in rows:
		var k := String((r as Dictionary).get("kind", "item"))
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(r)
	var out: Array = []
	for k in by_kind:
		var group: Array = by_kind[k]
		var row: Dictionary = group[_pick_weighted_row(group, rng)]
		if rng.randf() * 100.0 >= float(row.get("chance", 100)):
			continue
		var got := _monster_grant(row, rng)
		if not got.is_empty():
			out.append(got)
	return out

static func _monster_grant(row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var lo := int(row.get("min", 1))
	var hi := int(row.get("max", 1))
	var qty := rng.randi_range(mini(lo, hi), maxi(lo, hi))
	match String(row.get("kind", "item")):
		"item":
			var key := String(row.get("key", ""))
			if key == "" or qty <= 0:
				return {}
			return {"kind": "item", "key": key, "count": qty}
		"skill_scroll":
			var sid := int(row.get("skill", 0))
			if sid <= 0:
				return {}
			var lv := _pick_level(row, rng)
			return {"kind": "item", "key": Loadout.item_key(sid, lv), "count": 1}
		"egg":
			var did := int(row.get("dragon", 0))
			if did <= 0:
				return {}
			return {"kind": "item", "key": EggGacha.key_for(did), "count": maxi(1, qty)}
		"currency":
			var cur := String(row.get("currency", ""))
			if cur == "" or qty <= 0:
				return {}
			return {"kind": "currency", "currency": cur, "count": qty}
	return {}

static func _levels_of(row: Dictionary) -> Array:
	var levels: Array = row.get("levels", [])
	if not levels.is_empty():
		return levels
	var out: Array = []
	for i in (row.get("level_weights", [1]) as Array).size():
		out.append(i + 1)
	return out

static func _pick_weighted_row(rows: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in rows:
		total += maxf(0.0, float((r as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rng.randi() % rows.size()
	var x := rng.randf() * total
	for i in rows.size():
		x -= maxf(0.0, float((rows[i] as Dictionary).get("weight", 1)))
		if x <= 0.0:
			return i
	return rows.size() - 1

static func monster_keys(table: Dictionary, monster_id: int) -> Array:
	var out: Array = []
	for r in monster_table(table, monster_id):
		var row: Dictionary = r
		match String(row.get("kind", "item")):
			"item":
				out.append(String(row.get("key", "")))
			"skill_scroll":
				for lv in _levels_of(row):
					out.append(Loadout.item_key(int(row.get("skill", 0)), int(lv)))
			"egg":
				out.append(EggGacha.key_for(int(row.get("dragon", 0))))
	return out

static func is_allowed(key: String, stage: Dictionary, item_defs: Dictionary,
		table: Dictionary, hero := false, mode := "",
		monster_doc: Dictionary = {}, monster_id := 0) -> bool:
	if key == "":
		return false
	var m := mode if mode != "" else (MODE_HERO if hero else MODE_NORMAL)
	if monster_keys(monster_doc, monster_id).has(key):
		return true
	if key.begins_with(EggGacha.KEY_PREFIX):
		return egg_pool(stage, hero).has(EggGacha.dragon_of(key)) \
			or (hero and egg_pool(stage, true, true).has(EggGacha.dragon_of(key)))
	if not Gem.parse_item_key(key).is_empty():
		return true
	if Equipment.parse_item_key(key) != "":
		return true
	if food_pool(item_defs, stage.get("element", "")).has(key):
		return true
	if key == essence_of(item_defs, stage.get("element", "")):
		return true
	if String((table.get("rare_element", {}) as Dictionary).get("modes", {}).get(m, "")) != "":
		for r in (table.get("rare_element", {}).get("pool", []) as Array):
			if String((r as Dictionary).get("key", "")) == key:
				return true
	if drink_pool(table, item_defs).has(key):
		return true
	for d in special_table(stage, m):
		var dp: Dictionary = d
		if String(dp.get("kind", "item")) == "skill_scroll":
			for lv in _levels_of(dp):
				if Loadout.item_key(int(dp.get("skill", 0)), int(lv)) == key:
					return true
		elif String(dp.get("item", dp.get("key", ""))) == key:
			return true
	return false

static func egg_pool(stage: Dictionary, hero: bool, hero_only := false) -> Array:
	var out: Array = []
	for d in (stage.get("dragons", []) as Array):
		var did := int((d as Dictionary).get("id", 0))
		if did <= 0:
			continue
		var is_h := bool((d as Dictionary).get("hero", false))
		if is_h and not hero:
			continue
		if hero_only != is_h:
			continue
		out.append(did)
	out.sort()
	return out

static func roll_egg(table: Dictionary, stage: Dictionary, source: String,
		rng: RandomNumberGenerator, hero := false) -> String:
	var cfg: Dictionary = table.get("egg", {})
	if cfg.is_empty():
		return ""
	if hero:
		var hp := egg_pool(stage, true, true)
		if not hp.is_empty():
			var hc := float((cfg.get("hero_chance", {}) as Dictionary).get(source, 0.0))
			if rng.randf() < hc:
				return EggGacha.KEY_PREFIX + str(hp[rng.randi() % hp.size()])
	var pool := egg_pool(stage, hero)
	if pool.is_empty():
		return ""
	if rng.randf() >= float((cfg.get("chance", {}) as Dictionary).get(source, 0.0)):
		return ""
	return EggGacha.KEY_PREFIX + str(pool[rng.randi() % pool.size()])

static func roll_exploration(table: Dictionary, level: int, source: String,
		equip_table: Dictionary, rng: RandomNumberGenerator, kades := false,
		field := 0, artifact_mult := 1.0) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var src: Dictionary = (exp_t.get("sources", {}) as Dictionary).get(source, {})
	if src.is_empty():
		return ""
	if kades:
		var a := roll_artifact(table, source, rng, field, artifact_mult, equip_table)
		if a != "":
			return a
	if rng.randf() >= float(src.get("chance", 0.0)):
		return ""
	var quality := int(src.get("quality", 0))
	if kades:
		quality += int((table.get("kades", {}) as Dictionary).get("quality_bonus", 0))
	return _roll_gem_or_equip(table, level, quality, equip_table, rng)

static func _roll_gem_or_equip(table: Dictionary, level: int, quality: int,
		equip_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var kw: Dictionary = exp_t.get("kind_weights", {"gem": 50, "equip": 50})
	var gw := float(kw.get("gem", 50))
	var total := gw + float(kw.get("equip", 50))
	if total <= 0.0:
		return ""
	if rng.randf() * total < gw:
		return _roll_gem(table, level, quality, rng)
	return _roll_equip(table, level, quality, equip_table, rng)

static func _roll_gem(table: Dictionary, level: int, quality: int,
		rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var pool: Array = exp_t.get("gem_pool", [])
	if pool.is_empty():
		return ""
	var cfg: Dictionary = exp_t.get("gem_tier", {})
	var tier := _band_roll(cfg, level, quality, rng)
	return Gem.item_key(String(pool[rng.randi() % pool.size()]), tier)

static func _roll_equip(table: Dictionary, level: int, quality: int,
		equip_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var exp_t: Dictionary = table.get("exploration", {})
	var kinds: Array = exp_t.get("equip_kinds", [])
	if kinds.is_empty():
		return ""
	var cfg: Dictionary = exp_t.get("equip_grade", {})
	var kind := String(kinds[rng.randi() % kinds.size()])
	var grade := _band_roll(cfg, level, quality / 2, rng)
	return Equipment.item_key("basic:%s:%d" % [kind, clamp_grade(equip_table, kind, grade)],
		Equipment.roll_instance("drop", rng, equip_table))

static func clamp_grade(equip_table: Dictionary, kind: String, grade: int) -> int:
	var gr: Array = (equip_table.get("basic", {}) as Dictionary).get(kind, {}).get("grades", [])
	if gr.is_empty():
		return maxi(0, grade)
	return clampi(grade, 0, gr.size() - 1)

static func _band_roll(cfg: Dictionary, level: int, quality: int,
		rng: RandomNumberGenerator) -> int:
	var center := float(level) * float(cfg.get("per_level", 0.1)) + float(quality)
	var band := int(cfg.get("band", 1))
	var lo := int(floor(center)) - band
	var hi := int(floor(center)) + band
	var vmin := int(cfg.get("min", 0))
	var vmax := int(cfg.get("max", 6))
	lo = clampi(lo, vmin, vmax)
	hi = clampi(hi, lo, vmax)
	return rng.randi_range(lo, hi)

static func roll_artifact(table: Dictionary, source: String,
		rng: RandomNumberGenerator, field := 0, artifact_mult := 1.0,
		equip_table: Dictionary = {}) -> String:
	var kd: Dictionary = table.get("kades", {})
	var ch: Dictionary = kd.get("artifact_chance", {})
	if rng.randf() >= clampf(float(ch.get(source, 0.0)) * artifact_mult, 0.0, 1.0):
		return ""
	var types := artifact_types_for(table, field)
	if types.is_empty():
		return ""
	var grade := _weighted_index(kd.get("artifact_grade", {}).get("weights", [1]), rng)
	var kind := String(types[rng.randi() % types.size()])
	if equip_table.is_empty():
		return Equipment.item_key("artifact:%s:%d" % [kind, grade])
	return Equipment.item_key("artifact:%s:%d" % [kind, grade],
		Equipment.roll_instance("drop", rng, equip_table))

static func artifact_types_for(table: Dictionary, field: int) -> Array:
	var kd: Dictionary = table.get("kades", {})
	var by: Dictionary = kd.get("artifact_by_dungeon", {})
	var lst: Array = by.get(str(field), [])
	return lst if not lst.is_empty() else (kd.get("artifact_types", []) as Array)

static func shop_gems(table: Dictionary) -> Array:
	var sh: Dictionary = table.get("shop", {})
	var pr: Dictionary = sh.get("gem_price", {})
	var out: Array = []
	for name in (sh.get("gem_pool", []) as Array):
		for t in (sh.get("gem_tiers", []) as Array):
			out.append({"key": Gem.item_key(String(name), int(t)),
				"price": int(pr.get("base", 0)) + int(t) * int(pr.get("per_tier", 0))})
	return out

static func shop_equips(table: Dictionary) -> Array:
	var sh: Dictionary = table.get("shop", {})
	var pr: Dictionary = sh.get("equip_price", {})
	var out: Array = []
	for kind in (sh.get("equip_kinds", []) as Array):
		for g in (sh.get("equip_grades", []) as Array):
			out.append({"key": Equipment.item_key("basic:%s:%d" % [String(kind), int(g)]),
				"price": int(pr.get("base", 0)) + int(g) * int(pr.get("per_grade", 0))})
	return out

static func roll_gem_from(cfg: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	var cats: Array = cfg.get("categories", [])
	var names: Array = []
	for n in (gem_table.get("gems", {}) as Dictionary):
		if cats.has(String((gem_table["gems"][n] as Dictionary).get("category", ""))):
			names.append(String(n))
	if names.is_empty():
		return ""
	names.sort()
	var nm := String(names[rng.randi() % names.size()])
	var mx := Gem.max_tier(nm, gem_table)
	var lo := clampi(int(cfg.get("tier_min", 0)), 0, maxi(0, mx))
	var raw_hi := int(cfg.get("tier_max", -1))
	var hi := mx if raw_hi < 0 else clampi(raw_hi, lo, mx)
	return Gem.item_key(nm, rng.randi_range(lo, hi))

static func roll_gem_gacha(table: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	return roll_gem_from(table.get("gacha", {}).get("gem", {}), gem_table, rng)

static func slot_faces(table: Dictionary, gem_table: Dictionary) -> Array:
	var cfg: Dictionary = table.get("slot", {})
	var gcfg: Dictionary = cfg.get("gem", {})
	var w: Dictionary = cfg.get("weights", {})
	var tier := int(gcfg.get("tier_min", 0))
	var faces: Array = []
	for c in (gcfg.get("categories", []) as Array):
		var names: Array = []
		for n in (gem_table.get("gems", {}) as Dictionary):
			if String((gem_table["gems"][n] as Dictionary).get("category", "")) == String(c):
				names.append(String(n))
		if names.is_empty():
			continue
		names.sort()
		var each := float(w.get(String(c), 0.0)) / float(names.size())
		for n in names:
			var t := clampi(tier, 0, maxi(0, Gem.max_tier(String(n), gem_table)))
			faces.append({"kind": "gem", "gem_name": String(n), "tier": t,
				"key": Gem.item_key(String(n), t), "weight": each})
	for it in (cfg.get("items", []) as Array):
		faces.append({"kind": "item", "key": String(it), "weight": float(w.get(String(it), 0.0))})
	return faces

static func _pick_face(faces: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for f in faces:
		total += maxf(0.0, float((f as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return rng.randi() % faces.size()
	var r := rng.randf() * total
	for i in faces.size():
		r -= maxf(0.0, float((faces[i] as Dictionary).get("weight", 0.0)))
		if r <= 0.0:
			return i
	return faces.size() - 1

static func _slot_prize_key(face: Dictionary, cfg: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator) -> String:
	if String(face.get("kind", "")) != "gem":
		return String(face.get("key", ""))
	var gcfg: Dictionary = cfg.get("gem", {})
	var nm := String(face.get("gem_name", ""))
	var mx := Gem.max_tier(nm, gem_table)
	var lo := clampi(int(gcfg.get("tier_min", 0)), 0, maxi(0, mx))
	var raw_hi := int(gcfg.get("tier_max", -1))
	var hi := mx if raw_hi < 0 else clampi(raw_hi, lo, mx)
	return Gem.item_key(nm, rng.randi_range(lo, hi))

static func roll_slot(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg: Dictionary = table.get("slot", {})
	var faces := slot_faces(table, gem_table)
	var out := {"win": false, "reels": [0, 0, 0], "key": "", "count": 0}
	if faces.is_empty():
		return out
	if rng.randf() < float(cfg.get("win_rate", 0.0)):
		var i := _pick_face(faces, rng)
		out["win"] = true
		out["reels"] = [i, i, i]
		out["key"] = _slot_prize_key(faces[i], cfg, gem_table, rng)
		out["count"] = 1
		return out
	var r: Array = [_pick_face(faces, rng), _pick_face(faces, rng), _pick_face(faces, rng)]
	if faces.size() > 1 and r[0] == r[1] and r[1] == r[2]:
		r[2] = (int(r[2]) + 1 + rng.randi() % (faces.size() - 1)) % faces.size()
	out["reels"] = r
	return out

static func roll_slot_many(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		out.append(roll_slot(table, gem_table, rng))
	return out

static func roll_gem_box(table: Dictionary, gem_table: Dictionary, rng: RandomNumberGenerator) -> String:
	return roll_gem_from(table.get("box", {}).get("jem_random", {}), gem_table, rng)

static func roll_gem_box_many(table: Dictionary, gem_table: Dictionary,
		rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		var k := roll_gem_box(table, gem_table, rng)
		if k != "":
			out.append(k)
	return out

static func _exclusive_pool(equip_table: Dictionary) -> Array:
	var out: Array = []
	for x in (equip_table.get("exclusive", {}).get("list", []) as Array):
		var item := x as Dictionary
		if not bool(item.get("implemented", false)):
			continue
		if bool(item.get("gacha_excluded", false)):
			continue
		out.append(item)
	return out

static func _special_pool(equip_table: Dictionary) -> Array:
	var out: Array = []
	for family in (equip_table.get("special", {}) as Dictionary):
		var family_def: Dictionary = equip_table["special"][family]
		if not bool(family_def.get("implemented", false)):
			continue
		if bool(family_def.get("gacha_excluded", false)):
			continue
		for item in (family_def.get("items", []) as Array):
			out.append({"family": String(family), "item": item})
	return out

static func roll_equip_gacha(table: Dictionary, equip_table: Dictionary,
		rng: RandomNumberGenerator, grade_id: String = "high") -> String:
	var eq: Dictionary = table.get("gacha", {}).get("equip", {})
	var g: Dictionary = (eq.get("grades", {}) as Dictionary).get(grade_id, {})
	if g.is_empty():
		return ""
	var events: Array = Equipment.event_pool(equip_table)
	var ew := float(g.get("event_weight", 50)) if not events.is_empty() else 0.0
	var bw := float(g.get("basic_weight", 50))
	var excl: Array = _exclusive_pool(equip_table)
	var xw := float(g.get("exclusive_weight", 0)) if not excl.is_empty() else 0.0
	var special: Array = _special_pool(equip_table)
	var sw := float(g.get("special_weight", 0)) if not special.is_empty() else 0.0
	var total := ew + bw + xw + sw
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	if sw > 0.0 and pick < sw:
		var inst_sp := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")),
			rng, equip_table)
		var sp: Dictionary = special[rng.randi() % special.size()]
		var spi: Dictionary = sp["item"]
		return Equipment.item_key("special:%s:%s" % [String(sp["family"]),
			String(spi.get("name", ""))], inst_sp)
	pick -= sw
	if xw > 0.0 and pick < xw:
		var inst0 := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")),
			rng, equip_table)
		var x: Dictionary = excl[rng.randi() % excl.size()]
		return Equipment.item_key("exclusive:%s" % String(x.get("name", "")), inst0)
	pick -= xw
	var inst := Equipment.roll_instance(String(g.get("rarity_source", "shop_gacha")), rng, equip_table)
	if pick < ew:
		var e: Dictionary = events[rng.randi() % events.size()]
		return Equipment.item_key("event:%s" % String(e.get("name", "")), inst)
	var kinds: Array = table.get("exploration", {}).get("equip_kinds", [])
	var grades: Array = g.get("basic_grades", [0])
	if kinds.is_empty():
		return ""
	var kind := String(kinds[rng.randi() % kinds.size()])
	var grade := int(grades[rng.randi() % grades.size()])
	return Equipment.item_key("basic:%s:%d" % [kind, clamp_grade(equip_table, kind, grade)], inst)

static func display_name(key: String, gem_table: Dictionary, equip_table: Dictionary) -> String:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return Gem.display_name(String(g["name"]), int(g["tier"]), gem_table)
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(equip_table).get(ck, {})
		if not it.is_empty():
			return String(it.get("name", ck))
	return key

static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if r < acc:
			return i
	return weights.size() - 1
