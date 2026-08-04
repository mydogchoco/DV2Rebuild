extends SceneTree
## 4세대/등급 7.0 드래곤 타입 간 1:1 밸런스 회귀 테스트.
##
## 고정 조건(사용자 지정):
## - 같은 속성, 4세대(stat_tier 6b), 등급 7.0, Lv45, 스킬 Lv5
## - 일반 등급 카이저 발록의 투구
## - 샌즈의 소울젬 최고 티어 3개
## - 타입별 지정 스킬 2개
##
## 실행:
##   godot --headless --path . --script res://scripts/tools/test_type_balance.gd --
##   godot ... -- --trials=50 --attack-scale=1.1 --attack-exponent=1.0 --defense-exponent=0.9

const LEVEL := 45
const SKILL_LEVEL := 5
const FIXED_SKILL_LIMIT := 3.0
const NO_SKILL_LIMIT := 2.0
const HELMET := "special:balrog:카이저 발록의 투구"
const HOURGLASS := "special:fiod:피오드의 텅 빈 모래시계"
const SOUL_GEM := "샌즈의 소울젬"
const TYPES := ["def", "atk", "ad", "hp", "hd", "ha"]
const SKILLS := {
	"def": [13, 56],
	"atk": [14, 56],
	"ad": [36, 56],
	"hp": [54, 32],
	"hd": [54, 32],
	"ha": [14, 56],
}
const TWO_EQUIP_META_SKILLS := {
	"def": [56],
	"atk": [56],
	"ad": [36],
	"hp": [54],
	"hd": [56],
	"ha": [56],
}

var _dragons: Array
var _stat_table: Dictionary
var _gems: Dictionary
var _equipment: Dictionary
var _equip_effects: Dictionary
var _skills: Dictionary
var _cfg: Dictionary
var _defs: Dictionary = {}
var _blueprints: Dictionary = {}
var _fiod_def_atk := false
var _two_equip_meta := false


func _init() -> void:
	_dragons = _load("res://data/dragons.json")
	_stat_table = _load("res://data/stat_table.json")
	_gems = _load("res://data/gems.json")
	_equipment = _load("res://data/equipment.json")
	_equip_effects = _load("res://data/equip_effects.json")
	_skills = _load("res://data/skills.json")
	_cfg = _load("res://data/combat.json")

	var trials := 1000
	var assert_limit := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			trials = maxi(1, int(arg.trim_prefix("--trials=")))
		elif arg.begins_with("--attack-exponent="):
			_cfg["damage"]["attack_exponent"] = float(arg.trim_prefix("--attack-exponent="))
		elif arg.begins_with("--defense-exponent="):
			_cfg["damage"]["defense_exponent"] = float(arg.trim_prefix("--defense-exponent="))
		elif arg.begins_with("--guard-exponent="):
			_cfg["damage"]["guard_exponent"] = float(arg.trim_prefix("--guard-exponent="))
		elif arg.begins_with("--attack-scale="):
			_cfg["damage"]["attack_scale"] = float(arg.trim_prefix("--attack-scale="))
		elif arg.begins_with("--stat-pivot="):
			_cfg["damage"]["stat_pivot"] = float(arg.trim_prefix("--stat-pivot="))
		elif arg == "--no-assert":
			assert_limit = false
		elif arg == "--fiod-def-atk":
			_fiod_def_atk = true
		elif arg == "--two-equip-meta":
			_two_equip_meta = true

	var errors := _prepare_blueprints()
	if errors > 0:
		printerr("TYPE BALANCE FAIL: setup errors=", errors)
		quit(1)
		return

	var atk_exp := float(_cfg.get("damage", {}).get("attack_exponent", 1.0))
	var def_exp := float(_cfg.get("damage", {}).get("defense_exponent", 1.0))
	print("TYPE BALANCE: level=%d grade=7.0 trials/pair=%d attack_scale=%.3f attack_exp=%.3f defense_exp=%.3f" %
		[LEVEL, trials * 2, float(_cfg.get("damage", {}).get("attack_scale", 1.0)), atk_exp, def_exp])
	for type in TYPES:
		var s: Dictionary = _blueprints[type]
		var shown_loadout: Array = TWO_EQUIP_META_SKILLS[type] if _two_equip_meta else SKILLS[type]
		print("  %-3s hp=%4d att=%4d def=%4d pure=%d depure=%d equip=%s skills=%s" %
			[type, s["hp"], s["att"], s["def"], s.get("pure", 0), s.get("depure", 0),
			String(s.get("_balance_equip", "")), str(shown_loadout)])

	var failures := 0
	if _two_equip_meta:
		var meta := _run_suite("TWO EQUIP META", trials, true, 2.5)
		failures = int(meta["failures"])
	else:
		var fixed := _run_suite("FIXED SKILLS", trials, true, FIXED_SKILL_LIMIT)
		var bare := _run_suite("NO SKILLS", trials, false, NO_SKILL_LIMIT)
		failures = int(fixed["failures"]) + int(bare["failures"])
	if failures > 0 and assert_limit:
		printerr("TYPE BALANCE FAIL: %d suite aggregate limits exceeded" % failures)
		quit(1)
	else:
		print("TYPE BALANCE PASS")
		quit(0)


func _run_suite(label: String, trials: int, with_skills: bool, limit: float) -> Dictionary:
	print("\n%s" % label)
	var worst_ratio := 0.0
	var worst_pair := ""
	var pair_failures := 0
	var totals := {}
	for type in TYPES:
		totals[type] = 0
	for i in TYPES.size():
		for j in range(i + 1, TYPES.size()):
			var ta: String = TYPES[i]
			var tb: String = TYPES[j]
			var result := _matchup(ta, tb, trials, with_skills)
			var wa := int(result["a"])
			var wb := int(result["b"])
			var draws := int(result["draw"])
			var ratio := float(maxi(wa, wb)) / float(maxi(1, mini(wa, wb)))
			totals[ta] = int(totals[ta]) + wa
			totals[tb] = int(totals[tb]) + wb
			var pair_limit := 3.3 if _two_equip_meta and ta in ["ad", "hp"] and tb in ["ad", "hp"] else 2.5
			var pair_suffix := " limit=%.1f" % pair_limit if _two_equip_meta else ""
			print("  %3s vs %-3s  %4d:%-4d draw=%3d ratio=%.3f%s" %
				[ta, tb, wa, wb, draws, ratio, pair_suffix])
			if _two_equip_meta and ratio > pair_limit:
				pair_failures += 1
			if ratio > worst_ratio:
				worst_ratio = ratio
				worst_pair = "%s/%s" % [ta, tb]
	var best_type := ""
	var worst_type := ""
	var best_wins := -1
	var worst_wins := 1 << 30
	for type in TYPES:
		var wins := int(totals[type])
		if wins > best_wins:
			best_wins = wins
			best_type = type
		if wins < worst_wins:
			worst_wins = wins
			worst_type = type
	var aggregate_ratio := float(best_wins) / float(maxi(1, worst_wins))
	print("WORST MATCHUP %s: %s ratio=%.3f (reference only)" % [label, worst_pair, worst_ratio])
	print("TOTAL %s: %s" % [label, str(totals)])
	print("AGGREGATE %s: %s/%s ratio=%.3f (limit=%.3f)" %
		[label, best_type, worst_type, aggregate_ratio, limit])
	return {"aggregate_ratio": aggregate_ratio, "totals": totals,
		"failures": pair_failures + (1 if aggregate_ratio > limit else 0)}


func _prepare_blueprints() -> int:
	var errors := 0
	for type in TYPES:
		var found: Dictionary = {}
		for raw in _dragons:
			var d := raw as Dictionary
			if String(d.get("generation", "")) == "4" and String(d.get("type", "")) == type:
				found = d
				break
		if found.is_empty():
			printerr("No generation-4 dragon for type ", type)
			errors += 1
			continue
		if String(found.get("stat_tier", "")) != "6b":
			printerr("Unexpected stat tier for ", type, ": ", found.get("stat_tier"))
			errors += 1
			continue
		_defs[type] = found
		var stats := Growth.compute_stats(found, _stat_table, LEVEL)
		var max_tier := Gem.max_tier(SOUL_GEM, _gems)
		var gem_slots: Array = []
		for slot in 3:
			gem_slots.append({"name": SOUL_GEM, "tier": max_tier})
		stats = Gem.apply(stats, {"types": ["ALL", "ALL", "ALL"], "slots": gem_slots}, _gems)
		var equip_key := HOURGLASS if _fiod_def_atk and type in ["def", "atk"] else HELMET
		var equip_slots: Array = [{"key": equip_key, "options": [], "grade": 0,
			"enhance": 0, "belong": 0}]
		if _two_equip_meta:
			equip_slots = [
				{"key": HELMET, "options": [], "grade": 0, "enhance": 0, "belong": 0},
				{"key": HOURGLASS, "options": [], "grade": 0, "enhance": 0, "belong": 0},
			]
			equip_key = "%s + %s" % [HELMET, HOURGLASS]
		var equip := {"slots": equip_slots, "pieces": []}
		stats = Equipment.apply(stats, equip, _equipment)
		stats["equip_keys"] = EquipEffect.keys_of(equip)
		stats["atk_type"] = type
		stats["dragon_id"] = int(found.get("id", 0))
		stats["grade"] = 7.0
		stats["_balance_equip"] = equip_key
		_blueprints[type] = stats
	return errors


func _matchup(type_a: String, type_b: String, trials: int, with_skills: bool) -> Dictionary:
	var out := {"a": 0, "b": 0, "draw": 0}
	for i in trials:
		# 같은 seed로 양 진영을 교대하여 ally/enemy 및 선공 판정 편향을 상쇄한다.
		_count_result(out, type_a, type_b, 1000003 + i * 7919, true, with_skills)
		_count_result(out, type_b, type_a, 1000003 + i * 7919, false, with_skills)
	return out


func _count_result(out: Dictionary, ally_type: String, enemy_type: String,
		seed: int, a_is_ally: bool, with_skills: bool) -> void:
	var a := _combatant(ally_type, "ally", with_skills)
	var b := _combatant(enemy_type, "enemy", with_skills)
	EquipEffect.apply_battle([a], [b], _equip_effects, {})
	EquipEffect.apply_battle([b], [a], _equip_effects, {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var result := Battle.simulate([a], [b], rng, _cfg, _skills)
	match String(result["winner"]):
		"ally": out["a" if a_is_ally else "b"] += 1
		"enemy": out["b" if a_is_ally else "a"] += 1
		_: out["draw"] += 1


func _combatant(type: String, side: String, with_skills: bool) -> Dictionary:
	var skills: Array = []
	if with_skills:
		var loadout: Array = TWO_EQUIP_META_SKILLS[type] if _two_equip_meta else SKILLS[type]
		for id in loadout:
			skills.append({"id": id, "level": SKILL_LEVEL})
	return Battle.make_combatant(type, side, "shadow", _blueprints[type], 0.0, skills)


func _load(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Cannot open ", path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		printerr("Invalid JSON ", path)
		return {}
	return parsed
