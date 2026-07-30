extends SceneTree
## 헤드리스 검증 — 각성 스킬 시트 반영분(data/skill_awaken.json).
## 시트: docs/input/sheets/skill_awaken.csv (사용자 기입 2026-07-29)
## 빌드: scripts/tools/build_skill_awaken.py
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_skill_awaken.gd --quit-after 3

func _init() -> void:
	var fails := 0
	var d = _json("res://data/skill_awaken.json")
	var dragons = _json("res://data/dragons.json")

	var skills: Array = d.get("skills", [])
	# 원작 102종 + 자작 드래곤용 추가분. 시트가 늘 수 있으므로 하한만 못박는다.
	fails += _true("적어도 원작 102종은 있다 (%d)" % skills.size(), skills.size() >= 102)

	# no 는 1..102 연속·유일해야 한다(dragons 배정이 이 번호를 참조한다).
	var seen := {}
	for s in skills:
		var no := int((s as Dictionary).get("no", 0))
		fails += _true("no 중복 없음 (%d)" % no, not seen.has(no))
		seen[no] = true
		fails += _true("이름 있음 (no=%d)" % no, String((s as Dictionary).get("name", "")) != "")
		# 아이콘은 원작 자산 skill/evolution/1~18.png 범위 안이어야 한다.
		var ic := int((s as Dictionary).get("icon", 0))
		fails += _true("아이콘 1~18 (no=%d, icon=%d)" % [no, ic], ic >= 1 and ic <= 18)
		var p := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % ic
		fails += _true("아이콘 리소스 존재 (%d)" % ic, ResourceLoader.exists(p))

	# 배정: by_dragon 의 키는 실제 도감 id 여야 하고, 값은 위 no 집합 안이어야 한다.
	var ids := {}
	for dr in dragons:
		ids[int((dr as Dictionary)["id"])] = true
	var by: Dictionary = d.get("by_dragon", {})
	fails += _true("배정된 드래곤이 있다 (%d종)" % by.size(), by.size() > 0)
	for k in by:
		fails += _true("도감에 있는 id (%s)" % k, ids.has(int(k)))
		for no in (by[k] as Array):
			fails += _true("존재하는 각성스킬 no (%d)" % int(no), seen.has(int(no)))

	# skills[].dragons 와 by_dragon 은 같은 관계를 양방향으로 담는다 — 어긋나면 빌드 버그.
	var back := {}
	for s in skills:
		for did in ((s as Dictionary).get("dragons", []) as Array):
			back[str(int(did))] = true
	fails += _eq("양방향 색인 크기 일치", back.size(), by.size())

	# 시트 표본 — 사용자가 적은 그대로인지 몇 줄 찍어 본다.
	fails += _eq("no=1 이름", String(_find(skills, 1).get("name", "")), "각성된 드래곤의 감각")
	fails += _eq("no=1 아이콘", int(_find(skills, 1).get("icon", 0)), 14)
	# ⚠️ JSON 숫자는 Godot 에서 float 로 들어온다 — Array.has(16) 는 16.0 과 안 맞는다.
	fails += _true("피닉스(8)가 '공격의 날개'(16)", _has_no(by.get("8", []), 16))
	# 자작 드래곤(사용자가 dragons.csv/skill_awaken.csv 에 추가) — id 와 각성스킬이 이어졌나.
	fails += _true("샛별(666) → 각성스킬 666", _has_no(by.get("666", []), 666))
	fails += _true("한울(777) → 각성스킬 777", _has_no(by.get("777", []), 777))

	# 이름을 못 찾은 항목이 남아 있으면 알린다(치명은 아니지만 배정이 빠진다).
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
