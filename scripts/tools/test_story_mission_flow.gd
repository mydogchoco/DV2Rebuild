extends Node

const EP := 2

func _ready() -> void:
	var fails := 0
	if not String(SaveSystem.save_dir).contains("test_save"):
		print("  FAIL 실세이브로 돌고 있다 — 러너가 DV2_TEST_SAVE=1 을 안 걸었다")
		print("[test_story_mission_flow] 1 FAIL")
		get_tree().quit()
		return
	UserDB.set_progress("scenario_1_0", true)
	UserDB.set_progress("story_mission_at_%d" % EP, 0)
	UserDB.set_progress("story_sq_%d" % EP, 0)
	UserDB.set_progress("scenario_%d_0" % EP, false)

	var sp := StoryProgress.spec(EP)
	var brk := int(sp.get("break_after", -1))
	fails += _eq("발급 지점", brk, 20)

	var story := _open()
	var guard := 0
	while int(story.get("_idx")) <= brk and guard < 400:
		story.call("_play_flow")
		guard += 1
	story.call("_play_flow")
	await get_tree().process_frame
	var issued := StoryProgress.mission_resume(EP)
	fails += _true("발급 지점에서 멈추고 이어볼 자리를 남겼다", issued > 0)
	var ph := -1
	var lines: Array = story.get("_lines")
	for i in range(min(brk + 1, lines.size())):
		if String((lines[i] as Dictionary).get("text", "")).contains("%"):
			ph = i
			break
	fails += _true("발급 전에 자리표시자 줄이 있다", ph >= 0)
	if ph >= 0:
		story.call("_show_line", ph)
		var shown := String((story.get("_label") as Label).text)
		fails += _true("화면 라벨에 요구치가 박힌다: %s" % shown.substr(0, 30),
			shown.contains("5번") and not shown.contains("%"))
	story.set("_no", 53)
	var vague := String(story.call("_fill_count", "타락한 정령을 %1$s마리 정도만 부탁드려요!"))
	story.set("_no", EP)
	fails += _eq("요구치 없는 회차는 '몇 마리'", vague, "타락한 정령을 몇 마리 정도만 부탁드려요!")
	fails += _eq("미션 중 스토리 배지 없음", StoryProgress.mark_field(), 0)
	fails += _eq("안내 화살표는 미션 던전을 짚는다", StoryProgress.notify_field(), 1)
	fails += _true("아직 회차를 다 본 것이 아니다", not StoryProgress.seen(EP))
	fails += _eq("수행 중인 미션 = 그 회차", StoryProgress.pending_episode(), EP)
	fails += _true("다음 회차는 아직 잠김", not StoryProgress.unlocked(EP + 1))
	story.queue_free()
	await get_tree().process_frame

	var skipper := _open()
	await get_tree().process_frame
	skipper.call("_finish")
	await get_tree().process_frame
	fails += _true("스킵해도 회차가 완료되지 않는다", not StoryProgress.seen(EP))
	fails += _eq("스킵 뒤에도 미션은 그대로", StoryProgress.pending_episode(), EP)
	skipper.queue_free()
	await get_tree().process_frame

	var c0 := StoryProgress.count(EP)
	var adv := _enter_dungeon({})
	await get_tree().process_frame
	fails += _eq("던전에 들어서면 1회 오른다", StoryProgress.count(EP), c0 + 1)
	adv.queue_free()
	await get_tree().process_frame
	var c1 := StoryProgress.count(EP)
	if UserDB.dragons().is_empty():
		UserDB.add_dragon(1, 10)
	var adv2 := _enter_dungeon({"party_uids": [UserDB.active_uid()],
		"party_ready": true, "enc": 1})
	await get_tree().process_frame
	fails += _eq("이어지는 조우는 다시 세지 않는다", StoryProgress.count(EP), c1)
	adv2.queue_free()
	await get_tree().process_frame

	fails += _eq("낮은 그대로", StoryProgress.place_name({"field": 14}), "칼바람의 산맥")
	fails += _eq("밤은 (밤)", StoryProgress.place_name({"field": 14, "night": true}),
		"칼바람의 산맥(밤)")
	fails += _eq("카데스는 (카데스의 공간)", StoryProgress.place_name({"field": 14, "kades": 1}),
		"칼바람의 산맥(카데스의 공간)")
	fails += _eq("던전 이름도 위상을 붙인다",
		Data.stage_display_name(Data.stage("514")), "칼바람의 산맥(밤)")
	fails += _eq("팝업 제목은 축약", Data.stage_display_name(Data.stage("614"), true),
		"칼바람의 산맥(카데스)")
	var sp84: Dictionary = Data.story_episode(84).get("submission", {})
	fails += _eq("84화 = 수중동굴(밤) 고가",
		"%s / %s" % [StoryProgress.place_name(sp84), StoryProgress.target_name(sp84)],
		"수중동굴(밤) / 고가 (Goga)")
	var sp94: Dictionary = Data.story_episode(94).get("submission", {})
	fails += _true("94화 목표 이름: %s" % StoryProgress.target_name(sp94),
		StoryProgress.target_name(sp94).contains("제우스 주니어"))

	var done := 0
	for i in int(sp.get("count", 0)) - StoryProgress.count(EP):
		done = StoryProgress.note_event({"kind": "ADVENTURE", "field": 1, "region": "yutakan"})
	fails += _eq("5회째에 완료 신호", done, EP)
	fails += _eq("완료 뒤 수행 중 미션 없음", StoryProgress.pending_episode(), 0)

	var story2 := _open()
	await get_tree().process_frame
	fails += _true("이어보기가 발급 줄 뒤에서 시작한다 (_idx=%d > %d)"
		% [int(story2.get("_idx")), brk], int(story2.get("_idx")) > brk)
	story2.queue_free()

	if fails == 0:
		print("[test_story_mission_flow] ALL PASS")
	else:
		print("[test_story_mission_flow] %d FAIL" % fails)
	get_tree().quit()

func _enter_dungeon(extra: Dictionary) -> Node:
	var packed: PackedScene = load("res://scenes/adventure.tscn")
	var s := packed.instantiate()
	var p := {"stage": "1", "region": "yutakan", "hero": false, "night": false, "run_seed": 1}
	p.merge(extra, true)
	s.call("enter", p)
	add_child(s)
	return s

func _open() -> Node:
	var packed: PackedScene = load("res://scenes/story.tscn")
	var s := packed.instantiate()
	s.call("enter", {"no": EP, "part": 0, "back": "worldmap"})
	add_child(s)
	return s

func _eq(what: String, got, want) -> int:
	if got == want:
		print("  ok   %s = %s" % [what, str(got)])
		return 0
	print("  FAIL %s = %s (기대 %s)" % [what, str(got), str(want)])
	return 1

func _true(what: String, cond: bool) -> int:
	print(("  ok   " if cond else "  FAIL ") + what)
	return 0 if cond else 1
