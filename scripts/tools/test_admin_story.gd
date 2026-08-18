extends SceneTree

const EP := 5
const KEY := "0_11"
const WANT_EXPR := 5
const WANT_MOUTH := 2

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails := 0
	var data := root.get_node_or_null("/root/Data")
	var user_db := root.get_node_or_null("/root/UserDB")

	var ov: Dictionary = data.call("admin_story_line", EP, KEY)
	fails += _true("%d화 %s 개작 존재" % [EP, KEY], not ov.is_empty())
	fails += _eq("초상 NPC", String(ov.get("npc", "")), "sundaegun")
	fails += _eq("표정", int(ov.get("expr", 0)), WANT_EXPR)
	fails += _eq("정지 입", int(ov.get("mouth", 0)), WANT_MOUTH)
	fails += _true("없는 줄은 빈 값",
		(data.call("admin_story_line", EP, "0_1") as Dictionary).is_empty())
	fails += _eq("기본 위치", int(data.call("admin_story_default", "pos", -1)), 2)

	var spk: Dictionary = data.call("story_speaker", 70, "0_1")
	fails += _eq("70화 0_1 화자 이름", String(spk.get("name", "")), "란돌프")
	fails += _eq("70화 0_1 화자 폴더", String(spk.get("npc", "")), "randolph")
	fails += _true("화자 복원은 개작 블록에 없다",
		(data.call("admin_story_line", 70, "0_1") as Dictionary).is_empty())
	fails += _eq("78화 화자 복원 있음", (data.call("story_speaker", 78, "0_1") as Dictionary).is_empty(), false)
	var face39: Dictionary = data.call("admin_story_line", 39, "0_3")
	fails += _eq("39화 0_3 초상", String(face39.get("npc", "")), "sundaegun")
	fails += _true("39화 0_3 표정 기입 복구", int(face39.get("expr", 0)) > 0)
	fails += _true("101화 표정 기입 있음",
		not (data.call("admin_story_line", 101, "0_1") as Dictionary).is_empty())
	fails += _eq("86화 2_22 화자(시트 우선)",
		String((data.call("story_speaker", 86, "2_22") as Dictionary).get("name", "")), "즈믄")
	fails += _eq("86화 2_23 화자(시트 우선)",
		String((data.call("story_speaker", 86, "2_23") as Dictionary).get("name", "")), "누리")

	var packed: PackedScene = load("res://scenes/story.tscn")
	var story := packed.instantiate()
	story.call("enter", {"no": EP, "part": 0, "back": "worldmap"})
	root.add_child(story)
	await process_frame
	await process_frame

	var reached := false
	for _i in 200:
		var keys: PackedStringArray = story.get("_line_keys")
		var idx := int(story.get("_idx")) - 1
		if idx >= 0 and idx < keys.size() and keys[idx] == KEY:
			reached = true
			break
		story.call("_reveal_all")
		story.call("_advance")
		await process_frame
	fails += _true("%d화 %s 줄에 도달" % [EP, KEY], reached)

	if reached:
		var talker: Node2D = story.get("_talker")
		if user_db.call("is_admin"):
			fails += _true("ADMIN: 선대군 초상이 선다",
				talker != null and String(talker.get("npc_name")) == "sundaegun")
			if talker != null:
				fails += _eq("ADMIN: 표정", int(talker.get("_art_emo")), WANT_EXPR)
				fails += _true("ADMIN: 대사 중 입 움직임", bool(talker.get("_talking")))
				story.call("_reveal_all")
				var fr: Array = talker.get("_mouth_fr")
				var i := int(talker.get("_mouth_i"))
				fails += _eq("ADMIN: 정지 입 프레임",
					int(fr[i]) if i >= 0 and i < fr.size() else -1, WANT_MOUTH)
				fails += _eq("ADMIN: 이름칸", String((story.get("_name_label") as Label).text), "선대군")
		else:
			fails += _true("일반: 선대군이 서지 않는다",
				talker == null or String(talker.get("npc_name")) != "sundaegun")
			var slots: Dictionary = story.get("_npc_slots")
			for p in slots.values():
				fails += _true("일반: 어떤 슬롯에도 선대군 없음",
					String(p.get("npc_name")) != "sundaegun")

	story.queue_free()
	await process_frame
	if fails == 0:
		print("[test_admin_story] PASS (ADMIN=%s)" % user_db.call("is_admin"))
	quit(1 if fails else 0)

func _true(what: String, ok: bool) -> int:
	if not ok:
		print("FAIL: %s" % what)
	return 0 if ok else 1

func _eq(what: String, got, want) -> int:
	if got != want:
		print("FAIL: %s — got %s want %s" % [what, got, want])
		return 1
	return 0
