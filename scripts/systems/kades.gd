class_name Kades
extends RefCounted

static func penalty_pct(cfg: Dictionary, awakened: bool, dragon_element: String,
		field_element: String) -> int:
	if awakened:
		return 0
	var p: Dictionary = cfg.get("unawakened_penalty_pct", {})
	if p.is_empty():
		return 0
	if p.has(dragon_element):
		return int(p[dragon_element])
	if dragon_element != "" and dragon_element == field_element:
		return int(p.get("same_element", 0))
	return int(p.get("other", 0))

const PENALIZED := ["hp", "att", "def"]

static func apply_penalty(stats: Dictionary, pct: int) -> Dictionary:
	if pct <= 0:
		return stats
	var out := stats.duplicate()
	var mult := float(100 - clampi(pct, 0, 99)) / 100.0
	for k in PENALIZED:
		out[k] = maxi(1, int(round(float(int(out.get(k, 0))) * mult)))
	return out

static func boss_level(cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var b: Dictionary = cfg.get("boss_level", {})
	if b.is_empty():
		return 0
	return rng.randi_range(int(b.get("min", 0)), int(b.get("max", 0)))

static func boss_stat_mult(cfg: Dictionary, stat: String, lv: int, lv0: int) -> float:
	var c: Array = cfg.get("boss_stat_curve", {}).get(stat, [])
	if c.size() < 2 or lv <= 0 or lv0 <= 0:
		return 1.0
	var a := float(c[0])
	var b := float(c[1])
	var base := a * float(lv0) + b
	if base <= 0.0:
		return 1.0
	return maxf(1.0, (a * float(lv) + b) / base)

static func always_battle(cfg: Dictionary) -> bool:
	return bool(cfg.get("always_battle", false))

static func map_disabled(cfg: Dictionary) -> bool:
	return bool(cfg.get("map_disabled", false))
