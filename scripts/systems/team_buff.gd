class_name TeamBuff
extends RefCounted

static func _is_activated(required: Dictionary, party_races: Array) -> bool:
	if required.is_empty():
		return false
	var need: Dictionary = required.duplicate(true)
	for race in party_races:
		if need.has(race) and int(need[race]) > 0:
			need[race] = int(need[race]) - 1
	for race in need:
		if int(need[race]) > 0:
			return false
	return true

static func active_buffs(party_races: Array, table: Dictionary) -> Array:
	var out: Array = []
	var buffs: Array = table.get("buffs", [])
	for b in buffs:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var combine: Dictionary = _as_int_dict(b.get("combine", {}))
		if _is_activated(combine, party_races):
			out.append(b)
	return out

static func aggregate_stats(active: Array) -> Dictionary:
	var total: Dictionary = {}
	for b in active:
		var eff: Dictionary = b.get("effect", {})
		for stat in eff:
			if typeof(eff[stat]) == TYPE_DICTIONARY:
				continue
			total[stat] = float(total.get(stat, 0.0)) + float(eff[stat])
	return total

static func aggregate_typed(active: Array) -> Dictionary:
	var total: Dictionary = {}
	for b in active:
		var eff: Dictionary = b.get("effect", {})
		for stat in eff:
			var mode := "flat"
			var value := 0.0
			if typeof(eff[stat]) == TYPE_DICTIONARY:
				mode = String((eff[stat] as Dictionary).get("mode", "flat"))
				value = float((eff[stat] as Dictionary).get("value", 0))
			else:
				value = float(eff[stat])
			var slot: Dictionary = total.get(str(stat), {"pct": 0.0, "point": 0.0, "flat": 0.0})
			slot[mode] = float(slot.get(mode, 0.0)) + value
			total[str(stat)] = slot
	return total

static func stats_for_party(party_races: Array, table: Dictionary) -> Dictionary:
	return aggregate_stats(active_buffs(party_races, table))

static func typed_for_party(party_races: Array, table: Dictionary) -> Dictionary:
	return aggregate_typed(active_buffs(party_races, table))

static func apply(stats: Dictionary, typed: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate()
	for raw in typed:
		var stat := "att" if String(raw) == "atk" else String(raw)
		var t: Dictionary = typed[raw]
		var v := float(int(out.get(stat, 0)))
		v += float(t.get("flat", 0.0)) + float(t.get("point", 0.0))
		v *= 1.0 + float(t.get("pct", 0.0)) / 100.0
		out[stat] = int(round(v))
	return out

static func _as_int_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[str(k)] = int(d[k])
	return out
