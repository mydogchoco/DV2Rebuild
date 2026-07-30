extends SceneTree
## 헤드리스 장비 아이콘 배선 스모크 (§8 — 오토로드 없이 데이터/리소스만 본다).
## 실행: godot --headless --path . --script res://scripts/tools/test_equip_icons.gd --quit-after 3
##
## 2026-07-31 위키 복원분 검증. 확인 항목
##   ① 구현 대상 장비가 **하나도 빠짐없이** 아이콘을 갖는가
##      (일반 38 · 아티팩트 36 · 이벤트 25 · 특수 12 · 편린 6)
##   ② 전용 장비 95종 아이콘이 행 번호 키로 전부 들어와 있는가(수치 부재로 카탈로그엔 미등재)
##   ③ 모든 프레임이 실제로 로드되고 형제 규격 95×95 인가

const E := preload("res://scripts/systems/equipment.gd")

func _init() -> void:
	var fails := 0
	var eq: Dictionary = _json("res://data/equipment.json")
	var im: Dictionary = _json("res://data/icon_map.json")

	# ① 카탈로그 전량 — 키에서 섹션/논리키를 뽑아 icon_map 을 친다(Icons.equip_texture 와 같은 규약).
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
		var e: Dictionary = (im.get(sec, {}) as Dictionary).get(key, {})
		if e.is_empty():
			fails += _fail("카탈로그 %s → icon_map %s/%s 없음" % [k, sec, key]); miss += 1
		else:
			fails += _load_ok(e, k)
	print("카탈로그 %d종 · 아이콘 누락 %d" % [cat.size(), miss])
	fails += _eq("카탈로그 크기", cat.size(), 38 + 25 + 12 + 36)

	# ② 편린 6 · 전용 95
	for p in (eq["pieces"]["list"] as Array):
		var pe: Dictionary = (im.get("piece", {}) as Dictionary).get(String(p["name"]), {})
		if pe.is_empty():
			fails += _fail("편린 아이콘 없음: %s" % p["name"])
		else:
			fails += _load_ok(pe, String(p["name"]))
	var exl: Array = eq["exclusive"]["list"]
	var ex_ok := 0
	for i in exl.size():
		var xe: Dictionary = (im.get("exclusive", {}) as Dictionary).get(str(i), {})
		if xe.is_empty():
			fails += _fail("전용 장비 아이콘 없음: index %d" % i)
		else:
			fails += _load_ok(xe, "exclusive:%d" % i)
			ex_ok += 1
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
	# 원본 아틀라스 프레임은 여백을 잘라내 크기가 제각각이다(src 가 95×95). 위키 복원분만
	# 캔버스 그대로이므로 그쪽만 규격을 본다.
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
