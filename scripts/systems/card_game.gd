class_name CardGame
extends RefCounted

static func make_deck(mode: String, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var g: Dictionary = (cfg.get("games", {}) as Dictionary).get(mode, {})
	if g.is_empty():
		return {}
	var n := int(g.get("cards", 8))
	var cards: Array = []
	if mode == "avoid":
		var lo := int(g.get("blanks_min", 1))
		var hi := int(g.get("blanks_max", 2))
		var blanks: int = clampi(lo + (rng.randi_range(0, maxi(0, hi - lo))), 1, n - 1)
		for i in blanks:
			cards.append(_blank(cfg))
		for i in (n - blanks):
			cards.append(roll_reward(cfg, rng))
	else:
		var pairs := int(n / 2)
		var picked: Array = []
		var guard := 0
		while picked.size() < pairs and guard < 200:
			guard += 1
			var r := roll_reward(cfg, rng)
			var sig := _signature(r)
			var dup := false
			for q in picked:
				if _signature(q) == sig:
					dup = true
					break
			if not dup:
				picked.append(r)
		while picked.size() < pairs:
			picked.append(_blank(cfg))
		for r2 in picked:
			cards.append(r2)
			cards.append((r2 as Dictionary).duplicate(true))
	_shuffle(cards, rng)
	for i in cards.size():
		(cards[i] as Dictionary)["id"] = i
	return {"mode": mode, "cards": cards, "chances": int(g.get("chances", 1))}

static func roll_reward(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = cfg.get("rewards", [])
	if pool.is_empty():
		return _blank(cfg)
	var total := 0.0
	for r in pool:
		total += maxf(0.0, float((r as Dictionary).get("weight", 0)))
	if total <= 0.0:
		return _blank(cfg)
	var x := rng.randf() * total
	for r in pool:
		x -= maxf(0.0, float((r as Dictionary).get("weight", 0)))
		if x <= 0.0:
			return _materialize(r as Dictionary, rng)
	return _materialize(pool[pool.size() - 1] as Dictionary, rng)

static func _materialize(def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {
		"kind": String(def.get("kind", "none")),
		"label": String(def.get("label", "")),
		"frame": String(def.get("frame", "")),
	}
	match String(def.get("kind", "")):
		"gold", "diamond":
			var lo := int(def.get("min", 0))
			var hi := int(def.get("max", lo))
			out["amount"] = rng.randi_range(lo, maxi(lo, hi))
		"egg":
			var pool: Array = def.get("pool", [])
			if pool.is_empty():
				return _blank({})
			out["dragon_id"] = int(pool[rng.randi_range(0, pool.size() - 1)])
		"buff_att", "buff_def":
			out["tier"] = int(def.get("tier", 1))
	return out

static func _blank(cfg: Dictionary) -> Dictionary:
	var b: Dictionary = cfg.get("blank", {})
	return {"kind": "none", "label": String(b.get("label", "꽝")),
		"frame": String(b.get("frame", "fail"))}

static func _signature(r: Dictionary) -> String:
	return "%s:%d:%d:%d" % [String(r.get("kind", "")), int(r.get("amount", -1)),
		int(r.get("dragon_id", -1)), int(r.get("tier", -1))]

static func is_match(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("kind", "")) == "none" or String(b.get("kind", "")) == "none":
		return false
	if String(a.get("kind", "")) != String(b.get("kind", "")):
		return false
	for k in ["amount", "dragon_id", "tier"]:
		if int(a.get(k, -1)) != int(b.get(k, -1)):
			return false
	return true

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
