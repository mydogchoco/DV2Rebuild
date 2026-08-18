extends Node

func _ready() -> void:
	_run()

var _snap_state: Dictionary = {}
var _snap_coin := 0
var _snap_unlock := false

func _run() -> void:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260804

	_snap_state = UserDB.get_pmeta(Colosseum.PMETA_KEY, {}).duplicate(true)
	_snap_coin = UserDB.item_count(Colosseum.coin_key())
	_snap_unlock = bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false))

	var tlist: Array = (Data.colosseum.get("tier", {}) as Dictionary).get("list", [])
	fails += _eq("티어 6단계", tlist.size(), 6)
	var prev_name := ""
	for t: Dictionary in tlist:
		var m := int(t.get("min_rating", 0))
		var nm := String(t.get("name", ""))
		fails += _eq("tier(%d)" % m, String(Colosseum.tier_of(m).get("name", "")), nm)
		if m > 0:
			fails += _eq("tier(%d)" % (m - 1),
				String(Colosseum.tier_of(m - 1).get("name", "")), prev_name)
		prev_name = nm
	fails += _eq("tier(99999)", String(Colosseum.tier_of(99999).get("name", "")), "MASTER")
	var band := Colosseum.tier_band()
	for i in range(2, tlist.size()):
		fails += _eq("갭 등간격(%d)" % i,
			int((tlist[i] as Dictionary)["min_rating"]) - int((tlist[i - 1] as Dictionary)["min_rating"]),
			band)
	fails += _eq("갭 = 원작 200 × 배수", band,
		200 * int((Data.colosseum.get("tier", {}) as Dictionary).get("gap_mult", 1)))

	var r_gold := int((tlist[2] as Dictionary)["min_rating"])
	var r_dia := int((tlist[4] as Dictionary)["min_rating"])
	var r_master := int((tlist[5] as Dictionary)["min_rating"])
	fails += _eq("frame.border(GOLD)", Colosseum.tier_frame(r_gold, "border"),
		"common/list_frame_gold.png")
	fails += _eq("frame.icon(MASTER)", Colosseum.tier_frame(r_master, "icon"),
		"common/tier_icon_master.png")
	fails += _eq("frame.icon(DIAMOND)→platinum", Colosseum.tier_frame(r_dia, "icon"),
		"common/tier_icon_platinum.png")
	fails += _eq("to_next(실버 직전)", Colosseum.to_next_tier(
		int((tlist[1] as Dictionary)["min_rating"]) - 1), 1)
	fails += _eq("to_next(MASTER)", Colosseum.to_next_tier(r_master), 0)

	var w0 := Colosseum.rating_delta(true, 0, 1000)
	var w5 := Colosseum.rating_delta(true, 5, 1000)
	var w99 := Colosseum.rating_delta(true, 99, 1000)
	fails += _b("연승이 승리 보상을 키운다", w5 > w0)
	fails += _b("연승 보너스에 상한이 있다", w99 <= w0 + 12)
	var lo_bronze := Colosseum.rating_delta(false, 0, 0)
	var lo_master := Colosseum.rating_delta(false, 0, r_master)
	fails += _b("패배는 음수", lo_bronze < 0 and lo_master < 0)
	fails += _b("상위 티어일수록 패배 손실이 크다", lo_master < lo_bronze)

	for t: Dictionary in tlist:
		var m := int(t.get("min_rating", 0))
		var p := Colosseum.rating_points(m)
		var w := int(p["win"])
		var l := int(p["lose"])
		fails += _b("%s 승리는 양수" % String(t["name"]), w > 0)
		fails += _b("%s 패배는 음수" % String(t["name"]), l < 0)
		match int(t.get("id", 0)):
			4:
				fails += _eq("DIAMOND 승패 ±0", -l, w)
			5:
				fails += _b("MASTER 패배 > 승리 (%d vs %d)" % [-l, w], -l > w)
				fails += _b("MASTER 패배가 '소폭'만 크다 (%d vs %d)" % [-l, w],
					-l <= int(round(float(w) * 1.25)))
			_:
				fails += _b("%s 는 승리가 더 크다 (%d vs %d)" % [String(t["name"]), w, -l], w > -l)
	for i in range(1, tlist.size()):
		var lo_hi := int(Colosseum.rating_points(
			int((tlist[i] as Dictionary)["min_rating"]))["lose"])
		var lo_lo := int(Colosseum.rating_points(
			int((tlist[i - 1] as Dictionary)["min_rating"]))["lose"])
		fails += _b("패배 손실 단조 증가(%d)" % i, lo_hi < lo_lo)
	fails += _b("MASTER 도 연승이면 오른다",
		Colosseum.rating_delta(true, 99, r_master)
			+ Colosseum.rating_delta(false, 0, r_master) > 0)

	if Data.dragons.is_empty():
		print("  ⚠️ dragons.json 비어 있음 — 봇 검증 건너뜀")
	else:
		var novice := Colosseum.make_bot("novice", "team", 1000, rng)
		fails += _eq("초급 파티 3", (novice["dragons"] as Array).size(), 3)
		fails += _b("초급 닉 있음", String(novice["nick"]) != "")
		for d: Dictionary in novice["dragons"]:
			fails += _eq("초급 레벨 50", int(d["level"]), 50)
			fails += _b("초급 미각성", not bool(d["awakened"]))
			fails += _eq("gain_log 길이", (d["gain_log"] as Array).size(), 49)

		var adept := Colosseum.make_bot("adept", "team", 2000, rng)
		for d: Dictionary in adept["dragons"]:
			fails += _b("중급 각성", bool(d["awakened"]))
			for e in Gem.slots(d["gems"]):
				var nm := String((e as Dictionary).get("name", ""))
				var cat := String(Data.gems["gems"].get(nm, {}).get("category", ""))
				fails += _b("중급 젬 분류(%s=%s)" % [nm, cat], cat == "hybrid" or cat == "soul")
				fails += _eq("중급 젬 최고티어(%s)" % nm, int((e as Dictionary).get("tier", -1)),
					Gem.max_tier(nm, Data.gems))
			for s in (d["equip"].get("slots", []) as Array):
				var g := int((s as Dictionary).get("grade", -1))
				fails += _b("중급 장비 등급 %d" % g, g >= 3 and g <= 4)
			for sk in (d["skills"] as Array):
				var lv := int((sk as Dictionary).get("level", 0))
				fails += _b("중급 스킬 레벨 %d" % lv, lv >= 4 and lv <= 5)

		for d: Dictionary in adept["dragons"]:
			fails += _b("봇 uid 격리", int(d["uid"]) >= Colosseum.BOT_UID_BASE)

		var sum := PartyStats.summary_of(adept["dragons"], false, "")
		fails += _eq("summary_of 3기", sum.size(), 3)
		for p: Dictionary in sum:
			fails += _b("HP>0 (%s)" % String(p.get("name", "")), int(p["hp_max"]) > 0)
			fails += _b("ATT>0", int((p["stats"] as Dictionary).get("att", 0)) > 0)
			fails += _b("속성 있음", String(p["element"]) != "")

		var n_sum := PartyStats.summary_of(novice["dragons"], false, "")
		var n_pow := _power(n_sum)
		var a_pow := _power(sum)
		fails += _b("중급 > 초급 (%d vs %d)" % [a_pow, n_pow], a_pow > n_pow)

		var cfg := _load(_data_file("combat.json"))
		var skills := _load(_data_file("skills.json"))
		var pa := _combatants(n_sum, "ally")
		var pb := _combatants(sum, "enemy")
		var res: Dictionary = Battle.simulate(pa, pb, rng, cfg, skills)
		fails += _b("승자 결정", String(res.get("winner", "")) != "")
		fails += _b("이벤트 발생", (res.get("events", []) as Array).size() > 0)

	if not Data.dragons.is_empty():
		var list := Colosseum.roll_opponents("team", rng)
		fails += _eq("상대 목록 크기", list.size(), int(Data.colosseum["bots"]["list_size"]))
		var nicks := {}
		for o: Dictionary in list:
			fails += _b("상대에 드래곤 있음", (o["dragons"] as Array).size() > 0)
			nicks[String(o["nick"])] = true
		fails += _eq("닉 중복 없음", nicks.size(), list.size())

		var mstate := Colosseum.state()
		mstate["guard_served"] = {}
		mstate["straight_single"] = 0
		mstate["straight_team"] = 0
		Colosseum.save_state(mstate)
		for mode in ["single", "team"]:
			var foe := Colosseum.roll_match(mode, rng)
			fails += _b("매칭 상대 1기 (%s)" % mode, not foe.is_empty())
			fails += _eq("매칭 파티 크기 (%s)" % mode, (foe["dragons"] as Array).size(),
				Colosseum.party_size(mode))
			fails += _b("매칭 상대 닉 (%s)" % mode, String(foe.get("nick", "")) != "")

		var board := Colosseum.ladder("team", false, rng)
		fails += _eq("보드 행수", board.size(), Colosseum.LADDER_SIZE)
		var desc := true
		for i in range(1, board.size()):
			if int(board[i]["rating"]) > int(board[i - 1]["rating"]):
				desc = false
		fails += _b("보드 내림차순", desc)
		var board2 := Colosseum.ladder("team", false, rng)
		fails += _eq("보드 고정", String(board2[0]["nick"]), String(board[0]["nick"]))
		var rank := Colosseum.my_rank("team", false)
		fails += _b("내 순위 1..N+1 (%d)" % rank, rank >= 1 and rank <= board.size() + 1)
		var wk := Colosseum.ladder("team", true, rng)
		fails += _eq("주간 보드 행수", wk.size(), Colosseum.LADDER_SIZE)

	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	var sched := [[0, ""], [24, ""], [25, "누리"], [49, "누리"], [50, "라온"], [74, "라온"],
				  [75, "누리"], [99, "누리"], [100, "라온"], [149, "라온"], [150, "라온"],
				  [998, "라온"], [999, "선대군"]]
	for c in sched:
		var g := Colosseum.guard_for(int(c[0]))
		fails += _eq("guard(%d연승)" % int(c[0]), String(g.get("name", "")), String(c[1]))
	fails += _eq("선대군 문턱(해금 뒤)", Colosseum.guard_streak_at(Colosseum.guard_for(999)), 999)
	fails += _eq("다음 방지봇까지(150연승·해금 뒤)", Colosseum.next_guard_in(150), 849)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var sched_first := [[150, "라온"], [332, "라온"], [333, "선대군"], [998, "선대군"],
						[999, "선대군"]]
	for c in sched_first:
		var gf := Colosseum.guard_for(int(c[0]))
		fails += _eq("guard(%d연승·해금 전)" % int(c[0]), String(gf.get("name", "")), String(c[1]))
	fails += _eq("선대군 문턱(해금 전)", Colosseum.guard_streak_at(Colosseum.guard_for(999)), 333)
	fails += _eq("다음 방지봇까지(150연승·해금 전)", Colosseum.next_guard_in(150), 183)
	fails += _eq("누리 문턱은 하나", Colosseum.guard_streak_at(Colosseum.guard_for(25)), 25)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, _snap_unlock)
	fails += _eq("25연승 대사단계", String(Colosseum.guard_for(25).get("talk_stage", "")), "A")
	fails += _eq("75연승 대사단계", String(Colosseum.guard_for(75).get("talk_stage", "")), "B")
	fails += _eq("150연승 대사단계", String(Colosseum.guard_for(150).get("talk_stage", "")), "C")
	fails += _b("누리A 원작 대사 실림", (Colosseum.guard_for(25).get("lines", []) as Array).size() > 0)
	fails += _b("라온C 원작 대사 실림", (Colosseum.guard_for(150).get("lines", []) as Array).size() > 0)
	fails += _eq("다음 방지봇까지(0연승)", Colosseum.next_guard_in(0), 25)

	var gsrc: Dictionary = Colosseum.guard_for(999)
	if not gsrc.is_empty() and not (gsrc.get("dragons", []) as Array).is_empty():
		var did := int((gsrc["dragons"][0] as Dictionary).get("id", 0))
		var r0 := RandomNumberGenerator.new()
		r0.seed = 20260804
		var r1 := RandomNumberGenerator.new()
		r1.seed = 20260804
		var plain := {"key": "t", "name": "평범", "rating": 1000, "talk_stage": "",
					  "dragons": [{"id": did, "level": 50, "awakened": true}]}
		var b0 := Colosseum.make_guard(plain, "single", r0)
		var s0: Dictionary = (PartyStats.summary_of(b0["dragons"], false, "")[0] as Dictionary)["stats"]
		var ovd := {"id": did, "level": 50, "awakened": true,
					"stats": {"hp": 12345, "att": 678, "cri": 42}, "grade": 9.5}
		var b1 := Colosseum.make_guard({"key": "t", "name": "임의", "rating": 1000,
			"talk_stage": "", "dragons": [ovd]}, "single", r1)
		var row1: Dictionary = PartyStats.summary_of(b1["dragons"], false, "")[0]
		var s1: Dictionary = row1["stats"]
		fails += _eq("임의 HP 최종값", int(s1.get("hp", 0)), 12345)
		fails += _eq("임의 공격 최종값", int(s1.get("att", 0)), 678)
		fails += _eq("임의 크리 최종값", int(s1.get("cri", 0)), 42)
		fails += _eq("임의 HP → hp_max", int(row1.get("hp_max", 0)), 12345)
		fails += _eq("임의 등급 표시", float(row1.get("grade", 0.0)), 9.5)
		fails += _eq("빈 칸은 계산대로(방어)", int(s1.get("def", 0)), int(s0.get("def", 0)))
		fails += _b("오버라이드 없으면 계산값 유지", int(s0.get("hp", 0)) != 12345)
	else:
		print("  SKIP 임의 스탯 검증 — colosseum_guard.csv 에 999연승 봇 드래곤이 없다")

	var gsv := Colosseum.state()
	gsv["guard_served"] = {}
	gsv["straight_team"] = 24
	Colosseum.save_state(gsv)
	fails += _b("24연승엔 안 나온다", not Colosseum.guard_active("team"))
	gsv["straight_team"] = 25
	Colosseum.save_state(gsv)
	fails += _b("25연승부터 나온다", Colosseum.guard_active("team"))
	fails += _eq("그 상대는 누리", String(Colosseum.pending_guard("team").get("name", "")), "누리")

	fails += _sheet_guard(50, "라온", 3)
	fails += _sheet_guard(25, "누리", 1)
	fails += _sheet_guard(999, "선대군", 3)

	var raon := Colosseum.make_guard(Colosseum.guard_for(50), "team", rng)
	if not (raon.get("dragons", []) as Array).is_empty():
		var d0: Dictionary = raon["dragons"][0]
		var rows := PartyStats.summary_of(raon["dragons"], false, "")
		var st0: Dictionary = (rows[0] as Dictionary)["stats"]
		fails += _eq("라온1 HP(시트 929)", int(st0.get("hp", 0)), 929)
		fails += _eq("라온1 방어(시트 266)", int(st0.get("def", 0)), 266)
		var ent := Gem.entries(d0.get("gems", {}))
		var filled := 0
		for e in ent:
			if e != null:
				filled += 1
		fails += _eq("라온1 젬 3칸", filled, 3)
		fails += _eq("라온1 젬1 이름", String((ent[0] as Dictionary).get("name", "")), "공격의 젬")
		fails += _eq("라온1 젬3 이름", String((ent[2] as Dictionary).get("name", "")), "체력의 젬")
		fails += _eq("라온1 스킬 수", (d0.get("skills", []) as Array).size(), 2)
		fails += _eq("라온1 스킬1", int((d0["skills"][0] as Dictionary).get("id", 0)), 11)
		fails += _eq("라온1 스킬2 레벨", int((d0["skills"][1] as Dictionary).get("level", 0)), 5)
		fails += _eq("라온1 장착 스킬칸", (d0.get("skill_equip", []) as Array), [11, 13])
		fails += _eq("라온1 장비 없음", (d0.get("equip", {}).get("slots", []) as Array).size(), 0)

	var sun := Colosseum.make_guard(Colosseum.guard_for(999), "team", rng)
	if not (sun.get("dragons", []) as Array).is_empty():
		var s0d: Dictionary = sun["dragons"][0]
		var ent2 := Gem.entries(s0d.get("gems", {}))
		fails += _eq("선대군1 젬 이름", String((ent2[0] as Dictionary).get("name", "")), "공격의 소울젬")
		fails += _eq("선대군1 젬 티어(최대)", int((ent2[0] as Dictionary).get("tier", -1)),
			Gem.max_tier("공격의 소울젬", Data.gems))
		var eslots: Array = s0d.get("equip", {}).get("slots", [])
		fails += _eq("선대군1 장비 4칸", eslots.size(), 4)
		var keys: Array = []
		for e in eslots:
			keys.append(String((e as Dictionary).get("key", "")))
		fails += _b("선대군1 전용장비 장착(한울의 불꽃)", keys.has("exclusive:한울의 불꽃"))
		var row0: Dictionary = PartyStats.summary_of(sun["dragons"], false, "")[0]
		fails += _eq("선대군1 등급 표시(시트 7)", float(row0.get("grade", 0.0)), 7.0)

	var nuri := Colosseum.make_guard(Colosseum.guard_for(25), "single", rng)
	if not (nuri.get("dragons", []) as Array).is_empty():
		var nrow: Dictionary = PartyStats.summary_of(nuri["dragons"], false, "")[0]
		var nst: Dictionary = nrow["stats"]
		fails += _eq("누리 방어(시트 30000)", int(nst.get("def", 0)), 30000)
		fails += _b("누리 크리 2.7 유지(소수)", absf(float(nst.get("cri", 0.0)) - 2.7) < 0.001)
		fails += _b("누리 HP 범위 15~40", int(nst.get("hp", 0)) >= 15 and int(nst.get("hp", 0)) <= 40)
		fails += _b("누리 공격 범위 250~300",
			int(nst.get("att", 0)) >= 250 and int(nst.get("att", 0)) <= 300)
		var foe := Battle.make_combatant("N", "enemy", String(nrow["element"]), nst)
		fails += _b("누리 관통 면역", bool(foe.get("immune_pure", false)))
		fails += _b("누리 추가피해 면역", bool(foe.get("immune_bonus", false)))
		fails += _b("누리 스킬 면역 30/13",
			(foe.get("skill_immune", []) as Array).has(30)
			and (foe.get("skill_immune", []) as Array).has(13))
		var hero := Battle.make_combatant("H", "ally", "fire",
			{"hp": 5000, "att": 500, "def": 300, "cri": 0, "evd": 0, "blk": 0, "pure": 200})
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 7
		var evs: Array = Battle._apply_skill_effect(hero, {"id": 30, "level": 5}, [hero], [foe],
			rng2, Data.combat, Data.skills)
		var dmg30 := 0
		for e: Dictionary in evs:
			dmg30 += int(e.get("damage", 0))
		fails += _eq("아수라일섬 면역 = 피해 0", dmg30, 0)
		fails += _b("면역 이벤트 표시", evs.size() > 0 and bool((evs[0] as Dictionary).get("immune", false)))
		var before := int(foe["hp"])
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = 9
		var na: Dictionary = Battle.resolve_attack(hero, foe, rng3, Data.combat, Data.skills)
		fails += _b("평타는 들어간다", int(na.get("damage", 0)) > 0 or bool(na.get("miss", false)))
		fails += _b("관통 면역 — 평타 피해가 관통(200)보다 작다", int(na.get("damage", 0)) < 200)
		foe["hp"] = before
		var rng4 := RandomNumberGenerator.new()
		rng4.seed = 11
		var mine: Array = []
		for i in 3:
			mine.append(Battle.make_combatant("A%d" % i, "ally", "fire",
				{"hp": 4000, "att": 600, "def": 400, "cri": 10, "evd": 10, "blk": 10}))
		var boss := Battle.make_combatant("N", "enemy", String(nrow["element"]), nst)
		var res: Dictionary = Battle.simulate(mine, [boss], rng4, Data.combat, Data.skills)
		fails += _b("누리전이 상한 안에서 끝난다(%d라운드)" % int(res.get("rounds", 0)),
			int(res.get("rounds", 0)) < 200 and String(res.get("winner", "")) != "")
		var nd: Dictionary = (nuri["dragons"][0] as Dictionary)
		var shown: Dictionary = StatusPanel.display_stats(nd)
		var stot: Dictionary = shown["total"]
		fails += _eq("상태창 방어 표기 = 전투값", int(stot.get("def", 0)), int(nst.get("def", 0)))
		fails += _eq("상태창 방어 표기(시트 30000)", int(stot.get("def", 0)), 30000)
		fails += _b("상태창 크리 표기 2.7 유지", absf(float(stot.get("cri", 0.0)) - 2.7) < 0.001)
		fails += _b("임의 스탯 칸은 분해 표기 생략", (shown["fixed"] as Array).has("def"))
		fails += _b("미지정 칸은 계산값 유지", (shown["fixed"] as Array).has("blk") == false)

	UserDB.begin_batch()
	var g999 := Colosseum.guard_for(999)
	fails += _b("선대군 최초 조우 대사가 있다", not (g999.get("lines_first", []) as Array).is_empty())
	fails += _b("선대군 반복 대사가 있다", not (g999.get("lines", []) as Array).is_empty())
	fails += _b("최초와 반복이 다르다", g999.get("lines_first", []) != g999.get("lines", []))
	fails += _eq("누리(25) 최초 전용 대사 없음",
		(Colosseum.guard_for(25).get("lines_first", []) as Array).size(), 0)
	fails += _b("누리(25) 원작 대사 실림",
		not (Colosseum.guard_for(25).get("lines", []) as Array).is_empty())

	for at: int in [25, 75]:
		var cast := {}
		var emos := {}
		for ln in (Colosseum.guard_for(at).get("lines", []) as Array):
			var d: Dictionary = ln
			cast[String(d.get("npc", ""))] = true
			emos[int(d.get("emotion", 0))] = true
			fails += _b("누리(%d) 줄에 화자 이름표" % at, String(d.get("name", "")) != "")
			fails += _b("누리(%d) 자리는 좌/우" % at, int(d.get("pos", 0)) in [1, 2])
			fails += _b("누리(%d) 초상 실재: %s" % [at, d.get("npc", "")],
				NpcPortrait.has_art(String(d.get("npc", ""))))
		fails += _b("누리(%d) 화자 2명(누리+즈믄)" % at, cast.has("nuri") and cast.has("jimon"))
		fails += _b("누리(%d) 표정이 한 종류가 아니다" % at, emos.size() > 1)
	for at: int in [50, 100, 150]:
		var cast2 := {}
		for ln in (Colosseum.guard_for(at).get("lines", []) as Array):
			var d: Dictionary = ln
			cast2[String(d.get("npc", ""))] = true
			fails += _b("라온(%d) 자리는 가운데" % at, int(d.get("pos", 0)) == 3)
		fails += _b("라온(%d) 혼자 말한다" % at, cast2.size() == 1 and cast2.has("raon"))
	var firsts_seen := {}
	for ln in (Colosseum.guard_for(25).get("lines", []) as Array):
		var d: Dictionary = ln
		var who := String(d.get("npc", ""))
		if bool(d.get("first_show", false)):
			fails += _b("누리A 등장 연출은 그 화자의 첫 줄뿐: %s" % who, not firsts_seen.has(who))
			firsts_seen[who] = true
	fails += _eq("누리A 등장 연출 2건(누리·즈믄)", firsts_seen.size(), 2)

	var st0 := Colosseum.state()
	st0["guard_met"] = {}
	Colosseum.save_state(st0)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var meet1 := Colosseum.make_guard(g999, "team", rng)
	fails += _b("첫 등장은 first_meet", bool(meet1.get("first_meet", false)))
	Colosseum.consume_guard("team", meet1)
	fails += _eq("조우 횟수 기록", Colosseum.met_count("sundaegun"), 1)
	fails += _b("이겨서 해금을 못 받았으면 다음에도 최초 대사",
		bool(Colosseum.make_guard(g999, "single", rng).get("first_meet", false)))
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	fails += _b("해금 뒤에는 3vs3 도 반복",
		not bool(Colosseum.make_guard(g999, "team", rng).get("first_meet", true)))
	fails += _b("해금 뒤에는 1vs1 도 반복(모드 통합)",
		not bool(Colosseum.make_guard(g999, "single", rng).get("first_meet", true)))
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var nuri1 := Colosseum.make_guard(Colosseum.guard_for(25), "team", rng)
	fails += _b("누리 첫 등장은 first_meet", bool(nuri1.get("first_meet", false)))
	Colosseum.consume_guard("team", nuri1)
	fails += _b("누리는 1vs1 에서도 반복(모드 통합)",
		not bool(Colosseum.make_guard(Colosseum.guard_for(25), "single", rng).get("first_meet", true)))
	var meet2 := Colosseum.make_guard(g999, "team", rng)

	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var r_win := Colosseum.apply_result("team", true, "선대군", meet2)
	fails += _b("이기면 안 열린다", not bool(r_win.get("unlocked", false))
		and not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)))
	var nuri_bot := Colosseum.make_guard(Colosseum.guard_for(25), "team", rng)
	var r_nuri := Colosseum.apply_result("team", false, "누리", nuri_bot)
	fails += _b("다른 방지봇에게 져도 안 열린다", not bool(r_nuri.get("unlocked", false))
		and not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)))
	var r_lose := Colosseum.apply_result("team", false, "선대군", meet2)
	fails += _b("선대군에게 지면 열린다", bool(r_lose.get("unlocked", false)))
	fails += _b("해금 플래그가 섰다", bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)))
	fails += _b("이미 열려 있으면 다시 알리지 않는다",
		not bool(Colosseum.apply_result("team", false, "선대군", meet2).get("unlocked", false)))
	var st1 := Colosseum.state()
	st1["straight_team"] = 998
	st1["guard_served"] = {}
	Colosseum.save_state(st1)
	Colosseum.apply_result("team", true, "봇")
	if UserDB.is_admin():
		fails += _b("관리자면 999연승에도 선대군이 안 나온다", not Colosseum.guard_active("team"))
		fails += _eq("관리자면 상대가 비어 있다",
			String(Colosseum.pending_guard("team").get("name", "")), "")
	else:
		fails += _b("999연승 달성 → 다음 판은 방지봇", Colosseum.guard_active("team"))
		fails += _eq("그 상대는 선대군",
			String(Colosseum.pending_guard("team").get("name", "")), "선대군")
		var sun_foe := Colosseum.make_guard(Colosseum.pending_guard("team"), "team", rng)
		Colosseum.consume_guard("team", sun_foe)
		Colosseum.apply_result("team", true, "선대군", sun_foe)
		fails += _b("선대군도 이기면 다시 안 나온다", not Colosseum.guard_active("team"))
		Colosseum.apply_result("team", false, "봇")
		var st_re := Colosseum.state()
		st_re["straight_team"] = 999
		Colosseum.save_state(st_re)
		fails += _eq("연승을 다시 쌓으면 또 만난다",
			String(Colosseum.pending_guard("team").get("name", "")), "선대군")
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)

	var stg := Colosseum.state()
	stg["straight_team"] = 24
	stg["guard_served"] = {}
	stg["guard_met"] = {}
	Colosseum.save_state(stg)
	var grng := RandomNumberGenerator.new()
	grng.seed = 20260806
	var guard_hits: Array = []
	for i in 10:
		var gfoe := Colosseum.roll_match("team", grng)
		Colosseum.consume_guard("team", gfoe)
		Colosseum.apply_result("team", true, String(gfoe.get("nick", "")), gfoe)
		if bool(gfoe.get("guard", false)):
			guard_hits.append(Colosseum.streak_of("team"))
	fails += _eq("25문턱 방지봇은 딱 한 판 (연승 %s)" % str(guard_hits), guard_hits.size(), 1)
	if guard_hits.size() == 1:
		fails += _eq("등장은 문턱 바로 다음 판", int(guard_hits[0]), 26)
	var stl := Colosseum.state()
	stl["straight_team"] = 24
	Colosseum.save_state(stl)
	Colosseum.apply_result("team", false, "봇")
	var st2 := Colosseum.state()
	st2["straight_team"] = 25
	Colosseum.save_state(st2)
	fails += _b("연승이 끊기면 같은 문턱을 다시 만난다", Colosseum.guard_active("team"))
	var st3 := Colosseum.state()
	st3["straight_single"] = 25
	st3["guard_served"] = {"team": [25]}
	Colosseum.save_state(st3)
	fails += _b("모드별로 따로 센다(1vs1 문턱 유지)", Colosseum.guard_active("single"))

	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var stf := Colosseum.state()
	stf["guard_served"] = {}
	stf["straight_team"] = 332
	Colosseum.save_state(stf)
	fails += _b("해금 전 332연승엔 선대군이 안 나온다",
		String(Colosseum.pending_guard("team").get("name", "")) != "선대군")
	stf = Colosseum.state()
	stf["straight_team"] = 333
	Colosseum.save_state(stf)
	if UserDB.is_admin():
		fails += _b("관리자면 333연승에도 안 나온다", not Colosseum.guard_active("team"))
	else:
		var sfoe := Colosseum.make_guard(Colosseum.pending_guard("team"), "team", rng)
		fails += _eq("해금 전 333연승에 선대군", String(sfoe.get("nick", "")), "선대군")
		fails += _eq("소진 기록은 333 문턱으로", int(sfoe.get("guard_at", 0)), 333)
		fails += _b("최초 조우 대사", bool(sfoe.get("first_meet", false)))
		Colosseum.consume_guard("team", sfoe)
		fails += _b("문턱당 1회는 그대로(같은 연승에서 다시 안 나온다)",
			not Colosseum.guard_active("team"))
		fails += _b("333에서 져도 해금은 열린다",
			bool(Colosseum.apply_result("team", false, "선대군", sfoe).get("unlocked", false)))
		var stg2 := Colosseum.state()
		stg2["guard_served"] = {}
		stg2["straight_team"] = 333
		Colosseum.save_state(stg2)
		fails += _eq("해금 뒤 333연승은 다시 라온(150) 담당",
			String(Colosseum.pending_guard("team").get("name", "")), "라온")
		stg2 = Colosseum.state()
		stg2["guard_served"] = {}
		stg2["straight_team"] = 999
		Colosseum.save_state(stg2)
		fails += _eq("해금 뒤에는 999연승에서 만난다",
			String(Colosseum.pending_guard("team").get("name", "")), "선대군")
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)

	var rankers: Array = Data.colosseum.get("rankers", [])
	fails += _b("랭커 풀이 실렸다", rankers.size() >= 1)
	if not rankers.is_empty():
		var seen_excl := false
		var seen_enh := false
		for rec: Dictionary in rankers:
			var who := String(rec.get("nick", ""))
			fails += _b("%s 드래곤이 있다" % who, not (rec.get("dragons", []) as Array).is_empty())
			for d: Dictionary in (rec.get("dragons", []) as Array):
				fails += _b("%s 드래곤 id 해석" % who, int(d.get("id", 0)) > 0
					and not Data.get_dragon(int(d.get("id", 0))).is_empty())
				for e: Dictionary in (d.get("equip", []) as Array):
					if String(e.get("key", "")).begins_with("exclusive:"):
						seen_excl = true
					if int(e.get("enhance", 0)) > 0:
						seen_enh = true
		fails += _b("전용장비 표기가 실제 전용 장비로 풀렸다", seen_excl)
		fails += _b("비고의 '최대 강화'가 횟수로 실렸다", seen_enh)

		var rk: Dictionary = Colosseum._make_ranker(rankers[0], "team", rng)
		var rd: Array = rk.get("dragons", [])
		fails += _eq("랭커 3vs3 = 3마리", rd.size(), 3)
		if not rd.is_empty():
			var d0: Dictionary = rd[0]
			fails += _eq("젬 3칸 장착", (d0.get("gems", {}).get("slots", []) as Array).size(), 3)
			fails += _eq("장비 4칸 장착", (d0.get("equip", {}).get("slots", []) as Array).size(), 4)
			fails += _eq("장착 스킬 2칸", (d0.get("skill_equip", []) as Array).size(), 2)
			var slot0: Dictionary = (d0["equip"]["slots"] as Array)[0]
			fails += _eq("희귀도 = 에픽(4)", int(slot0.get("grade", 0)), 4)
			fails += _eq("강화가 상한까지 굴려졌다", int(slot0.get("enhance", 0)),
				Equipment.enhance_limit(4, Data.equipment))
			var base_sum := 0
			for o: Dictionary in ((rankers[0]["dragons"][0] as Dictionary)["equip"][0]["options"] as Array):
				base_sum += int(o.get("value", 0))
			var now_sum := 0
			for o2: Dictionary in (slot0.get("options", []) as Array):
				now_sum += int(o2.get("value", 0))
			fails += _b("강화로 옵션 값이 커졌다(%d → %d)" % [base_sum, now_sum], now_sum > base_sum)
		var many := -1
		var many_d := -1
		for i in rankers.size():
			for j in ((rankers[i] as Dictionary).get("dragons", []) as Array).size():
				if (((rankers[i]["dragons"][j] as Dictionary).get("skills", []) as Array).size()
						> Loadout.SKILL_SLOTS):
					many = i
					many_d = j
					break
			if many >= 0:
				break
		if many >= 0:
			var pool := {}
			for s: Dictionary in ((rankers[many]["dragons"][many_d] as Dictionary)["skills"] as Array):
				pool[int(s.get("id", 0))] = true
			var want_id := int((rankers[many]["dragons"][many_d] as Dictionary).get("id", 0))
			var pairs := {}
			var bad := 0
			for _t in 40:
				for rd2: Dictionary in (Colosseum._make_ranker(rankers[many], "team", rng)
						.get("dragons", []) as Array):
					if int(rd2.get("id", 0)) != want_id:
						continue
					var eqs: Array = rd2.get("skill_equip", [])
					for sid in eqs:
						if int(sid) != 0 and not pool.has(int(sid)):
							bad += 1
					pairs[str(eqs)] = true
			fails += _eq("장착 스킬은 적어 둔 것 중에서만 나온다", bad, 0)
			fails += _b("2개 초과면 조합이 매번 같지 않다", pairs.size() > 1)

		var cap := int((Data.combat.get("judge", {}) as Dictionary).get("pure_cap", 0))
		fails += _eq("관통 상한이 데이터에 있다", cap, 100)
		var raw_pure := int(Equipment.apply({}, (rd[0] as Dictionary).get("equip", {}),
			Data.equipment).get("pure", 0))
		fails += _b("랭커 장비 관통 합이 상한을 넘는다(시험 전제 %d)" % raw_pure, raw_pure > cap)
		var cap_row: Dictionary = PartyStats.summary_of(rd, false, "")[0]
		fails += _eq("실 능력치의 관통은 상한까지만",
			int((cap_row["stats"] as Dictionary).get("pure", 0)), cap)

		fails += _eq("랭커 1vs1 = 1마리",
			(Colosseum._make_ranker(rankers[0], "single", rng).get("dragons", []) as Array).size(), 1)
		var big := -1
		for i in rankers.size():
			if ((rankers[i] as Dictionary).get("dragons", []) as Array).size() > 3:
				big = i
				break
		if big >= 0:
			var combos := {}
			for _t in 30:
				var ids: Array = []
				for d3: Dictionary in (Colosseum._make_ranker(rankers[big], "team", rng)
						.get("dragons", []) as Array):
					ids.append(int(d3.get("id", 0)))
				combos[str(ids)] = true
			fails += _b("4마리 명단은 조합이 갈린다", combos.size() > 1)
		var rparty := PartyStats.summary_of(rd, false, "")
		fails += _eq("랭커 파티 스탯 3", rparty.size(), 3)
		fails += _b("랭커 HP가 0이 아니다", int((rparty[0]["stats"] as Dictionary).get("hp", 0)) > 0)

	fails += _coin_and_shop()

	fails += _season_and_rankers(rng)

	fails += _restore_save()
	print("\n[test_colosseum] %s" % ("ALL PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _restore_save() -> int:
	var ck := Colosseum.coin_key()
	UserDB.set_pmeta(Colosseum.PMETA_KEY, _snap_state)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, _snap_unlock)
	var drift := UserDB.item_count(ck) - _snap_coin
	if drift > 0:
		UserDB.use_item(ck, drift)
	elif drift < 0:
		UserDB.add_item(ck, -drift)
	UserDB.save()
	var f := _eq("세이브 복원(주화)", UserDB.item_count(ck), _snap_coin)
	var disk := _load(SaveSystem.SAVE_PATH)
	var got: Dictionary = (disk.get("meta", {}) as Dictionary).get(Colosseum.PMETA_KEY, {})
	for k in _snap_state:
		f += _eq("세이브 복원(디스크) %s" % k,
			JSON.stringify(got.get(k)), JSON.stringify(_snap_state[k]))
	f += _eq("세이브 복원(디스크) 주화",
		int((disk.get("inventory", {}) as Dictionary).get(ck, 0)), _snap_coin)
	f += _eq("세이브 복원(디스크) 해금 플래그",
		bool((disk.get("meta", {}) as Dictionary).get(Summon.FLAG_UNLOCK, false)), _snap_unlock)
	return f

func _coin_and_shop() -> int:
	var f := 0
	var ck := Colosseum.coin_key()

	var cdef: Dictionary = Data.items.get(ck, {})
	f += _b("주화가 items.json 에 있다 (%s)" % ck, not cdef.is_empty())
	f += _eq("주화 category", String(cdef.get("category", "")), "currency")
	var cpath := Data.item_icon_path(ck)
	f += _b("주화 아이콘이 실제로 로드된다 (%s)" % cpath,
		cpath != "" and ResourceLoader.exists(cpath))

	var wk: Dictionary = (Data.colosseum.get("coin", {}) as Dictionary).get("season", {})
	f += _b("시즌 보상표가 비어 있지 않다", not wk.is_empty())
	for tid in wk:
		var r: Dictionary = wk[tid]
		f += _eq("환율 티어%s coin=dia×10" % tid, int(r.get("coin", 0)), int(r.get("dia", 0)) * 10)

	var w0 := Colosseum.match_coin("single", true, 0)
	var w5 := Colosseum.match_coin("single", true, 5)
	var w99 := Colosseum.match_coin("single", true, 99)
	var lo := Colosseum.match_coin("single", false, 0)
	f += _b("승리 > 패배", w0 > lo)
	f += _b("패배도 0보다 크다", lo > 0)
	f += _b("연승이 판당 주화를 키운다", w5 > w0)
	f += _b("연승 보너스에 상한이 있다", w99 == w0 + 10)
	f += _eq("3vs3 는 2배", Colosseum.match_coin("team", true, 0), w0 * 2)

	var silver := int(((Data.colosseum.get("tier", {}).get("list", []) as Array)[1]
		as Dictionary).get("min_rating", 1200))
	var s := Colosseum.state()
	s["single"] = silver - 1
	s["straight_single"] = 0
	s["tier_paid"] = []
	Colosseum.save_state(s)
	var before_coin := UserDB.item_count(ck)
	var r1 := Colosseum.apply_result("single", true)
	var bonus := int((Data.colosseum.get("coin", {}).get("tier_up", {}) as Dictionary).get("1", 0))
	f += _b("승급 판정", bool(r1.get("tier_up", false)))
	f += _eq("승급 보너스가 붙었다", int(r1.get("coin_tier_bonus", 0)), bonus)
	f += _eq("실지급 = 판당 + 보너스",
		UserDB.item_count(ck) - before_coin,
		int(r1.get("coin", 0)) + int(r1.get("coin_tier_bonus", 0)))
	var s2 := Colosseum.state()
	s2["single"] = silver - 1
	Colosseum.save_state(s2)
	var r2 := Colosseum.apply_result("single", true)
	f += _eq("같은 티어 승급 보너스는 1회뿐", int(r2.get("coin_tier_bonus", 0)), 0)

	var ek_s: String = Colosseum.energy_keys("single")[0]
	var ek_t: String = Colosseum.energy_keys("team")[0]
	var s3 := Colosseum.state()
	s3[ek_s] = Colosseum.ticket_max() - 1
	s3[ek_t] = Colosseum.ticket_max() - 1
	s3[Colosseum.energy_keys("single")[1]] = int(Time.get_unix_time_from_system())
	s3[Colosseum.energy_keys("team")[1]] = int(Time.get_unix_time_from_system())
	Colosseum.save_state(s3)
	var add1: Dictionary = Colosseum.add_ticket(1)
	f += _eq("두 모드 모두 1 회복", add1.size(), 2)
	f += _eq("1vs1 이 1 찼다", int(add1.get("single", 0)), 1)
	f += _eq("만땅이면 아무 데도 안 찬다", Colosseum.add_ticket(1).size(), 0)
	f += _eq("상한을 넘지 않는다", Colosseum.ticket_of("single"), Colosseum.ticket_max())

	f += _b("1vs1 소모 성공", Colosseum.spend_ticket("single"))
	f += _eq("1vs1 만 줄었다", Colosseum.ticket_of("single"), Colosseum.ticket_max() - 1)
	f += _eq("3vs3 은 그대로", Colosseum.ticket_of("team"), Colosseum.ticket_max())

	f += _eq("회복 주기 600초", int(Data.colosseum.get("ticket", {}).get("recover_seconds", 0)), 600)
	var now := int(Time.get_unix_time_from_system())
	var s4 := Colosseum.state()
	s4[ek_s] = 0
	s4[Colosseum.energy_keys("single")[1]] = now - 600 * 3 - 10
	Colosseum.save_state(s4)
	var rec := Colosseum.refresh_ticket("single", now)
	f += _eq("30분 → 3개 회복", int(rec.get(ek_s, 0)), 3)
	f += _eq("남은 10초는 다음 회복에 이월",
		int(rec.get(Colosseum.energy_keys("single")[1], 0)), now - 10)

	var s_old := Colosseum.state()
	s_old.erase(ek_s); s_old.erase(ek_t)
	s_old.erase(Colosseum.energy_keys("single")[1])
	s_old.erase(Colosseum.energy_keys("team")[1])
	s_old["energy"] = 4
	s_old["energy_at"] = now
	Colosseum.save_state(s_old)
	var mig_energy := Colosseum.state()
	f += _eq("옛 공유값이 1vs1 로", int(mig_energy.get(ek_s, -1)), 4)
	f += _eq("옛 공유값이 3vs3 로", int(mig_energy.get(ek_t, -1)), 4)
	f += _b("옛 키는 걷힌다", not mig_energy.has("energy"))

	var cost := Colosseum.refill_cost()
	f += _b("충전가가 있다", cost > 0)
	var dia0 := UserDB.diamond()
	var s5 := Colosseum.state()
	s5[ek_s] = 0
	s5[Colosseum.energy_keys("single")[1]] = now
	Colosseum.save_state(s5)
	UserDB.add_currency("diamond", (cost - 1) - dia0)
	var poor := Colosseum.buy_refill("single")
	f += _eq("부족하면 거절", String(poor.get("reason", "")), "money")
	f += _eq("거절이면 피로도 그대로", Colosseum.ticket_of("single"), 0)
	f += _eq("거절이면 다이아 그대로", UserDB.diamond(), cost - 1)
	UserDB.add_currency("diamond", 1)
	var ok := Colosseum.buy_refill("single")
	f += _b("충전 성공", bool(ok.get("ok", false)))
	f += _eq("가득 채운다", Colosseum.ticket_of("single"), Colosseum.ticket_max())
	f += _eq("채운 칸 수", int(ok.get("filled", 0)), Colosseum.ticket_max())
	f += _eq("값을 치렀다", UserDB.diamond(), 0)
	UserDB.add_currency("diamond", cost)
	var full := Colosseum.buy_refill("single")
	f += _eq("만땅이면 거절", String(full.get("reason", "")), "full")
	f += _eq("만땅이면 값도 안 받는다", UserDB.diamond(), cost)
	UserDB.add_currency("diamond", dia0 - UserDB.diamond())

	var gm := int((Data.colosseum.get("tier", {}) as Dictionary).get("gap_mult", 1))
	var gb := int((Data.colosseum.get("tier", {}) as Dictionary).get("gap_base", 1000))
	var s6 := Colosseum.state()
	s6["single"] = gb + 800
	s6["tournament"] = gb
	s6.erase("rating_gap_mult")
	Colosseum.save_state(s6)
	var mig := Colosseum.state()
	f += _eq("환산 후 배수 기록", int(mig.get("rating_gap_mult", 0)), gm)
	f += _eq("환산값 = 기준점 + 거리×배수", int(mig.get("single", 0)), gb + 800 * gm)
	f += _eq("기준점은 그대로", int(mig.get("tournament", 0)), gb)
	f += _eq("티어 유지(DIAMOND)", String(Colosseum.tier_of(int(mig.get("single", 0)))
		.get("name", "")), "DIAMOND")
	f += _b("옛 사다리는 버린다", (mig.get("pvp_total_rank", {}) as Dictionary).is_empty())

	var pvp: Dictionary = {}
	for t: Dictionary in Data.shop.get("tabs", []):
		if String(t.get("id", "")) == "pvp":
			pvp = t
	f += _b("상점에 PVP 탭이 있다", not pvp.is_empty())
	if pvp.is_empty():
		return f
	f += _eq("PVP 지갑", String(pvp.get("wallet", "")), "pvp")
	f += _eq("PVP NPC = 라온", String(pvp.get("npc", "")), "raon")
	var stock: Array = pvp.get("stock", [])
	f += _b("진열 품목이 있다", stock.size() > 0)
	for e: Dictionary in stock:
		var k := String(e.get("item", ""))
		var idef: Dictionary = Data.items.get(k, {})
		f += _b("PVP 품목 %s 가 items.json 에 있다" % k, not idef.is_empty())
		f += _eq("PVP 품목 %s offline" % k, String(idef.get("offline", "")), "impl")
		f += _eq("PVP 품목 %s 는 주화로 산다" % k, String(e.get("cur", "")), ck)
		f += _b("PVP 품목 %s 가격 > 0" % k, int(e.get("price", 0)) > 0)
		var ip := Data.item_icon_path(k)
		f += _b("PVP 품목 %s 아이콘 로드" % k, ip != "" and ResourceLoader.exists(ip))
	var ikey := String(pvp.get("icon", ""))
	f += _b("PVP 탭 아이콘 존재 (%s)" % ikey,
		ResourceLoader.exists("res://assets/converted/%s.tres" % ikey))
	f += _b("PVP 탭 배경 존재 (%s)" % String(pvp.get("tab_bg", "")),
		ResourceLoader.exists("res://assets/converted/common_ui/common_%s.tres"
			% String(pvp.get("tab_bg", ""))))
	return f

func _sheet_guard(streak: int, name: String, dragons: int) -> int:
	var g := Colosseum.guard_for(streak)
	var f := _eq("시트 %d연승 = %s" % [streak, name], String(g.get("name", "")), name)
	f += _eq("%s 드래곤 수" % name, (g.get("dragons", []) as Array).size(), dragons)
	return f

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

func _season_and_rankers(rng: RandomNumberGenerator) -> int:
	var f := 0
	var cfg: Dictionary = Data.colosseum.get("season", {})

	f += _eq("시즌 주기 21일", int(cfg.get("days", 0)), 21)
	f += _eq("season_days()", Colosseum.season_days(), 21)
	var span := 21 * 86400
	f += _eq("season_span()", Colosseum.season_span(), span)
	var left := Colosseum.season_left_sec()
	f += _b("남은 시간이 0 < left ≤ 주기 (%d)" % left, left > 0 and left <= span)
	var now := int(Time.get_unix_time_from_system())
	f += _eq("남은 시간 = 앵커 + 주기 − 지금", left,
		Colosseum.season_start() + span - now)
	f += _eq("시즌 번호 = 에폭 격자", Colosseum.season_index(), int(now / 86400 / 21))

	var dia0 := UserDB.currency("diamond")
	var coin0 := UserDB.item_count(Colosseum.coin_key())

	var seed_state := Colosseum.state()
	seed_state.erase("season_start")
	seed_state["reward_week"] = 0
	seed_state["reward_season"] = 0
	seed_state["tournament"] = 4321
	seed_state["straight_team"] = 7
	Colosseum.save_state(seed_state)
	var got: Array = Colosseum.claim_rewards()
	var after_seed := Colosseum.state()
	f += _b("앵커가 없으면 시즌 보상을 주지 않는다", _kinds(got).find("season") < 0)
	f += _eq("심기만 한다 — 레이팅 유지", int(after_seed.get("tournament", 0)), 4321)
	f += _eq("심기만 한다 — 연승 유지", int(after_seed.get("straight_team", 0)), 7)
	f += _eq("앵커가 격자 경계로 심겼다", int(after_seed.get("season_start", -1)),
		Colosseum.season_index() * span)
	f += _b("주간 시절 키는 지운다", not after_seed.has("reward_week"))
	f += _b("격자 인덱스 시절 키도 지운다", not after_seed.has("reward_season"))

	var st := Colosseum.state()
	st["season_start"] = now - span - 100
	st["reward_day"] = _today_idx()
	st["tournament"] = 4321
	st["single"] = 2500
	st["straight_team"] = 7
	st["straight_team_best"] = 9
	st["guard_served"] = {"team": [25]}
	st["tier_paid"] = [1, 2, 3]
	Colosseum.save_state(st)
	var tier_before := Colosseum.tier_of(4321)
	var want: Dictionary = ((Data.colosseum.get("coin", {}) as Dictionary).get("season", {}) as Dictionary) \
		.get(str(int(tier_before.get("id", 0))), {})
	var dia1 := UserDB.currency("diamond")
	var coin1 := UserDB.item_count(Colosseum.coin_key())
	var rows: Array = Colosseum.claim_rewards()
	var srow := {}
	for r: Dictionary in rows:
		if String(r.get("kind", "")) == "season":
			srow = r
	var end := Colosseum.state()
	var start := int((Data.colosseum.get("rating", {}) as Dictionary).get("start", 1000))
	f += _b("시즌 교체 시 시즌 보상이 나온다", not srow.is_empty())
	f += _eq("보상은 끝난 시즌의 티어로", String((srow.get("tier", {}) as Dictionary).get("name", "")),
		String(tier_before.get("name", "")))
	f += _eq("시즌 보상 다이아", int(srow.get("dia", 0)), int(want.get("dia", -1)))
	f += _eq("시즌 보상 주화", int(srow.get("coin", 0)), int(want.get("coin", -1)))
	var paid_dia := 0
	var paid_coin := 0
	for r: Dictionary in rows:
		paid_dia += int(r.get("dia", 0))
		paid_coin += int(r.get("coin", 0))
	f += _eq("다이아가 실제로 들어왔다", UserDB.currency("diamond"), dia1 + paid_dia)
	f += _eq("주화가 실제로 들어왔다", UserDB.item_count(Colosseum.coin_key()), coin1 + paid_coin)
	f += _eq("레이팅 강등(3vs3, 두 티어 아래)", int(end.get("tournament", -1)), 2000)
	f += _eq("레이팅 강등(1vs1, 바닥은 시작점)", int(end.get("single", -1)), start)
	f += _eq("티어도 따라 내려간다", String(Colosseum.tier_of(int(end.get("tournament", 0))).get("name", "")),
		"SILVER")
	f += _eq("강등 계산(다이아 → 골드)", Colosseum.demoted_rating(5500), 3000)
	f += _eq("강등 계산(브론즈는 제자리)", Colosseum.demoted_rating(1400), start)
	f += _eq("연승 초기화", int(end.get("straight_team", -1)), 0)
	f += _eq("최고 연승 초기화", int(end.get("straight_team_best", -1)), 0)
	f += _eq("방지봇 문턱 이력 초기화", (end.get("guard_served", {}) as Dictionary).size(), 0)
	f += _eq("앵커가 지난 경계로", int(end.get("season_start", -1)), now - 100)
	f += _eq("tier_paid 는 남는다", JSON.stringify(end.get("tier_paid", [])), JSON.stringify([1, 2, 3]))
	var again: Array = Colosseum.claim_rewards()
	f += _b("같은 시즌에 두 번 주지 않는다", _kinds(again).find("season") < 0)
	var skip := Colosseum.state()
	skip["season_start"] = now - span * 3 - 50
	skip["reward_day"] = _today_idx()
	Colosseum.save_state(skip)
	var many: Array = Colosseum.claim_rewards()
	var n_season := 0
	for r: Dictionary in many:
		if String(r.get("kind", "")) == "season":
			n_season += 1
	f += _eq("3주기를 건너뛰어도 보상 1회", n_season, 1)
	f += _eq("앵커는 마지막 경계로", int(Colosseum.state().get("season_start", -1)), now - 50)

	f += _eq("즉시 종료 비용", Colosseum.season_reset_cost(), 300)
	var st2 := Colosseum.state()
	st2["season_start"] = now - 3600
	st2["reward_day"] = _today_idx()
	st2["tournament"] = 4321
	st2["straight_team"] = 5
	st2["straight_team_best"] = 5
	Colosseum.save_state(st2)
	var keep_dia := UserDB.currency("diamond")
	UserDB.add_currency("diamond", -keep_dia)
	var poor := Colosseum.buy_season_reset()
	f += _b("다이아 부족 → 실패", not bool(poor.get("ok", false)))
	f += _eq("실패 이유", String(poor.get("reason", "")), "money")
	f += _eq("실패면 레이팅 그대로", int(Colosseum.state().get("tournament", 0)), 4321)
	f += _eq("실패면 앵커 그대로", int(Colosseum.state().get("season_start", 0)), now - 3600)
	UserDB.add_currency("diamond", 1000)
	var bought := Colosseum.buy_season_reset()
	var st3 := Colosseum.state()
	f += _b("즉시 종료 성공", bool(bought.get("ok", false)))
	f += _eq("즉시 종료 보상 = 그 티어 표", int(bought.get("dia", 0)), int(want.get("dia", -1)))
	f += _eq("비용을 뺀 다이아", UserDB.currency("diamond"),
		1000 - 300 + int(want.get("dia", 0)))
	f += _eq("즉시 종료 후 레이팅 강등", int(st3.get("tournament", -1)), 2000)
	f += _eq("즉시 종료 후 연승 초기화", int(st3.get("straight_team", -1)), 0)
	f += _b("시즌 시계가 다시 시작됐다(남은 시간 ≈ 주기)",
		Colosseum.season_left_sec() > span - 60)
	var top_dia := int((((Data.colosseum.get("coin", {}) as Dictionary).get("season", {}) as Dictionary)
		.get("5", {}) as Dictionary).get("dia", 0))
	f += _b("최고 티어 보상(%d) < 비용(300)" % top_dia, top_dia < Colosseum.season_reset_cost())

	UserDB.add_currency("diamond", dia0 - UserDB.currency("diamond"))

	var rankers: Array = Data.colosseum.get("rankers", [])
	f += _b("랭커 시트가 비어 있지 않다", not rankers.is_empty())
	var seen := {}
	var prev := 1 << 30
	for r: Dictionary in rankers:
		var rt := int(r.get("rating", 0))
		f += _eq("랭커 %s 티어" % r.get("nick", "?"),
			String(Colosseum.tier_of(rt).get("name", "")), "MASTER")
		f += _b("랭커 %s 점수 내림차순(%d)" % [r.get("nick", "?"), rt], rt < prev)
		f += _b("랭커 %s 점수 중복 없음" % r.get("nick", "?"), not seen.has(rt))
		seen[rt] = true
		prev = rt
		f += _eq("랭커 %s 상대 점수 = 보드 점수" % r.get("nick", "?"),
			int(Colosseum._make_ranker(r, "team", rng).get("rating", 0)), rt)
	var board: Array = Colosseum._gen_ladder("team", false, rng)
	for i in rankers.size():
		f += _eq("보드 %d위 = 랭커 시트 %d번" % [i + 1, i],
			String((board[i] as Dictionary).get("nick", "")),
			String((rankers[i] as Dictionary).get("nick", "")))
	var master_min := int((((Data.colosseum.get("tier", {}) as Dictionary).get("list", []) as Array)[5]
		as Dictionary).get("min_rating", 0))
	for i in range(rankers.size(), board.size()):
		f += _b("채움 봇 %d 는 마스터 미만" % i,
			int((board[i] as Dictionary).get("rating", 0)) < master_min)
	print("[test_colosseum] §8 시즌 #%d · 남은 %d일 · 랭커 %d명 마스터 고정(%d~%d)"
		% [Colosseum.season_index(), left / 86400, rankers.size(),
		   int((rankers[rankers.size() - 1] as Dictionary).get("rating", 0)),
		   int((rankers[0] as Dictionary).get("rating", 0))])
	return f

func _kinds(rows: Array) -> Array:
	var out: Array = []
	for r: Dictionary in rows:
		out.append(String(r.get("kind", "")))
	return out

func _today_idx() -> int:
	return int(Time.get_unix_time_from_system() / 86400)

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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
