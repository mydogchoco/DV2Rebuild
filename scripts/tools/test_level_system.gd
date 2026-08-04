extends SceneTree
## 헤드리스 LevelSystem 단위 테스트 (§10 — logic은 화면 없이 검증 가능).
## 실행: godot --headless --script res://scripts/tools/test_level_system.gd
## LevelSystem은 순수 logic이라 autoload 없이 합성 데이터로 검증한다(실제 곡선은 파일로 로드해 정합성만 확인).

func _init() -> void:
	var fails := 0

	# 합성: atk 4성 = base 199/21/21, growth 11/5/2 (레벨업 delta = growth와 동일)
	var table := {"atk": {"4": {
		"base": {"hp": 199, "att": 21, "def": 21},
		"growth": {"hp": 11, "att": 5, "def": 2}}}}
	var dragon := {"type": "atk", "stat_tier": "4"}
	# 합성 곡선: 일반상한3, 각성상한5. req[L-1]=L→L+1 필요 exp.
	var curve := {"cap": 3, "cap_awakened": 5, "req": [100, 200, 300, 400]}

	# 1) exp_to_next 범위
	fails += _eq("next(1)", LevelSystem.exp_to_next(curve, 1), 100)
	fails += _eq("next(2)", LevelSystem.exp_to_next(curve, 2), 200)
	fails += _eq("next(0)=0", LevelSystem.exp_to_next(curve, 0), 0)
	fails += _eq("next(5)=beyond0", LevelSystem.exp_to_next(curve, 5), 0)

	# apply_exp(랜덤롤 모델): 레벨 진행(exp 산술)은 롤과 무관 — gains 개수/exp만 검증. maxs=스탯별 최대상승.
	var maxs := {"hp": 13, "att": 2, "def": 5}   # stat_table growth = 스탯별 최대 상승량
	var cfg0 := {"transcend": {"hp": 4, "att": 1, "def": 1}, "transcend_chance": 0.0,
		"triple_max_base": 0.0, "triple_max_step": 0.0, "triple_max_cap": 1.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	# 2) 레벨업 없음: gained 50 < 100
	var r := LevelSystem.apply_exp(curve, cfg0, maxs, 1, 0, 50, rng)
	fails += _eq("noup level", r["level"], 1)
	fails += _eq("noup exp", r["exp"], 50)
	fails += _eq("noup gained", r["levels_gained"], 0)
	fails += _eq("noup exp_max", r["exp_max"], 100)
	fails += _eq("noup capped", r["capped"], false)

	# 3) 정확히 1레벨업: gained 100 → gains 1개, 각 상승 [1,max]
	r = LevelSystem.apply_exp(curve, cfg0, maxs, 1, 0, 100, rng)
	fails += _eq("up1 level", r["level"], 2)
	fails += _eq("up1 exp", r["exp"], 0)
	fails += _eq("up1 gained", r["levels_gained"], 1)
	fails += _eq("up1 gains size", (r["gains"] as Array).size(), 1)
	fails += _eq("up1 exp_max(next=2)", r["exp_max"], 200)
	fails += _true("up1 hp in [1,13]", int(r["gains"][0]["hp"]) >= 1 and int(r["gains"][0]["hp"]) <= 13)
	fails += _true("up1 def in [1,5]", int(r["gains"][0]["def"]) >= 1 and int(r["gains"][0]["def"]) <= 5)

	# 4) 잔여 경험치 이월: gained 250 → +100(→2), 150<200 → lv2 exp150
	r = LevelSystem.apply_exp(curve, cfg0, maxs, 1, 0, 250, rng)
	fails += _eq("carry level", r["level"], 2)
	fails += _eq("carry exp", r["exp"], 150)
	fails += _eq("carry gained", r["levels_gained"], 1)

	# 5) 일반 상한(3)에서 멈춤 + 잉여 폐기: gained 999, 상한3
	r = LevelSystem.apply_exp(curve, cfg0, maxs, 1, 0, 999, rng)
	fails += _eq("cap level", r["level"], 3)
	fails += _eq("cap capped", r["capped"], true)
	fails += _eq("cap exp=0", r["exp"], 0)
	fails += _eq("cap exp_max=0", r["exp_max"], 0)
	fails += _eq("cap levels_gained", r["levels_gained"], 2)

	# 6) 각성 시 상한5까지: gained 1000(=100+200+300+400) → lv5, 4롤
	r = LevelSystem.apply_exp(curve, cfg0, maxs, 1, 0, 1000, rng, true)
	fails += _eq("awk level", r["level"], 5)
	fails += _eq("awk capped", r["capped"], true)
	fails += _eq("awk levels_gained", r["levels_gained"], 4)
	fails += _eq("awk gains size", (r["gains"] as Array).size(), 4)

	# 7) 이미 상한: 추가 exp 무시
	r = LevelSystem.apply_exp(curve, cfg0, maxs, 3, 0, 500, rng)
	fails += _eq("atcap level", r["level"], 3)
	fails += _eq("atcap levels_gained", r["levels_gained"], 0)
	fails += _eq("atcap capped", r["capped"], true)

	# 10) pity_prob: base + step*count, 천장 (별도 cfg — cfg0은 결정론 위해 base 0)
	var pcfg := {"triple_max_base": 0.014, "triple_max_step": 0.002, "triple_max_cap": 1.0}
	fails += _true("pity base", absf(LevelSystem.pity_prob(pcfg, 0) - 0.014) < 1e-6)
	fails += _true("pity +10", absf(LevelSystem.pity_prob(pcfg, 10) - 0.034) < 1e-6)
	fails += _true("pity cap", absf(LevelSystem.pity_prob(pcfg, 100000) - 1.0) < 1e-6)

	# 11) guarantee "triple" (초월0) → 전스탯 정확히 max, triple
	var rt := LevelSystem.roll_level(cfg0, maxs, rng, 0.0, "triple")
	fails += _eq("triple hp=max", rt["hp"], 13)
	fails += _eq("triple att=max", rt["att"], 2)
	fails += _eq("triple def=max", rt["def"], 5)
	fails += _eq("triple maxes", rt["maxes"], 3)
	fails += _eq("triple flag", rt["triple"], true)

	# 12) guarantee "amor" → 전스탯 초월맥스(max+가산)
	var ra := LevelSystem.roll_level(cfg0, maxs, rng, 0.0, "amor")
	fails += _eq("amor hp=max+4", ra["hp"], 17)
	fails += _eq("amor att=max+1", ra["att"], 3)
	fails += _eq("amor def=max+1", ra["def"], 6)
	fails += _eq("amor tmax.hp", ra["tmax"]["hp"], true)
	fails += _eq("amor triple", ra["triple"], true)

	# 13) 초월맥스 강제(chance=1) → 모든 스탯 max+가산
	var cfg_t := cfg0.duplicate(true); cfg_t["transcend_chance"] = 1.0
	var rtr := LevelSystem.roll_level(cfg_t, maxs, rng, 0.0, "")
	fails += _eq("trans hp", rtr["hp"], 17)
	fails += _eq("trans def", rtr["def"], 6)
	fails += _eq("trans maxes", rtr["maxes"], 3)

	# 14) guarantee "max2" (초월0, pity0) → 최소 2스탯 max
	for i in 20:
		var rm := LevelSystem.roll_level(cfg0, maxs, rng, 0.0, "max2")
		fails += _true("max2 >=2 maxes iter%d" % i, int(rm["maxes"]) >= 2)

	# 15) 일반 롤: 각 스탯 [1,max] 범위, 초월0이면 gain<=max
	for i in 50:
		var rn := LevelSystem.roll_level(cfg0, maxs, rng, 0.0, "")
		for s in ["hp", "att", "def"]:
			var g := int(rn[s])
			fails += _true("range %s iter%d" % [s, i], g >= 1 and g <= int(maxs[s]))

	# 16) 강제 트리플(pity=1.0) → 항상 triple
	for i in 10:
		var rp := LevelSystem.roll_level(cfg0, maxs, rng, 1.0, "")
		fails += _eq("pity1 triple iter%d" % i, rp["triple"], true)

	# 17) 저장 모델: Growth.main_stats = base(티어) + 영구base보정 + Σgain_log. tier_growth=최대상승량.
	var tbl := {"atk": {"4": {"base": {"hp": 199, "att": 21, "def": 21},
		"growth": {"hp": 11, "att": 5, "def": 2}}}}
	var dgn := {"type": "atk", "stat_tier": "4"}
	fails += _eq("tier_growth hp", Growth.tier_growth(dgn, tbl)["hp"], 11)
	fails += _eq("tier_base hp", Growth.tier_base(dgn, tbl)["hp"], 199)
	var glog := [{"hp": 11, "att": 5, "def": 2}, {"hp": 5, "att": 3, "def": 1}]   # 레벨업 2회 롤
	var ms := Growth.main_stats(dgn, tbl, glog, {})
	fails += _eq("main hp", ms["hp"], 199 + 11 + 5)
	fails += _eq("main att", ms["att"], 21 + 5 + 3)
	fails += _eq("main def", ms["def"], 21 + 2 + 1)
	fails += _eq("main cri fixed", ms["cri"], 10)
	# 영구 base 보정(축복받은 둥지 +8/2/2)
	var ms2 := Growth.main_stats(dgn, tbl, glog, {"hp": 8, "att": 2, "def": 2})
	fails += _eq("main+nest hp", ms2["hp"], 199 + 16 + 8)
	# 빈 로그 = 레벨1 = base
	fails += _eq("main empty=base", Growth.main_stats(dgn, tbl, [], {})["hp"], 199)

	# 9) 실제 곡선 파일 정합성(data/level_curve.json)
	var f := FileAccess.open("res://data/level_curve.json", FileAccess.READ)
	if f == null:
		fails += 1
		print("  FAIL real curve: missing data/level_curve.json")
	else:
		var real: Dictionary = JSON.parse_string(f.get_as_text())
		var req: Array = real.get("req", [])
		fails += _eq("real req size(49)", req.size(), 49)
		fails += _eq("real cap", int(real.get("cap", 0)), 50)
		fails += _eq("real cap_awakened", int(real.get("cap_awakened", 0)), 50)
		fails += _eq("real next(1)", LevelSystem.exp_to_next(real, 1), 40)
		var cum := 0
		for x in req:
			cum += int(x)
		# 누적 → lv50 ≈ 관측앵커 1,625,625 (반올림 오차 허용)
		fails += _true("real cum≈1.62M", absi(cum - 1625625) < 50)

	if fails == 0:
		print("[test_level_system] ✅ ALL PASS")
	else:
		print("[test_level_system] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL %s" % label)
	return 1
