extends SceneTree

func _init() -> void:
	var fails := 0
	var d = _json(_data_file("skill_awaken.json"))
	var dragons = _json(_data_file("dragons.json"))

	var skills: Array = d.get("skills", [])
	fails += _true("적어도 원작 102종은 있다 (%d)" % skills.size(), skills.size() >= 102)

	var seen := {}
	for s in skills:
		var no := int((s as Dictionary).get("no", 0))
		fails += _true("no 중복 없음 (%d)" % no, not seen.has(no))
		seen[no] = true
		fails += _true("이름 있음 (no=%d)" % no, String((s as Dictionary).get("name", "")) != "")
		var ic := int((s as Dictionary).get("icon", 0))
		fails += _true("아이콘 1~18 (no=%d, icon=%d)" % [no, ic], ic >= 1 and ic <= 18)
		var p := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % ic
		fails += _true("아이콘 리소스 존재 (%d)" % ic, ResourceLoader.exists(p))

	var ids := {}
	for dr in dragons:
		ids[int((dr as Dictionary)["id"])] = true
	var by: Dictionary = d.get("by_dragon", {})
	fails += _true("배정된 드래곤이 있다 (%d종)" % by.size(), by.size() > 0)
	for k in by:
		fails += _true("도감에 있는 id (%s)" % k, ids.has(int(k)))
		for no in (by[k] as Array):
			fails += _true("존재하는 각성스킬 no (%d)" % int(no), seen.has(int(no)))

	var back := {}
	for s in skills:
		for did in ((s as Dictionary).get("dragons", []) as Array):
			back[str(int(did))] = true
	fails += _eq("양방향 색인 크기 일치", back.size(), by.size())

	fails += _eq("no=1 이름", String(_find(skills, 1).get("name", "")), "각성된 드래곤의 감각")
	fails += _eq("no=1 아이콘", int(_find(skills, 1).get("icon", 0)), 14)
	fails += _true("피닉스(8)가 '공격의 날개'(16)", _has_no(by.get("8", []), 16))
	fails += _true("샛별(666) → 각성스킬 666", _has_no(by.get("666", []), 666))
	fails += _true("한울(777) → 각성스킬 777", _has_no(by.get("777", []), 777))

	if d.has("_unmatched_names"):
		printerr("  주의: 도감에서 못 찾은 드래곤 이름 %d건" % (d["_unmatched_names"] as Array).size())

	if fails == 0:
		print("[test_skill_awaken] ALL PASS  (skills %d / 배정 %d종)" % [skills.size(), by.size()])
		quit(0)
	else:
		printerr("[test_skill_awaken] %d FAIL" % fails)
		quit(1)

func _has_no(arr, no: int) -> bool:
	for v in (arr as Array):
		if int(v) == no:
			return true
	return false

func _find(skills: Array, no: int) -> Dictionary:
	for s in skills:
		if int((s as Dictionary).get("no", 0)) == no:
			return s
	return {}

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
