class_name AwakenSkill
extends RefCounted

const STACK_ONCE := "once"

const PATCH_FIELD := "_awaken_patch"

static func apply_battle(allies: Array, enemies: Array, table: Dictionary,
		ctx: Dictionary = {}) -> Array:
	var by_no := _index(table)
	var fired: Array = []
	var used_once := {}
	for c in allies:
		(c as Dictionary)["_party"] = allies
	for c in enemies:
		(c as Dictionary)["_party"] = enemies
	for owner in allies:
		var no := int(owner.get("awaken_no", 0))
		if no <= 0:
			continue
		var s: Dictionary = by_no.get(no, {})
		var eff: Dictionary = s.get("effect", {})
		if eff.is_empty() or not bool(eff.get("impl", false)):
			continue
		eff = _patched(eff, owner, no)
		if String(eff.get("stack", "")) == STACK_ONCE:
			if used_once.has(no):
				continue
			used_once[no] = true
		if not Battle.effect_cond_ok(eff.get("cond", null), owner, allies, enemies, ctx):
			continue
		var any := false
		for op in (eff.get("ops", []) as Array):
			if (op as Dictionary).has("from"):
				continue
			if Battle.apply_effect_op(op as Dictionary, owner, allies, enemies, ctx, no):
				any = true
		for r in (eff.get("react", []) as Array):
			var re := (r as Dictionary).duplicate(true)
			re["kind"] = Battle.REACT
			re["no"] = no
			(owner["effects"] as Array).append(re)
			any = true
		var dyn: Array = eff.get("dyn", [])
		if not dyn.is_empty():
			for d in dyn:
				var entry := (d as Dictionary).duplicate(true)
				entry["kind"] = "dyn"
				entry["no"] = no
				entry["turns"] = -1
				(owner["effects"] as Array).append(entry)
			any = true
		if any or _has_derived(eff):
			fired.append({"no": no, "name": String(s.get("name", "")),
				"owner": String(owner.get("name", ""))})
	for owner2 in allies:
		var no2 := int(owner2.get("awaken_no", 0))
		if no2 <= 0:
			continue
		var s2: Dictionary = by_no.get(no2, {})
		var eff2: Dictionary = s2.get("effect", {})
		if eff2.is_empty() or not bool(eff2.get("impl", false)):
			continue
		eff2 = _patched(eff2, owner2, no2)
		if not Battle.effect_cond_ok(eff2.get("cond", null), owner2, allies, enemies, ctx):
			continue
		for op in (eff2.get("ops", []) as Array):
			if (op as Dictionary).has("from"):
				Battle.apply_effect_op(op as Dictionary, owner2, allies, enemies, ctx, no2)
	return fired

static func _patched(eff: Dictionary, owner: Dictionary, no: int) -> Dictionary:
	var mods: Array = owner.get(PATCH_FIELD, [])
	var hit: Array = []
	for m in mods:
		if int((m as Dictionary).get("no", 0)) == no:
			hit.append(m)
	if hit.is_empty():
		return eff
	var e := eff.duplicate(true)
	for m in hit:
		var mod := m as Dictionary
		for path in (mod.get("patch", {}) as Dictionary):
			_set_path(e, String(path), (mod["patch"] as Dictionary)[path])
		for o in (mod.get("add_ops", []) as Array):
			(e["ops"] as Array).append((o as Dictionary).duplicate(true))
		if not (mod.get("add_react", []) as Array).is_empty():
			if not e.has("react"):
				e["react"] = []
			for r in (mod["add_react"] as Array):
				(e["react"] as Array).append((r as Dictionary).duplicate(true))
	return e

static func _set_path(root: Dictionary, path: String, spec) -> void:
	var parts := path.split(".")
	var cur = root
	for i in parts.size() - 1:
		var k := String(parts[i])
		if cur is Array:
			var idx := int(k)
			if idx < 0 or idx >= (cur as Array).size():
				return
			cur = (cur as Array)[idx]
		elif cur is Dictionary:
			if not (cur as Dictionary).has(k):
				return
			cur = (cur as Dictionary)[k]
		else:
			return
	var last := String(parts[parts.size() - 1])
	var old = null
	if cur is Dictionary:
		old = (cur as Dictionary).get(last, null)
	elif cur is Array:
		var li := int(last)
		if li < 0 or li >= (cur as Array).size():
			return
		old = (cur as Array)[li]
	else:
		return
	var val = spec
	if spec is String and (spec as String).length() > 1:
		var s := spec as String
		if s[0] == "+" or s[0] == "*":
			var n := float(s.substr(1))
			var base := float(old) if old != null else 0.0
			val = (base + n) if s[0] == "+" else (base * n)
	if cur is Dictionary:
		(cur as Dictionary)[last] = val
	else:
		(cur as Array)[int(last)] = val

static func _has_derived(eff: Dictionary) -> bool:
	for op in (eff.get("ops", []) as Array):
		if (op as Dictionary).has("from"):
			return true
	return false

static func explore_bonus(party: Array, table: Dictionary) -> Dictionary:
	var by_no := _index(table)
	var out := {"gold_pct": 0, "artifact_chance_pct": 0}
	for d in party:
		var no := int((d as Dictionary).get("awaken_no", 0))
		if no <= 0:
			continue
		var eff: Dictionary = (by_no.get(no, {}) as Dictionary).get("effect", {})
		if eff.is_empty() or not bool(eff.get("impl", false)):
			continue
		var ex: Dictionary = eff.get("explore", {})
		for m in ((d as Dictionary).get(PATCH_FIELD, []) as Array):
			var mod := m as Dictionary
			if int(mod.get("no", 0)) == no and mod.has("explore"):
				ex = ex.duplicate()
				for k2 in (mod["explore"] as Dictionary):
					ex[k2] = (mod["explore"] as Dictionary)[k2]
		for k in out:
			out[k] = int(out[k]) + int(ex.get(k, 0))
	return out

static func mult_of(bonus: Dictionary, key: String) -> float:
	return 1.0 + float(int(bonus.get(key, 0))) / 100.0

static func _index(table: Dictionary) -> Dictionary:
	var out := {}
	for s in (table.get("skills", []) as Array):
		out[int((s as Dictionary).get("no", 0))] = s
	return out
