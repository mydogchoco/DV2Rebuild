extends SceneTree

func _init() -> void:
	var fails := 0
	var dragons: Array = _json(_data_file("dragons.json"))
	var voices: Dictionary = (_json(_data_file("dragon_voices.json")) as Dictionary).get("voices", {})
	var aw: Dictionary = _json(_data_file("skill_awaken.json"))
	var by_dragon: Dictionary = aw.get("by_dragon", {})

	var named := 0
	var with_desc := 0
	var nbsp := 0
	for d in dragons:
		if bool((d as Dictionary).get("name_from_player", false)):
			continue
		named += 1
		var s := String((d as Dictionary).get("desc", ""))
		if s != "":
			with_desc += 1
		if s.contains(char(0xA0)):
			nbsp += 1
		if s == "":
			print("  · 설명 미기입: id=%d %s" % [int((d as Dictionary).get("id", 0)),
					String((d as Dictionary).get("name", ""))])
	fails += _true("도감 설명 370종 이상 실림 (있음 %d / 이름있는 종 %d)" % [with_desc, named],
			with_desc >= 370)
	fails += _true("설명에 U+00A0 없음 (발견 %d)" % nbsp, nbsp == 0)

	var no_set := {}
	for s in (aw.get("skills", []) as Array):
		no_set[int((s as Dictionary).get("no", -1))] = true
	var assigned := 0
	var drift := 0
	var unknown_no := 0
	for d in dragons:
		var did := int((d as Dictionary).get("id", 0))
		var own := int((d as Dictionary).get("awaken_skill", 0))
		var lst: Array = []
		for v in (by_dragon.get(str(did), []) as Array):
			lst.append(int(v))
		if own > 0:
			assigned += 1
			if not no_set.has(own):
				unknown_no += 1
				print("  ✗ id=%d 각성스킬 no=%d 가 skill_awaken.json 에 없다" % [did, own])
			if not lst.has(own):
				drift += 1
				print("  ✗ id=%d dragons.csv=%d 인데 비고 배정=%s" % [did, own, str(lst)])
		elif not lst.is_empty():
			drift += 1
			print("  ✗ id=%d dragons.csv 는 비었는데 비고 배정=%s" % [did, str(lst)])
	fails += _true("각성스킬 140종 배정 (실제 %d)" % assigned, assigned == 140)
	fails += _true("두 시트 배정 일치 (드리프트 %d)" % drift, drift == 0)
	fails += _true("모든 배정이 실재하는 스킬 no (미상 %d)" % unknown_no, unknown_no == 0)

	var missing := 0
	var covered := 0
	for k in voices:
		var e: Dictionary = voices[k]
		for st in ["baby", "child", "adult"]:
			var n := int(e.get(st, 0))
			if n <= 0:
				continue
			if not FileAccess.file_exists("res://assets/music/voice%d.mp3" % n):
				missing += 1
				print("  ✗ id=%s %s → voice%d.mp3 없음" % [k, st, n])
	for d in dragons:
		if bool((d as Dictionary).get("name_from_player", false)):
			continue
		if voices.has(str(int((d as Dictionary).get("id", 0)))):
			covered += 1
	fails += _true("보이스 파일 전부 실재 (없음 %d)" % missing, missing == 0)
	fails += _true("이름 있는 종 전부 보이스 배정 (%d / %d)" % [covered, named], covered >= named)

	if fails == 0:
		print("[test_dragon_sheet] ALL PASS  (설명 %d · 각성 %d · 보이스 %d종)"
				% [with_desc, assigned, voices.size()])
	else:
		print("[test_dragon_sheet] FAIL %d" % fails)
	quit(1 if fails > 0 else 0)

func _true(label: String, ok: bool) -> int:
	print(("  ok  " if ok else "  FAIL ") + label)
	return 0 if ok else 1

func _json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	return JSON.parse_string(f.get_as_text())

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
