class_name AwakenStone
extends RefCounted

const STARS := [3, 4, 5, 6]

static func need(cfg: Dictionary, star: int) -> int:
	return int(_sc(cfg).get("points_needed", {}).get(str(star), 0))

static func egg_points(cfg: Dictionary, star: int) -> int:
	return int(_sc(cfg).get("egg_points_by_star", {}).get(str(star), 0))

static func max_kinds(cfg: Dictionary) -> int:
	return int(_sc(cfg).get("max_egg_kinds_per_batch", 10))

static func batch_points(cfg: Dictionary, entries: Array) -> int:
	var sum := 0
	for e in entries:
		sum += egg_points(cfg, int((e as Dictionary).get("star", 0))) * int(e.get("count", 0))
	return sum

static func check_batch(cfg: Dictionary, star: int, have_points: int, entries: Array) -> String:
	if not STARS.has(star):
		return _ui("#78b8db35")
	var kinds := 0
	var total := 0
	for e in entries:
		var c := int((e as Dictionary).get("count", 0))
		if c > 0:
			kinds += 1
			total += c
	if total <= 0:
		return _ui("#8d748634")
	if kinds > max_kinds(cfg):
		return _ui("#304284d5")
	return ""

static func overflow(cfg: Dictionary, star: int, have_points: int, entries: Array) -> int:
	var n := need(cfg, star)
	if n <= 0:
		return 0
	return maxi(0, have_points + batch_points(cfg, entries) - n)

static func apply(cfg: Dictionary, star: int, have_points: int, entries: Array) -> Dictionary:
	var p := have_points + batch_points(cfg, entries)
	var n := need(cfg, star)
	var done := n > 0 and p >= n
	return {"points": 0 if done else p, "complete": done}

static func reward_key(star: int) -> String:
	return "evol_jewel_%d" % star

static func _sc(cfg: Dictionary) -> Dictionary:
	return cfg.get("stone_craft", {})

static func _ui(key: String) -> String:
	return UiText.get_text(key)
