extends SceneTree

const A := preload("res://scripts/systems/awaken_skill.gd")
const B := preload("res://scripts/systems/battle.gd")

var _table: Dictionary = {}
var _combat: Dictionary = {}

func _init() -> void:
	var fails := 0
	_table = _json(_data_file("skill_awaken.json"))
	_combat = _json(_data_file("combat.json"))

	fails += _schema_checks()
	fails += _static_checks()
	fails += _condition_checks()
	fails += _explore_checks()
	fails += _damage_pipeline_checks()
	fails += _derived_checks()
	fails += _system_checks()
	fails += _custom_dragon_checks()
	fails += _dynamic_checks()
	fails += _react_checks()
	fails += _late_batch_checks()

	if fails == 0:
		var p: Dictionary = _table.get("_effect_progress", {})
		print("[test_awaken_skill] ALL PASS  (이식 %d / %d)" % [
			int(p.get("_impl", 0)), int(p.get("_total", 0))])
		quit(0)
	else:
		printerr("[test_awaken_skill] %d FAIL" % fails)
		quit(1)

func _schema_checks() -> int:
	var f := 0
	var skills: Array = _table.get("skills", [])
	f += _eq("각성스킬 수 = _effect_progress._total", skills.size(),
		int((_table.get("_effect_progress", {}) as Dictionary).get("_total", -1)))
	f += _true("적어도 원작 102종은 있다", skills.size() >= 102)
	var n_impl := 0
	for s in skills:
		var no := int((s as Dictionary).get("no", 0))
		var e: Dictionary = (s as Dictionary).get("effect", {})
		f += _true("no=%d 에 effect 가 있다" % no, not e.is_empty())
		f += _true("no=%d tier 표기" % no, String(e.get("tier", "")) in ["A", "B", "C", "D"])
		if bool(e.get("impl", false)):
			n_impl += 1
			var has_work := not (e.get("ops", []) as Array).is_empty() \
				or not (e.get("dyn", []) as Array).is_empty() \
				or not (e.get("react", []) as Array).is_empty() \
				or not (e.get("explore", {}) as Dictionary).is_empty()
			f += _true("no=%d impl 인데 하는 일이 없다" % no, has_work)
		else:
			f += _true("no=%d why 기록" % no, String(e.get("why", "")) != "")
	f += _eq("impl 개수 = _effect_progress", n_impl,
		int((_table.get("_effect_progress", {}) as Dictionary).get("_impl", -1)))
	return f

func _static_checks() -> int:
	var f := 0
	var p1 := _party([[1, "fire"], [0, "fire"]])
	A.apply_battle(p1, [_enemy("aqua")], _table, {})
	f += _eq("1 자기 크리 +10", B._eff(p1[0], "cri") - B._eff(p1[1], "cri"), 10)
	f += _eq("1 은 아군에게 안 걸린다", B._eff(p1[1], "cri"), 10)

	var p3 := _party([[3, "fire"]])
	A.apply_battle(p3, [_enemy("aqua")], _table, {})
	f += _eq("3 크리파워 +50", B._eff(p3[0], "cri_pow"), 50)

	var p67 := _party([[67, "dark"]])
	A.apply_battle(p67, [_enemy("light")], _table, {})
	f += _eq("67 방어력 ×1.5", B._eff(p67[0], "def"), 150)

	var p15 := _party([[15, "fire"], [0, "aqua"], [0, "light"]])
	A.apply_battle(p15, [_enemy("dark")], _table, {})
	for i in 3:
		f += _eq("15 아군 %d 공격력 ×1.1" % i, B._eff(p15[i], "att"), 110)

	var p57 := _party([[57, "wind"], [0, "fire"]])
	var hp0 := int(p57[1]["hp_max"])
	A.apply_battle(p57, [_enemy("dark")], _table, {})
	f += _eq("57 아군 hp_max ×1.1", int(p57[1]["hp_max"]), int(round(float(hp0) * 1.1)))
	f += _eq("57 현재 체력도 함께", int(p57[1]["hp"]), int(p57[1]["hp_max"]))

	var p53 := _party([[53, "earth"], [0, "earth"], [0, "fire"]])
	A.apply_battle(p53, [_enemy("dark")], _table, {})
	f += _eq("53 땅 아군 방어 ×1.15", B._eff(p53[1], "def"), 115)
	f += _eq("53 불 아군은 그대로", B._eff(p53[2], "def"), 100)

	var p88 := _party([[88, "dark"], [0, "fire"], [0, "fire"]])
	A.apply_battle(p88, [_enemy("light")], _table, {})
	f += _eq("88 불 2마리 → 크리 +16", B._eff(p88[0], "cri") - 10, 16)

	var p59 := _party([[59, "dark"], [0, "fire"]])
	A.apply_battle(p59, [_enemy("light")], _table, {})
	f += _eq("59 회피 10 → 50 (%p 가산)", B._eff(p59[0], "evd"), 50)
	f += _eq("59 는 아군에게 안 걸린다", B._eff(p59[1], "evd"), 10)
	f += _true("59 실효 회피 50%", is_equal_approx(
		B._evade_chance(_enemy("light"), p59[0], 70), 50.0))

	var p30 := _party([[30, "wind"], [0, "fire"]])
	A.apply_battle(p30, [_enemy("dark")], _table, {})
	f += _eq("30 아군 depure +30", B._eff(p30[1], "depure"), 30)
	return f

func _condition_checks() -> int:
	var f := 0
	var yes := _party([[19, "dark"], [0, "shadow"]])
	A.apply_battle(yes, [_enemy("fire")], _table, {})
	f += _eq("19 그림자 있음 → 공격 ×1.6", B._eff(yes[0], "att"), 160)
	var no := _party([[19, "dark"], [0, "fire"]])
	A.apply_battle(no, [_enemy("fire")], _table, {})
	f += _eq("19 그림자 없음 → 무효", B._eff(no[0], "att"), 100)

	var d2 := _party([[94, "dark"], [0, "dark"], [0, "fire"]])
	A.apply_battle(d2, [_enemy("fire")], _table, {})
	f += _eq("94 어둠 2 → 공격 ×1.5", B._eff(d2[0], "att"), 150)
	var d1 := _party([[94, "dark"], [0, "fire"], [0, "fire"]])
	A.apply_battle(d1, [_enemy("fire")], _table, {})
	f += _eq("94 어둠 1 → 무효", B._eff(d1[0], "att"), 100)

	var solo := _party([[20, "shadow"]])
	A.apply_battle(solo, [_enemy("fire")], _table, {})
	f += _eq("20 혼자면 무효", B._dmg_taken_mult(solo[0]), 1.0)
	var duo := _party([[20, "shadow"], [0, "fire"]])
	A.apply_battle(duo, [_enemy("fire")], _table, {})
	f += _true("20 둘이면 자신 받는 피해 +20%", is_equal_approx(B._dmg_taken_mult(duo[0]), 1.2))
	f += _true("20 아군 주는 피해 +10%", is_equal_approx(B._dmg_deal_mult(duo[1]), 1.1))

	var nolight := _party([[82, "light"], [0, "fire"]])
	A.apply_battle(nolight, [_enemy("dark")], _table, {})
	f += _eq("82 상대에 빛 없음 → blk +15", B._eff(nolight[1], "blk") - 10, 15)
	var withlight := _party([[82, "light"], [0, "fire"]])
	A.apply_battle(withlight, [_enemy("light")], _table, {})
	f += _eq("82 상대에 빛 있음 → blk +30", B._eff(withlight[1], "blk") - 10, 30)

	var onfield := _party([[4, "earth"]])
	A.apply_battle(onfield, [_enemy("fire")], _table, {"field_element": "earth"})
	f += _eq("4 땅 지역 → 공격 ×1.2", B._eff(onfield[0], "att"), 120)
	var offfield := _party([[4, "earth"]])
	A.apply_battle(offfield, [_enemy("fire")], _table, {"field_element": "fire"})
	f += _eq("4 다른 지역 → 무효", B._eff(offfield[0], "att"), 100)

	var vsboss := _party([[33, "light"]])
	A.apply_battle(vsboss, [_enemy("dark")], _table, {"enemy_boss": true})
	f += _true("33 보스전 → 주는 피해 ×2", is_equal_approx(B._dmg_deal_mult(vsboss[0]), 2.0))
	var vsmob := _party([[33, "light"]])
	A.apply_battle(vsmob, [_enemy("dark")], _table, {"enemy_boss": false})
	f += _true("33 일반몹 → 무효", is_equal_approx(B._dmg_deal_mult(vsmob[0]), 1.0))
	return f

func _explore_checks() -> int:
	var f := 0
	var b1 := A.explore_bonus([{"awaken_no": 42}], _table)
	f += _eq("42 골드 +50%", int(b1["gold_pct"]), 50)
	f += _true("42 배수 1.5", is_equal_approx(A.mult_of(b1, "gold_pct"), 1.5))
	var b2 := A.explore_bonus([{"awaken_no": 17}], _table)
	f += _eq("17 아티팩트 확률 +50%", int(b2["artifact_chance_pct"]), 50)
	var b3 := A.explore_bonus([{"awaken_no": 42}, {"awaken_no": 17}], _table)
	f += _eq("합산 골드", int(b3["gold_pct"]), 50)
	f += _eq("합산 아티팩트", int(b3["artifact_chance_pct"]), 50)
	var b4 := A.explore_bonus([{"awaken_no": 0}], _table)
	f += _eq("미각성 → 0", int(b4["gold_pct"]), 0)
	f += _true("배수 1.0", is_equal_approx(A.mult_of(b4, "gold_pct"), 1.0))
	var b5 := A.explore_bonus([{"awaken_no": 2}], _table)
	f += _eq("미이식은 무효", int(b5["gold_pct"]), 0)
	return f

func _damage_pipeline_checks() -> int:
	var f := 0
	var atk: Dictionary = B.make_combatant("A", "ally", "fire",
		{"hp": 10, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0, "awaken_no": 16})
	var plain: Dictionary = B.make_combatant("P", "ally", "fire",
		{"hp": 10, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0})
	A.apply_battle([atk, plain], [_enemy("aqua")], _table, {})
	f += _true("16 주는 피해 ×1.2", is_equal_approx(B._dmg_deal_mult(atk), 1.2))
	f += _true("16 은 옆 드래곤에 안 걸린다", is_equal_approx(B._dmg_deal_mult(plain), 1.0))

	var d1: Dictionary = B.make_combatant("D1", "enemy", "wind", {"hp": 100000, "att": 1, "def": 1})
	var d2: Dictionary = B.make_combatant("D2", "enemy", "wind", {"hp": 100000, "att": 1, "def": 1})
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var boost: Dictionary = B._deal_attack(atk, d1, 1000, false, rng, _combat, {})
	var base: Dictionary = B._deal_attack(plain, d2, 1000, false, rng, _combat, {})
	f += _eq("16 실제 피해 1200 vs 1000", [int(boost["damage"]), int(base["damage"])], [1200, 1000])

	var tank: Dictionary = B.make_combatant("T", "ally", "wind",
		{"hp": 100000, "att": 1, "def": 1, "awaken_no": 14})
	A.apply_battle([tank], [_enemy("fire")], _table, {})
	f += _eq("14 100 피해 → 85", int(B._apply_dmg(tank, 100)["dmg"]), 85)
	f += _eq("14 10 피해 → 최소 1", int(B._apply_dmg(tank, 10)["dmg"]), 1)

	var soft: Dictionary = B.make_combatant("S", "ally", "light",
		{"hp": 100000, "att": 1, "def": 1, "awaken_no": 39})
	A.apply_battle([soft], [_enemy("dark")], _table, {})
	f += _eq("39 100 피해 → 90", int(B._apply_dmg(soft, 100)["dmg"]), 90)
	return f

func _derived_checks() -> int:
	var f := 0
	var p24 := _party([[24, "light"]])
	A.apply_battle(p24, [_enemy("dark")], _table, {})
	f += _eq("24 크리 10 → 공격 110", B._eff(p24[0], "att"), 110)
	var p24b := _party([[24, "light"], [88, "dark"], [0, "fire"]])
	A.apply_battle(p24b, [_enemy("dark")], _table, {})
	f += _eq("24 는 88 이 올린 크리(10+8)를 본다", B._eff(p24b[0], "att"), 118)

	var p48 := _party([[48, "light"]])
	var hp48 := int(p48[0]["hp_max"])
	A.apply_battle(p48, [_enemy("dark")], _table, {})
	f += _eq("48 방어 100 → 체력 +10%", int(p48[0]["hp_max"]), int(round(float(hp48) * 1.1)))

	var p86 := _party([[86, "holy"]])
	A.apply_battle(p86, [_enemy("dark")], _table, {})
	f += _eq("86 depure = 방어 100 × 0.1", B._eff(p86[0], "depure"), 10)
	f += _eq("86 pure = 공격 100 × 0.1", B._eff(p86[0], "pure"), 10)

	var top := _party([[18, "light"], [0, "fire"]])
	top[0]["grade"] = 8.0; top[1]["grade"] = 5.0
	A.apply_battle(top, [_enemy("dark")], _table, {})
	f += _eq("18 최고등급 → 공격 +방어50%", B._eff(top[0], "att"), 150)
	var low := _party([[18, "light"], [0, "fire"]])
	low[0]["grade"] = 3.0; low[1]["grade"] = 9.0
	A.apply_battle(low, [_enemy("dark")], _table, {})
	f += _eq("18 아니면 무효", B._eff(low[0], "att"), 100)
	var alone := _party([[18, "light"]])
	A.apply_battle(alone, [_enemy("dark")], _table, {})
	f += _eq("18 1대1이면 무조건 발동", B._eff(alone[0], "att"), 150)

	var g4 := _party([[61, "earth"], [0, "earth"], [0, "earth"]])
	A.apply_battle(g4, [_enemy("dark")], _table, {})
	f += _eq("61 땅 3마리 → +30%(상한)", B._eff(g4[0], "att"), 130)
	return f

func _system_checks() -> int:
	var f := 0
	var p22 := _party([[22, "dark"], [0, "fire"]])
	A.apply_battle(p22, [_enemy("light")], _table, {})
	f += _true("22 충전율 1.15", is_equal_approx(B._gauge_rate(p22[0]), 1.15))
	f += _true("22 는 아군에 안 걸린다", is_equal_approx(B._gauge_rate(p22[1]), 1.0))

	var weak := _party([[27, "earth"], [0, "earth"]])
	A.apply_battle(weak, [_enemy("dark")], _table, {})
	f += _true("27 방어 100 → 무효", is_equal_approx(B._gauge_rate(weak[1]), 1.0))
	var strong := _party([[27, "earth"], [0, "earth"], [0, "fire"]])
	strong[0]["def"] = 600
	A.apply_battle(strong, [_enemy("dark")], _table, {})
	f += _true("27 방어 600 → 땅 아군 1.3", is_equal_approx(B._gauge_rate(strong[1]), 1.3))
	f += _true("27 불 아군은 그대로", is_equal_approx(B._gauge_rate(strong[2]), 1.0))

	var p77 := _party([[77, "fire"]])
	A.apply_battle(p77, [_enemy("aqua")], _table, {})
	f += _true("77 게이지 바닥 15", is_equal_approx(B._gauge_min(p77[0]), 15.0))

	var p97 := _party([[97, "light"], [0, "fire"]])
	A.apply_battle(p97, [_enemy("dark")], _table, {})
	f += _true("97 아군 시작 게이지 30", is_equal_approx(float(p97[1]["awaken_gauge"]), 30.0))
	var p97b := _party([[97, "light"], [97, "light"]])
	A.apply_battle(p97b, [_enemy("dark")], _table, {})
	f += _true("97 중첩 불가", is_equal_approx(float(p97b[0]["awaken_gauge"]), 30.0))

	var p23 := _party([[23, "light"], [0, "fire"]])
	A.apply_battle(p23, [_enemy("dark")], _table, {})
	f += _eq("23 아군 사용횟수 +1", B._skill_uses_bonus(p23[1]), 1)

	var p98 := _party([[98, "chaos"], [0, "chaos"], [0, "chaos"], ])
	A.apply_battle(p98, [_enemy("dark")], _table, {})
	f += _eq("98 혼돈 3마리 → +3", B._skill_uses_bonus(p98[0]), 3)

	var p89 := _party([[89, "light"], [0, "fire"]])
	A.apply_battle(p89, [_enemy("dark")], _table, {})
	f += _eq("89 아군 효과레벨 +1", B._skill_level_bonus(p89[1]), 1)
	return f

func _custom_dragon_checks() -> int:
	var f := 0
	var by := {}
	for s in (_table.get("skills", []) as Array):
		by[int((s as Dictionary).get("no", 0))] = s

	f += _true("666 새벽을 가져오는 자 있음", by.has(666))
	f += _true("777 성좌의 주권자 있음", by.has(777))
	if not (by.has(666) and by.has(777)):
		return f
	f += _true("666 은 전 조항 이식(partial 없음)",
		(by[666]["effect"].get("partial", []) as Array).is_empty())
	f += _true("777 은 전 조항 이식(partial 없음)",
		(by[777]["effect"].get("partial", []) as Array).is_empty())

	var p666 := _party([[666, "chaos"], [0, "fire"]])
	A.apply_battle(p666, [_enemy("light")], _table, {})
	f += _eq("666 자신 pure +25", B._eff(p666[0], "pure"), 25)
	f += _eq("666 자신 depure_pct 66", B._eff(p666[0], "depure_pct"), 66)
	f += _eq("666 아군 공격력 +6%", B._eff(p666[1], "att"), 106)
	f += _true("666 아군 받는 피해 −6%", is_equal_approx(B._dmg_taken_mult(p666[1]), 0.94))
	f += _true("666 아군 주는 피해 +36%", is_equal_approx(B._dmg_deal_mult(p666[1]), 1.36))
	var piercer: Dictionary = B.make_combatant("P", "enemy", "fire",
		{"hp": 999, "att": 1, "def": 1, "pure": 100})
	f += _eq("666 관통 100 → 34", B._pure_damage(piercer, p666[0]), 34)
	var foe666: Dictionary = _enemy("light")
	B._aw_on_evade(p666[0], foe666, RandomNumberGenerator.new())
	f += _eq("666 회피 → 상대 혼란", B._has_flag(foe666, "confused"), true)

	var p777 := _party([[777, "fire"]])
	A.apply_battle(p777, [_enemy("aqua")], _table, {})
	f += _eq("777 크리파워 +50", B._eff(p777[0], "cri_pow"), 50)
	f += _eq("777 pure_pct 50", B._eff(p777[0], "pure_pct"), 50)
	var hanul: Dictionary = B.make_combatant("H", "ally", "fire",
		{"hp": 999, "att": 1, "def": 1, "pure": 100, "awaken_no": 777})
	A.apply_battle([hanul], [_enemy("aqua")], _table, {})
	var dummy: Dictionary = B.make_combatant("D", "enemy", "aqua", {"hp": 999, "att": 1, "def": 1})
	f += _eq("777 관통 100 → 150", B._pure_damage(hanul, dummy), 150)
	f += _true("777 피해 상한 25%", is_equal_approx(B._dmg_cap_pct(p777[0]), 25.0))
	var cap_hp := int(p777[0]["hp_max"])
	f += _eq("777 큰 피해가 hp_max 25% 로 잘린다",
		int(B._apply_dmg(p777[0], cap_hp * 10)["dmg"]), int(round(float(cap_hp) * 0.25)))
	var p777b := _party([[777, "fire"]])
	A.apply_battle(p777b, [_enemy("aqua")], _table, {})
	for bad in B.DEBUFF_FLAGS:
		B._add_flag(p777b[0], String(bad), 3, 15)
		f += _eq("777 %s 무시" % bad, B._has_flag(p777b[0], String(bad)), false)
	var plain2 := _party([[0, "fire"]])
	B._add_flag(plain2[0], "stun", 3, 15)
	f += _eq("면역 없으면 기절이 걸린다", B._has_flag(plain2[0], "stun"), true)
	B._add_flag(p777b[0], "survive_once", -1, 50)
	f += _eq("777 자기 버프(survive_once)는 유지", B._has_flag(p777b[0], "survive_once"), true)
	B._add_flag(p777b[0], "evade_sure", -1, 81)
	f += _eq("777 자기 버프(evade_sure)는 유지", B._has_flag(p777b[0], "evade_sure"), true)
	(p777b[0]["effects"] as Array).append({"kind": "dot", "pct": 5, "turns": 2, "source": 32})
	f += _true("777 지속피해(dot)는 안 막는다(경계 확인)",
		B._has_flag(p777b[0], "status_immune"))
	var evi: Dictionary = B._mark_immune({"target": "A0", "debuff": "confused", "turns": 2}, p777b[0])
	f += _eq("면역 대상 이벤트에서 debuff 표기가 사라진다", evi.has("debuff"), false)
	f += _eq("면역 사실은 immune 로 남는다", bool(evi.get("immune", false)), true)
	var evn: Dictionary = B._mark_immune({"target": "E0", "debuff": "confused", "turns": 2}, plain2[0])
	f += _eq("면역 아닌 대상은 debuff 가 그대로", String(evn.get("debuff", "")), "confused")
	var p777c := _party([[777, "fire"]])
	A.apply_battle(p777c, [_enemy("aqua")], _table, {})
	p777c[0]["cri"] = 100
	var plain777: Dictionary = _party([[0, "fire"]])[0]
	plain777["cri"] = 100
	var guard777: Dictionary = B.make_combatant("G7", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "evd": 60, "blk": 60})
	var rng777 := RandomNumberGenerator.new()
	var n777 := 600
	var miss := [0, 0]
	var blkn := [0, 0]
	for side in 2:
		var atk: Dictionary = plain777 if side == 0 else p777c[0]
		for i in n777:
			rng777.seed = 3000 + i
			var r: Dictionary = B.resolve_attack(atk, guard777, rng777, _combat, {})
			if bool(r.get("miss", false)):
				miss[side] += 1
			elif bool(r.get("block", false)):
				blkn[side] += 1
	var rate0 := float(blkn[0]) / float(n777 - miss[0])
	var rate7 := float(blkn[1]) / float(n777 - miss[1])
	f += _true("777 크리 시 회피가 줄어든다 (%d → %d / %d)" % [miss[0], miss[1], n777],
		miss[1] < miss[0])
	f += _true("777 크리 시 막기 비율이 줄어든다 (%.2f → %.2f)" % [rate0, rate7], rate7 < rate0)

	var p50 := _party([[50, "light"], [0, "fire"]])
	A.apply_battle(p50, [_enemy("dark")], _table, {})
	f += _eq("50 자신 depure_pct 50", B._eff(p50[0], "depure_pct"), 50)
	f += _eq("50 아군 체력 +10%", int(p50[1]["hp_max"]), 1100)
	var p70 := _party([[70, "dark"], [0, "fire"]])
	A.apply_battle(p70, [_enemy("light")], _table, {})
	f += _eq("70 아군 depure_pct 50", B._eff(p70[1], "depure_pct"), 50)
	f += _eq("70 자신 pure_pct 50", B._eff(p70[0], "pure_pct"), 50)
	return f

func _dynamic_checks() -> int:
	var f := 0
	var p99 := _party([[99, "chaos"]])
	A.apply_battle(p99, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 만피면 무효", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.0))
	p99[0]["hp"] = int(p99[0]["hp_max"]) / 2
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 체력 50% → 주는 피해 ×1.5", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.5))
	p99[0]["hp"] = int(p99[0]["hp_max"])
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 회복하면 다시 무효", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.0))

	var p5 := _party([[5, "fire"]])
	A.apply_battle(p5, [_enemy("aqua")], _table, {})
	B._aw_refresh_dynamic(p5, [_enemy("aqua")])
	f += _eq("5 만피면 확정크리 아님", B._has_flag(p5[0], "crit_sure"), false)
	p5[0]["hp"] = int(p5[0]["hp_max"]) / 4
	B._aw_refresh_dynamic(p5, [_enemy("aqua")])
	f += _eq("5 체력 25% → 확정크리", B._has_flag(p5[0], "crit_sure"), true)

	var p12 := _party([[12, "earth"]])
	var hp12 := int(p12[0]["hp_max"])
	A.apply_battle(p12, [_enemy("fire")], _table, {})
	f += _eq("12 최대 체력 +50%", int(p12[0]["hp_max"]), int(round(float(hp12) * 1.5)))
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 만피면 공격 −20%", B._eff(p12[0], "att"), 80)
	p12[0]["hp"] = int(p12[0]["hp_max"]) / 2
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 절반 잃으면 −20+100 = +80%", B._eff(p12[0], "att"), 180)
	var before12 := int(p12[0]["hp_max"])
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 반복 갱신해도 최대체력 불변", int(p12[0]["hp_max"]), before12)

	var p58 := _party([[58, "light"], [0, "light"], [0, "light"]])
	A.apply_battle(p58, [_enemy("dark")], _table, {})
	B._aw_refresh_dynamic(p58, [_enemy("dark")])
	f += _eq("58 빛 3마리 → +60%(상한)", B._eff(p58[0], "att"), 160)
	p58[1]["alive"] = false
	B._aw_refresh_dynamic(p58, [_enemy("dark")])
	f += _eq("58 2마리 → +40%", B._eff(p58[0], "att"), 140)

	var p72 := _party([[72, "dark"], [0, "fire"]])
	A.apply_battle(p72, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p72, [_enemy("light")])
	f += _true("72 생존 중 아군 피해 −10%", is_equal_approx(B._dmg_taken_mult(p72[1]), 0.9))
	p72[0]["alive"] = false
	B._aw_refresh_dynamic(p72, [_enemy("light")])
	f += _true("72 사망 시 −20%", is_equal_approx(B._dmg_taken_mult(p72[1]), 0.8))

	var p37 := _party([[37, "dark"], [0, "fire"]])
	A.apply_battle(p37, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p37, [_enemy("light")])
	f += _eq("37 아군 무사하면 무효", B._eff(p37[0], "att"), 100)
	p37[1]["alive"] = false
	B._aw_refresh_dynamic(p37, [_enemy("light")])
	f += _eq("37 아군 사망 → 공격 +30%", B._eff(p37[0], "att"), 130)
	f += _eq("37 회피 +10", B._eff(p37[0], "evd"), 20)
	return f

func _react_checks() -> int:
	var f := 0
	var rng := RandomNumberGenerator.new(); rng.seed = 5

	var p21 := _party([[21, "earth"]])
	A.apply_battle(p21, [_enemy("fire")], _table, {})
	f += _eq("21 시작은 그대로", B._eff(p21[0], "def"), 100)
	for i in 3:
		B._aw_on_hit_taken(p21[0], _enemy("fire"), 10, rng)
	f += _eq("21 3회 피격 → +15%", B._eff(p21[0], "def"), 115)
	for i in 30:
		B._aw_on_hit_taken(p21[0], _enemy("fire"), 10, rng)
	f += _eq("21 누적 상한 50%", B._eff(p21[0], "def"), 150)

	var p63 := _party([[63, "light"]])
	A.apply_battle(p63, [_enemy("dark")], _table, {})
	for i in 4:
		B._aw_on_attack_done(p63[0], _enemy("dark"), rng)
	f += _eq("63 4회 공격 → +40%", B._eff(p63[0], "att"), 140)

	var p64 := _party([[64, "aqua"], [0, "fire"]])
	A.apply_battle(p64, [_enemy("dark")], _table, {})
	for i in 3:
		B._aw_on_block(p64[0], rng)
	f += _eq("64 아군 공격 +6%", B._eff(p64[1], "att"), 106)
	f += _eq("64 아군 방어 +6%", B._eff(p64[1], "def"), 106)

	var p2 := _party([[2, "dark"]])
	A.apply_battle(p2, [_enemy("light")], _table, {})
	var foe2: Dictionary = _enemy("light")
	f += _eq("2 크리 추가피해 = 상대 최대체력 5%", B._aw_on_crit_bonus(p2[0], foe2), 50)

	var p96 := _party([[96, "wind"]])
	A.apply_battle(p96, [_enemy("fire")], _table, {})
	var hit := 0
	for i in 6:
		var foe: Dictionary = _enemy("fire")
		B._aw_on_evade(p96[0], foe, rng)
		if B._has_flag(foe, "confused"):
			hit += 1
	f += _eq("96 전투당 4회까지만", hit, 4)

	for spec in [[96, "evade"], [666, "evade"], [800, "evade"], [600, "evade"],
			[40, "hit_unguarded"], [85, "skill_cast"]]:
		var no := int(spec[0])
		if not (_table.get("skills", []) as Array).any(func(s): return int(s.get("no", 0)) == no):
			continue
		var pr := _party([[no, "wind"]])
		A.apply_battle(pr, [_enemy("fire")], _table, {})
		var want := 0
		for e in (pr[0]["effects"] as Array):
			var d := e as Dictionary
			if String(d.get("kind", "")) == B.REACT and String(d.get("on", "")) == String(spec[1]):
				want = int(d.get("turns", 0))
		f += _eq("%d 반응이 표의 지속턴을 보존" % no, want, 1)
		var target: Dictionary = _enemy("fire")
		match String(spec[1]):
			"evade":          B._aw_on_evade(pr[0], target, rng)
			"hit_unguarded":  B._aw_on_hit_unguarded(pr[0], target, rng)
			"skill_cast":     B._aw_on_skill_cast(pr[0], [target], rng)
		f += _eq("%d 혼란 지속 1턴(무기한 아님)" % no, B._flag_turns(target, "confused"), 1)

	var sim_ally: Dictionary = B.make_combatant("PO", "ally", "wind", {
		"hp": 500000, "att": 100, "def": 100, "cri": 0, "evd": 70, "blk": 0, "awaken_no": 96})
	var sim_foe: Dictionary = B.make_combatant("E0", "enemy", "fire",
		{"hp": 500000, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	A.apply_battle([sim_ally], [sim_foe], _table, {})
	var sim_rng := RandomNumberGenerator.new()
	sim_rng.seed = 12345
	var sim: Dictionary = B.simulate([sim_ally], [sim_foe], sim_rng, _combat, {}, 120)
	var selfhits := 0
	for ev in (sim["events"] as Array):
		if String((ev as Dictionary).get("type", "")) == "confused":
			selfhits += 1
	f += _eq("96 전투 전체에서 자해는 4회뿐", selfhits, 4)
	f += _eq("96 전투 끝에 혼란이 남지 않는다", B._has_flag(sim_foe, "confused"), false)

	var p81 := _party([[81, "wind"]])
	A.apply_battle(p81, [_enemy("fire")], _table, {})
	B._aw_on_skill_cast(p81[0], [])
	f += _eq("81 스킬 발동 → 확정 회피 플래그", B._has_flag(p81[0], "evade_sure"), true)

	var p45 := _party([[45, "fire"]])
	A.apply_battle(p45, [_enemy("aqua")], _table, {})
	B._aw_on_hit_taken(p45[0], _enemy("aqua"), 60, rng)
	B._aw_on_hit_taken(p45[0], _enemy("aqua"), 60, rng)
	f += _eq("45 누적분 1/3 방출", B._aw_on_attack_bonus(p45[0], _enemy("aqua"), rng), 33)
	f += _eq("45 방출 뒤 초기화", B._aw_on_attack_bonus(p45[0], _enemy("aqua"), rng), 0)

	var p101 := _party([[101, "light"], [0, "fire"]])
	A.apply_battle(p101, [_enemy("dark")], _table, {})
	B._bind_side_gauge(p101)
	B._aw_on_death(p101[0])
	f += _true("101 아군 게이지 +50 (진영 공유 칸)",
		is_equal_approx(B.gauge_of(p101[1]), 50.0))
	return f

func _late_batch_checks() -> int:
	var f := 0
	var rng := RandomNumberGenerator.new()

	var p25 := _party([[25, "aqua"]])
	var e25 := _enemy("fire")
	AwakenSkill.apply_battle(p25, [e25], _table, {})
	for i in 5:
		B._aw_on_attack_done(p25[0], e25, rng, 10)
	f += _eq("25 상대 방어율 -21(3회에서 멈춤)", B._eff(e25, "blk"), 10 - 21)
	f += _eq("25 자신 크리 +21", B._eff(p25[0], "cri"), 10 + 21)

	var p26 := _party([[26, "fire"]])
	AwakenSkill.apply_battle(p26, [], _table, {})
	f += _eq("26 체력이 넉넉하면 그대로", B._aw_fix_damage(p26[0], 500), 500)
	p26[0]["hp"] = 100
	f += _eq("26 체력 20% 이하면 1", B._aw_fix_damage(p26[0], 500), 1)

	var p35 := _party([[35, "aqua"], [0, "aqua"], [0, "fire"]])
	AwakenSkill.apply_battle(p35, [], _table, {})
	p35[0]["alive"] = false
	B._aw_on_death(p35[0])
	f += _eq("35 물속성 아군에 보호막", B._aw_fix_damage(p35[1], 500), 1)
	f += _eq("35 다른 속성엔 미적용", B._aw_fix_damage(p35[2], 500), 500)

	var p41 := _party([[41, "dark"]])
	var e41 := _enemy("light")
	AwakenSkill.apply_battle(p41, [e41], _table, {})
	e41["awaken_gauge"] = 50.0
	rng.seed = 7
	B._aw_on_skill_cast(p41[0], [e41], rng)
	var changed := B._eff(e41, "def") < 100 or B._eff(e41, "att") < 100 			or float(e41["awaken_gauge"]) < 50.0
	f += _true("41 상대에게 무작위 디버프", changed)

	var p46 := _party([[46, "dark"]])
	var e46 := _enemy("light")
	AwakenSkill.apply_battle(p46, [e46], _table, {})
	p46[0]["hp"] = 900
	B._aw_on_attack_done(p46[0], e46, rng, 100)
	f += _eq("46 체력이 넉넉하면 회복 없음", int(p46[0]["hp"]), 900)
	p46[0]["hp"] = 400
	B._aw_on_attack_done(p46[0], e46, rng, 100)
	f += _eq("46 준 피해의 50% 회복", int(p46[0]["hp"]), 450)
	f += _eq("46 공격력 +10%", B._eff(p46[0], "att"), 110)

	var p52 := _party([[52, "earth"]])
	AwakenSkill.apply_battle(p52, [], _table, {})
	f += _eq("52 정액 40 감소", int(B._apply_dmg(p52[0], 500)["dmg"]), 460)
	f += _eq("52 바닥 30 아래로는 안 깎인다", int(B._apply_dmg(p52[0], 50)["dmg"]), 30)
	B._aw_on_hit_taken(p52[0], _enemy("fire"), 10, rng)
	f += _true("52 피격 후 받는 피해 증가", B._dmg_taken_mult(p52[0]) > 1.0)
	B._aw_on_attack_done(p52[0], _enemy("fire"), rng, 10)
	f += _eq("52 공격하면 초기화", B._dmg_taken_mult(p52[0]), 1.0)

	var a60 := _party([[60, "wind"]])
	var b60 := [_enemy("fire")]
	AwakenSkill.apply_battle(a60, b60, _table, {})
	f += _eq("60 한쪽만이면 아군 선공", B._consume_initiative(a60, b60), "ally")
	AwakenSkill.apply_battle(b60, a60, _table, {})
	b60[0]["awaken_no"] = 60
	AwakenSkill.apply_battle(b60, a60, _table, {})
	f += _eq("60 양쪽 다면 무효", B._consume_initiative(a60, b60), "")

	var p65 := _party([[65, "holy"]])
	AwakenSkill.apply_battle(p65, [], _table, {})
	p65[0]["hp"] = 500
	for i in 3:
		B._aw_on_block(p65[0], rng)
	B._aw_on_attack_bonus(p65[0], _enemy("dark"), rng, 0)
	f += _true("65 막기 누적분만큼 회복 (%d)" % int(p65[0]["hp"]), int(p65[0]["hp"]) > 500)

	var p69 := _party([[69, "dark"]])
	p69[0]["grade"] = 5.0
	var foes := [_enemy("light"), _enemy("light"), _enemy("light")]
	AwakenSkill.apply_battle(p69, foes, _table, {})
	B._aw_refresh_dynamic(p69, foes)
	var m1 := B._dmg_deal_mult(p69[0])
	foes[0]["alive"] = false
	foes[1]["alive"] = false
	B._aw_refresh_dynamic(p69, foes)
	f += _true("69 상대 사망마다 배율 증가 (%.2f → %.2f)" % [m1, B._dmg_deal_mult(p69[0])],
		B._dmg_deal_mult(p69[0]) > m1)

	var p75 := _party([[75, "aqua"]])
	AwakenSkill.apply_battle(p75, [], _table, {})
	B._aw_on_attack_bonus(p75[0], _enemy("fire"), rng, 90)
	f += _true("75 방어 시 누적분 감소", B._aw_fix_damage(p75[0], 500) < 500)

	var p78 := _party([[78, "fire"]])
	AwakenSkill.apply_battle(p78, [], _table, {})
	var wall := B.make_combatant("W", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "blk": 100})
	var blocked := 0
	var free := 0
	var plain: Dictionary = _party([[0, "fire"]])[0]
	for i in 40:
		rng.seed = 1000 + i
		if int(B._deal_attack(plain, wall, 1000, true, rng, _combat, {})["damage"]) < 1000:
			blocked += 1
		rng.seed = 1000 + i
		if int(B._deal_attack(p78[0], wall, 1000, true, rng, _combat, {})["damage"]) < 1000:
			free += 1
	f += _true("78 보통은 스킬도 막힌다 (%d/40)" % blocked, blocked > 0)
	f += _eq("78 용암의 노련함은 안 막힌다", free, 0)

	var p79 := _party([[79, "wind"]])
	var w79: Dictionary = _party([[0, "wind"]])[0]
	p79.append(w79)
	AwakenSkill.apply_battle(p79, [], _table, {})
	f += _true("79 always_double 플래그", B._has_flag(p79[0], "always_double"))
	f += _eq("79 바람 아군 증뎀 10%", B._dmg_deal_mult(w79), 1.1)

	var p91 := _party([[91, "dark"]])
	AwakenSkill.apply_battle(p91, [], _table, {})
	f += _eq("91 체력 +15%", int(p91[0]["hp_max"]), 1150)

	var p93 := _party([[93, "fire"]])
	AwakenSkill.apply_battle(p93, [], _table, {})
	p93[0]["cri"] = 100
	var guard := B.make_combatant("G", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "evd": 60, "blk": 60})
	var plain2: Dictionary = _party([[0, "fire"]])[0]
	plain2["cri"] = 100
	var miss_plain := 0
	var miss_sun := 0
	for i in 60:
		rng.seed = 2000 + i
		if bool(B.resolve_attack(plain2, guard, rng, _combat, {}).get("miss", false)):
			miss_plain += 1
		rng.seed = 2000 + i
		if bool(B.resolve_attack(p93[0], guard, rng, _combat, {}).get("miss", false)):
			miss_sun += 1
	f += _true("93 크리 시 회피가 줄어든다 (%d → %d)" % [miss_plain, miss_sun],
		miss_sun < miss_plain)
	return f

func _party(spec: Array) -> Array:
	var out: Array = []
	for i in spec.size():
		var e: Array = spec[i]
		out.append(B.make_combatant("A%d" % i, "ally", String(e[1]), {
			"hp": 1000, "att": 100, "def": 100, "cri": 10, "evd": 10, "blk": 10,
			"awaken_no": int(e[0]),
		}))
	return out

func _enemy(el: String) -> Dictionary:
	return B.make_combatant("E0", "enemy", el, {"hp": 1000, "att": 100, "def": 100})

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
