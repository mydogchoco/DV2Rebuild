extends SceneTree

const TYPES := ["def", "atk", "ad", "hp", "hd", "ha"]
const GENERATION_4_STAT_TIERS := ["6b"]
const PARTY_SIZE := 3
const ELEMENTS := ["aqua", "earth", "fire", "wind", "light", "dark", "holy", "chaos", "shadow"]
const NORMAL_MAX_FAILURE_RATE := 0.20
const BOSS_MAX_FAILURE_RATE := 0.60
const EXCLUDED_STAGE_IDS := [8]
const EXCLUDED_ENEMY_IDS := [72]

var _stages: Dictionary
var _table: Dictionary
var _cfg: Dictionary
var _skills: Dictionary

func _init() -> void:
	_stages = _json(_data_file("stages.json")).get("stages", {})
	_table = _json(_data_file("stat_table.json"))
	_cfg = _json(_data_file("combat.json"))
	_skills = _json(_data_file("skills.json"))
	var trials := 20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			trials = maxi(1, int(arg.trim_prefix("--trials=")))
		elif arg.begins_with("--attack-scale="):
			_cfg["damage"]["attack_scale"] = float(arg.trim_prefix("--attack-scale="))
		elif arg.begins_with("--stat-pivot="):
			_cfg["damage"]["stat_pivot"] = float(arg.trim_prefix("--stat-pivot="))
		elif arg.begins_with("--attack-exponent="):
			_cfg["damage"]["attack_exponent"] = float(arg.trim_prefix("--attack-exponent="))
		elif arg.begins_with("--defense-exponent="):
			_cfg["damage"]["defense_exponent"] = float(arg.trim_prefix("--defense-exponent="))

	var total := 0
	var losses := 0
	var draws := 0
	var hard_failures := 0
	var worst_matchup_failure_rate := 0.0
	var worst_matchup_failure_label := "패배 없음"
	var worst_matchup_failure_limit := NORMAL_MAX_FAILURE_RATE
	var fastest_hits := 1 << 30
	var fastest_label := ""
	var worst_hp_ratio := 1.0
	var worst_hp_label := ""
	var max_rounds := 0
	var stage_rows: Array = []
	for sid in range(1, 16):
		if sid in EXCLUDED_STAGE_IDS:
			continue
		var st: Dictionary = _stages.get(str(sid), {})
		if String(st.get("region", "")) != "yutakan":
			continue
		var level := int(st.get("level", 1))
		var enemies: Array = st.get("enemies", [])
		var stage_losses := 0
		var stage_worst_hp := 1.0
		var stage_fastest := 1 << 30
		for enemy_raw in enemies:
			var enemy: Dictionary = enemy_raw
			if int(enemy.get("id", 0)) in EXCLUDED_ENEMY_IDS:
				continue
			var is_boss := bool(enemy.get("boss", false))
			var matchup_failure_limit := BOSS_MAX_FAILURE_RATE if is_boss else NORMAL_MAX_FAILURE_RATE
			var enemy_element := String(enemy.get("element", "none"))
			var party_element := _worst_party_element(enemy_element)
			for type in TYPES:
				for tier in GENERATION_4_STAT_TIERS:
					var matchup_failures := 0
					var ddef := {"type": type, "stat_tier": tier}
					var stats := Growth.compute_stats(ddef, _table, level)
					var max_normal := Battle.damage(int(stats["att"]), int(enemy.get("def", 0)),
						0.0, _best_outgoing_mult(enemy_element), 1.0,
						float(_cfg["damage"].get("rand_max", 1.05)), _cfg)
					var hits := int(ceil(float(enemy.get("hp_max", 1)) / float(maxi(1, max_normal))))
					if hits < stage_fastest:
						stage_fastest = hits
					if hits < fastest_hits:
						fastest_hits = hits
						fastest_label = "%s / %s-%s / %s" % [st.get("name", sid), type, tier, enemy.get("name", "적")]
					for trial in trials:
						var party: Array = []
						for i in PARTY_SIZE:
							party.append(Battle.make_combatant("A%d" % i, "ally", party_element,
								stats, 0.0, []))
						var foe := Battle.make_combatant("E0", "enemy", enemy_element,
							{"hp": int(enemy.get("hp_max", 1)), "att": int(enemy.get("att", 1)),
							 "def": int(enemy.get("def", 0)), "cri": 8, "evd": 6, "blk": 8},
							0.0, _enemy_skills(enemy))
						_apply_phase2(foe, st)
						var rng := RandomNumberGenerator.new()
						rng.seed = 20260802 + sid * 1000003 + enemy.get("id", 0) * 7919 \
							+ TYPES.find(type) * 1009 + GENERATION_4_STAT_TIERS.find(tier) * 97 + trial
						var result := Battle.simulate(party, [foe], rng, _cfg, _skills)
						total += 1
						max_rounds = maxi(max_rounds, int(result.get("rounds", 0)))
						var battle_failed := false
						match String(result.get("winner", "draw")):
							"ally": pass
							"enemy": losses += 1; stage_losses += 1; battle_failed = true
							_: draws += 1; stage_losses += 1; battle_failed = true
						if battle_failed:
							matchup_failures += 1
						var hp_now := 0
						var hp_max := 0
						for c in party:
							hp_now += int((c as Dictionary).get("hp", 0))
							hp_max += int((c as Dictionary).get("hp_max", 1))
						var ratio := float(hp_now) / float(maxi(1, hp_max))
						stage_worst_hp = minf(stage_worst_hp, ratio)
						if ratio < worst_hp_ratio:
							worst_hp_ratio = ratio
							worst_hp_label = "%s / %s-%s / %s / seed %d" % [st.get("name", sid), type,
								tier, enemy.get("name", "적"), rng.seed]
					var matchup_failure_rate := float(matchup_failures) / float(trials)
					if matchup_failure_rate > worst_matchup_failure_rate:
						worst_matchup_failure_rate = matchup_failure_rate
						worst_matchup_failure_limit = matchup_failure_limit
						worst_matchup_failure_label = "%s / %s-%s / %s" % [st.get("name", sid), type,
							tier, enemy.get("name", "적")]
					if matchup_failure_rate > matchup_failure_limit:
						hard_failures += 1
		stage_rows.append({"id": sid, "name": st.get("name", ""), "level": level,
			"losses": stage_losses, "fastest": stage_fastest, "worst_hp": stage_worst_hp})

	print("YUTAKAN DAY BALANCE: trials=%d attack_scale=%.3f pivot=%.1f attack_exp=%.3f defense_exp=%.3f" %
		[trials, float(_cfg["damage"].get("attack_scale", 1.0)), float(_cfg["damage"].get("stat_pivot", 100.0)),
		 float(_cfg["damage"].get("attack_exponent", 1.0)), float(_cfg["damage"].get("defense_exponent", 0.9))])
	print("  generation=4 stat_tiers=%s excluded_stages=%s excluded_enemies=%s" %
		[str(GENERATION_4_STAT_TIERS), str(EXCLUDED_STAGE_IDS), str(EXCLUDED_ENEMY_IDS)])
	for row in stage_rows:
		print("  %2d %-10s Lv%2d loss=%4d fastest=%d-hit worst_hp=%5.1f%%" %
			[row["id"], row["name"], row["level"], row["losses"], row["fastest"], float(row["worst_hp"]) * 100.0])
	print("TOTAL battles=%d losses=%d draws=%d max_rounds=%d" % [total, losses, draws, max_rounds])
	print("WORST MATCHUP failure=%.3f%% (%s, limit=%.1f%%)" %
		[worst_matchup_failure_rate * 100.0, worst_matchup_failure_label,
		 worst_matchup_failure_limit * 100.0])
	print("FASTEST normal=%d-hit (%s)" % [fastest_hits, fastest_label])
	print("WORST remaining HP=%.1f%% (%s)" % [worst_hp_ratio * 100.0, worst_hp_label])
	var fails := hard_failures
	if fastest_hits < 2:
		printerr("FAIL: 정상 평타 한방 컷 발생 — %s" % fastest_label)
		fails += 1
	elif fastest_hits == 2:
		print("ALLOW: 약한 낮 일반 몬스터 2타 처치 — %s" % fastest_label)
	if fails == 0:
		print("[test_yutakan_day_balance] ALL PASS")
	else:
		printerr("[test_yutakan_day_balance] FAIL count=", fails)
	quit(1 if fails > 0 else 0)

func _enemy_skills(enemy: Dictionary) -> Array:
	var out: Array = []
	for id in (enemy.get("skills", []) as Array):
		out.append({"id": int(id), "level": 1})
	return out

func _apply_phase2(foe: Dictionary, stage: Dictionary) -> void:
	var summon: Dictionary = stage.get("summon", {})
	var p: Dictionary = summon.get("phase2", {})
	if p.is_empty():
		return
	foe["phase"] = 1
	foe["phase2_at"] = float(p.get("hp_threshold", 0.0))
	foe["phase2_taken_mult"] = float(p.get("damage_taken_mult", 1.0))

func _worst_party_element(enemy_element: String) -> String:
	if enemy_element in ["", "none", "무"]:
		return "shadow"
	var worst := "shadow"
	var worst_score := INF
	for party_element in ELEMENTS:
		var outgoing := Battle.element_mult(party_element, enemy_element, _cfg)
		var incoming := Battle.element_mult(enemy_element, party_element, _cfg)
		var score := outgoing / maxf(0.01, incoming)
		if score < worst_score:
			worst_score = score
			worst = party_element
	return worst

func _best_outgoing_mult(enemy_element: String) -> float:
	var best := 1.0
	for party_element in ELEMENTS:
		best = maxf(best, Battle.element_mult(party_element, enemy_element, _cfg))
	return best

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
