class_name DrinkCraft

const BASE_TIER := 0

static func cfg(defs: Dictionary) -> Dictionary:
	return defs.get("drink_craft", {})

static func parse(defs: Dictionary, key: String) -> Dictionary:
	var c := cfg(defs)
	if key == String(c.get("base_item", "drink")):
		return {"family": "", "tier": BASE_TIER}
	for f in (c.get("families", []) as Array):
		var pre := "%s_drink" % String(f)
		if not key.begins_with(pre):
			continue
		var tail := key.substr(pre.length())
		if not tail.is_valid_int():
			continue
		var t := int(tail)
		if t < 1:
			continue
		return {"family": String(f), "tier": t}
	return {}

static func can_upgrade(defs: Dictionary, key: String) -> bool:
	var d := parse(defs, key)
	return not d.is_empty() and int(d["tier"]) < int(cfg(defs).get("max_tier", 3))

static func is_essence(item_def: Dictionary) -> bool:
	return String(item_def.get("subcategory", "")) == "essence"

static func family_of_essence(defs: Dictionary, item_def: Dictionary) -> String:
	var el := String(item_def.get("element", ""))
	return String((cfg(defs).get("essence_family", {}) as Dictionary).get(el, ""))

static func result_key(defs: Dictionary, drink_key: String, essence_def: Dictionary) -> String:
	if not can_upgrade(defs, drink_key):
		return ""
	var d := parse(defs, drink_key)
	var fam := String(d["family"])
	if fam == "":
		fam = family_of_essence(defs, essence_def)
		if fam == "":
			return ""
	return "%s_drink%d" % [fam, int(d["tier"]) + 1]

static func gold_each(defs: Dictionary, drink_key: String) -> int:
	var d := parse(defs, drink_key)
	if d.is_empty():
		return 0
	var tbl: Dictionary = cfg(defs).get("gold_by_tier", {})
	return int(tbl.get(str(int(d["tier"])), 0))

static func essence_each(defs: Dictionary) -> int:
	return maxi(1, int(cfg(defs).get("essence_per_craft", 3)))

static func success_pct(defs: Dictionary) -> int:
	return clampi(int(cfg(defs).get("success_pct", 100)), 0, 100)

static func max_count(defs: Dictionary, drink_key: String, have_drink: int,
		have_essence: int, gold: int) -> int:
	if not can_upgrade(defs, drink_key):
		return 0
	var n := maxi(0, have_drink)
	n = mini(n, int(have_essence / essence_each(defs)))
	var g := gold_each(defs, drink_key)
	if g > 0:
		n = mini(n, int(gold / g))
	return n

static func cycle_count(cnt: int, delta: int, max_cnt: int) -> int:
	if max_cnt <= 0:
		return 0
	var n := cnt + delta
	if n > max_cnt:
		return 1
	if n < 1:
		return max_cnt
	return n

static func roll(defs: Dictionary, count: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var pct := success_pct(defs)
	var ok := 0
	for _i in maxi(0, count):
		var r := (rng.randf() if rng != null else randf()) * 100.0
		if r < float(pct):
			ok += 1
	return {"ok_n": ok, "fail_n": maxi(0, count) - ok}
