extends SceneTree
## 헤드리스 StoryQuest 단위 테스트 (§8 — logic 은 화면 없이 검증).
##
## 검증 대상 = 원작 `ScenarioSubQuestData` 하드코딩분을 그대로 옮겼는지.
## 기준값은 전부 디컴프 축자다:
##   · `scenairoClickCountCheck()` case 0x50(80화) → 0x27 = 39
##   · `getScenarioSubQuestFiled` case 0x50/0x51 → 필드 4, `!param_2` 가드 = **밤에만**
##   · case 0x5d(93화) → `getDBYutakanKades()==1` 일 때 필드 9
##   · `isBattleCountClick` case 0x67(103화) → 0x13 = 19
##   · `getEventMarkFieldValue` .rodata[sn-0x4f]: 79→1002 · 90→24 · 146→999
##   · `getEventBattleData` 이벤트 29 → 몬스터 75 / Lv50 / HP1100 / 공200 / 방125 / 필드 601
##   · `ScenarioManager::setSpecialReward` → 26화 드래곤 9 · 58화 87 · 78화 105 (전부 Lv50)
##
## 실행: godot --headless --path . --script res://scripts/tools/test_story_quest.gd --quit-after 3

const SQ := preload("res://scripts/systems/story_quest.gd")

func _init() -> void:
	var fails := 0
	var f := FileAccess.open("res://data/story_subquest.json", FileAccess.READ)
	if f == null:
		print("FAIL: data/story_subquest.json 없음 — extract_story_subquest.py 실행")
		quit(1)
		return
	var sq: Dictionary = JSON.parse_string(f.get_as_text())
	var story: Dictionary = _json("res://data/story.json")
	var scenario: Dictionary = _json("res://data/scenario.json")

	# ── ① 추출표가 원작 축자값과 일치하는가 ────────────────────────────────────
	fails += _eq("80화 탐험 클릭 수(0x27)", int(sq["click_count"]["80"]), 39)
	fails += _eq("81화 탐험 클릭 수(=5)", int(sq["click_count"]["81"]), 5)
	fails += _eq("88화 탐험 클릭 수(0x35)", int(sq["click_count"]["88"]), 53)
	fails += _eq("103화 배틀 클릭 수(0x13)", int(sq["battle_click_count"]["103"]), 19)
	fails += _eq("마크필드 79화", int(sq["mark_field"]["79"]), 1002)
	fails += _eq("마크필드 90화", int(sq["mark_field"]["90"]), 24)
	fails += _eq("마크필드 146화", int(sq["mark_field"]["146"]), 999)
	fails += _eq("마크필드 엔트리 수(0x44)", (sq["mark_field"] as Dictionary).size(), 68)
	fails += _eq("2화 진입 필드(WorldMapScene getScenarioMark)", int(sq["entry_field"]["2"]), 1)
	fails += _eq("8화 진입 필드(WorldMapScene getScenarioMark)", int(sq["entry_field"]["8"]), 3)
	fails += _eq("46화 진입 필드(WorldMapScene getScenarioMark)", int(sq["entry_field"]["46"]), 15)

	var f80: Dictionary = sq["subquest_field"]["80"]
	fails += _eq("80화 서브퀘 필드", int(f80["field"]), 4)
	fails += _true("80화는 밤 조건", bool(f80["night"]))
	var f93: Dictionary = sq["subquest_field"]["93"]
	fails += _eq("93화 서브퀘 필드", int(f93["field"]), 9)
	fails += _eq("93화 카데스 조건", int((f93["requires"] as Dictionary)["kades"]), 1)
	fails += _eq("서브퀘 필드 회차 수", (sq["subquest_field"] as Dictionary).size(), 32)
	fails += _eq("서브 단계(param_1 == 2)", int(sq["subquest_substep"]), 2)

	var eb: Dictionary = sq["event_battle"]["29"]
	fails += _eq("이벤트29 몬스터", int(eb["monster_no"]), 75)
	fails += _eq("이벤트29 Lv", int(eb["lv"]), 50)
	fails += _eq("이벤트29 HP", int(eb["hp"]), 1100)
	fails += _eq("이벤트29 공격", int(eb["att"]), 200)
	fails += _eq("이벤트29 방어", int(eb["def"]), 125)
	fails += _eq("이벤트29 필드", int(eb["field_no"]), 601)
	fails += _eq("이벤트 전투 수", (sq["event_battle"] as Dictionary).size(), 3)
	# lv99 / 9만 스탯 = 격파 불가 벽 몬스터(원작 isImitationBattle/loseEventBattle 짝).
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

	# 45화는 본문 23줄이 있어 열람 가능해야 한다. 제목만 복원된 140~146화는 영구 잠금한다.
	var episodes: Dictionary = story.get("episodes", {})
	var scenarios: Dictionary = scenario.get("scenarios", {})
	fails += _true("45화 구현됨(회색 화면 회귀)", SQ.implemented_with(episodes["45"], scenarios["45"]))
	fails += _eq("45화 대사 수", ((scenarios["45"] as Dictionary)["parts"][0]["lines"] as Array).size(), 23)
	fails += _true("139화 구현됨", SQ.implemented_with(episodes["139"], scenarios["139"]))
	for no in range(140, 147):
		fails += _true("%d화 미구현 영구 잠금" % no,
			not SQ.implemented_with(episodes[str(no)], scenarios.get(str(no), {})))

	# ── ② 순수 규칙 ────────────────────────────────────────────────────────────
	var sp80 := SQ.spec_of(sq, 80)
	fails += _eq("spec_of(80).need", int(sp80["need"]), 39)
	fails += _true("spec_of(1) 없음(표 밖)", SQ.spec_of(sq, 1).is_empty())
	# 표에 없는 회차 = 서브퀘스트 없음 ⇒ 통과해야 한다(게이트를 막으면 스토리가 멈춘다).
	fails += _true("게이트: 표 밖 회차는 통과", SQ.cleared_with(sq, 1, 0))
	fails += _true("게이트: 미달", not SQ.cleared_with(sq, 80, 38))
	fails += _true("게이트: 달성", SQ.cleared_with(sq, 80, 39))
	fails += _true("게이트: 초과", SQ.cleared_with(sq, 80, 40))

	# 카운트 조건 — 필드/밤/카데스
	fails += _true("80화: 밤 + 필드4 → 카운트", SQ.counts_for(sp80, 4, true, {}))
	fails += _true("80화: 낮이면 카운트 안 함", not SQ.counts_for(sp80, 4, false, {}))
	fails += _true("80화: 다른 필드면 카운트 안 함", not SQ.counts_for(sp80, 5, true, {}))
	var sp93 := SQ.spec_of(sq, 93)
	fails += _true("93화: 카데스 아니면 카운트 안 함", not SQ.counts_for(sp93, 9, false, {"kades": 0}))
	fails += _true("93화: 카데스면 카운트", SQ.counts_for(sp93, 9, false, {"kades": 1}))
	# selectmap 조건(96·97화)은 일부러 무시한다 — 필드 일치가 더 강한 검사다(story_quest.gd 주석).
	var sp96 := SQ.spec_of(sq, 96)
	fails += _true("96화: selectmap 무시하고 필드로 판정", SQ.counts_for(sp96, 22, false, {}))

	# 배너 문구 — 원작 `QuestTitle_ADVENTURE`("%d회 탐험") 문면 + 진행 카운터
	var line := SQ.line_with(sq, {}, 80, 7, "바람의 신전")
	fails += _true("배너에 필드명", line.contains("바람의 신전"))
	fails += _true("배너에 39회 탐험", line.contains("39회 탐험"))
	fails += _true("배너에 진행 7/39", line.contains("7/39"))
	fails += _true("배너에 밤 표기", line.contains("(밤)"))
	var line2 := SQ.line_with(sq, {"submission": "돌의 정령"}, 80, 0, "")
	fails += _true("서브미션 이름 포함(QuestTitleSub)", line2.contains("서브미션 : 돌의 정령"))
	fails += _true("필드명 없으면 번호로", line2.contains("필드 4"))

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
