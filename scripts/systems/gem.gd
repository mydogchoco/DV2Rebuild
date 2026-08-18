class_name Gem
extends RefCounted

static func description_category(name: String, table: Dictionary) -> String:
	if name == "샌즈의 젬":
		return "sands"
	if name == "샌즈의 소울젬":
		return "sands_soul"
	return String(gem_def(name, table).get("category", ""))

const SLOTS := 3
const FLAT_KEYS := ["hp", "att", "def"]
const PCT_KEYS := ["hp_pct", "att_pct", "def_pct"]
const SUB_KEYS := ["cri", "evd", "blk"]

static func gem_def(gem_name: String, table: Dictionary) -> Dictionary:
	return (table.get("gems", {}) as Dictionary).get(gem_name, {})

static func max_tier(gem_name: String, table: Dictionary) -> int:
	var tiers: Array = gem_def(gem_name, table).get("tiers", [])
	return tiers.size() - 1

static func tier_stats(gem_name: String, tier: int, table: Dictionary) -> Dictionary:
	var tiers: Array = gem_def(gem_name, table).get("tiers", [])
	if tiers.is_empty():
		return {}
	return tiers[clampi(tier, 0, tiers.size() - 1)]

static func slots(gems_field: Dictionary) -> Array:
	if gems_field.has("slots"):
		var out: Array = []
		for e in entries(gems_field):
			if e != null:
				out.append(e)
		return out
	return migrate(gems_field)

static func entries(gems_field: Dictionary) -> Array:
	var out: Array = [null, null, null]
	var raw: Array = gems_field.get("slots", []) if gems_field.has("slots") else migrate(gems_field)
	for i in mini(raw.size(), SLOTS):
		var s = raw[i]
		if typeof(s) == TYPE_DICTIONARY and String((s as Dictionary).get("name", "")) != "":
			var e: Dictionary = (s as Dictionary).duplicate()
			e["name"] = String(s["name"])
			e["tier"] = int(s.get("tier", 0))
			if e.has("points"): e["points"] = int(e["points"])
			if e.has("potions"): e["potions"] = int(e["potions"])
			out[i] = e
	return out

static func migrate(old: Dictionary) -> Array:
	var out: Array = []
	for stat: String in FLAT_KEYS:
		var nk: String = "_name_" + stat
		if old.has(nk):
			out.append({"name": String(old[nk]), "tier": int(old.get("_tier_" + stat, 0))})
	return out

static func aggregate(gems_field: Dictionary, table: Dictionary) -> Dictionary:
	var flat := {"hp": 0, "att": 0, "def": 0}
	var pct := {"hp": 0.0, "att": 0.0, "def": 0.0}
	var sub := {"cri": 0.0, "evd": 0.0, "blk": 0.0}
	for s in slots(gems_field):
		if is_broken(s):
			continue
		var t := tier_stats(String(s["name"]), int(s["tier"]), table)
		for k: String in FLAT_KEYS:
			flat[k] = int(flat[k]) + int(t.get(k, 0))
			pct[k] = float(pct[k]) + float(t.get(k + "_pct", 0))
		for k: String in SUB_KEYS:
			sub[k] = float(sub[k]) + float(t.get(k, 0))
	return {"flat": flat, "pct": pct, "sub": sub}

static func apply(stats: Dictionary, gems_field: Dictionary, table: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	var agg := aggregate(gems_field, table)
	var flat: Dictionary = agg["flat"]
	var pct: Dictionary = agg["pct"]
	var sub: Dictionary = agg["sub"]
	for k in FLAT_KEYS:
		var v := float(int(out.get(k, 0)) + int(flat[k]))
		v *= 1.0 + float(pct[k]) / 100.0
		out[k] = int(round(v))
	for k in SUB_KEYS:
		out[k] = int(out.get(k, 0)) + int(round(float(sub[k])))
	return out

const FALLBACK_TYPE := "ALL"

static func type_order(table: Dictionary) -> Array:
	var o: Array = (table.get("slot_types", {}) as Dictionary).get("order", [])
	return o if not o.is_empty() else ["ATT", "DEF", "HP", "ALL"]

static func types(gems_field: Dictionary) -> Array:
	var out: Array = []
	var raw: Array = gems_field.get("types", [])
	for i in SLOTS:
		var t := String(raw[i]) if i < raw.size() else ""
		out.append(t if t != "" else FALLBACK_TYPE)
	return out

static func random_types(table: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var order := type_order(table)
	var out: Array = []
	for _i in SLOTS:
		var k := (rng.randi() if rng != null else randi()) % order.size()
		out.append(String(order[k]))
	return out

static func set_types(gems_field: Dictionary, new_types: Array) -> Dictionary:
	var out := gems_field.duplicate(true)
	out["types"] = types({"types": new_types})
	out["slots"] = entries(gems_field)
	return out

static func accepts(slot_type: String, gem_name: String, table: Dictionary) -> bool:
	var acc: Dictionary = (table.get("slot_types", {}) as Dictionary).get("accept", {})
	if acc.is_empty():
		return true
	var allow: Array = acc.get(slot_type, acc.get(FALLBACK_TYPE, []))
	return allow.has(String(gem_def(gem_name, table).get("code", "")))

static func fit_slot(gems_field: Dictionary, gem_name: String, table: Dictionary) -> int:
	var ty := types(gems_field)
	var en := entries(gems_field)
	for i in SLOTS:
		if en[i] == null and accepts(String(ty[i]), gem_name, table):
			return i
	return -1

static func all_full(gems_field: Dictionary) -> bool:
	for e in entries(gems_field):
		if e == null:
			return false
	return true

static func equip(gems_field: Dictionary, gem_name: String, tier: int, table: Dictionary,
		meta: Dictionary = {}) -> Dictionary:
	var slot := fit_slot(gems_field, gem_name, table)
	if slot < 0:
		return {}
	return equip_at(gems_field, slot, gem_name, tier, table, meta)

static func equip_at(gems_field: Dictionary, slot: int, gem_name: String, tier: int,
		table: Dictionary, meta: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= SLOTS or gem_def(gem_name, table).is_empty():
		return {}
	var en := entries(gems_field)
	if en[slot] != null:
		return {}
	var ty := types(gems_field)
	if not accepts(String(ty[slot]), gem_name, table):
		return {}
	var e := {"name": gem_name, "tier": clampi(tier, 0, maxi(0, max_tier(gem_name, table)))}
	if int(meta.get("points", 0)) > 0:
		e["points"] = int(meta["points"])
	if int(meta.get("potions", 0)) > 0:
		e["potions"] = int(meta["potions"])
	if bool(meta.get("broken", false)):
		e["broken"] = true
	en[slot] = e
	return {"types": ty, "slots": en}

static func equip_key(gems_field: Dictionary, key: String, table: Dictionary) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {}
	return equip(gems_field, String(g["name"]), int(g["tier"]), table, g)

static func unequip_at(gems_field: Dictionary, slot: int) -> Dictionary:
	var en := entries(gems_field)
	if slot >= 0 and slot < SLOTS:
		en[slot] = null
	return {"types": types(gems_field), "slots": en}

static func upgrade_at(gems_field: Dictionary, slot: int, table: Dictionary) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var name := String(en[slot]["name"])
	var tier := int(en[slot]["tier"])
	if tier >= max_tier(name, table):
		return {}
	en[slot] = {"name": name, "tier": tier + 1}
	return {"types": types(gems_field), "slots": en}

static func is_broken(entry) -> bool:
	return typeof(entry) == TYPE_DICTIONARY and bool((entry as Dictionary).get("broken", false))

static func base_success(gem_name: String, tier: int, table: Dictionary) -> int:
	var cfg: Dictionary = (table.get("upgrade", {}) as Dictionary).get("success", {})
	var floor_pct := int(cfg.get("floor_pct", 14))
	if String(gem_def(gem_name, table).get("category", "")) == "soul":
		return clampi(int(cfg.get("base_pct_soul_start", 90)) - int(cfg.get("step_pct_soul", 7)) * tier,
			floor_pct, 100)
	var tbl: Dictionary = cfg.get("by_tier_pct", {})
	if tbl.has(str(tier + 1)):
		return int(tbl[str(tier + 1)])
	return floor_pct

static func upgrade_cost(tier: int, table: Dictionary) -> int:
	var tbl: Dictionary = (table.get("upgrade", {}) as Dictionary).get("cost_gold", {}).get("by_tier", {})
	if tbl.has(str(tier + 1)):
		return int(tbl[str(tier + 1)])
	return 3000 + 600 * maxi(0, tier)

static func point_bonus(points: int, table: Dictionary) -> int:
	var cfg: Dictionary = (table.get("upgrade", {}) as Dictionary).get("success", {})
	return int(floor(float(maxi(0, points)) * float(cfg.get("point_rate", 0.5))))

static func success_chance(gems_field: Dictionary, slot: int, table: Dictionary) -> int:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return 0
	var e: Dictionary = en[slot]
	return clampi(base_success(String(e["name"]), int(e["tier"]), table)
		+ point_bonus(int(e.get("points", 0)), table), 0, 100)

static func inst_success_chance(inst: Dictionary, table: Dictionary) -> int:
	if inst.is_empty():
		return 0
	return clampi(base_success(String(inst.get("name", "")), int(inst.get("tier", 0)), table)
		+ point_bonus(int(inst.get("points", 0)), table), 0, 100)

static func _normal_cfg(table: Dictionary) -> Dictionary:
	return (table.get("upgrade", {}) as Dictionary).get("normal", {})

static func normal_upgrade_gold(tier: int, table: Dictionary, count := 1) -> int:
	var per := int(_normal_cfg(table).get("gold_per_tier", 500))
	return per * (maxi(0, tier) + 1) * maxi(1, count)

static func normal_success_rate(target_tier: int, mat_tier: int, table: Dictionary) -> float:
	var r: Dictionary = _normal_cfg(table).get("rate", {})
	var base := float(r.get("base", 35.0))
	var tstep := float(r.get("target_step", 2.5))
	var mstep := float(r.get("mat_step", 1.0))
	var div := float(r.get("divisor", 25.0))
	var fl := float(r.get("floor_pct", 5)) / 100.0
	if div == 0.0:
		return fl
	var v := (base - tstep * float(maxi(0, target_tier) + 1) + mstep * float(maxi(0, mat_tier) + 1)) / div
	return maxf(fl, v)

static func normal_success_pct(target_tier: int, mat_tier: int, table: Dictionary) -> int:
	return clampi(int(round(normal_success_rate(target_tier, mat_tier, table) * 100.0)), 0, 100)

static func is_category(gem_name: String, table: Dictionary, want: String) -> bool:
	return String(gem_def(gem_name, table).get("category", "")) == want

static func roll_normal_upgrade(inst: Dictionary, mat_tier: int, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if inst.is_empty() or is_broken(inst):
		return {}
	var e: Dictionary = inst.duplicate()
	var nm := String(e.get("name", ""))
	var tier := int(e.get("tier", 0))
	if tier >= max_tier(nm, table):
		return {}
	var rate := normal_success_rate(tier, mat_tier, table)
	var ok := (rng.randf() if rng != null else randf()) < rate
	if ok:
		e["tier"] = tier + 1
	else:
		e["broken"] = true
	return {"inst": e, "ok": ok, "broken": not ok,
			"chance_pct": normal_success_pct(tier, mat_tier, table)}

static func inst_add_potion(inst: Dictionary, potion: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if inst.is_empty() or is_broken(inst):
		return {}
	var up: Dictionary = table.get("upgrade", {})
	var max_try := int(up.get("potion_max_per_try", 5))
	var e: Dictionary = inst.duplicate()
	var used := int(e.get("potions", 0))
	if used >= max_try:
		return {}
	var gained := 0
	if potion.has("points"):
		var lo := int((potion["points"] as Array)[0])
		var hi := int((potion["points"] as Array)[1])
		gained = lo + ((rng.randi() if rng != null else randi()) % maxi(1, hi - lo + 1))
	else:
		gained = int(potion.get("success_pct", 0))
	var pts := int(e.get("points", 0)) + gained
	var reset := false
	if pts > int(up.get("alchemy_point_overflow", 100)):
		pts = 0
		reset = true
	e["points"] = pts
	e["potions"] = used + 1
	return {"inst": e, "gained": gained, "points": pts, "reset": reset,
			"uses_left": max_try - (used + 1)}

static func inst_roll_upgrade(inst: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if inst.is_empty() or is_broken(inst):
		return {}
	var e: Dictionary = inst.duplicate()
	var nm := String(e.get("name", ""))
	var tier := int(e.get("tier", 0))
	if tier >= max_tier(nm, table):
		return {}
	var chance := inst_success_chance(e, table)
	var roll := (rng.randf() if rng != null else randf()) * 100.0
	var ok := roll < float(chance)
	e["points"] = 0
	e["potions"] = 0
	if ok:
		e["tier"] = tier + 1
	else:
		e["broken"] = true
	return {"inst": e, "ok": ok, "broken": not ok, "chance": chance}

static func inst_repair(inst: Dictionary) -> Dictionary:
	if not is_broken(inst):
		return {}
	var e: Dictionary = inst.duplicate()
	e.erase("broken")
	return e

static func add_potion(gems_field: Dictionary, slot: int, potion: Dictionary, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var r := inst_add_potion(en[slot], potion, table, rng)
	if r.is_empty():
		return {}
	en[slot] = r["inst"]
	r.erase("inst")
	r["field"] = {"types": types(gems_field), "slots": en}
	return r

static func roll_upgrade(gems_field: Dictionary, slot: int, table: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var r := inst_roll_upgrade(en[slot], table, rng)
	if r.is_empty():
		return {}
	en[slot] = r["inst"]
	r.erase("inst")
	r["field"] = {"types": types(gems_field), "slots": en}
	return r

static func hybrid_pool(table: Dictionary) -> Array:
	var out: Array = []
	for name in (table.get("gems", {}) as Dictionary):
		if String((table["gems"][name] as Dictionary).get("category", "")) == "hybrid":
			out.append(String(name))
	out.sort()
	return out

static func sands_bonus(item_key: String, table: Dictionary) -> int:
	for s in ((table.get("craft", {}) as Dictionary).get("sands_tear_items", []) as Array):
		if String((s as Dictionary).get("item", "")) == item_key:
			return int((s as Dictionary).get("sands_bonus_pct", 0))
	return 0

static func sands_chance(table: Dictionary, bonus_pct: int) -> int:
	var pool := hybrid_pool(table)
	if pool.is_empty():
		return 0
	var base := int(round(100.0 / float(pool.size())))
	return clampi(base + maxi(0, bonus_pct), 0, 100)

static func craft_hybrid(table: Dictionary, bonus_pct: int = 0,
		rng: RandomNumberGenerator = null) -> String:
	var pool := hybrid_pool(table)
	if pool.is_empty():
		return ""
	var sands := String((table.get("craft", {}) as Dictionary).get("sands_gem_name", "샌즈의 젬"))
	if not pool.has(sands):
		sands = ""
	var roll := int((rng.randf() if rng != null else randf()) * 100.0)
	if sands != "" and roll < sands_chance(table, bonus_pct):
		return sands
	var rest: Array = pool.duplicate()
	if sands != "":
		rest.erase(sands)
	if rest.is_empty():
		return sands
	return String(rest[(rng.randi() if rng != null else randi()) % rest.size()])

static func disassemble_dust(tier: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	var base := float(dc.get("dust_pow_base", 1.55))
	var div := int(dc.get("dust_div", 10))
	return maxi(1, int(pow(base, float(maxi(0, tier)))) / maxi(1, div))

static func disassemble_gold(count: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	return maxi(0, count) * int(dc.get("gold_per_gem", 500))

static func disassemble_special(tier: int, table: Dictionary) -> int:
	var dc: Dictionary = table.get("disassemble", {})
	var min_t := int(dc.get("special_min_tier", 13))
	var lvl := tier + 1
	if lvl < min_t:
		return 0
	var lo := int(dc.get("special_min", 1))
	var hi := int(dc.get("special_max", 36))
	var span := maxi(1, 18 - min_t)
	return clampi(lo + int(round(float(hi - lo) * float(lvl - min_t) / float(span))), lo, hi)

static func dust_key_for(gem_name: String) -> String:
	if "방어" in gem_name:
		return "def_powder"
	if "체력" in gem_name:
		return "hp_powder"
	return "att_powder"

static func repair_cost(tier: int, table: Dictionary) -> int:
	var tbl: Dictionary = (table.get("upgrade", {}) as Dictionary).get("repair_diamond", {})
	var vals: Array = tbl.values()
	if vals.is_empty():
		return tier + 1
	return int(vals[clampi(tier, 0, vals.size() - 1)])

static func repair(gems_field: Dictionary, slot: int) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or not is_broken(en[slot]):
		return {}
	var e: Dictionary = (en[slot] as Dictionary).duplicate()
	e.erase("broken")
	en[slot] = e
	return {"types": types(gems_field), "slots": en}

static func promote_at(gems_field: Dictionary, slot: int, table: Dictionary) -> Dictionary:
	var en := entries(gems_field)
	if slot < 0 or slot >= SLOTS or en[slot] == null:
		return {}
	var name := String(en[slot]["name"])
	var gd := gem_def(name, table)
	var to_code := String(gd.get("promote_to", ""))
	if to_code == "":
		return {}
	if int(en[slot]["tier"]) < max_tier(name, table):
		return {}
	var to_name := name_of_code(to_code, table)
	if to_name == "":
		return {}
	if not accepts(String(types(gems_field)[slot]), to_name, table):
		return {}
	en[slot] = {"name": to_name, "tier": 0}
	return {"types": types(gems_field), "slots": en}

static func primary_stat(code: String) -> String:
	var c := code.substr(4) if code.begins_with("SOUL") else code
	if c.begins_with("HP"):
		return "hp"
	if c.begins_with("ATT"):
		return "att"
	if c.begins_with("DEF"):
		return "def"
	return "hp"

static func display_name(gem_name: String, tier: int, table: Dictionary) -> String:
	var gd := gem_def(gem_name, table)
	if gd.is_empty():
		return gem_name
	if String(gd.get("category", "")) == "soul":
		return "%s +%d" % [gem_name, tier + 1]
	var t := tier_stats(gem_name, tier, table)
	return "%s +%d" % [gem_name, int(t.get(primary_stat(String(gd.get("code", ""))), 0))]

static func shape_label(gem_name: String, tier: int, table: Dictionary) -> String:
	var gd := gem_def(gem_name, table)
	if String(gd.get("category", "")) == "soul":
		return "%d단계" % (tier + 1)
	var shapes: Array = gd.get("shapes", [])
	return String(shapes[tier]) if tier >= 0 and tier < shapes.size() else "%d단계" % (tier + 1)

const STAT_KR := {
	"hp": "체력", "att": "공격력", "def": "방어력",
	"hp_pct": "체력", "att_pct": "공격력", "def_pct": "방어력",
	"cri": "크리티컬 확률", "evd": "회피율", "blk": "방어율",
}

static func effect_text(gem_name: String, tier: int, table: Dictionary) -> String:
	var t := tier_stats(gem_name, tier, table)
	var parts: PackedStringArray = []
	for k: String in FLAT_KEYS:
		if int(t.get(k, 0)) != 0:
			parts.append("%s +%d" % [String(STAT_KR[k]), int(t[k])])
	for k2: String in PCT_KEYS:
		if int(t.get(k2, 0)) != 0:
			parts.append("%s +%d%%" % [String(STAT_KR[k2]), int(t[k2])])
	for k3: String in SUB_KEYS:
		if int(t.get(k3, 0)) != 0:
			parts.append("%s +%d%%" % [String(STAT_KR[k3]), int(t[k3])])
	return ", ".join(parts)

static func name_of_code(code: String, table: Dictionary) -> String:
	for n in (table.get("gems", {}) as Dictionary):
		if String((table["gems"][n] as Dictionary).get("code", "")) == code:
			return String(n)
	return ""

const ITEM_PREFIX := "gem:"

const META_POINTS := "p"
const META_POTIONS := "u"
const META_BROKEN := "x"

static func item_key(gem_name: String, tier: int, meta: Dictionary = {}) -> String:
	var body := "%s:%d" % [gem_name, tier]
	var tok: PackedStringArray = []
	if int(meta.get("points", 0)) > 0:
		tok.append("%s%d" % [META_POINTS, int(meta["points"])])
	if int(meta.get("potions", 0)) > 0:
		tok.append("%s%d" % [META_POTIONS, int(meta["potions"])])
	if bool(meta.get("broken", false)):
		tok.append(META_BROKEN)
	if tok.is_empty():
		return ITEM_PREFIX + body
	return "%s%s@%s" % [ITEM_PREFIX, ",".join(tok), body]

static func parse_item_key(key: String) -> Dictionary:
	if not key.begins_with(ITEM_PREFIX):
		return {}
	var rest := key.substr(ITEM_PREFIX.length())
	var meta := ""
	var at := rest.find("@")
	if at > 0:
		meta = rest.substr(0, at)
		rest = rest.substr(at + 1)
	var cut := rest.rfind(":")
	if cut <= 0:
		return {}
	var out := {"name": rest.substr(0, cut), "tier": int(rest.substr(cut + 1)),
		"points": 0, "potions": 0, "broken": false}
	for t in meta.split(",", false):
		var s := String(t)
		var body := s.substr(1)
		match s.substr(0, 1):
			META_POINTS: out["points"] = int(body) if body.is_valid_int() else 0
			META_POTIONS: out["potions"] = int(body) if body.is_valid_int() else 0
			META_BROKEN: out["broken"] = true
	return out

static func item_key_meta(key: String) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {"points": 0, "potions": 0, "broken": false}
	return {"points": int(g["points"]), "potions": int(g["potions"]), "broken": bool(g["broken"])}

static func slot_to_item_key(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var e: Dictionary = entry
	return item_key(String(e.get("name", "")), int(e.get("tier", 0)), e)

static func item_key_to_slot(key: String) -> Dictionary:
	var g := parse_item_key(key)
	if g.is_empty():
		return {}
	var e := {"name": String(g["name"]), "tier": int(g["tier"])}
	if int(g["points"]) > 0:
		e["points"] = int(g["points"])
	if int(g["potions"]) > 0:
		e["potions"] = int(g["potions"])
	if bool(g["broken"]):
		e["broken"] = true
	return e
