class_name Growth

const BASE_GRADE := 7.0
const STAGE_BREAKS := {"baby": 9, "child": 24}

const AURA_ADULT_LEVEL := 45

static func is_aura_adult(level: int) -> bool:
	return level >= AURA_ADULT_LEVEL

static func level_cap(_awakened := false) -> int:
	return 50

static func stage_for_level(level: int) -> String:
	if level <= STAGE_BREAKS["baby"]:
		return "baby"
	if level <= STAGE_BREAKS["child"]:
		return "child"
	return "adult"

static func spine_stage(dragon: Dictionary) -> String:
	return "e" if bool(dragon.get("awakened", false)) else stage_for_level(int(dragon.get("level", 1)))

static func portrait_stage(dragon: Dictionary) -> String:
	return "evolution" if bool(dragon.get("awakened", false)) else stage_for_level(int(dragon.get("level", 1)))

static func _tier_row(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var typ = dragon_def.get("type")
	var tier = dragon_def.get("stat_tier")
	var row = stat_table.get(typ, {}).get(tier)
	return row if row != null else {}

static func tier_growth(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0}
	var g: Dictionary = row["growth"]
	return {"hp": int(g["hp"]), "att": int(g["att"]), "def": int(g["def"])}

static func tier_base(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0}
	var b: Dictionary = row["base"]
	return {"hp": int(b["hp"]), "att": int(b["att"]), "def": int(b["def"])}

static func main_stats(dragon_def: Dictionary, stat_table: Dictionary, gain_log: Array,
		base_bonus: Dictionary = {}) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var out := {"cri": 10, "evd": 10, "blk": 10}
	for k in ["hp", "att", "def"]:
		var g := 0
		for e in gain_log:
			g += int((e as Dictionary).get(k, 0))
		out[k] = int(row["base"][k]) + int(base_bonus.get(k, 0)) + g
	return out

static func _effective(row: Dictionary, stat_bonus: Dictionary) -> Dictionary:
	var bb: Dictionary = stat_bonus.get("base", {})
	var gb: Dictionary = stat_bonus.get("growth", {})
	var base := {}
	var growth := {}
	for k in ["hp", "att", "def"]:
		base[k] = float(row["base"][k]) + float(bb.get(k, 0))
		growth[k] = float(row["growth"][k]) + float(gb.get(k, 0))
	return {"base": base, "growth": growth}

static func compute_stats(dragon_def: Dictionary, stat_table: Dictionary, level: int,
		stat_bonus: Dictionary = {}) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var eff := _effective(row, stat_bonus)
	var lv := maxi(1, level) - 1
	var out := {"cri": 10, "evd": 10, "blk": 10}
	for k in ["hp", "att", "def"]:
		out[k] = int(eff["base"][k] + eff["growth"][k] * lv)
	return out

static func compute_grade(dragon_def: Dictionary, stat_table: Dictionary,
		stat_bonus: Dictionary = {}, gain_log: Array = [], grade_cfg: Dictionary = {}) -> float:
	var bb: Dictionary = stat_bonus.get("base", {})
	var gb: Dictionary = stat_bonus.get("growth", {})
	var d := {"hp": 0.0, "att": 0.0, "def": 0.0}
	for k in ["hp", "att", "def"]:
		d[k] = float(bb.get(k, 0)) + float(gb.get(k, 0))
	if not gain_log.is_empty():
		var mx := tier_growth(dragon_def, stat_table)
		var mode := String(grade_cfg.get("baseline", "max"))
		for e in gain_log:
			var ed: Dictionary = e
			for k in ["hp", "att", "def"]:
				var m := float(mx.get(k, 0))
				if m <= 0.0:
					continue
				var g := float(ed.get(k, 0))
				match mode:
					"excess_only": d[k] = float(d[k]) + maxf(0.0, g - m)
					"avg": d[k] = float(d[k]) + (g - (1.0 + m) * 0.5)
					_: d[k] = float(d[k]) + (g - m)
	var div := float(grade_cfg.get("hp_divisor", 4))
	if is_zero_approx(div):
		div = 4.0
	return BASE_GRADE + 0.1 * (float(d["hp"]) / div + float(d["att"]) + float(d["def"]))

static func next_level(level: int, awakened := false) -> int:
	return mini(level_cap(awakened), level + 1)
