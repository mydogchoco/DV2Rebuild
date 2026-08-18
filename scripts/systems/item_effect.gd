class_name ItemEffect

static func drink_of(defs: Dictionary, key: String) -> Dictionary:
	var d: Dictionary = defs.get("drink", {})
	var stats: Dictionary = d.get("stats", {})
	for prefix in stats.keys():
		if not key.begins_with(String(prefix)):
			continue
		var tail := key.substr(String(prefix).length())
		if not tail.is_valid_int():
			continue
		var tier := int(tail)
		if tier < 1:
			continue
		return {
			"stat": String(stats[prefix]),
			"tier": tier,
			"pct": int(d.get("pct_per_tier", 5)) * tier,
			"turns": int(d.get("duration_turns", 10)),
		}
	return {}

static func apply_drink(active: Dictionary, eff: Dictionary) -> Dictionary:
	if eff.is_empty():
		return active.duplicate(true)
	var out := active.duplicate(true)
	var s := String(eff["stat"])
	var cur: Dictionary = out.get(s, {"pct": 0, "turns": 0})
	out[s] = {
		"pct": maxi(int(cur.get("pct", 0)), int(eff["pct"])),
		"turns": int(cur.get("turns", 0)) + int(eff["turns"]),
	}
	return out

static func tick(active: Dictionary) -> Dictionary:
	var out := {}
	for s in active.keys():
		var b: Dictionary = active[s]
		var t := int(b.get("turns", 0)) - 1
		if t > 0:
			out[s] = {"pct": int(b.get("pct", 0)), "turns": t}
	return out

static func mult(active: Dictionary, stat: String) -> float:
	var b: Dictionary = active.get(stat, {})
	return 1.0 + float(int(b.get("pct", 0))) / 100.0

static func pct(active: Dictionary, stat: String) -> int:
	var b: Dictionary = active.get(stat, {})
	return int(b.get("pct", 0))

static func reward_buff_of(defs: Dictionary, key: String) -> Dictionary:
	var cfg: Dictionary = defs.get("reward_buff", {})
	var row = (cfg.get("items", {}) as Dictionary).get(key, null)
	if not (row is Dictionary):
		return {}
	return {
		"axis": String((row as Dictionary).get("axis", "")),
		"mult": int((row as Dictionary).get("mult", 1)),
		"seconds": int(cfg.get("duration_sec", 3600)),
	}

static func reward_buff_mult(active: Dictionary, axis: String, now: int) -> float:
	var b = active.get(axis, null)
	if not (b is Dictionary):
		return 1.0
	if int((b as Dictionary).get("until", 0)) <= now:
		return 1.0
	return maxf(1.0, float(int((b as Dictionary).get("mult", 1))))

static func reward_buff_left(active: Dictionary, axis: String, now: int) -> int:
	var b = active.get(axis, null)
	if not (b is Dictionary):
		return 0
	return maxi(0, int((b as Dictionary).get("until", 0)) - now)

static func apply_reward_buff(active: Dictionary, eff: Dictionary, now: int) -> Dictionary:
	if eff.is_empty():
		return {"ok": false, "active": active.duplicate(true), "reason": "배수권이 아닙니다"}
	var axis := String(eff["axis"])
	var mult := int(eff["mult"])
	var secs := int(eff["seconds"])
	var out := active.duplicate(true)
	var left := reward_buff_left(active, axis, now)
	var cur := int(reward_buff_mult(active, axis, now))
	if left <= 0:
		out[axis] = {"mult": mult, "until": now + secs}
		return {"ok": true, "active": out, "reason": ""}
	if mult < cur:
		return {"ok": false, "active": out,
			"reason": "이미 %d배 버프가 걸려 있습니다 (남은 시간 %d분)" % [cur, int(ceil(float(left) / 60.0))]}
	if mult == cur:
		out[axis] = {"mult": cur, "until": now + left + secs}
	else:
		out[axis] = {"mult": mult, "until": now + maxi(left, secs)}
	return {"ok": true, "active": out, "reason": ""}

static func prune_reward_buff(active: Dictionary, now: int) -> Dictionary:
	var out := {}
	for a in active.keys():
		var b = active[a]
		if b is Dictionary and int((b as Dictionary).get("until", 0)) > now:
			out[a] = (b as Dictionary).duplicate()
	return out

static func reward_buff_left_text(sec: int) -> String:
	if sec <= 0:
		return ""
	var m := int(ceil(float(sec) / 60.0))
	if m < 60:
		return "%d분" % m
	return "%d시간 %d분" % [m / 60, m % 60]

static func heal_usable(defs: Dictionary, key: String, level: int) -> bool:
	for t in (defs.get("heal_potion", {}).get("tiers", []) as Array):
		if String((t as Dictionary).get("key", "")) == key:
			return level >= int(t.get("level_min", 1)) and level <= int(t.get("level_max", 50))
	return false

static func heal_amount(defs: Dictionary, hp: int, hp_max: int) -> int:
	var pct := int(defs.get("heal_potion", {}).get("heal_pct_of_max", 30))
	return mini(maxi(0, hp_max - hp), int(round(float(hp_max) * float(pct) / 100.0)))

const FOOD_MAX := 100

static func food_max(defs: Dictionary) -> int:
	return int(defs.get("feed", {}).get("food_max", FOOD_MAX))

static func is_starving(defs: Dictionary, food: int) -> bool:
	return clampi(food, 0, food_max(defs)) <= 0

static func is_feed(item_def: Dictionary) -> bool:
	return String(item_def.get("category", "")) == "food" \
		and String(item_def.get("subcategory", "")) == "feed"

static func feed_matches(item_def: Dictionary, dragon_element: String) -> bool:
	var el := String(item_def.get("element", ""))
	if el == "" or el == "null":
		return true
	return el == dragon_element

static func feed_restore_pct(defs: Dictionary, key: String) -> int:
	var f: Dictionary = defs.get("feed", {})
	var pct: Dictionary = f.get("restore_pct", {})
	if (f.get("full", []) as Array).has(key):
		return int(pct.get("full", 100))
	return int(pct.get("half", 50))

static func food_after_feed(defs: Dictionary, item_def: Dictionary, key: String,
		dragon_element: String, food: int) -> int:
	var fmax := food_max(defs)
	var cur := clampi(food, 0, fmax)
	if not (is_feed(item_def) and feed_matches(item_def, dragon_element)):
		return cur
	var pct := feed_restore_pct(defs, key)
	if pct >= 100:
		return fmax
	return mini(fmax, cur + int(round(float(fmax) * float(pct) / 100.0)))

static func starving_uids(defs: Dictionary, uids: Array, get_dragon: Callable) -> Array:
	var out: Array = []
	var fmax := food_max(defs)
	for uid in uids:
		var d: Dictionary = get_dragon.call(int(uid))
		if is_starving(defs, int(d.get("food", fmax))):
			out.append(int(uid))
	return out

static func find_matching_feed(items: Dictionary, item_defs: Dictionary,
		dragon_element: String) -> String:
	for k in items:
		if int(items[k]) <= 0:
			continue
		var idef: Dictionary = item_defs.get(k, {})
		if is_feed(idef) and feed_matches(idef, dragon_element):
			return String(k)
	return ""

static func has_matching_feed(items: Dictionary, item_defs: Dictionary,
		dragon_element: String) -> bool:
	return find_matching_feed(items, item_defs, dragon_element) != ""

static func feed_is_full(defs: Dictionary, key: String) -> bool:
	return feed_restore_pct(defs, key) >= 100
