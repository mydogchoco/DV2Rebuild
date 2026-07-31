extends SceneTree
## 헤드리스 AdventureRun 단위 테스트 (§8 — logic은 화면 없이 검증).
## 검증 대상 = 원작 이벤트 큐 구조(docs/ref/porting/AdventureEventFlow.md §1):
##   · 한 스텝의 **마지막은 항상 몬스터**
##   · 사전 이벤트는 **최대 1개**(종전엔 5개가 동시에 터졌다 — 이 테스트가 막는 회귀)
##   · **보스 조우에는 사전 이벤트가 붙지 않는다**
##   · 게이트: fortress_only / needs_hurt / min_enc
## 실행: godot --headless --path . --script res://scripts/tools/test_adventure_run.gd --quit-after 3

const A := preload("res://scripts/systems/adventure_run.gd")

const N := 3000

func _init() -> void:
	var fails := 0
	var cfg = _json("res://data/adventure_events.json")
	var stages: Dictionary = (_json("res://data/stages.json") as Dictionary)["stages"]

	fails += _true("steps 블록 있음", cfg.has("steps"))
	fails += _true("run 블록 있음", cfg.has("run"))
	fails += _eq("스텝당 최대 1개", int(cfg["steps"]["max_events_per_step"]), 1)

	# 적이 여러 마리인 일반 지역 하나를 고른다(보스가 아닌 조우가 존재해야 한다).
	var sid := ""
	for k in stages:
		if int((stages[k].get("enemies", []) as Array).size()) >= 4:
			sid = String(k); break
	fails += _true("표본 스테이지 찾음", sid != "")
	var st: Dictionary = stages[sid]
	var total := int((st.get("enemies", []) as Array).size())

	# 1) 구조 — 마지막은 항상 몬스터, 사전 이벤트는 0 또는 1개.
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var bad_tail := 0
	var too_many := 0
	var seen: Dictionary = {}
	for i in N:
		var enc := i % maxi(1, total - 1)          # 보스 직전까지만
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

	# 2) 보스 조우 — 사전 이벤트 없음.
	var brng := RandomNumberGenerator.new(); brng.seed = 9
	var boss_extra := 0
	for _i in N:
		var bs := A.build_steps(st, cfg, total - 1,
			{"hurt": true, "fortress": true, "random_boss": false}, brng)
		if bs.size() != 1: boss_extra += 1
		if not bool((bs[0] as Dictionary).get("boss", false)): boss_extra += 1
	fails += _eq("보스 조우에 사전 이벤트", boss_extra, 0)

	# 랜덤보스 스테이지(혼돈의 틈새 등)도 마찬가지.
	var rbs := A.build_steps(st, cfg, 0,
		{"hurt": true, "fortress": true, "random_boss": true}, brng)
	fails += _eq("랜덤보스 = 몬스터 1스텝", rbs.size(), 1)
	fails += _true("랜덤보스는 boss 표시", bool((rbs[0] as Dictionary).get("boss", false)))

	# 3) 게이트 — 해골요새 전용 이벤트는 일반 지역에서 안 나온다.
	var frng := RandomNumberGenerator.new(); frng.seed = 21
	var leaked: Dictionary = {}
	for _i in N:
		for s in A.build_steps(st, cfg, 1,
				{"hurt": true, "fortress": false, "random_boss": false}, frng):
			var t := String((s as Dictionary).get("type", ""))
			if t == A.SHOP or t == A.CHOICE or t == A.CARDGAME:
				leaked[t] = true
	fails += _eq("일반 지역에 요새 전용 이벤트 누출", leaked.size(), 0)

	# 4) 게이트 — 안 다쳤으면 회복샘이 안 나온다.
	var hrng := RandomNumberGenerator.new(); hrng.seed = 33
	var heal_leak := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 3,
				{"hurt": false, "fortress": true, "random_boss": false}, hrng):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				heal_leak += 1
	fails += _eq("멀쩡한데 회복샘", heal_leak, 0)

	# 5) 게이트 — min_enc(회복샘은 첫 조우 enc=0 에 안 나온다).
	var e0 := RandomNumberGenerator.new(); e0.seed = 44
	var early_heal := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 0,
				{"hurt": true, "fortress": true, "random_boss": false}, e0):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				early_heal += 1
	fails += _eq("첫 조우에 회복샘", early_heal, 0)
	# 반대로 enc>=1 에서는 나온다(게이트가 영영 막아 버리지 않았는지).
	var e1 := RandomNumberGenerator.new(); e1.seed = 44
	var late_heal := 0
	for _i in N:
		for s in A.build_steps(st, cfg, 1,
				{"hurt": true, "fortress": true, "random_boss": false}, e1):
			if A.is_heal(String((s as Dictionary).get("type", ""))):
				late_heal += 1
	fails += _true("enc>=1 에서는 회복샘이 나온다", late_heal > 0)

	# 6) 결정성 — 같은 시드면 같은 큐(씬이 다시 지어져도 이벤트가 바뀌면 안 된다).
	var d1 := RandomNumberGenerator.new(); d1.seed = 777
	var d2 := RandomNumberGenerator.new(); d2.seed = 777
	var same := true
	for _i in 200:
		var a := A.build_steps(st, cfg, 2, {"hurt": true, "fortress": true, "random_boss": false}, d1)
		var b := A.build_steps(st, cfg, 2, {"hurt": true, "fortress": true, "random_boss": false}, d2)
		if str(a) != str(b): same = false
	fails += _true("같은 시드 → 같은 큐", same)

	# 7) 조우 전 선택지 — 도망 버튼은 항상 준다(부스트 단일버튼 조건은 ⚫CUT).
	fails += _true("일반 조우 도망 가능", A.offers_escape(false))
	fails += _true("보스도 도망 버튼(원작 양버튼 경로)", A.offers_escape(true))
	fails += _eq("요새는 '포기한다'", A.escape_frame(true), "scene_adventure_choice_giveup_KR")
	fails += _eq("그 밖은 '도망간다'", A.escape_frame(false), "scene_adventure_choice_run_KR")

	# 8) 도망 성공률 — 보스가 더 어렵다.
	var rr := RandomNumberGenerator.new(); rr.seed = 101
	var ok_n := 0
	var ok_b := 0
	for _i in N:
		if A.run_succeeds(cfg, false, rr): ok_n += 1
		if A.run_succeeds(cfg, true, rr): ok_b += 1
	fails += _true("도망이 성공하긴 한다", ok_n > 0)
	fails += _true("보스 도망이 더 어렵다", ok_b < ok_n)

	# ── 유타칸 밤 = **1회 조우 후 종료** (사용자 확정 2026-07-31) ──────────────
	# 원작 문구 확인: <NightTutorial_talk10> "강력한 만큼 긴 전투 때문에 탐험은 단 한번!
	# 계속 이어갈 수가 없어." / 코드 = checkAdventureNightEnd → m_nEventType 0x1d(Finish).
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
	for e in (nst.get("enemies", []) as Array):
		if not bool((e as Dictionary).get("boss", false)):
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
		if bool(s0.get("boss", false)):
			cnt["boss"] += 1
			if not bool(en.get("boss", false)): off_roster += 1
		else:
			cnt["encounter"] += 1
			if not commons.has(int(en.get("id", 0))): off_roster += 1
	fails += _eq("밤은 항상 스텝 1개", bad_len, 0)
	fails += _eq("밤 스텝은 항상 final", not_final, 0)
	fails += _eq("밤 조우 대상이 편성 밖", off_roster, 0)
	# 2 : 3 : 5 (사용자 확정). 표본 12000 이면 ±2%p 안에 들어온다.
	var tot := float(cnt["nothing"] + cnt["encounter"] + cnt["boss"])
	var p_no := float(cnt["nothing"]) / tot
	var p_en := float(cnt["encounter"]) / tot
	var p_bo := float(cnt["boss"]) / tot
	fails += _true("밤 아무것도 ≈20%% (%.3f)" % p_no, absf(p_no - 0.2) < 0.02)
	fails += _true("밤 랜덤조우 ≈30%% (%.3f)" % p_en, absf(p_en - 0.3) < 0.02)
	fails += _true("밤 지역보스 ≈50%% (%.3f)" % p_bo, absf(p_bo - 0.5) < 0.02)
	# 밤에는 사전 이벤트(보물·상점·회복샘)가 붙지 않는다.
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
