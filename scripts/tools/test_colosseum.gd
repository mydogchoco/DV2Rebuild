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


# 🔴 2026-08-06 — 이 테스트는 **실제 세이브를 건드린다.** `apply_result` 를 여러 번 부르므로
#   레이팅·연승·guard_left·전적이 실제로 바뀌고, 2026-08-06 부터는 **주화까지 지급**된다
#   (실제로 한 번 새 나갔다: MASTER 승급 보너스 500주화가 사용자 세이브에 들어갔다).
#   그래서 검증 전체를 스냅샷/복원으로 감싼다. 아래 두 값이 그 스냅샷이다.
var _snap_state: Dictionary = {}
var _snap_coin := 0


func _run() -> void:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260804

	_snap_state = UserDB.get_pmeta(Colosseum.PMETA_KEY, {}).duplicate(true)
	_snap_coin = UserDB.item_count(Colosseum.coin_key())

	# ── 1. 티어 경계 — 원작 하드코딩과 1:1 -------------------------------------
	# 🔴 정정 2026-08-04 — 경계는 stringsData_KR.xml `Colosseum_Rating_0~5` 가 정본이다:
	#   1200 미만 / 1200↑ / 1400↑ / 1600↑ / 1800↑ / 2000↑ (6단계 · 200점 등간격).
	#   종전에 쓰던 StrategyManager::GetTier(1200/1500/1900/2300)는 **시즌 시스템**이었다.
	var cases := [
		[0, "BRONZE"], [1199, "BRONZE"], [1200, "SILVER"], [1399, "SILVER"],
		[1400, "GOLD"], [1599, "GOLD"], [1600, "PLATINUM"], [1799, "PLATINUM"],
		[1800, "DIAMOND"], [1999, "DIAMOND"], [2000, "MASTER"], [99999, "MASTER"],
	]
	for c in cases:
		var t := Colosseum.tier_of(int(c[0]))
		fails += _eq("tier(%d)" % int(c[0]), String(t.get("name", "")), String(c[1]))

	# 티어 프레임 경로 — 보유 프레임만 가리켜야 한다(diamond 는 없다).
	fails += _eq("frame.border(1400)", Colosseum.tier_frame(1400, "border"),
		"common/list_frame_gold.png")
	fails += _eq("frame.icon(2000)", Colosseum.tier_frame(2000, "icon"),
		"common/tier_icon_master.png")
	# DIAMOND 는 아이콘이 미보유 → platinum 으로 대체돼야 한다(티어 자체는 살아 있다).
	fails += _eq("frame.icon(1800)=diamond→platinum", Colosseum.tier_frame(1800, "icon"),
		"common/tier_icon_platinum.png")
	fails += _eq("to_next(1199)", Colosseum.to_next_tier(1199), 1)
	fails += _eq("to_next(2000)", Colosseum.to_next_tier(2000), 0)

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

		# ── 7-b. 랜덤 매칭 — 구판 흐름(시작 버튼 → 덱 선택 → 상대 1기 배정) ──────
		# 근거: `__ColosseumScene::onClickedColosseum1vs1/3vs3` 에 후보 목록이 없다.
		#
		# ⚠️ 여기는 **일반 봇 경로**를 본다 → 연승과 문턱 기록을 눕히고 들어간다.
		#    실제 세이브가 연승 중이면 roll_match 가 연승방지봇을 돌려주고,
		#    그중 누리는 시트상 드래곤이 1마리라 3vs3 파티 크기 검사가 터진다
		#    (2026-08-06 실제로 그렇게 빨간불이 났다 — 코드가 아니라 세이브 상태 탓이었다).
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

		# ── 7-c. 랭킹 보드 — 원작 pvp_total_rank / pvp_week_rank ────────────────
		var board := Colosseum.ladder("team", false, rng)
		fails += _eq("보드 행수", board.size(), Colosseum.LADDER_SIZE)
		var desc := true
		for i in range(1, board.size()):
			if int(board[i]["rating"]) > int(board[i - 1]["rating"]):
				desc = false
		fails += _b("보드 내림차순", desc)
		# 같은 호출은 같은 보드를 준다(세이브에 남는다) — 순위가 매 프레임 흔들리면 안 된다.
		var board2 := Colosseum.ladder("team", false, rng)
		fails += _eq("보드 고정", String(board2[0]["nick"]), String(board[0]["nick"]))
		var rank := Colosseum.my_rank("team", false)
		fails += _b("내 순위 1..N+1 (%d)" % rank, rank >= 1 and rank <= board.size() + 1)
		# 주간 보드는 별도 축이다.
		var wk := Colosseum.ladder("team", true, rng)
		fails += _eq("주간 보드 행수", wk.size(), Colosseum.LADDER_SIZE)

	# ── 8. 연승방지봇 스케줄 (🟦 사용자 확정: 25 누리A·50 라온A·75 누리B·100 라온B·150 라온C·999 선대군)
	var sched := [[0, ""], [24, ""], [25, "누리"], [49, "누리"], [50, "라온"], [74, "라온"],
				  [75, "누리"], [99, "누리"], [100, "라온"], [149, "라온"], [150, "라온"],
				  [998, "라온"], [999, "선대군"]]
	for c in sched:
		var g := Colosseum.guard_for(int(c[0]))
		fails += _eq("guard(%d연승)" % int(c[0]), String(g.get("name", "")), String(c[1]))
	# 대사 단계가 스케줄과 함께 확정되는가(원작 대사 단계 수와 일치해야 한다).
	fails += _eq("25연승 대사단계", String(Colosseum.guard_for(25).get("talk_stage", "")), "A")
	fails += _eq("75연승 대사단계", String(Colosseum.guard_for(75).get("talk_stage", "")), "B")
	fails += _eq("150연승 대사단계", String(Colosseum.guard_for(150).get("talk_stage", "")), "C")
	fails += _b("누리A 원작 대사 실림", (Colosseum.guard_for(25).get("lines", []) as Array).size() > 0)
	fails += _b("라온C 원작 대사 실림", (Colosseum.guard_for(150).get("lines", []) as Array).size() > 0)
	fails += _eq("다음 방지봇까지(0연승)", Colosseum.next_guard_in(0), 25)
	fails += _eq("다음 방지봇까지(150연승)", Colosseum.next_guard_in(150), 849)

	# ── 9. 연승방지봇 임의 스탯 (🟦 이벤트성 매치 — 시트가 적은 칸이 최종 능력치를 덮어쓴다)
	#   빈 칸은 평소 계산 그대로여야 한다(= 선대군은 기존 드래곤 스탯·등급을 따른다).
	var gsrc: Dictionary = Colosseum.guard_for(999)
	if not gsrc.is_empty() and not (gsrc.get("dragons", []) as Array).is_empty():
		var did := int((gsrc["dragons"][0] as Dictionary).get("id", 0))
		# 시트가 스탯을 안 적은 경우 = 계산대로.
		# 젬·장비가 무작위로 굴려지므로 두 봇은 **같은 시드**로 만들어야 비교가 성립한다.
		var r0 := RandomNumberGenerator.new()
		r0.seed = 20260804
		var r1 := RandomNumberGenerator.new()
		r1.seed = 20260804
		var plain := {"key": "t", "name": "평범", "rating": 1000, "talk_stage": "",
					  "dragons": [{"id": did, "level": 50, "awakened": true}]}
		var b0 := Colosseum.make_guard(plain, "single", r0)
		var s0: Dictionary = (PartyStats.summary_of(b0["dragons"], false, "")[0] as Dictionary)["stats"]
		# 같은 드래곤에 임의 스탯을 얹으면 그 칸만 정확히 그 값이 된다.
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
		# 안 적은 칸(방어)은 덮어쓰지 않는다.
		fails += _eq("빈 칸은 계산대로(방어)", int(s1.get("def", 0)), int(s0.get("def", 0)))
		# 플레이어 경로엔 이 필드가 없다 — 오버라이드 없는 레코드는 값이 그대로여야 한다.
		fails += _b("오버라이드 없으면 계산값 유지", int(s0.get("hp", 0)) != 12345)
	else:
		# 조용히 건너뛰면 "통과"로 보인다 — 시트가 비면 여기서 티가 나야 한다.
		print("  SKIP 임의 스탯 검증 — colosseum_guard.csv 에 999연승 봇 드래곤이 없다")

	# 등장 판정은 **연승 수 + 그 문턱을 붙어 봤는가** 두 가지로만 한다(문턱당 1회).
	#   여기서는 아직 아무것도 안 붙어 본 상태에서 문턱 전/후를 본다. 소진 뒤 동작은 §12-b.
	var gsv := Colosseum.state()
	gsv["guard_served"] = {}
	gsv["straight_team"] = 24
	Colosseum.save_state(gsv)
	fails += _b("24연승엔 안 나온다", not Colosseum.guard_active("team"))
	gsv["straight_team"] = 25
	Colosseum.save_state(gsv)
	fails += _b("25연승부터 나온다", Colosseum.guard_active("team"))
	fails += _eq("그 상대는 누리", String(Colosseum.pending_guard("team").get("name", "")), "누리")

	# ── 10. 시트 기입분이 실제 상대에 반영되는가 (docs/input/sheets/colosseum_guard.csv)
	#   빌더가 이름을 id·키로 확정하고(build_colosseum.py), 여기서 **장착까지** 확인한다.
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
		# 젬 '일반젬 중간 등급 공공체' → 공/공/체 3칸이 실제로 채워져야 한다.
		var ent := Gem.entries(d0.get("gems", {}))
		var filled := 0
		for e in ent:
			if e != null:
				filled += 1
		fails += _eq("라온1 젬 3칸", filled, 3)
		fails += _eq("라온1 젬1 이름", String((ent[0] as Dictionary).get("name", "")), "공격의 젬")
		fails += _eq("라온1 젬3 이름", String((ent[2] as Dictionary).get("name", "")), "체력의 젬")
		# 스킬 '철갑 방패, 복수의 거울 5레벨' → 학습 + 두 칸 장착.
		fails += _eq("라온1 스킬 수", (d0.get("skills", []) as Array).size(), 2)
		fails += _eq("라온1 스킬1", int((d0["skills"][0] as Dictionary).get("id", 0)), 11)
		fails += _eq("라온1 스킬2 레벨", int((d0["skills"][1] as Dictionary).get("level", 0)), 5)
		fails += _eq("라온1 장착 스킬칸", (d0.get("skill_equip", []) as Array), [11, 13])
		# 장비 칸이 비어 있으면 **굴리지 않는다**(저작한 상대라 랜덤 에픽이 붙으면 안 된다).
		fails += _eq("라온1 장비 없음", (d0.get("equip", {}).get("slots", []) as Array).size(), 0)

	var sun := Colosseum.make_guard(Colosseum.guard_for(999), "team", rng)
	if not (sun.get("dragons", []) as Array).is_empty():
		var s0d: Dictionary = sun["dragons"][0]
		var ent2 := Gem.entries(s0d.get("gems", {}))
		# ⚠️ 아래 리터럴은 **시트(colosseum_guard.csv)를 그대로 옮긴 값**이다 — 시트를 고치면
		#   여기도 같이 고쳐야 한다(2026-08-06: 샌즈→공격의 소울젬 · 장비 3→4칸으로 갱신).
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

	# ── 11. 누리의 면역 — 이벤트 규칙이 전투에서 실제로 먹는가
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
		# 아수라일섬(30)은 상대 방어력 비례라 30000 방어에 치명적인데, 면역이면 0 이어야 한다.
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
		# 평타는 통한다(관통 200 은 빠지고 방어 계산분만) — 면역이 전투 자체를 막으면 안 된다.
		var before := int(foe["hp"])
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = 9
		var na: Dictionary = Battle.resolve_attack(hero, foe, rng3, Data.combat, Data.skills)
		fails += _b("평타는 들어간다", int(na.get("damage", 0)) > 0 or bool(na.get("miss", false)))
		fails += _b("관통 면역 — 평타 피해가 관통(200)보다 작다", int(na.get("damage", 0)) < 200)
		foe["hp"] = before
		# 전투가 실제로 끝나는가 — 30000 방어 + 낮은 HP 는 "평타로만 깎는" 퍼즐이라
		# 라운드 상한(200) 안에 결판이 나야 한다.
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

	# ── 12. 등장 대사(최초/반복) + 오리지널 컨텐츠 해금 -------------------------
	#
	# ⚠️ 여기서부터 세이브를 건드린다 — `begin_batch()` 로 **디스크 기록을 끈다**
	#    (사용자 세이브에 999연승·해금 플래그가 새면 안 된다). 끝나고 저장하지 않는다.
	UserDB.begin_batch()
	var g999 := Colosseum.guard_for(999)
	fails += _b("선대군 최초 조우 대사가 있다", not (g999.get("lines_first", []) as Array).is_empty())
	fails += _b("선대군 반복 대사가 있다", not (g999.get("lines", []) as Array).is_empty())
	fails += _b("최초와 반복이 다르다", g999.get("lines_first", []) != g999.get("lines", []))
	# 원작 대사(라온·누리)는 등장마다 단계가 달라 최초/반복을 가르지 않는다.
	fails += _eq("누리(25) 최초 전용 대사 없음",
		(Colosseum.guard_for(25).get("lines_first", []) as Array).size(), 0)
	fails += _b("누리(25) 원작 대사 실림",
		not (Colosseum.guard_for(25).get("lines", []) as Array).is_empty())

	# ── 12-a. 대사 연출(화자·표정) — 원작 MatchingLayer::showNuriEvent/showRaonEvent 채굴본
	#
	# 🔴 2026-08-06 사용자 지적: 누리가 대사를 전부 읽고 있었고 표정도 미배선이었다.
	#    원작은 줄마다 TalkNpc(화자·몸통·표정·자리)를 따로 만든다 — 누리 이벤트는 2인극이다.
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
	# 첫 줄만 등장 연출(isFirstShow) — 화자별로 처음 나오는 줄에 딱 한 번씩.
	var firsts_seen := {}
	for ln in (Colosseum.guard_for(25).get("lines", []) as Array):
		var d: Dictionary = ln
		var who := String(d.get("npc", ""))
		if bool(d.get("first_show", false)):
			fails += _b("누리A 등장 연출은 그 화자의 첫 줄뿐: %s" % who, not firsts_seen.has(who))
			firsts_seen[who] = true
	fails += _eq("누리A 등장 연출 2건(누리·즈믄)", firsts_seen.size(), 2)

	# 최초 → 반복을 가르는 기준. 🔴 2026-08-07 사용자 확정 — **선대군만 해금 플래그**
	#   (`Summon.FLAG_UNLOCK`, 평문 `MeetAdmin`)로 가른다. 최초 대사가 선물 안내라
	#   실제로 받을 때(= 선대군에게 패배)까지 나와야 하기 때문이다. 나머지 방지봇은 종전대로
	#   조우 횟수(`guard_met`). 둘 다 **모드 축이 없어** 1vs1·3vs3 을 통틀어 한 번이다.
	var st0 := Colosseum.state()
	st0["guard_met"] = {}
	Colosseum.save_state(st0)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	var meet1 := Colosseum.make_guard(g999, "team", rng)
	fails += _b("첫 등장은 first_meet", bool(meet1.get("first_meet", false)))
	# 2026-08-06: `consume_guard` 가 (foe) → (mode, foe) 로 바뀌었다(문턱 소진이 모드별 기록이 됐다).
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
	# 나머지 방지봇(누리)은 조우 횟수 기준이고, 그 횟수도 모드를 가리지 않는다.
	var nuri1 := Colosseum.make_guard(Colosseum.guard_for(25), "team", rng)
	fails += _b("누리 첫 등장은 first_meet", bool(nuri1.get("first_meet", false)))
	Colosseum.consume_guard("team", nuri1)
	fails += _b("누리는 1vs1 에서도 반복(모드 통합)",
		not bool(Colosseum.make_guard(Colosseum.guard_for(25), "single", rng).get("first_meet", true)))
	var meet2 := Colosseum.make_guard(g999, "team", rng)

	# 해금 = **선대군에게 졌을 때만**. 이기거나 다른 방지봇이면 안 열린다.
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
	# 999연승을 채운 판에서만 선대군이 나온다(등장 조건 자체).
	var st1 := Colosseum.state()
	st1["straight_team"] = 998
	st1["guard_served"] = {}
	Colosseum.save_state(st1)
	Colosseum.apply_result("team", true, "봇")          # 999연승 달성 판
	# 🟦 2026-08-06 — **관리자 모드에서는 선대군이 아예 안 나온다**(`guards[].skip_if_admin`).
	#   그래서 이 구간은 `UserDB.ADMIN` 값에 따라 반대 명제를 검증한다 — 어느 쪽으로 켜 두든
	#   테스트가 통과해야 "플래그가 실제로 먹는다"를 확인한 것이 된다.
	if UserDB.is_admin():
		fails += _b("관리자면 999연승에도 선대군이 안 나온다", not Colosseum.guard_active("team"))
		fails += _eq("관리자면 상대가 비어 있다",
			String(Colosseum.pending_guard("team").get("name", "")), "")
	else:
		fails += _b("999연승 달성 → 다음 판은 방지봇", Colosseum.guard_active("team"))
		fails += _eq("그 상대는 선대군",
			String(Colosseum.pending_guard("team").get("name", "")), "선대군")
		# 🟦 2026-08-06 — 선대군도 **예외 없이 1회**다. 이겨서 지나치면 이번 연승에선 끝이고,
		#   다시 만나려면 연승을 끊고 999를 다시 쌓아야 한다(사용자 확정: 약한 드래곤을 대신
		#   내보내 일부러 질 수 있으므로 해금이 막히지 않는다).
		var sun_foe := Colosseum.make_guard(Colosseum.pending_guard("team"), "team", rng)
		Colosseum.consume_guard("team", sun_foe)
		Colosseum.apply_result("team", true, "선대군", sun_foe)   # 이긴다 → 1000연승
		fails += _b("선대군도 이기면 다시 안 나온다", not Colosseum.guard_active("team"))
		# 연승을 끊고 999를 다시 쌓으면 또 만난다.
		Colosseum.apply_result("team", false, "봇")               # 패배 → 연승 0 · 문턱 기록 삭제
		var st_re := Colosseum.state()
		st_re["straight_team"] = 999
		Colosseum.save_state(st_re)
		fails += _eq("연승을 다시 쌓으면 또 만난다",
			String(Colosseum.pending_guard("team").get("name", "")), "선대군")
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)          # 뒷정리(디스크엔 안 쓴다)

	# ── 12-b. 문턱당 1회 (🔴 2026-08-06 사용자 지적 — 25연승 뒤 32연승까지 누리만 나왔다) ──
	#
	# 로비와 **같은 순서**로 굴린다: roll_match → consume_guard → apply_result.
	# 25 문턱을 밟은 다음 판에 딱 한 번 누리가 나오고, 그 뒤로는 50까지 일반 봇이어야 한다.
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
	# 등장 시점 = 문턱을 밟은 **다음 판**(그 판을 이기면 연승 26).
	if guard_hits.size() == 1:
		fails += _eq("등장은 문턱 바로 다음 판", int(guard_hits[0]), 26)
	# 연승이 끊기면 기록이 비워져 **다시 25에서** 만난다(같은 문턱 재도전).
	var stl := Colosseum.state()
	stl["straight_team"] = 24
	Colosseum.save_state(stl)
	Colosseum.apply_result("team", false, "봇")          # 패배 → 연승 0 · 문턱 기록 삭제
	var st2 := Colosseum.state()
	st2["straight_team"] = 25
	Colosseum.save_state(st2)
	fails += _b("연승이 끊기면 같은 문턱을 다시 만난다", Colosseum.guard_active("team"))
	# 1vs1 과 3vs3 은 **다른 축**이다 — 3vs3 에서 소진해도 1vs1 문턱은 남아 있어야 한다.
	var st3 := Colosseum.state()
	st3["straight_single"] = 25
	st3["guard_served"] = {"team": [25]}
	Colosseum.save_state(st3)
	fails += _b("모드별로 따로 센다(1vs1 문턱 유지)", Colosseum.guard_active("single"))

	# ── 13. 랭커 시트(docs/input/sheets/colosseum_ranker.csv) -------------------
	#
	# 시트가 이름으로 적은 드래곤·젬·스킬·장비가 **실제 상대**까지 왔는지 본다.
	# 빌더가 이름을 못 읽으면 애초에 data/colosseum.json 을 안 쓰므로, 여기서는
	# "실린 것이 게임에서 그대로 장착되는가"를 확인한다.
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

		# 실제로 상대를 만들어 본다 — 3vs3(3마리) / 1vs1(1마리).
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
			# 강화는 옵션 값을 키운다 — 시트가 적은 '최적'(상한 롤)보다 커져 있어야 한다.
			var base_sum := 0
			for o: Dictionary in ((rankers[0]["dragons"][0] as Dictionary)["equip"][0]["options"] as Array):
				base_sum += int(o.get("value", 0))
			var now_sum := 0
			for o2: Dictionary in (slot0.get("options", []) as Array):
				now_sum += int(o2.get("value", 0))
			fails += _b("강화로 옵션 값이 커졌다(%d → %d)" % [base_sum, now_sum], now_sum > base_sum)
		# 🟦 스킬을 2개보다 많이 적으면 **전투마다 그 중 랜덤 2개**를 장착한다.
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
						continue                     # 명단에서 골라 쓰므로 매번 나오진 않는다
					var eqs: Array = rd2.get("skill_equip", [])
					for sid in eqs:
						if int(sid) != 0 and not pool.has(int(sid)):
							bad += 1
					pairs[str(eqs)] = true
			fails += _eq("장착 스킬은 적어 둔 것 중에서만 나온다", bad, 0)
			fails += _b("2개 초과면 조합이 매번 같지 않다", pairs.size() > 1)

		# 🟦 관통 상한 — 장비로 쌓은 몫은 combat.json `judge.pure_cap` 에서 잘린다.
		var cap := int((Data.combat.get("judge", {}) as Dictionary).get("pure_cap", 0))
		fails += _eq("관통 상한이 데이터에 있다", cap, 100)
		# 장비만으로 쌓인 값(자르기 전) — 강화까지 마친 실제 장착분에서 센다.
		var raw_pure := int(Equipment.apply({}, (rd[0] as Dictionary).get("equip", {}),
			Data.equipment).get("pure", 0))
		fails += _b("랭커 장비 관통 합이 상한을 넘는다(시험 전제 %d)" % raw_pure, raw_pure > cap)
		var cap_row: Dictionary = PartyStats.summary_of(rd, false, "")[0]
		fails += _eq("실 능력치의 관통은 상한까지만",
			int((cap_row["stats"] as Dictionary).get("pure", 0)), cap)

		fails += _eq("랭커 1vs1 = 1마리",
			(Colosseum._make_ranker(rankers[0], "single", rng).get("dragons", []) as Array).size(), 1)
		# 명단이 party 보다 많으면 매번 같은 조합만 나오지 않는다(명단에서 고른다).
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
		# 랭커가 실제 전투에 설 수 있는가(스탯 해석까지).
		var rparty := PartyStats.summary_of(rd, false, "")
		fails += _eq("랭커 파티 스탯 3", rparty.size(), 3)
		fails += _b("랭커 HP가 0이 아니다", int((rparty[0]["stats"] as Dictionary).get("hp", 0)) > 0)

	# ── 7. 주화 경제 + 상점 PVP 탭 (2026-08-06) --------------------------------
	fails += _coin_and_shop()

	fails += _restore_save()
	print("\n[test_colosseum] %s" % ("ALL PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## 검증이 실제 진행도를 바꾸지 않았음을 보장한다(§ 위 주석).
func _restore_save() -> int:
	var ck := Colosseum.coin_key()
	UserDB.set_pmeta(Colosseum.PMETA_KEY, _snap_state)
	var drift := UserDB.item_count(ck) - _snap_coin
	if drift > 0:
		UserDB.use_item(ck, drift)
	elif drift < 0:
		UserDB.add_item(ck, -drift)
	# ⚠️ 메모리만 되돌려선 부족하다 — `_commit()` 은 `_autosave` 가 켜져 있을 때만 디스크에
	#   쓴다(UserDB.begin_batch 가 꺼 놓을 수 있고, 실제로 복원분이 디스크까지 안 내려가
	#   guard_left 가 검증 도중 값(0)으로 남는 것을 2026-08-06 에 관측했다).
	#   `UserDB.save()` 는 `_autosave` 를 되켜고 동기로 쓴다 → 여기서 못을 박는다.
	UserDB.save()
	var f := _eq("세이브 복원(주화)", UserDB.item_count(ck), _snap_coin)
	# 디스크에 실제로 그렇게 적혔는지 **파일을 다시 읽어** 확인한다(메모리 비교는 같은
	# 객체끼리라 늘 통과한다 — 그 자기참조 함정 때문에 위 관측을 놓칠 뻔했다).
	var disk := _load(SaveSystem.SAVE_PATH)
	var got: Dictionary = (disk.get("meta", {}) as Dictionary).get(Colosseum.PMETA_KEY, {})
	for k in _snap_state:
		f += _eq("세이브 복원(디스크) %s" % k,
			JSON.stringify(got.get(k)), JSON.stringify(_snap_state[k]))
	f += _eq("세이브 복원(디스크) 주화",
		int((disk.get("inventory", {}) as Dictionary).get(ck, 0)), _snap_coin)
	return f


## 콜로세움 주화(재화) · 판당 지급 · 상점 PVP 탭 배선.
##
## ⚠️ 이 절은 **세이브를 건드리는 경로**(apply_result → add_item/save_state)를 탄다.
##    실제 세이브를 망가뜨리지 않도록 앞뒤로 스냅샷/복원한다.
func _coin_and_shop() -> int:
	var f := 0
	var ck := Colosseum.coin_key()

	# 7-1. 재화가 **정의된 아이템**인가. 이게 이 작업의 출발점이었다 —
	#      colosseum.gd 가 add_item 으로 주화를 주는데 items.json 에 정의가 없어
	#      가방에서 이름·아이콘 없는 유령 항목이었다(new_game.json 이 2026-07-31 에 겪은 것과 같은 형태).
	var cdef: Dictionary = Data.items.get(ck, {})
	f += _b("주화가 items.json 에 있다 (%s)" % ck, not cdef.is_empty())
	f += _eq("주화 category", String(cdef.get("category", "")), "currency")
	var cpath := Data.item_icon_path(ck)
	f += _b("주화 아이콘이 실제로 로드된다 (%s)" % cpath,
		cpath != "" and ResourceLoader.exists(cpath))

	# 7-2. 가격표가 딛고 선 환율 — `coin.weekly` 6티어가 전부 coin = dia × 10.
	#      이게 깨지면 data/shop.json PVP 탭의 가격 근거가 통째로 무너진다.
	var wk: Dictionary = (Data.colosseum.get("coin", {}) as Dictionary).get("weekly", {})
	f += _b("주간 보상표가 비어 있지 않다", not wk.is_empty())
	for tid in wk:
		var r: Dictionary = wk[tid]
		f += _eq("환율 티어%s coin=dia×10" % tid, int(r.get("coin", 0)), int(r.get("dia", 0)) * 10)

	# 7-3. 판당 지급 규칙.
	var w0 := Colosseum.match_coin("single", true, 0)
	var w5 := Colosseum.match_coin("single", true, 5)
	var w99 := Colosseum.match_coin("single", true, 99)
	var lo := Colosseum.match_coin("single", false, 0)
	f += _b("승리 > 패배", w0 > lo)
	f += _b("패배도 0보다 크다", lo > 0)
	f += _b("연승이 판당 주화를 키운다", w5 > w0)
	f += _b("연승 보너스에 상한이 있다", w99 == w0 + 10)
	f += _eq("3vs3 는 2배", Colosseum.match_coin("team", true, 0), w0 * 2)

	# 7-4. 실제 지급 + 티어 승급 보너스는 **한 번만**.
	# (세이브 복원은 _run() 끝의 _restore_save() 가 통째로 맡는다.)
	# SILVER 문턱(1200) 바로 아래에서 한 판 이기면 승급 + 보너스가 붙어야 한다.
	var s := Colosseum.state()
	s["single"] = 1199
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
	# 같은 티어를 다시 밟아도 보너스는 없다.
	var s2 := Colosseum.state()
	s2["single"] = 1199
	Colosseum.save_state(s2)
	var r2 := Colosseum.apply_result("single", true)
	f += _eq("같은 티어 승급 보너스는 1회뿐", int(r2.get("coin_tier_bonus", 0)), 0)

	# 7-5. 입장권 회복(자양강장제) — 상한에서 멈추고, 멈추면 0 을 돌려준다.
	var s3 := Colosseum.state()
	s3["energy"] = Colosseum.ticket_max() - 1
	s3["energy_at"] = int(Time.get_unix_time_from_system())
	Colosseum.save_state(s3)
	f += _eq("입장권 1 회복", Colosseum.add_ticket(1), 1)
	f += _eq("만땅이면 회복 0", Colosseum.add_ticket(1), 0)
	f += _eq("상한을 넘지 않는다",
		int(Colosseum.refresh_ticket().get("energy", 0)), Colosseum.ticket_max())

	# 7-6. 상점 PVP 탭 배선 — 진열한 것이 전부 살아 있는 아이템인가.
	var pvp: Dictionary = {}
	for t: Dictionary in Data.shop.get("tabs", []):
		if String(t.get("id", "")) == "pvp":
			pvp = t
	f += _b("상점에 PVP 탭이 있다", not pvp.is_empty())
	if pvp.is_empty():
		return f
	f += _eq("PVP 지갑", String(pvp.get("wallet", "")), "pvp")
	# 원작 setSeller(ShopScene.c:4674~4734) 가 tab 1 에 라온을 박아 둔다.
	f += _eq("PVP NPC = 라온", String(pvp.get("npc", "")), "raon")
	var stock: Array = pvp.get("stock", [])
	f += _b("진열 품목이 있다", stock.size() > 0)
	for e: Dictionary in stock:
		var k := String(e.get("item", ""))
		var idef: Dictionary = Data.items.get(k, {})
		f += _b("PVP 품목 %s 가 items.json 에 있다" % k, not idef.is_empty())
		# `offline != impl` 인 것을 팔면 살 수는 있는데 쓸 수 없는 아이템이 된다.
		f += _eq("PVP 품목 %s offline" % k, String(idef.get("offline", "")), "impl")
		f += _eq("PVP 품목 %s 는 주화로 산다" % k, String(e.get("cur", "")), ck)
		f += _b("PVP 품목 %s 가격 > 0" % k, int(e.get("price", 0)) > 0)
		var ip := Data.item_icon_path(k)
		f += _b("PVP 품목 %s 아이콘 로드" % k, ip != "" and ResourceLoader.exists(ip))
	# 탭 아이콘·배경도 실제로 있는 프레임이어야 한다(원작 프레임 부재분을 대체했다).
	var ikey := String(pvp.get("icon", ""))
	f += _b("PVP 탭 아이콘 존재 (%s)" % ikey,
		ResourceLoader.exists("res://assets/converted/%s.tres" % ikey))
	f += _b("PVP 탭 배경 존재 (%s)" % String(pvp.get("tab_bg", "")),
		ResourceLoader.exists("res://assets/converted/common_ui/common_%s.tres"
			% String(pvp.get("tab_bg", ""))))
	return f


## 시트 기입분이 data/colosseum.json 까지 왔는지(빌더 단계) 확인한다.
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
