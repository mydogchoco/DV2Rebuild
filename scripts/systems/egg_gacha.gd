class_name EggGacha
extends RefCounted

static func is_gacha_egg(item: Dictionary) -> bool:
	var sub := String(item.get("subcategory", ""))
	return sub == "gacha_egg" or sub == "element_egg"

const KEY_PREFIX := "egg:"

static func key_for(dragon_id: int) -> String:
	return KEY_PREFIX + str(dragon_id)

static func dragon_of(key: String) -> int:
	var base := EggItem.base_of(key)
	if not base.begins_with(KEY_PREFIX):
		return 0
	var s := base.substr(KEY_PREFIX.length())
	return int(s) if s.is_valid_int() else 0

static func item_def(key: String, dragons: Dictionary) -> Dictionary:
	var id := dragon_of(key)
	if id <= 0 or not dragons.has(id):
		return {}
	var d: Dictionary = dragons[id]
	return {
		"name": "%s의 알" % String(d.get("name", "드래곤 %d" % id)),
		"category": "egg",
		"subcategory": "dragon_egg",
		"element": d.get("element", null),
		"dragon_id": id,
		"tier": int(d.get("star", 0)),
		"stack": true,
		"offline": "impl",
		"egg_grade": EggItem.grade_of(key),
	}

static func roll(item_key: String, item: Dictionary, cfg: Dictionary,
		dragons: Dictionary, rng: RandomNumberGenerator) -> int:
	if cfg.is_empty() or dragons.is_empty():
		return 0
	var spec: Dictionary = {}
	var element := ""
	if String(item.get("subcategory", "")) == "element_egg":
		spec = cfg.get("element_pool", {})
		element = String(item.get("element", ""))
		if element == "":
			return 0
	else:
		spec = (cfg.get("pools", {}) as Dictionary).get(item_key, {})
	if spec.is_empty():
		return 0

	var weights: Dictionary = spec.get("star_weights", {})
	if weights.is_empty():
		return 0
	var exclude := as_ints(spec.get("exclude", []))
	var overrides: Dictionary = spec.get("star_pool_override", {})

	for s in _weighted_order(weights.keys(), weights, rng):
		var pool := candidates(dragons, int(s), element, overrides, exclude)
		if pool.is_empty():
			continue
		return int(pool[_randi(rng, pool.size())])
	return 0

static func roll_many(item_key: String, item: Dictionary, cfg: Dictionary,
		dragons: Dictionary, rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in maxi(0, n):
		var did := roll(item_key, item, cfg, dragons, rng)
		if did > 0:
			out.append(did)
	return out

static func _weighted_order(stars: Array, weights: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var rest: Array = stars.duplicate()
	rest.sort_custom(func(a, b): return int(a) < int(b))
	var out: Array = []
	while not rest.is_empty():
		var total := 0.0
		for s in rest:
			total += maxf(0.0, float(weights.get(s, 0)))
		if total <= 0.0:
			out.append_array(rest)
			break
		var r := _randf(rng) * total
		var pick = rest[rest.size() - 1]
		for s in rest:
			r -= maxf(0.0, float(weights.get(s, 0)))
			if r <= 0.0:
				pick = s
				break
		out.append(pick)
		rest.erase(pick)
	return out

static func candidates(dragons: Dictionary, star: int, element: String,
		overrides: Dictionary, exclude_raw: Array) -> Array:
	var exclude := as_ints(exclude_raw)
	var forced = overrides.get(str(star), null)
	if forced is Array:
		return as_ints(forced).filter(func(i): return not exclude.has(i))
	var out: Array = []
	for id in dragons:
		var d: Dictionary = dragons[id]
		if bool(d.get("dex_hidden", false)):
			continue
		if bool(d.get("acquire_locked", false)):
			continue
		if int(d.get("star", 0)) != star:
			continue
		var del = d.get("element")
		if element != "" and (del if typeof(del) == TYPE_STRING else "") != element:
			continue
		if exclude.has(int(id)):
			continue
		out.append(int(id))
	out.sort()
	return out

static func star_chance_pct(item_key: String, item: Dictionary, cfg: Dictionary,
		star: int, dragons: Dictionary = {}) -> float:
	var spec: Dictionary = {}
	if String(item.get("subcategory", "")) == "element_egg":
		spec = cfg.get("element_pool", {})
	else:
		spec = (cfg.get("pools", {}) as Dictionary).get(item_key, {})
	var w: Dictionary = spec.get("star_weights", {})
	if w.is_empty():
		return 0.0
	var total := 0.0
	for k in w:
		total += maxf(0.0, float(w[k]))
	if total <= 0.0:
		return 0.0
	if not dragons.is_empty():
		var element := String(item.get("element", "")) if String(item.get("subcategory", "")) == "element_egg" else ""
		var eff := 0.0
		for k in w:
			if not candidates(dragons, int(k), element,
					spec.get("star_pool_override", {}), spec.get("exclude", [])).is_empty():
				eff += maxf(0.0, float(w[k]))
		total = eff if eff > 0.0 else total
	return maxf(0.0, float(w.get(str(star), 0))) / total * 100.0

static func as_ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out

static func _randf(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()

static func _randi(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 1:
		return 0
	return rng.randi_range(0, n - 1) if rng != null else randi_range(0, n - 1)
