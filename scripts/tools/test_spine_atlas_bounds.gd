extends SceneTree

const ROOT := "res://assets/converted"

const KNOWN_PAGE_MISSING := [4138, 4204, 4205, 4210]

func _initialize() -> void:
	var fails := 0
	var dirs := PackedStringArray()
	var da := DirAccess.open(ROOT)
	if da == null:
		print("  ✗ %s 를 열 수 없다" % ROOT)
		quit(1)
		return
	for sub in da.get_directories():
		if sub.begins_with("dragon_") or sub.begins_with("monster_"):
			dirs.append(sub)

	var page_size := {}
	var skeletons := 0
	var slots_checked := 0
	var page_missing := {}
	for sub in dirs:
		var d2 := DirAccess.open("%s/%s" % [ROOT, sub])
		if d2 == null:
			continue
		for fn in d2.get_files():
			if not fn.ends_with(".json") or fn.begins_with("_"):
				continue
			var path := "%s/%s/%s" % [ROOT, sub, fn]
			var txt := FileAccess.get_file_as_string(path)
			if txt.is_empty():
				fails += _fail("빈 파일 %s" % path)
				continue
			var data = JSON.parse_string(txt)
			if not (data is Dictionary):
				fails += _fail("파싱 실패 %s" % path)
				continue
			skeletons += 1
			var outside := 0
			var nullpng := 0
			for s in (data as Dictionary).get("slots", []):
				var png = s.get("png")
				if png == null or String(png).is_empty():
					nullpng += 1
					continue
				var key := String(png)
				if not page_size.has(key):
					page_size[key] = _png_size(key)
				var sz: Vector2i = page_size[key]
				if sz == Vector2i.ZERO:
					fails += _fail("페이지 PNG 를 못 읽었다: %s (%s)" % [key, path])
					page_size[key] = Vector2i(1 << 30, 1 << 30)
					continue
				var rr = s.get("region_rect", [])
				if (rr as Array).size() != 4:
					fails += _fail("region_rect 형식 오류 %s / %s" % [path, s.get("name")])
					continue
				slots_checked += 1
				var x := int(rr[0]); var y := int(rr[1])
				var w := int(rr[2]); var h := int(rr[3])
				if x < 0 or y < 0 or x + w > sz.x or y + h > sz.y:
					outside += 1
			if outside > 0:
				fails += _fail("%s: 슬롯 %d개가 텍스처 밖 (판본 불일치 아틀라스 의심 — %s)"
					% [path, outside, "아틀라스 좌표가 텍스처 밖 — 판본 불일치"])
			if nullpng > 0:
				page_missing[_id_of(sub)] = true

	print("스켈레톤 %d개 · 슬롯 %d칸 · 페이지 %d장 검사"
		% [skeletons, slots_checked, page_size.size()])
	if skeletons == 0:
		fails += _fail("검사한 스켈레톤이 0개다 — 변환 산출물이 없다(spine_batch 먼저)")

	var got := page_missing.keys()
	got.sort()
	var want := KNOWN_PAGE_MISSING.duplicate()
	want.sort()
	if got == want:
		print("아틀라스 PNG 부재 %d종 — 알려진 목록과 일치(Icons.SPINE_TEXTURE_MISSING)" % got.size())
	else:
		for id in got:
			if not (id in want):
				fails += _fail("드래곤 %d 의 아틀라스 PNG 가 새로 없어졌다" % id)
		for id in want:
			if not (id in got):
				fails += _fail("드래곤 %d 가 복구됐다 — KNOWN_PAGE_MISSING 과 "
					% id + "Icons.SPINE_TEXTURE_MISSING 에서 뺄 것")
	await process_frame
	fails += _check_awaken_routing()

	print("=== %s ===" % ("PASS" if fails == 0 else "FAIL %d건" % fails))
	quit(0 if fails == 0 else 1)

func _png_size(res_path: String) -> Vector2i:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var head := f.get_buffer(24)
	f.close()
	if head.size() < 24 or head[1] != 0x50 or head[2] != 0x4E or head[3] != 0x47:
		return Vector2i.ZERO
	return Vector2i(_be32(head, 16), _be32(head, 20))

func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]

func _check_awaken_routing() -> int:
	var fails := 0
	var ic: GDScript = ResourceLoader.load("res://scripts/ui/icons.gd", "GDScript",
		ResourceLoader.CACHE_MODE_IGNORE)
	if ic == null:
		return _fail("icons.gd 를 로드하지 못했다")
	var ids: Array = ic.get("AWAKEN_SPINE_MISSING")
	var table: Dictionary = ic.get("AWAKEN_FALLBACK_STAGE")
	for id in ids:
		for stage in table:
			var want := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, table[stage]]
			if not ResourceLoader.exists(want):
				fails += _fail("대체원이 없다: %s" % want)
				continue
			var dead := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, stage]
			if ResourceLoader.exists(dead):
				fails += _fail("각성체 씬이 되살아났다: %s (AWAKEN_ATLAS_MISSING 확인)" % dead)
				continue
			var got: String = ic.spine_scene(id, stage)
			if got != want:
				fails += _fail("드래곤 %d %s → \"%s\" (기대 %s)" % [id, stage, got, want])
	print("각성체 대체 라우팅 %d종 확인" % ids.size())
	return fails

func _id_of(sub: String) -> int:
	return int(sub.get_slice("_", 1))

func _fail(msg: String) -> int:
	print("  ✗ ", msg)
	return 1
