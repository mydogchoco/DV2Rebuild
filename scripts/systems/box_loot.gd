class_name BoxLoot
extends RefCounted

const KEY_COST := 1

static func box_of(table: Dictionary, box_key: String) -> Dictionary:
	return (table.get("boxes", {}) as Dictionary).get(box_key, {})

static func key_of(table: Dictionary, key_item: String) -> Dictionary:
	return (table.get("keys", {}) as Dictionary).get(key_item, {})

static func is_box(table: Dictionary, item_key: String) -> bool:
	return not box_of(table, item_key).is_empty()

static func is_key(table: Dictionary, item_key: String) -> bool:
	return not key_of(table, item_key).is_empty()

static func needs_key(table: Dictionary, box_key: String) -> bool:
	return not (box_of(table, box_key).get("keys", []) as Array).is_empty()

static func keys_for(table: Dictionary, box_key: String) -> Array:
	var out: Array = []
	for k in (box_of(table, box_key).get("keys", []) as Array):
		out.append(String(k))
	return out

static func usable_keys(table: Dictionary, box_key: String, owned: Dictionary) -> Array:
	var out: Array = []
	for k in keys_for(table, box_key):
		if int(owned.get(k, 0)) >= KEY_COST:
			out.append(k)
	return out

static func openable_boxes(table: Dictionary, key_item: String, owned: Dictionary) -> Array:
	var out: Array = []
	for b in (key_of(table, key_item).get("opens", []) as Array):
		if int(owned.get(String(b), 0)) > 0:
			out.append(String(b))
	return out

static func pool_for(table: Dictionary, box_key: String, key_item := "") -> Array:
	var box := box_of(table, box_key)
	if box.is_empty():
		return []
	var tiers: Dictionary = box.get("tiers", {})
	if tiers.is_empty():
		if needs_key(table, box_key) and not keys_for(table, box_key).has(key_item):
			return []
		return box.get("pool", [])
	var tier := String(key_of(table, key_item).get("tier", ""))
	return (tiers.get(tier, {}) as Dictionary).get("pool", [])

static func roll(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0
	for e in pool:
		total += maxi(0, int((e as Dictionary).get("weight", 1)))
	if total <= 0:
		return {}
	var hit := rng.randi_range(1, total)
	for e in pool:
		var ent := e as Dictionary
		hit -= maxi(0, int(ent.get("weight", 1)))
		if hit <= 0:
			return {"key": String(ent.get("item", "")), "count": maxi(1, int(ent.get("count", 1)))}
	return {}

static func open(table: Dictionary, box_key: String, owned: Dictionary,
		rng: RandomNumberGenerator, key_item := "") -> Dictionary:
	var fail := func(why: String) -> Dictionary:
		return {"ok": false, "reason": why, "consumed": [], "gained": []}
	if not is_box(table, box_key):
		return fail.call("unknown_box")
	if int(owned.get(box_key, 0)) <= 0:
		return fail.call("no_box")

	var used := key_item
	if needs_key(table, box_key):
		if used == "":
			var avail := usable_keys(table, box_key, owned)
			if avail.is_empty():
				return fail.call("no_key")
			used = String(avail[0])
		elif not keys_for(table, box_key).has(used):
			return fail.call("wrong_key")
		elif int(owned.get(used, 0)) < KEY_COST:
			return fail.call("no_key")
	else:
		used = ""

	var got := roll(pool_for(table, box_key, used), rng)
	if got.is_empty():
		return fail.call("empty_pool")

	var consumed: Array = [{"key": box_key, "count": 1}]
	if used != "":
		consumed.append({"key": used, "count": KEY_COST})
	return {"ok": true, "reason": "", "consumed": consumed, "gained": [got], "key_used": used}

static func open_many(table: Dictionary, box_key: String, owned: Dictionary,
		rng: RandomNumberGenerator, n: int, key_item := "") -> Dictionary:
	var pool_owned := owned.duplicate(true)
	var consumed: Dictionary = {}
	var gained: Dictionary = {}
	var done := 0
	for _i in maxi(0, n):
		var r := open(table, box_key, pool_owned, rng, key_item)
		if not bool(r.get("ok", false)):
			break
		for c in (r["consumed"] as Array):
			var ck := String((c as Dictionary)["key"])
			var cn := int((c as Dictionary)["count"])
			pool_owned[ck] = int(pool_owned.get(ck, 0)) - cn
			consumed[ck] = int(consumed.get(ck, 0)) + cn
		for g in (r["gained"] as Array):
			var gk := String((g as Dictionary)["key"])
			var gn := int((g as Dictionary)["count"])
			gained[gk] = int(gained.get(gk, 0)) + gn
		done += 1
	return {"ok": done > 0, "opened": done,
			"consumed": _pairs(consumed), "gained": _pairs(gained)}

static func _pairs(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append({"key": String(k), "count": int(d[k])})
	return out
