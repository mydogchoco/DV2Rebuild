extends SceneTree

const E := preload("res://scripts/systems/equipment.gd")

func _init() -> void:
	var fails := 0
	var eq: Dictionary = _json(_data_file("equipment.json"))
	var im: Dictionary = _json(_data_file("icon_map.json"))

	var cat := E.catalog(eq)
	var miss := 0
	for k: String in cat:
		var parts := k.split(":")
		var sec := ""
		var key := ""
		match parts[0]:
			"basic":
				sec = "equipment_basic"; key = "%s:%s" % [parts[1], parts[2]]
			"artifact":
				sec = "artifact"; key = "%s:%s" % [parts[1], parts[2]]
			"event":
				sec = "event"; key = parts[1]
			"special":
				sec = "special"; key = "%s:%s" % [parts[1], parts[2]]
			"exclusive":
				sec = "exclusive"; key = String(cat[k].get("name", ""))
		var e: Dictionary = (im.get(sec, {}) as Dictionary).get(key, {})
		if e.is_empty():
			fails += _fail("카탈로그 %s → icon_map %s/%s 없음" % [k, sec, key]); miss += 1
		else:
			fails += _load_ok(e, k)
	print("카탈로그 %d종 · 아이콘 누락 %d" % [cat.size(), miss])
	fails += _eq("카탈로그 크기", cat.size(), 38 + 25 + 12 + 36 + 97)

	for p in (eq["pieces"]["list"] as Array):
		var pe: Dictionary = (im.get("piece", {}) as Dictionary).get(String(p["name"]), {})
		if pe.is_empty():
			fails += _fail("편린 아이콘 없음: %s" % p["name"])
		else:
			fails += _load_ok(pe, String(p["name"]))
	var exl: Array = eq["exclusive"]["list"]
	var ex_ok := 0
	for x in exl:
		var xd := x as Dictionary
		var nm := String(xd.get("name", ""))
		var xe: Dictionary = (im.get("exclusive", {}) as Dictionary).get(nm, {})
		if xe.is_empty():
			fails += _fail("전용 장비 아이콘 없음: %s" % nm)
		else:
			fails += _load_ok(xe, "exclusive:" + nm)
			ex_ok += 1
		if int(xd.get("dragon_id", 0)) <= 0:
			fails += _fail("전용 장비 대상 드래곤 미확정: %s" % nm)
	print("편린 %d · 전용 %d/%d 아이콘 보유" % [(eq["pieces"]["list"] as Array).size(), ex_ok, exl.size()])

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _load_ok(e: Dictionary, label: String) -> int:
	var p := "res://assets/converted/%s/%s.tres" % [String(e["dir"]), String(e["frame"])]
	if not ResourceLoader.exists(p):
		return _fail("리소스 없음 %s (%s)" % [p, label])
	var tex: Texture2D = load(p)
	if tex == null:
		return _fail("로드 실패 %s (%s)" % [p, label])
	if bool(e.get("from_wiki", false)) and (tex.get_width() != 95 or tex.get_height() != 95):
		return _fail("%s 규격 %dx%d (위키 복원분은 95x95)" % [label, tex.get_width(), tex.get_height()])
	return 0

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text()) as Dictionary

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
