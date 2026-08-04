extends SceneTree
## 스토리 씬 진입 회귀 테스트.
## 실행: godot --headless --path . --script res://scripts/tools/test_story_scene.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fails := 0
	var user_db := root.get_node_or_null("/root/UserDB")
	var progress = load("res://scripts/core/story_progress.gd")
	user_db.call("begin_batch") # 테스트 진행도는 디스크에 기록하지 않는다.
	user_db.call("set_progress", "scenario_44_0", true)
	fails += _true("44화 관람 직후 45화 즉시 해금", progress.unlocked(45))
	for no in range(140, 147):
		fails += _true("%d화 영구 잠금" % no, not progress.unlocked(no))
	fails += _true("스토리 목록 스크립트 로드", load("res://scripts/ui/mission_layer.gd") != null)
	fails += _true("월드맵 스크립트 로드", load("res://scenes/worldmap.tscn") != null)
	var packed: PackedScene = load("res://scenes/story.tscn")
	if packed == null:
		print("FAIL: story.tscn 로드 실패")
		quit(1)
		return
	var data := root.get_node_or_null("/root/Data")
	var checked := 0
	for no in range(1, 140):
		var story := packed.instantiate()
		story.call("enter", {"no": no, "part": 0, "back": "worldmap"})
		root.add_child(story)
		await process_frame
		await process_frame

		var lines := story.get("_lines") as Array
		var label := story.get("_label") as Label
		fails += _true("%d화 대사 로드" % no, not lines.is_empty())
		fails += _true("%d화 첫 대사 표시" % no, label != null and label.text != "")
		var initial_bg := String(data.call("scenario_initial_bg", no))
		if initial_bg != "":
			var resolved := String(story.call("_bg_res", initial_bg))
			var bg := story.get("_bg_layer") as TextureRect
			fails += _true("%d화 초기 배경 경로 해석" % no, resolved != "")
			fails += _true("%d화 초기 배경 표시" % no,
				bg != null and bg.texture != null and bg.visible)
		if no == 45:
			fails += _eq("45화 대사 수", lines.size(), 23)
			fails += _true("45화 진행 흐름 존재", not (story.get("_flow") as Array).is_empty())
		if no == 20 or no == 26:
			fails += _true("%d화 미보유 who 초상 미생성" % no,
				(story.get("_npc_slots") as Dictionary).is_empty())
		checked += 1
		story.queue_free()
		await process_frame

	fails += _eq("구현 회차 진입 검사 수", checked, 139)
	packed = null
	progress = null
	data = null
	user_db = null
	for i in 3:
		await process_frame

	print("\n[test_story_scene] ", "PASS (%d화 전수)" % checked if fails == 0 else "FAIL %d건" % fails)
	quit(1 if fails > 0 else 0)


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
