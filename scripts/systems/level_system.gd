class_name LevelSystem

static func exp_to_next(curve: Dictionary, level: int) -> int:
	var req: Array = curve.get("req", [])
	if level < 1 or level > req.size():
		return 0
	return int(req[level - 1])

static func cap_for(curve: Dictionary, awakened: bool) -> int:
	if awakened:
		return int(curve.get("cap_awakened", 50))
	return int(curve.get("cap", 50))

const STATS := ["hp", "att", "def"]

static func pity_prob(roll_cfg: Dictionary, reroll_count: int) -> float:
	var base := float(roll_cfg.get("triple_max_base", 0.0))
	var step := float(roll_cfg.get("triple_max_step", 0.0))
	var cap := float(roll_cfg.get("triple_max_cap", 1.0))
	return minf(cap, base + step * maxi(0, reroll_count))

static func roll_level(roll_cfg: Dictionary, max_stats: Dictionary, rng: RandomNumberGenerator,
		pity_p := 0.0, guarantee := "") -> Dictionary:
	var extra: Dictionary = roll_cfg.get("transcend", {"hp": 4, "att": 1, "def": 1})
	var tc := float(roll_cfg.get("transcend_chance", 0.0))
	var force_triple := guarantee == "triple" or guarantee == "amor" or rng.randf() < pity_p
	var gain := {}
	var tmax := {}
	var is_max := {}
	for s in STATS:
		var mx := int(max_stats.get(s, 1))
		if mx < 1:
			mx = 1
		var trans := guarantee == "amor" or rng.randf() < tc
		var maxed := force_triple
		var r := mx
		if not force_triple:
			r = rng.randi_range(1, mx)
			maxed = r == mx
		if trans:
			gain[s] = mx + int(extra.get(s, 0)); maxed = true
		elif maxed:
			gain[s] = mx
		else:
			gain[s] = r
		tmax[s] = trans
		is_max[s] = maxed
	var need := 1 if guarantee == "max1" else (2 if guarantee == "max2" else 0)
	if need > 0:
		var cnt := 0
		for s in STATS:
			if is_max[s]:
				cnt += 1
		for s in STATS:
			if cnt >= need:
				break
			if not is_max[s]:
				gain[s] = int(max_stats.get(s, 1)); is_max[s] = true; cnt += 1
	var maxes := 0
	for s in STATS:
		if is_max[s]:
			maxes += 1
	return {"hp": int(gain["hp"]), "att": int(gain["att"]), "def": int(gain["def"]),
		"tmax": tmax, "is_max": is_max, "maxes": maxes, "triple": maxes == 3}

static func apply_exp(curve: Dictionary, roll_cfg: Dictionary, max_stats: Dictionary,
		level: int, exp: int, gained: int, rng: RandomNumberGenerator, awakened := false) -> Dictionary:
	var cap := cap_for(curve, awakened)
	level = clampi(level, 1, cap)
	exp = maxi(0, exp) + maxi(0, gained)
	var gains: Array = []

	while level < cap:
		var need := exp_to_next(curve, level)
		if need <= 0:
			break
		if exp < need:
			break
		exp -= need
		level += 1
		gains.append(roll_level(roll_cfg, max_stats, rng, 0.0, ""))

	var capped := level >= cap
	var exp_max := 0 if capped else exp_to_next(curve, level)
	if capped:
		exp = 0
	return {
		"level": level,
		"exp": exp,
		"exp_now": exp,
		"exp_max": exp_max,
		"levels_gained": gains.size(),
		"capped": capped,
		"gained": maxi(0, gained),
		"gains": gains,
	}
