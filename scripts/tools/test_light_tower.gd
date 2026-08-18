extends SceneTree

func _init() -> void:
	var fails := 0
	var wm = JSON.parse_string(FileAccess.open(_data_file("worldmap.json"), FileAccess.READ).get_as_text())
	var nat: Dictionary = (wm["regions"][0] as Dictionary)["native"]
	var lt: Dictionary = nat.get("light_tower", {})
	var dir := String(nat["atlas_dir"])

	fails += _eq("hour_cycle", str(lt.get("hour_cycle", [])),
			str(["water", "chaos", "dark", "ground", "fire", "holy", "light", "wind"]))
	var frames: Dictionary = lt.get("frames", {})
	fails += _eq("frames 9종", frames.size(), 9)

	var missing := 0
	for code in frames:
		if not ResourceLoader.exists("res://assets/converted/%s/%s.tres" % [dir, String(frames[code])]):
			missing += 1
			print("  없음: ", frames[code])
	fails += _eq("아트 파일 누락", missing, 0)

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
	fails += _eq("normal 은 회전 제외", seen.has("normal"), false)

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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
