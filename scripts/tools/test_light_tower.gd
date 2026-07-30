extends SceneTree
## 헤드리스 빛의 탑 속성회전 테스트 (§8).
## 원작 근거: WorldMapYutakanLayer::showLightTower @01b3a710
##   - tm_hour % 8 → 속성코드(:6990~7042)  0=A 1=C 2=D 3=E 4=F 5=H 6=L 7=W
##   - 코드 → map_yutakan_new/map_tower_*.png (:7100~)
## 실행: godot --headless --path . --script res://scripts/tools/test_light_tower.gd --quit-after 3

func _init() -> void:
	var fails := 0
	var wm = JSON.parse_string(FileAccess.open("res://data/worldmap.json", FileAccess.READ).get_as_text())
	var nat: Dictionary = (wm["regions"][0] as Dictionary)["native"]
	var lt: Dictionary = nat.get("light_tower", {})
	var dir := String(nat["atlas_dir"])

	# 원작 첫 switch(A C D E F H L W)를 속성명으로 그대로 옮겼는지.
	fails += _eq("hour_cycle", str(lt.get("hour_cycle", [])),
			str(["water", "chaos", "dark", "ground", "fire", "holy", "light", "wind"]))
	# 원작 두 번째 switch 는 9종(normal 포함).
	var frames: Dictionary = lt.get("frames", {})
	fails += _eq("frames 9종", frames.size(), 9)

	# 프레임이 전부 실제 변환 산출물로 존재하는가.
	var missing := 0
	for code in frames:
		if not ResourceLoader.exists("res://assets/converted/%s/%s.tres" % [dir, String(frames[code])]):
			missing += 1
			print("  없음: ", frames[code])
	fails += _eq("아트 파일 누락", missing, 0)

	# 24시간 전수: 매 시각이 표에 있는 코드로 풀리고, 8시간 주기로 반복한다.
	var cycle: Array = lt["hour_cycle"]
	var seen := {}
	for h in range(24):
		var code := String(cycle[h % cycle.size()])
		if not frames.has(code):
			fails += _eq("시각 %d 코드 %s 프레임" % [h, code], "없음", "있음")
		seen[code] = true
		if h >= 8:
			fails += _eq("h%d == h%d 주기" % [h, h - 8], code, String(cycle[(h - 8) % cycle.size()]))
	fails += _eq("24시간에 등장하는 속성", seen.size(), 8)
	# normal(기본형)은 회전에 안 나온다 — 원작 첫 switch 에 없다.
	fails += _eq("normal 은 회전 제외", seen.has("normal"), false)

	# 조각이 회전 표를 가리키는가.
	var tower_pieces := 0
	for p in (wm["regions"][0] as Dictionary).get("pieces", []):
		if String((p as Dictionary).get("frame_from", "")) == "light_tower":
			tower_pieces += 1
			fails += _eq("조각 field", int((p as Dictionary).get("field", -1)), 15)
	fails += _eq("light_tower 조각 수", tower_pieces, 1)

	print("실패 %d" % fails)
	quit(1 if fails > 0 else 0)


func _eq(name: String, got, want) -> int:
	if str(got) == str(want):
		print("  OK  %s = %s" % [name, str(got)])
		return 0
	print("  FAIL %s: got %s, want %s" % [name, str(got), str(want)])
	return 1
