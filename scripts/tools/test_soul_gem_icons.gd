extends SceneTree
## 헤드리스 소울젬 아이콘 배선 스모크 (§8 — 오토로드 없이 데이터/리소스만 본다).
## 실행: godot --headless --path . --script res://scripts/tools/test_soul_gem_icons.gd --quit-after 3
##
## 확인 항목
##   ① 위키에서 복원한 gem_soul 40장(4종 × 10단계)이 실제로 로드되고 형제 젬과 같은 95×95 인가
##   ② icon_map 에 폴백(fallback) 표시가 하나도 남아 있지 않은가
##      — 종전엔 소울젬이 같은 축 일반젬 최고티어 그림을 빌려 써서 가방에서 구분이 안 됐다
##   ③ 일반·혼성 190키가 그대로인가

func _init() -> void:
	var fails := 0
	var m: Dictionary = (JSON.parse_string(FileAccess.open(
		"res://data/icon_map.json", FileAccess.READ).get_as_text()) as Dictionary).get("gem", {})

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
