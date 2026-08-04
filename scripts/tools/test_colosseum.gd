extends Node
## 헤드리스 콜로세움 로직 테스트 (§8 — logic 은 화면 없이 검증).
##
## 검증 대상 = `scripts/systems/colosseum.gd`.
## 원작 근거: 티어 경계 `StrategyManager::GetTier` @0170f130 (docs/ref/porting/Colosseum.md §3).
##
## ⚠️ `--script` 모드로는 못 돌린다 — 그 모드엔 오토로드가 없어 `Data`/`UserDB` 가 미해결이다.
## **임시 오토로드**로 부팅 경로에 태운다(전용 러너가 등록·해제까지 한다):
##     python scripts/tools/run_test_colosseum.py

func _ready() -> void:
	_run()


func _run() -> void:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260804

	# ── 1. 티어 경계 — 원작 하드코딩과 1:1 -------------------------------------
	# GetTier: <1200→BRONZE · <1500→SILVER · <1900→GOLD · <2300→PLATINUM · 이상→MASTER
	var cases := [
		[0, "BRONZE"], [1199, "BRONZE"], [1200, "SILVER"], [1499, "SILVER"],
		[1500, "GOLD"], [1899, "GOLD"], [1900, "PLATINUM"], [2299, "PLATINUM"],
		[2300, "MASTER"], [99999, "MASTER"],
	]
	for c in cases:
		var t := Colosseum.tier_of(int(c[0]))
		fails += _eq("tier(%d)" % int(c[0]), String(t.get("name", "")), String(c[1]))

	# 티어 프레임 경로 — 보유 프레임만 가리켜야 한다(diamond 는 없다).
	fails += _eq("frame.border(1500)", Colosseum.tier_frame(1500, "border"),
		"common/list_frame_gold.png")
	fails += _eq("frame.icon(2300)", Colosseum.tier_frame(2300, "icon"),
		"common/tier_icon_master.png")
	fails += _eq("to_next(1199)", Colosseum.to_next_tier(1199), 1)
	fails += _eq("to_next(2300)", Colosseum.to_next_tier(2300), 0)

	# ── 2. 레이팅 증감 ---------------------------------------------------------
	var w0 := Colosseum.rating_delta(true, 0, 1000)
	var w5 := Colosseum.rating_delta(true, 5, 1000)
	var w99 := Colosseum.rating_delta(true, 99, 1000)
	fails += _b("연승이 승리 보상을 키운다", w5 > w0)
	fails += _b("연승 보너스에 상한이 있다", w99 <= w0 + 12)
	var lo_bronze := Colosseum.rating_delta(false, 0, 500)
	var lo_master := Colosseum.rating_delta(false, 0, 2400)
	fails += _b("패배는 음수", lo_bronze < 0 and lo_master < 0)
	fails += _b("상위 티어일수록 패배 손실이 크다", lo_master < lo_bronze)

	# ── 3. 봇 생성 — 분류별 규칙 -----------------------------------------------
	if Data.dragons.is_empty():
		print("  ⚠️ dragons.json 비어 있음 — 봇 검증 건너뜀")
	else:
		var novice := Colosseum.make_bot("novice", "team", 1000, rng)
		fails += _eq("초급 파티 3", (novice["dragons"] as Array).size(), 3)
		fails += _b("초급 닉 있음", String(novice["nick"]) != "")
		for d: Dictionary in novice["dragons"]:
			fails += _eq("초급 레벨 50", int(d["level"]), 50)
			fails += _b("초급 미각성", not bool(d["awakened"]))
			# 불변식: gain_log 길이 == level-1 (UserDB 와 같은 규칙)
			fails += _eq("gain_log 길이", (d["gain_log"] as Array).size(), 49)

		var adept := Colosseum.make_bot("adept", "team", 2000, rng)
		for d: Dictionary in adept["dragons"]:
			fails += _b("중급 각성", bool(d["awakened"]))
			# 혼성젬 또는 소울젬만, 그리고 최고 티어여야 한다.
			for e in Gem.slots(d["gems"]):
				var nm := String((e as Dictionary).get("name", ""))
				var cat := String(Data.gems["gems"].get(nm, {}).get("category", ""))
				fails += _b("중급 젬 분류(%s=%s)" % [nm, cat], cat == "hybrid" or cat == "soul")
				fails += _eq("중급 젬 최고티어(%s)" % nm, int((e as Dictionary).get("tier", -1)),
					Gem.max_tier(nm, Data.gems))
			# 장비 등급 유니크(3)~에픽(4)
			for s in (d["equip"].get("slots", []) as Array):
				var g := int((s as Dictionary).get("grade", -1))
				fails += _b("중급 장비 등급 %d" % g, g >= 3 and g <= 4)
			# 스킬 4~5레벨
			for sk in (d["skills"] as Array):
				var lv := int((sk as Dictionary).get("level", 0))
				fails += _b("중급 스킬 레벨 %d" % lv, lv >= 4 and lv <= 5)

		# 봇 uid 는 UserDB 와 겹치면 안 된다.
		for d: Dictionary in adept["dragons"]:
			fails += _b("봇 uid 격리", int(d["uid"]) >= Colosseum.BOT_UID_BASE)

		# ── 4. 봇이 플레이어와 **같은 경로**로 스탯을 받는가 --------------------
		var sum := PartyStats.summary_of(adept["dragons"], false, "")
		fails += _eq("summary_of 3기", sum.size(), 3)
		for p: Dictionary in sum:
			fails += _b("HP>0 (%s)" % String(p.get("name", "")), int(p["hp_max"]) > 0)
			fails += _b("ATT>0", int((p["stats"] as Dictionary).get("att", 0)) > 0)
			fails += _b("속성 있음", String(p["element"]) != "")

		# ── 5. 중급이 초급보다 세다(구성 규칙이 실제로 먹히는지) ----------------
		var n_sum := PartyStats.summary_of(novice["dragons"], false, "")
		var n_pow := _power(n_sum)
		var a_pow := _power(sum)
		fails += _b("중급 > 초급 (%d vs %d)" % [a_pow, n_pow], a_pow > n_pow)

		# ── 6. 봇 vs 봇 전투가 실제로 끝나는가 ---------------------------------
		var cfg := _load("res://data/combat.json")
		var skills := _load("res://data/skills.json")
		var pa := _combatants(n_sum, "ally")
		var pb := _combatants(sum, "enemy")
		var res: Dictionary = Battle.simulate(pa, pb, rng, cfg, skills)
		fails += _b("승자 결정", String(res.get("winner", "")) != "")
		fails += _b("이벤트 발생", (res.get("events", []) as Array).size() > 0)

	# ── 7. 상대 목록 ------------------------------------------------------------
	if not Data.dragons.is_empty():
		var list := Colosseum.roll_opponents("team", rng)
		fails += _eq("상대 목록 크기", list.size(), int(Data.colosseum["bots"]["list_size"]))
		var nicks := {}
		for o: Dictionary in list:
			fails += _b("상대에 드래곤 있음", (o["dragons"] as Array).size() > 0)
			nicks[String(o["nick"])] = true
		fails += _eq("닉 중복 없음", nicks.size(), list.size())

	print("\n[test_colosseum] %s" % ("ALL PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _power(party: Array) -> int:
	var t := 0
	for p: Dictionary in party:
		var st: Dictionary = p["stats"]
		t += int(st.get("hp", 0)) + int(st.get("att", 0)) * 10 + int(st.get("def", 0)) * 10
	return t


func _combatants(party: Array, side: String) -> Array:
	var out: Array = []
	for i in party.size():
		var p: Dictionary = party[i]
		out.append(Battle.make_combatant("%s%d" % [side.substr(0, 1).to_upper(), i],
			side, String(p["element"]), p["stats"]))
	return out


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}


func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1


func _b(label: String, ok: bool) -> int:
	if ok:
		return 0
	print("  FAIL %s" % label)
	return 1
