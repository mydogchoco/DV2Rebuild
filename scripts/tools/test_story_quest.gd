extends SceneTree

const SQ := preload("res://scripts/systems/story_quest.gd")

func _init() -> void:
	var fails := 0
	var f := FileAccess.open(_data_file("story_subquest.json"), FileAccess.READ)
	if f == null:
		print("FAIL: data/story_subquest.json 없음 — extract_story_subquest.py 실행")
		quit(1)
		return
	var sq: Dictionary = JSON.parse_string(f.get_as_text())
	var story: Dictionary = _json(_data_file("story.json"))
	var scenario: Dictionary = _json(_data_file("scenario.json"))

	fails += _eq("80화 탐험 클릭 수(0x27)", int(sq["click_count"]["80"]), 39)
	fails += _eq("81화 탐험 클릭 수(=5)", int(sq["click_count"]["81"]), 5)
	fails += _eq("88화 탐험 클릭 수(0x35)", int(sq["click_count"]["88"]), 53)
	fails += _eq("103화 배틀 클릭 수(0x13)", int(sq["battle_click_count"]["103"]), 19)
	fails += _eq("마크필드 79화", int(sq["mark_field"]["79"]), 1002)
	fails += _eq("마크필드 90화", int(sq["mark_field"]["90"]), 24)
	fails += _eq("마크필드 146화", int(sq["mark_field"]["146"]), 999)
	fails += _eq("마크필드 엔트리 수(0x44)", (sq["mark_field"] as Dictionary).size(), 68)
	var notify: Dictionary = sq["notify_field"]
	fails += _eq("2화 안내 필드(setScenarioNotification)", int(notify["2"]), 1)
	fails += _eq("8화 안내 필드(setScenarioNotification)", int(notify["8"]), 3)
	fails += _true("초반 회차가 표에 있다(1~78화의 유일한 출처)", notify.size() > 20)
	fails += _true("조건부 회차는 별도 표", (sq["notify_conditional"] as Dictionary).has("34"))
	fails += _true("조건부 회차는 고정 표에 없다", not notify.has("34"))

	var f80: Dictionary = sq["subquest_field"]["80"]
	fails += _eq("80화 서브퀘 필드", int(f80["field"]), 4)
	fails += _true("80화는 밤 조건", bool(f80["night"]))
	var f93: Dictionary = sq["subquest_field"]["93"]
	fails += _eq("93화 서브퀘 필드", int(f93["field"]), 9)
	fails += _eq("93화 카데스 조건", int((f93["requires"] as Dictionary)["kades"]), 1)
	fails += _eq("서브퀘 필드 회차 수", (sq["subquest_field"] as Dictionary).size(), 32)
	fails += _eq("서브 단계(param_1 == 2)", int(sq["subquest_substep"]), 2)

	var sm: Dictionary = sq["scenario_mark"]
	fails += _eq("배지 45화(case 0x2d)", int((sm["45"] as Dictionary)["field"]), 5)
	fails += _eq("배지 46화(case 0x2e)", int((sm["46"] as Dictionary)["field"]), 15)
	fails += _eq("배지 27화(case 0x1b)", int((sm["27"] as Dictionary)["field"]), 10)
	fails += _eq("배지 33화(case 0x21)", int((sm["33"] as Dictionary)["field"]), 14)
	fails += _eq("배지 16화(switch 앞 기본값 6)", int((sm["16"] as Dictionary)["field"]), 6)
	fails += _eq("배지 20화(caseD_b = 999)", int((sm["20"] as Dictionary)["field"]), 999)
	fails += _eq("배지 62화(밤 · uVar6 = 9)", int((sm["62"] as Dictionary)["field"]), 9)
	fails += _true("62화는 밤 조건", bool((sm["62"] as Dictionary)["night"]))
	fails += _eq("배지 표 회차 수", sm.size(), 81)
	var was_blank := [13, 16, 17, 20, 27, 31, 33, 35, 36, 37, 45, 46, 47, 51, 52,
		56, 57, 58, 59, 62, 63, 67, 71, 75, 76]
	var blank := 0
	for no in was_blank:
		if not sm.has(str(no)):
			blank += 1
	fails += _eq("마커 근거 없던 25회차가 전부 표에 있다", blank, 0)

	var eb: Dictionary = sq["event_battle"]["29"]
	fails += _eq("이벤트29 몬스터", int(eb["monster_no"]), 75)
	fails += _eq("이벤트29 Lv", int(eb["lv"]), 50)
	fails += _eq("이벤트29 HP", int(eb["hp"]), 1100)
	fails += _eq("이벤트29 공격", int(eb["att"]), 200)
	fails += _eq("이벤트29 방어", int(eb["def"]), 125)
	fails += _eq("이벤트29 필드", int(eb["field_no"]), 601)
	fails += _eq("이벤트 전투 수", (sq["event_battle"] as Dictionary).size(), 3)
	fails += _eq("이벤트26 HP(9만)", int((sq["event_battle"]["26"] as Dictionary)["hp"]), 90000)

	var sr: Dictionary = sq["special_reward"]
	fails += _eq("특별보상 건수", sr.size(), 3)
	fails += _eq("26화 보상 드래곤", int((sr["26"] as Dictionary)["dragon_no"]), 9)
	fails += _eq("58화 보상 드래곤", int((sr["58"] as Dictionary)["dragon_no"]), 87)
	fails += _eq("78화 보상 드래곤", int((sr["78"] as Dictionary)["dragon_no"]), 105)
	fails += _eq("78화 보상 레벨", int((sr["78"] as Dictionary)["level"]), 50)
	fails += _eq("78화 젬 색", String(((sr["78"] as Dictionary)["gem_colors"] as Array)[1]), "R")
	fails += _eq("78화 보상 원문",
		String((sr["78"] as Dictionary)["raw"]), "DRAGON:105:50:3:114:114:152:R:R:Y:29_2,32_2,101_2")

	var episodes: Dictionary = story.get("episodes", {})
	var scenarios: Dictionary = scenario.get("scenarios", {})
	fails += _true("45화 구현됨(회색 화면 회귀)", SQ.implemented_with(episodes["45"], scenarios["45"]))
	fails += _eq("45화 대사 수", ((scenarios["45"] as Dictionary)["parts"][0]["lines"] as Array).size(), 23)
	fails += _true("139화 구현됨", SQ.implemented_with(episodes["139"], scenarios["139"]))
	for no in range(140, 147):
		fails += _true("%d화 미구현 영구 잠금" % no,
			not SQ.implemented_with(episodes[str(no)], scenarios.get(str(no), {})))

	var ep2: Dictionary = episodes["2"]
	var sp2 := SQ.spec_of(ep2)
	fails += _eq("2화 조건 타입", String(sp2["type"]), "ADVENTURE")
	fails += _eq("2화 필드", int(sp2["field"]), 1)
	fails += _eq("2화 요구치", int(sp2["count"]), 5)
	fails += _true("조건 없는 회차는 빈 dict", SQ.spec_of(episodes["3"]).is_empty())
	var scen_all: Dictionary = scenario.get("scenarios", {})
	var breaks := 0
	for k in episodes:
		var sp := SQ.spec_of(episodes[k])
		if sp.is_empty():
			continue
		if not sp.has("break_after"):
			print("  FAIL %s화 발급 지점 없음" % k); fails += 1
			continue
		breaks += 1
		var total := 0
		for pt in ((scen_all.get(k, {}) as Dictionary).get("parts", []) as Array):
			total += ((pt as Dictionary).get("lines", []) as Array).size()
		if int(sp["break_after"]) >= total - 1:
			print("  FAIL %s화 발급 지점이 마지막 줄(이어볼 대사 없음)" % k); fails += 1
	fails += _eq("발급 지점 51건", breaks, 51)
	for k in ["61", "64", "68", "69", "77"]:
		fails += _true("%s화 서브미션 배선" % k,
			not (episodes[k] as Dictionary).get("submission", {}).is_empty())
	fails += _eq("64화 뎀프바논 2마리",
		int(((episodes["64"] as Dictionary)["submission"] as Dictionary)["count"]), 2)
	fails += _eq("77화 데몬 쉘터 2마리",
		int(((episodes["77"] as Dictionary)["submission"] as Dictionary)["count"]), 2)
	fails += _true("61화는 밤 조건",
		bool(((episodes["61"] as Dictionary)["submission"] as Dictionary).get("night", false)))

	var stages: Dictionary = _json(_data_file("stages.json")).get("stages", {})
	for k in ["84", "94"]:
		var lk: Dictionary = (episodes[k] as Dictionary)["submission"]
		fails += _eq("%s화 KILL 로 좁혔다" % k, String(lk.get("type", "")), "KILL")
		fails += _eq("%s화 수량 10" % k, int(lk.get("count", 0)), 10)
		var st: Dictionary = stages.get(str(int(lk["field"])), {})
		var pool: Array = (st.get("enemies", []) as Array)
		if bool(lk.get("night", false)):
			pool = ((st.get("night", {}) as Dictionary).get("enemies", []) as Array)
		elif int(lk.get("kades", 0)) != 0:
			pool = ((st.get("kades", {}) as Dictionary).get("enemies", []) as Array)
		var hit := ""
		for e in pool:
			if int((e as Dictionary).get("id", -1)) == int(lk["monster"]):
				hit = String((e as Dictionary).get("name", ""))
		fails += _true("%s화 목표 %s 가 그 위상 편성에 있다: %s"
			% [k, lk.get("monster_name", ""), hit],
			hit != "" and String(lk.get("monster_name", "")) in hit)

	fails += _true("게이트: 조건 없는 회차 통과", SQ.cleared_with(episodes["3"], 0))
	fails += _true("게이트: 미달", not SQ.cleared_with(ep2, 4))
	fails += _true("게이트: 달성", SQ.cleared_with(ep2, 5))
	fails += _true("게이트: 초과", SQ.cleared_with(ep2, 6))
	var sp80 := SQ.spec_of(episodes["80"])
	fails += _eq("80화 요구치", int(sp80["count"]), 1)
	fails += _eq("80화 필드", int(sp80["field"]), 4)
	fails += _true("80화는 밤 조건", bool(sp80.get("night", false)))
	fails += _true("80화: 밤에 그 필드면 카운트",
		SQ.counts_for(sp80, {"kind": "ADVENTURE", "field": 4, "night": true}))
	fails += _true("80화: 낮이면 카운트 안 함",
		not SQ.counts_for(sp80, {"kind": "ADVENTURE", "field": 4, "night": false}))
	var sp93 := SQ.spec_of(episodes["93"])
	fails += _true("93화: 카데스 아니면 카운트 안 함",
		not SQ.counts_for(sp93, {"kind": "ADVENTURE", "field": 9, "kades": 0}))
	fails += _true("93화: 카데스면 카운트",
		SQ.counts_for(sp93, {"kind": "ADVENTURE", "field": 9, "kades": 1}))
	for no in [141, 145]:
		fails += _true("%d화(파트 1개) 미션 없음" % no, SQ.spec_of(episodes[str(no)]).is_empty())

	fails += _true("2화: 희망의 숲 탐험 → 카운트",
		SQ.counts_for(sp2, {"kind": "ADVENTURE", "field": 1, "region": "yutakan"}))
	fails += _true("2화: 다른 필드면 안 셈",
		not SQ.counts_for(sp2, {"kind": "ADVENTURE", "field": 2, "region": "yutakan"}))
	fails += _true("2화: 퇴치는 안 셈",
		not SQ.counts_for(sp2, {"kind": "KILL", "field": 1, "region": "yutakan"}))
	var sp5 := SQ.spec_of(episodes["5"])
	fails += _true("5화: 난파선 아무 몬스터나 퇴치",
		SQ.counts_for(sp5, {"kind": "KILL", "field": 2, "monster": 7}))
	var sp38 := SQ.spec_of(episodes["38"])
	fails += _true("38화: 지정 몬스터만",
		SQ.counts_for(sp38, {"kind": "KILL", "field": 12, "monster": 56}))
	fails += _true("38화: 다른 몬스터는 안 셈",
		not SQ.counts_for(sp38, {"kind": "KILL", "field": 12, "monster": 52}))
	var sp8 := SQ.spec_of(episodes["8"])
	fails += _true("8화: 마법석 획득",
		SQ.counts_for(sp8, {"kind": "GATHER", "field": 3, "item": "stone2"}))
	fails += _true("8화: 다른 아이템은 안 셈",
		not SQ.counts_for(sp8, {"kind": "GATHER", "field": 3, "item": "gold"}))
	var sp25 := SQ.spec_of(episodes["25"])
	fails += _true("25화: 유타칸이면 어느 필드든",
		SQ.counts_for(sp25, {"kind": "ADVENTURE", "field": 11, "region": "yutakan"}))
	fails += _true("25화: 다른 지역은 안 셈",
		not SQ.counts_for(sp25, {"kind": "ADVENTURE", "field": 18, "region": "elf"}))
	var sp15 := SQ.spec_of(episodes["15"])
	var sp34 := SQ.spec_of(episodes["34"])
	fails += _true("15화: 콜로세움은 패배도 셈", SQ.counts_for(sp15, {"kind": "COLOSSEUM", "win": false}))
	fails += _true("34화: 승리만 셈", SQ.counts_for(sp34, {"kind": "COLOSSEUM", "win": true}))
	fails += _true("34화: 패배는 안 셈", not SQ.counts_for(sp34, {"kind": "COLOSSEUM", "win": false}))

	var line := SQ.line_with(ep2, 3, "희망의 숲")
	fails += _true("배너에 서브미션 이름", line.contains("서브미션 : 희망의 숲 조사"))
	fails += _true("배너에 5회 탐험", line.contains("5회 탐험"))
	fails += _true("배너에 진행 3/5", line.contains("3/5"))
	var line38 := SQ.line_with(episodes["38"], 0, "원혼의 폭포", "카디모프스")
	fails += _true("퇴치 배너 포맷", line38.contains("카디모프스 1마리 퇴치"))
	var line8 := SQ.line_with(episodes["8"], 0, "불의 산", "마법석")
	fails += _true("획득 배너 포맷", line8.contains("마법석 1개 획득"))
	fails += _eq("조건 없으면 배너도 없다", SQ.line_with(episodes["3"], 0, ""), "")

	print("\n[test_story_quest] ", "PASS" if fails == 0 else "FAIL %d건" % fails)
	quit(1 if fails > 0 else 0)

func _json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	print("FAIL %s: got=%s want=%s" % [what, str(got), str(want)])
	return 1

func _true(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("FAIL %s: false" % what)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
