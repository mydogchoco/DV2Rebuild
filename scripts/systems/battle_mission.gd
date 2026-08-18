class_name BattleMission

static func pick(defs: Dictionary, rng: RandomNumberGenerator) -> Array:
	var all: Array = (defs.get("missions", []) as Array).duplicate()
	var n := mini(int(defs.get("pick_count", 2)), all.size())
	var out: Array = []
	for i in n:
		if all.is_empty():
			break
		out.append(all.pop_at(rng.randi() % all.size()))
	return out

static func evaluate(missions: Array, events: Array, party_names: Array) -> Array:
	var out: Array = []
	for m in missions:
		var c := _count(String(m.get("rule", "")), int(m.get("rule_arg", 0)), events, party_names)
		out.append({"mission": m, "count": mini(c, int(m.get("goal", 1))),
			"done": c >= int(m.get("goal", 1))})
	return out

static func exp_bonus(progress: Array) -> float:
	var b := 0.0
	for p in progress:
		if bool(p.get("done", false)):
			b += float((p["mission"] as Dictionary).get("exp_bonus", 0.0))
	return b

static func _is_ours(name: Variant, party_names: Array) -> bool:
	if typeof(name) != TYPE_STRING:
		return false
	return party_names.has(name)

static func _count(rule: String, arg: int, events: Array, party: Array) -> int:
	match rule:
		"hits_taken":
			var n := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and not bool(e.get("miss", false)) \
						and not bool(e.get("block", false)) and int(e.get("damage", 0)) > 0:
					n += 1
			return n
		"blocks":
			var n2 := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and bool(e.get("block", false)):
					n2 += 1
			return n2
		"dodges":
			var n3 := 0
			for e in events:
				if _is_ours(e.get("defender"), party) and bool(e.get("miss", false)):
					n3 += 1
			return n3
		"combo_hits":
			var best := 0
			var run := 0
			var last := ""
			for e in events:
				var atk := String(e.get("attacker", ""))
				if not _is_ours(atk, party) or bool(e.get("miss", false)) or bool(e.get("block", false)):
					run = 0; last = ""
					continue
				if atk == last:
					run += 1
				else:
					run = 1; last = atk
				if run >= arg:
					best += 1
					run = 0; last = ""
			return best
	return 0
