extends SceneTree
## 헤드리스 Growth 단위 테스트 (§10 — logic은 화면 없이 검증 가능).
## 실행: godot --headless --script res://scripts/tools/test_growth.gd
## Growth는 순수 logic이라 autoload 없이 자체 합성 데이터로 검증한다.

func _init() -> void:
	var fails := 0
	# 합성 기준선표: 공격형(atk) 4성 = base 199/21/21, growth 11/5/2 (실제 stat_table.json 형식)
	var table := {"atk": {"4": {
		"base": {"hp": 199, "att": 21, "def": 21},
		"growth": {"hp": 11, "att": 5, "def": 2}}}}
	var dragon := {"type": "atk", "stat_tier": "4"}

	# 1) 기준선 스탯(편차0)
	var s1 := Growth.compute_stats(dragon, table, 1)
	fails += _eq("Lv1 hp", s1["hp"], 199)
	fails += _eq("Lv1 att", s1["att"], 21)
	fails += _eq("Lv1 cri", s1["cri"], 10)
	var s10 := Growth.compute_stats(dragon, table, 10)             # base + growth*9
	fails += _eq("Lv10 hp", s10["hp"], 199 + 11 * 9)
	fails += _eq("Lv10 att", s10["att"], 21 + 5 * 9)

	# 2) 기준선 등급 = 정확히 7.0
	fails += _eqf("base grade", Growth.compute_grade(dragon, table), 7.0)

	# 3) 검산(§K-10): 축복받은 둥지 base +8/+2/+2 → grade +0.6, hp +8
	var nest := {"base": {"hp": 8, "att": 2, "def": 2}, "growth": {"hp": 0, "att": 0, "def": 0}}
	fails += _eqf("nest grade", Growth.compute_grade(dragon, table, nest), 7.6)
	fails += _eq("nest Lv1 hp", Growth.compute_stats(dragon, table, 1, nest)["hp"], 207)

	# 4) growth 편차도 등급에 합산: growth +4hp/+1att/+1def → +0.1*(4/4 + 1 + 1) = +0.3
	var gdelta := {"growth": {"hp": 4, "att": 1, "def": 1}}
	fails += _eqf("growth-delta grade", Growth.compute_grade(dragon, table, gdelta), 7.3)
	# growth 편차는 레벨 스케일: Lv10 hp = (199) + (11+4)*9
	fails += _eq("growth-delta Lv10 hp", Growth.compute_stats(dragon, table, 10, gdelta)["hp"], 199 + 15 * 9)

	# 4-b) 레벨업 롤(gain_log)도 등급에 반영된다 — 🔴 2026-07-27 회귀방지.
	#      사용자 보고: "아모르의 축복(전 스탯 초월맥스)을 써도 등급이 훨씬 덜 오름".
	#      원인은 compute_grade 가 gain_log 를 아예 안 봤던 것. 초과분 = transcend 가산분 4/1/1.
	#      기대: max(11/5/2) 대비 hp+4, att+1, def+1 초과 → 0.1*(4/4 + 1 + 1) = +0.3
	var amor := [{"hp": 11 + 4, "att": 5 + 1, "def": 2 + 1}]
	fails += _eqf("amor grade (+0.3)", Growth.compute_grade(dragon, table, {}, amor), 7.3)
	# 기준선("max")에서는 미달 롤이 감점이다(사용자 확정 2026-07-27).
	#   hp 1/11(-10), att 1/5(-4), def 1/2(-1) → 0.1*(-10/4 - 4 - 1) = -0.75
	var poor := [{"hp": 1, "att": 1, "def": 1}]
	fails += _eqf("poor roll grade (-0.75)", Growth.compute_grade(dragon, table, {}, poor), 6.25)
	# 만점 롤(=기준선 그대로)이면 등급 불변.
	var perfect := [{"hp": 11, "att": 5, "def": 2}, {"hp": 11, "att": 5, "def": 2}]
	fails += _eqf("max rolls keep grade", Growth.compute_grade(dragon, table, {}, perfect), 7.0)
	# 노브 "excess_only": 미달은 0, 초과분만 가산 → 위 poor 는 등급 불변, amor 는 그대로 +0.3
	var cfg_ex := {"baseline": "excess_only"}
	fails += _eqf("excess_only poor", Growth.compute_grade(dragon, table, {}, poor, cfg_ex), 7.0)
	fails += _eqf("excess_only amor", Growth.compute_grade(dragon, table, {}, amor, cfg_ex), 7.3)
	# 부화 편차와 롤 편차는 합산된다(둘 다 Δ).
	fails += _eqf("nest + amor", Growth.compute_grade(dragon, table, nest, amor), 7.9)

	# 5) 레벨캡 / next_level / 단계
	fails += _eq("cap normal", Growth.level_cap(false), 45)
	fails += _eq("cap awakened", Growth.level_cap(true), 50)
	fails += _eq("next at cap", Growth.next_level(45), 45)
	fails += _eq("next awakened", Growth.next_level(45, true), 46)
	# 경계값 = 원작 Dragon.c 실측(10 / 25). 레벨 20은 **아직 성장기**다(예전 오답: adult).
	fails += _eq("stage baby", Growth.stage_for_level(9), "baby")
	fails += _eq("stage child", Growth.stage_for_level(10), "child")
	fails += _eq("stage child@20", Growth.stage_for_level(20), "child")
	fails += _eq("stage child@24", Growth.stage_for_level(24), "child")
	fails += _eq("stage adult", Growth.stage_for_level(25), "adult")

	# 7) 누락 티어 → 0 스탯(안전)
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
