extends SceneTree

const A := preload("res://scripts/systems/adventure_run.gd")

const N := 3000

func _init() -> void:
	var fails := 0
	var cfg = _json(_data_file("adventure_events.json"))
	var stages: Dictionary = (_json(_data_file("stages.json")) as Dictionary)["stages"]

	fails += _true("steps 블록 있음", cfg.has("steps"))
	fails += _true("run 블록 있음", cfg.has("run"))
	fails += _eq("스텝당 최대 1개", int(cfg["steps"]["max_events_per_step"]), 1)

	var sid := ""
	for k in stages:
		if int((stages[k].get("enemies", []) as Array).size()) >= 4:
			sid = String(k); break
	fails += _true("표본 스테이지 찾음", sid != "")
	var st: Dictionary = stages[sid]
	var total := int((st.get("enemies", []) as Array).size())

	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var bad_tail := 0
	var too_many := 0
	var seen: Dictionary = {}
	for i in N:
		var enc := i % maxi(1, total - 1)
		var steps := A.build_steps(st, cfg, enc,
			{"hurt": true, "fortress": true, "random_boss": false}, rng)
		if String((steps[steps.size() - 1] as Dictionary).get("type", "")) != A.MONSTER:
			bad_tail += 1
		if steps.size() > 2:
			too_many += 1
		for s in steps:
			seen[String((s as Dictionary).get("type", ""))] = true
	fails += _eq("마지막이 몬스터가 아닌 경우", bad_tail, 0)
	fails += _eq("사전 이벤트가 2개 이상인 경우", too_many, 0)
	fails += _true("사전 이벤트가 실제로 나오긴 한다", seen.size() > 1)

	var brng := RandomNumberGenerator.new(); brng.seed = 9
	var boss_extra := 0
	for _i in N:
		var bs := A.build_steps(st, cfg, total - 1,
			{"hurt": true, "fortress": true, "random_boss": false}, brng)
		if bs.size() != 1: boss_extra += 1
		if not bool((bs[0] as Dictionary).get("boss", false)): boss_extra += 1
	fails += _eq("보스 조우에 사전 이벤트", boss_extra, 0)

	var rbs := A.build_steps(st, cfg, 0,
		{"hurt": true, "fortress": true, "random_boss": true}, brng)
	fails += _eq("랜덤보스 = 몬스터 1스텝", rbs.size(), 1)
	fails += _true("랜덤보스는 boss 표시", bool((rbs[0] as Dictionary).get("boss", false)))

	var frng := RandomNumberGenerator.new(); frng.seed = 21
	var leaked: Dictionary = {}
	for _i in N:
		for s in A.build_steps(st, cfg, 1,
				{"hurt": true, "fortress": false, "random_boss": false}, frng):
			var t := String((s as Dictionary).get("type", ""))
			if t == A.SHOP or t == A.CHOICE or t == A.CARDGAME:
				leaked[t] = true
	fails += _eq("일반 지역에 요새 전용 이벤트 누출", leaked.size(), 0)

	var hrng := RandomNumberGenerator.new(); hrng.seed = 33
	var heal_leak := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 3,
				{"hurt": false, "fortress": true, "random_boss": false}, hrng):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				heal_leak += 1
	fails += _eq("멀쩡한데 회복샘", heal_leak, 0)

	var e0 := RandomNumberGenerator.new(); e0.seed = 44
	var early_heal := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 0,
				{"hurt": true, "fortress": true, "random_boss": false}, e0):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				early_heal += 1
	fails += _eq("첫 조우에 회복샘", early_heal, 0)
	var e1 := RandomNumberGenerator.new(); e1.seed = 44
	var late_heal := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 1,
				{"hurt": true, "fortress": true, "random_boss": false}, e1):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				late_heal += 1
	fails += _true("enc>=1 에서는 회복샘이 나온다", late_heal > 0)

	var d1 := RandomNumberGenerator.new(); d1.seed = 777
	var d2 := RandomNumberGenerator.new(); d2.seed = 777
	var same := true
	for _i in 200:
		var a := A.build_steps(st, cfg, 2, {"hurt": true, "fortress": true, "random_boss": false}, d1)
		var b := A.build_steps(st, cfg, 2, {"hurt": true, "fortress": true, "random_boss": false}, d2)
		if str(a) != str(b): same = false
	fails += _true("같은 시드 → 같은 큐", same)

	var enemies: Array = st.get("enemies", [])
	var boss_idx: Array = []
	for i in enemies.size():
		if bool((enemies[i] as Dictionary).get("boss", false)):
			boss_idx.append(i)
	fails += _eq("표본 스테이지의 보스는 마지막 1마리", str(boss_idx), str([total - 1]))
	var er := RandomNumberGenerator.new(); er.seed = 2468
	var missing_idx := 0
	var boss_leak := 0
	var per_enc: Array = []
	for enc2 in (total - 1):
		var seen_idx: Dictionary = {}
		for _i in N:
			var s2: Dictionary = A.build_steps(st, cfg, enc2,
				{"hurt": true, "fortress": true, "random_boss": false}, er).back()
			if not s2.has("enemy_index"):
				missing_idx += 1
				continue
			var ei := int(s2["enemy_index"])
			if ei in boss_idx:
				boss_leak += 1
			seen_idx[ei] = true
		per_enc.append(seen_idx.keys().size())
	fails += _eq("일반 조우에 상대가 안 실린 경우", missing_idx, 0)
	fails += _eq("일반 조우에 보스가 섞인 경우", boss_leak, 0)
	for enc3 in per_enc.size():
		fails += _eq("조우 %d 의 후보 수 = 비보스 전원" % enc3,
			int(per_enc[enc3]), total - 1)
	var bstep: Dictionary = A.build_steps(st, cfg, total - 1,
		{"hurt": true, "fortress": true, "random_boss": false}, er).back()
	fails += _true("보스 조우는 enemy_index 를 싣지 않는다", not bstep.has("enemy_index"))
	var allboss := {"enemies": [{"boss": true}, {"boss": true}]}
	var ab: Dictionary = A.build_steps(allboss, cfg, 0,
		{"hurt": true, "fortress": true, "random_boss": false}, er).back()
	fails += _true("비보스 후보가 없으면 상대를 싣지 않는다", not ab.has("enemy_index"))

	fails += _true("일반 조우 도망 가능", A.offers_escape(false))
	fails += _true("보스도 도망 버튼(원작 양버튼 경로)", A.offers_escape(true))
	fails += _eq("요새는 '포기한다'", A.escape_frame(true), "scene_adventure_choice_giveup_KR")
	fails += _eq("그 밖은 '도망간다'", A.escape_frame(false), "scene_adventure_choice_run_KR")

	var rr := RandomNumberGenerator.new(); rr.seed = 101
	for _i in N:
		fails += _true("일반 조우 확정 탈출", A.run_succeeds(cfg, false, rr))
		fails += _true("보스 조우 확정 탈출", A.run_succeeds(cfg, true, rr))

	var F := load("res://scripts/systems/field.gd")
	var D2 := load("res://scripts/systems/drops.gd")
	var night_base: Dictionary = stages["1"]
	var nst: Dictionary = F.apply_variant(night_base, D2.MODE_NIGHT)
	var nrng := RandomNumberGenerator.new(); nrng.seed = 4242
	var cnt := {"nothing": 0, "encounter": 0, "boss": 0}
	var bad_len := 0
	var not_final := 0
	var off_roster := 0
	var commons := {}
	var boss_mismatch := 0
	for e in (nst.get("enemies", []) as Array):
		if bool((e as Dictionary).get("encounter", false)):
			commons[int((e as Dictionary).get("id", 0))] = true
	for _i in N * 4:
		var steps := A.build_steps(nst, cfg, 0,
			{"hurt": true, "fortress": false, "random_boss": true, "night": true}, nrng)
		if steps.size() != 1: bad_len += 1
		var s0: Dictionary = steps[0]
		if not A.is_final(s0): not_final += 1
		if String(s0.get("type", "")) == A.NOTHING:
			cnt["nothing"] += 1
			continue
		var ei := int(s0.get("enemy_index", -1))
		var en: Dictionary = (nst["enemies"] as Array)[ei]
		if bool(s0.get("boss", false)) != bool(en.get("boss", false)): boss_mismatch += 1
		if bool(en.get("encounter", false)):
			cnt["encounter"] += 1
			if not commons.has(int(en.get("id", 0))): off_roster += 1
		else:
			cnt["boss"] += 1
			if not bool(en.get("boss", false)): off_roster += 1
	fails += _eq("밤은 항상 스텝 1개", bad_len, 0)
	fails += _eq("밤 스텝은 항상 final", not_final, 0)
	fails += _eq("밤 조우 대상이 편성 밖", off_roster, 0)
	fails += _eq("밤 스텝의 보스 취급이 편성과 다름", boss_mismatch, 0)
	var tot := float(cnt["nothing"] + cnt["encounter"] + cnt["boss"])
	var p_no := float(cnt["nothing"]) / tot
	var p_en := float(cnt["encounter"]) / tot
	var p_bo := float(cnt["boss"]) / tot
	fails += _true("밤 아무것도 ≈20%% (%.3f)" % p_no, absf(p_no - 0.2) < 0.02)
	fails += _true("밤 랜덤조우 ≈15%% (%.3f)" % p_en, absf(p_en - 0.15) < 0.02)
	fails += _true("밤 지역보스 ≈65%% (%.3f)" % p_bo, absf(p_bo - 0.65) < 0.02)
	var pre := 0
	for _i in 500:
		for s2 in A.build_steps(nst, cfg, 0,
				{"hurt": true, "fortress": true, "random_boss": true, "night": true}, nrng):
			var t2 := String((s2 as Dictionary).get("type", ""))
			if t2 != A.MONSTER and t2 != A.NOTHING: pre += 1
	fails += _eq("밤에 사전 이벤트", pre, 0)

	if fails == 0:
		print("[test_adventure_run] ALL PASS")
		quit(0)
	else:
		printerr("[test_adventure_run] %d FAIL" % fails)
		quit(1)

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
