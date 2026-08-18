class_name EggUpgrade
extends RefCounted

const CRYSTAL_TOKEN := "@element_crystal"

static func max_step(cfg: Dictionary) -> int:
	return int(cfg.get("max_step", 3))

static func hatch_grade(step: int, cfg: Dictionary) -> float:
	var g: Dictionary = cfg.get("grades", {})
	return float(g.get(str(step), 0.0))

static func recipe_for(egg_key: String, element: String, grade: int,
		up_data: Dictionary, lab_cfg: Dictionary = {}) -> Dictionary:
	if grade < 0 or grade >= max_step(lab_cfg):
		return {}
	var row := row_for(egg_key, grade, up_data)
	if row.is_empty():
		return {}
	var mats: Array = []
	for m in (row.get("materials", []) as Array):
		var md: Dictionary = m
		var key := String(md.get("item", ""))
		if key == CRYSTAL_TOKEN:
			key = element_crystal(element, up_data)
			if key == "":
				return {}
		mats.append({"item": key, "count": int(md.get("count", 1))})
	var out := row.duplicate()
	out["materials"] = mats
	out["target_grade"] = grade + 1
	return out

static func element_crystal(element: String, up_data: Dictionary) -> String:
	var m: Dictionary = up_data.get("_element_crystal", {})
	return String(m.get(element, ""))

static func row_for(egg_key: String, grade: int, up_data: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for r in (up_data.get("recipes", []) as Array):
		var d: Dictionary = r
		if int(d.get("grade", -1)) != grade:
			continue
		var t := String(d.get("type", ""))
		if t == egg_key:
			return d
		if t == "*":
			fallback = d
	return fallback

static func normalize(entry) -> Dictionary:
	var out: Dictionary = {}
	if entry is Dictionary:
		for k in (entry as Dictionary):
			var g := int(String(k)) if not (k is int or k is float) else int(k)
			var n := int((entry as Dictionary)[k])
			if g > 0 and n > 0:
				out[g] = int(out.get(g, 0)) + n
	elif entry is int or entry is float:
		var g2 := int(entry)
		if g2 > 0:
			out[g2] = 1
	return out

static func upgraded_key(item_key: String) -> String:
	return EggItem.key(EggItem.base_of(item_key), EggItem.grade_of(item_key) + 1)
