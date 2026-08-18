extends SceneTree

func _init() -> void:
	var fails := 0
	var m: Dictionary = (JSON.parse_string(FileAccess.open(
		_data_file("icon_map.json"), FileAccess.READ).get_as_text()) as Dictionary).get("gem", {})

	var ok := 0
	for c: String in ["SOULATT", "SOULDEF", "SOULHP", "SOULALL"]:
		for t in 10:
			var key := "%s:%d" % [c, t]
			var e: Dictionary = m.get(key, {})
			if e.is_empty():
				fails += _fail("icon_map 에 %s 없음" % key)
				continue
			if e.has("fallback"):
				fails += _fail("%s 가 아직 폴백(남의 아이콘)" % key)
				continue
			var p := "res://assets/converted/%s/%s.tres" % [String(e["dir"]), String(e["frame"])]
			if not ResourceLoader.exists(p):
				fails += _fail("리소스 없음 %s" % p)
				continue
			var tex: Texture2D = load(p)
			if tex == null:
				fails += _fail("로드 실패 %s" % p)
			elif tex.get_width() != 95 or tex.get_height() != 95:
				fails += _fail("%s 규격 %dx%d (형제 젬은 95x95)"
					% [key, tex.get_width(), tex.get_height()])
			else:
				ok += 1
	print("소울젬 텍스처 %d/40 로드" % ok)

	var normal := 0
	var fb := 0
	for k: String in m:
		if not k.begins_with("SOUL"):
			normal += 1
		if (m[k] as Dictionary).has("fallback"):
			fb += 1
	fails += _eq("일반·혼성 젬 키 수", normal, 190)
	fails += _eq("남은 폴백 수", fb, 0)

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _fail(msg: String) -> int:
	print("  ✗ ", msg)
	return 1

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  ✗ %s: %s (기대 %s)" % [label, got, want])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
