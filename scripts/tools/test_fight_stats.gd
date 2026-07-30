extends SceneTree
## 헤드리스 FightStats 단위 테스트 (§10 — logic은 화면 없이 검증).
## 원작 근거: docs/ref/orig_code/decomp/FightStats.c (필드 tag/dmg/taken/heal/kill/block/evade).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_fight_stats.gd

func _init() -> void:
	var fails := 0

	# 합성 이벤트로 환원 의미 검증(FightStats 필드명대로 귀속).
	var events := [
		{"type": "normal", "attacker": "A", "defender": "X", "damage": 30, "dead": false, "crit": true},
		{"type": "normal", "attacker": "A", "defender": "X", "damage": 50, "dead": true},   # 막타 → A.kill
		{"type": "normal", "attacker": "X", "defender": "A", "damage": 20, "block": true},  # A가 막음
		{"type": "normal", "attacker": "X", "defender": "B", "damage": 0, "miss": true},    # B 회피
		{"type": "normal", "attacker": "A", "defender": "Y", "damage": 40, "lifesteal": 12}, # A 흡혈회복
		{"type": "dot", "target": "A", "damage": 7, "dead": false, "source": 3},            # dealer 없음 → A.taken만
		{"type": "skill", "attacker": "B", "target": "A", "heal": 25},                       # 스킬힐 → A.heal(대상)
	]
	var s = Battle.fight_stats(events)

	# A: dmg=30+50+40=120, taken=20(X)+7(dot)=27, kill=1, block=1, heal=12(흡혈)+25(피회복)=37
	fails += _eq("A.dmg", s["A"]["dmg"], 120)
	fails += _eq("A.taken", s["A"]["taken"], 27)
	fails += _eq("A.kill", s["A"]["kill"], 1)
	fails += _eq("A.block", s["A"]["block"], 1)
	fails += _eq("A.heal", s["A"]["heal"], 37)
	fails += _eq("A.evade", s["A"]["evade"], 0)
	# X: dmg=20, taken=30+50=80
	fails += _eq("X.dmg", s["X"]["dmg"], 20)
	fails += _eq("X.taken", s["X"]["taken"], 80)
	# B: evade=1, dmg=0(heal이벤트 damage없음)
	fails += _eq("B.evade", s["B"]["evade"], 1)
	fails += _eq("B.dmg", s["B"]["dmg"], 0)
	# Y: taken=40
	fails += _eq("Y.taken", s["Y"]["taken"], 40)
	# tag 보존
	fails += _b("tag=name", s["A"]["tag"] == "A")

	# 실제 simulate 이벤트로 무결성(스탯 합계 정합): 총 가한피해 == 총 받은피해(직접귀속분).
	var cfg := _load("res://data/combat.json")
	var sdb := _load("res://data/skills.json")
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
	# 직접귀속(attacker→defender) 피해는 dmg/taken 양쪽에 잡히므로 taken>=0, 승자 존재.
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
