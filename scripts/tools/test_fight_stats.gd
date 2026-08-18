extends SceneTree

func _init() -> void:
	var fails := 0

	var events := [
		{"type": "normal", "attacker": "A", "defender": "X", "damage": 30, "dead": false, "crit": true},
		{"type": "normal", "attacker": "A", "defender": "X", "damage": 50, "dead": true},
		{"type": "normal", "attacker": "X", "defender": "A", "damage": 20, "block": true},
		{"type": "normal", "attacker": "X", "defender": "B", "damage": 0, "miss": true},
		{"type": "normal", "attacker": "A", "defender": "Y", "damage": 40, "lifesteal": 12},
		{"type": "dot", "target": "A", "damage": 7, "dead": false, "source": 3},
		{"type": "skill", "attacker": "B", "target": "A", "heal": 25},
	]
	var s = Battle.fight_stats(events)

	fails += _eq("A.dmg", s["A"]["dmg"], 120)
	fails += _eq("A.taken", s["A"]["taken"], 27)
	fails += _eq("A.kill", s["A"]["kill"], 1)
	fails += _eq("A.block", s["A"]["block"], 1)
	fails += _eq("A.heal", s["A"]["heal"], 37)
	fails += _eq("A.evade", s["A"]["evade"], 0)
	fails += _eq("X.dmg", s["X"]["dmg"], 20)
	fails += _eq("X.taken", s["X"]["taken"], 80)
	fails += _eq("B.evade", s["B"]["evade"], 1)
	fails += _eq("B.dmg", s["B"]["dmg"], 0)
	fails += _eq("Y.taken", s["Y"]["taken"], 40)
	fails += _b("tag=name", s["A"]["tag"] == "A")

	var cfg := _load(_data_file("combat.json"))
	var sdb := _load(_data_file("skills.json"))
	var rng := RandomNumberGenerator.new(); rng.seed = 20
	var pa := [Battle.make_combatant("용사", "ally", "fire", {"hp": 400, "att": 90, "def": 40}, 0.0, [])]
	var pb := [Battle.make_combatant("몹", "enemy", "aqua", {"hp": 300, "att": 70, "def": 30}, 0.0, [])]
	var res = Battle.simulate(pa, pb, rng, cfg, sdb, 200)
	var fs = Battle.fight_stats(res["events"])
	var total_dmg := 0
	var total_taken := 0
	for name in fs:
		total_dmg += int(fs[name]["dmg"])
		total_taken += int(fs[name]["taken"])
	fails += _b("simulate 스탯 생성", fs.size() >= 1)
	fails += _b("총 가한피해>0", total_dmg > 0)
	fails += _b("승자 존재", res["winner"] in ["ally", "enemy", "draw"])
	print("[test_fight_stats] simulate: 전투원 %d, 총딜 %d, 총피격 %d, 승자 %s" % [fs.size(), total_dmg, total_taken, res["winner"]])

	if fails == 0:
		print("[test_fight_stats] ALL PASS")
		quit(0)
	else:
		printerr("[test_fight_stats] %d FAIL" % fails)
		quit(1)

func _load(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}

func _eq(tag: String, got, want) -> int:
	if got == want:
		return 0
	printerr("FAIL %s: got=%s want=%s" % [tag, got, want])
	return 1

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
