extends SceneTree

func _init() -> void:
	var fails := 0
	var table := {"atk": {"4": {
		"base": {"hp": 199, "att": 21, "def": 21},
		"growth": {"hp": 11, "att": 5, "def": 2}}}}
	var dragon := {"type": "atk", "stat_tier": "4"}

	var s1 := Growth.compute_stats(dragon, table, 1)
	fails += _eq("Lv1 hp", s1["hp"], 199)
	fails += _eq("Lv1 att", s1["att"], 21)
	fails += _eq("Lv1 cri", s1["cri"], 10)
	var s10 := Growth.compute_stats(dragon, table, 10)
	fails += _eq("Lv10 hp", s10["hp"], 199 + 11 * 9)
	fails += _eq("Lv10 att", s10["att"], 21 + 5 * 9)

	fails += _eqf("base grade", Growth.compute_grade(dragon, table), 7.0)

	var nest := {"base": {"hp": 8, "att": 2, "def": 2}, "growth": {"hp": 0, "att": 0, "def": 0}}
	fails += _eqf("nest grade", Growth.compute_grade(dragon, table, nest), 7.6)
	fails += _eq("nest Lv1 hp", Growth.compute_stats(dragon, table, 1, nest)["hp"], 207)

	var gdelta := {"growth": {"hp": 4, "att": 1, "def": 1}}
	fails += _eqf("growth-delta grade", Growth.compute_grade(dragon, table, gdelta), 7.3)
	fails += _eq("growth-delta Lv10 hp", Growth.compute_stats(dragon, table, 10, gdelta)["hp"], 199 + 15 * 9)

	var amor := [{"hp": 11 + 4, "att": 5 + 1, "def": 2 + 1}]
	fails += _eqf("amor grade (+0.3)", Growth.compute_grade(dragon, table, {}, amor), 7.3)
	var poor := [{"hp": 1, "att": 1, "def": 1}]
	fails += _eqf("poor roll grade (-0.75)", Growth.compute_grade(dragon, table, {}, poor), 6.25)
	var perfect := [{"hp": 11, "att": 5, "def": 2}, {"hp": 11, "att": 5, "def": 2}]
	fails += _eqf("max rolls keep grade", Growth.compute_grade(dragon, table, {}, perfect), 7.0)
	var cfg_ex := {"baseline": "excess_only"}
	fails += _eqf("excess_only poor", Growth.compute_grade(dragon, table, {}, poor, cfg_ex), 7.0)
	fails += _eqf("excess_only amor", Growth.compute_grade(dragon, table, {}, amor, cfg_ex), 7.3)
	fails += _eqf("nest + amor", Growth.compute_grade(dragon, table, nest, amor), 7.9)

	fails += _eq("cap normal", Growth.level_cap(false), 50)
	fails += _eq("cap awakened", Growth.level_cap(true), 50)
	fails += _eq("next normal at 45", Growth.next_level(45), 46)
	fails += _eq("next awakened at 45", Growth.next_level(45, true), 46)
	fails += _eq("next at cap", Growth.next_level(50), 50)
	fails += _eq("stage baby", Growth.stage_for_level(9), "baby")
	fails += _eq("stage child", Growth.stage_for_level(10), "child")
	fails += _eq("stage child@20", Growth.stage_for_level(20), "child")
	fails += _eq("stage child@24", Growth.stage_for_level(24), "child")
	fails += _eq("stage adult", Growth.stage_for_level(25), "adult")
	fails += _eq("normal spine stage", Growth.spine_stage({"level": 50}), "adult")
	fails += _eq("awakened spine stage", Growth.spine_stage({"level": 50, "awakened": true}), "e")
	fails += _eq("awakened portrait stage", Growth.portrait_stage({"level": 50, "awakened": true}), "evolution")

	fails += _eq("missing tier hp", Growth.compute_stats({"type": "x", "stat_tier": "9"}, table, 5)["hp"], 0)

	if fails == 0:
		print("[test_growth] ✅ ALL PASS")
	else:
		print("[test_growth] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _eqf(label: String, got: float, want: float) -> int:
	if absf(got - want) < 0.0001:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1
