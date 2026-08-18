extends SceneTree
const T := preload("res://scripts/systems/titles.gd")

func _init() -> void:
	var fails := 0
	var table = JSON.parse_string(FileAccess.open(_data_file("titles.json"), FileAccess.READ).get_as_text())
	var list: Array = table["titles"]
	fails += _eq("칭호 149종", list.size(), 149)
	var bad := 0
	for t in list:
		var td := t as Dictionary
		if String(td.get("frame", "")) == "" or (td.get("unlock", {}) as Dictionary).is_empty():
			bad += 1
	fails += _eq("프레임·조건 누락", bad, 0)
	var missing := 0
	for t in list:
		var p := "res://assets/converted/%s/%s.tres" % [String(table["atlas_dir"]), String((t as Dictionary)["frame"])]
		if not ResourceLoader.exists(p):
			missing += 1
	fails += _eq("아트 파일 누락", missing, 0)
	fails += _eq("진행0 해금", T.unlocked_nos({}, table).size(), 0)
	var maxed := {"dragons": 999, "hatches": 9999, "battles": 99999,
			"max_level": 99, "gold": 99999999}
	fails += _eq("만렙 해금", T.unlocked_nos(maxed, table).size(), 149)
	var part := {"dragons": 5}
	var view := T.sorted_for_view(part, table)
	var first_locked := -1
	for i in view.size():
		if not T.is_unlocked(view[i], table if false else part):
			first_locked = i; break
	var all_before_ok := true
	for i in view.size():
		var un := T.is_unlocked(view[i], part)
		if first_locked >= 0 and i > first_locked and un:
			all_before_ok = false
	fails += _true("획득분이 앞쪽에 정렬", all_before_ok)
	var t1 := T.by_no(int(list[0]["title_no"]), table)
	fails += _true("진행률 0~1", T.progress_ratio(t1, {}) >= 0.0 and T.progress_ratio(t1, maxed) == 1.0)
	if fails == 0: print("[test_titles] ALL PASS")
	else: printerr("[test_titles] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _eq(l: String, g, w) -> int:
	if g == w: return 0
	printerr("  FAIL %s: got=%s want=%s" % [l, str(g), str(w)]); return 1
func _true(l: String, c: bool) -> int:
	if c: return 0
	printerr("  FAIL %s" % l); return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
