class_name EquipEffect
extends RefCounted

const SRC := "equip:"

static func awaken_mods(allies: Array, table: Dictionary) -> void:
	for owner in allies:
		var c := owner as Dictionary
		var no := int(c.get("awaken_no", 0))
		var mods: Array = []
		if no > 0:
			for key in (c.get("equip_keys", []) as Array):
				var spec := rule_for(String(key), table)
				if spec.is_empty() or not bool(spec.get("impl", false)):
					continue
				var m: Dictionary = spec.get("awaken_mod", {})
				if not m.is_empty() and int(m.get("no", 0)) == no:
					mods.append(m)
		c[AwakenSkill.PATCH_FIELD] = mods

static func apply_battle(allies: Array, enemies: Array, table: Dictionary,
		ctx: Dictionary = {}) -> Array:
	var fired: Array = []
	for c in allies:
		if not (c as Dictionary).has("_party"):
			(c as Dictionary)["_party"] = allies
	for c in enemies:
		if not (c as Dictionary).has("_party"):
			(c as Dictionary)["_party"] = enemies

	for owner in allies:
		for key in ((owner as Dictionary).get("equip_keys", []) as Array):
			var spec := rule_for(String(key), table)
			if spec.is_empty() or not bool(spec.get("impl", false)):
				continue
			if not Battle.effect_cond_ok(spec.get("cond", null), owner, allies, enemies, ctx):
				continue
			var any := false
			for o in (spec.get("ops", []) as Array):
				if Battle.apply_effect_op(o as Dictionary, owner, allies, enemies, ctx, 0,
						1.0, SRC):
					any = true
			for r in (spec.get("react", []) as Array):
				var where := String((r as Dictionary).get("plant", ""))
				var plant: Array = Battle._targets(where, owner, allies) if where != "" 					else [owner]
				for who in plant:
					var re := (r as Dictionary).duplicate(true)
					re.erase("plant")
					re["kind"] = Battle.REACT
					re["no"] = 0
					((who as Dictionary)["effects"] as Array).append(re)
				any = true
			for d in (spec.get("dyn", []) as Array):
				var de := (d as Dictionary).duplicate(true)
				de["kind"] = "dyn"
				de["no"] = 0
				de["turns"] = -1
				((owner as Dictionary)["effects"] as Array).append(de)
				any = true
			if any:
				fired.append({"key": String(key), "name": _name_of(String(key)),
					"owner": String((owner as Dictionary).get("name", ""))})
	return fired

static func static_stats(equip_field: Dictionary, table: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in keys_of(equip_field):
		var spec := rule_for(String(key), table)
		if spec.is_empty() or not bool(spec.get("impl", false)) or spec.has("cond"):
			continue
		for o in (spec.get("ops", []) as Array):
			var op := o as Dictionary
			if String(op.get("kind", "stat")) != "stat":
				continue
			if op.has("cond") or op.has("from") or op.has("per"):
				continue
			var s := String(op.get("stat", ""))
			if s == "" or s.begins_with("__"):
				continue
			var mode := "pct" if String(op.get("mode", "flat")) == "pct" else "flat"
			var slot: Dictionary = out.get(s, {"flat": 0.0, "pct": 0.0})
			slot[mode] = float(slot[mode]) + float(op.get("value", op.get("pct", 0.0)))
			out[s] = slot
	return out

static func apply_static(stats: Dictionary, equip_field: Dictionary,
		table: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	var add := static_stats(equip_field, table)
	for s in add:
		var slot: Dictionary = add[s]
		var v := float(int(out.get(s, 0)))
		out[s] = int(round(v * (1.0 + float(slot["pct"]) / 100.0) + float(slot["flat"])))
	return out

static func rule_for(key: String, table: Dictionary) -> Dictionary:
	if key.begins_with("exclusive:"):
		return (table.get("exclusive", {}) as Dictionary).get(key.substr(10), {})
	if key.begins_with("special:"):
		return (table.get("special", {}) as Dictionary).get(key.substr(8), {})
	return {}

static func _name_of(key: String) -> String:
	var parts := key.split(":")
	return String(parts[parts.size() - 1])

static func implemented(key: String, table: Dictionary) -> bool:
	return bool(rule_for(key, table).get("impl", false))

static func status_text(key: String, table: Dictionary) -> String:
	var spec := rule_for(key, table)
	if spec.is_empty():
		return ""
	if not bool(spec.get("impl", false)):
		var why := String(spec.get("why", ""))
		if why.begins_with("cut"):
			return "(오프라인 재구현에서 빠진 콘텐츠라 전투에 반영되지 않습니다)"
		if why.begins_with("skill:"):
			return "(해당 스킬이 아직 구현되지 않아 전투에 반영되지 않습니다)"
		return "(아직 전투에 반영되지 않습니다)"
	var partial := String(spec.get("partial", ""))
	return "(일부만 반영됩니다)" if partial != "" else ""

static func keys_of(equip_field: Dictionary) -> Array:
	var out: Array = []
	for s in (equip_field.get("slots", []) as Array):
		var k := String((s as Dictionary).get("key", ""))
		if k != "":
			out.append(k)
	return out
