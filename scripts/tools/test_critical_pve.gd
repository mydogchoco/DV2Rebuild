extends SceneTree
func _initialize() -> void:
	var vis := Vector2(1024, 692)
	var da := DirAccess.open("res://assets/converted")
	var checked := 0
	var no_frame := 0
	var bad_fit := []
	var sizes := {}
	for sub in da.get_directories():
		if not sub.begins_with("critical_"):
			continue
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % sub, FileAccess.READ)
		if f == null:
			continue
		var man = JSON.parse_string(f.get_as_text())
		if not (man is Dictionary):
			continue
		var id := sub.trim_prefix("critical_")
		var key := "dragon_dragon_%s_critical_critical" % id
		if not man.has(key):
			no_frame += 1
			continue
		checked += 1
		var src: Array = man[key].get("src", [man[key].get("w", 0), man[key].get("h", 0)])
		var w := float(src[0])
		var h := float(src[1])
		sizes["%dx%d" % [int(w), int(h)]] = int(sizes.get("%dx%d" % [int(w), int(h)], 0)) + 1
		var s := vis.x / w
		var fit_h := h * s
		if absf(fit_h - vis.y) / vis.y > 0.08:
			bad_fit.append("%s %dx%d -> h=%d" % [sub, int(w), int(h), int(fit_h)])
		if checked <= 5:
			var p := "res://assets/converted/%s/%s.tres" % [sub, key]
			if not ResourceLoader.exists(p) or load(p) == null:
				bad_fit.append("%s 로드 실패" % sub)
	print("critical 프레임 보유 드래곤: %d (프레임 없음 %d)" % [checked, no_frame])
	print("크기 분포: %s" % [sizes])
	print("화면 꽉 채우기 실패(±8%% 초과): %d %s" % [bad_fit.size(), bad_fit.slice(0, 5)])

	var hits := 0
	var cf := FileAccess.open(_data_file("combat.json"), FileAccess.READ)
	if cf:
		var cd = JSON.parse_string(cf.get_as_text())
		if cd is Dictionary:
			hits = int((cd.get("judge", {}) as Dictionary).get("crit_hits", 0))
	print("combat.json judge.crit_hits = %d" % hits)
	var bad := bad_fit.size() + (0 if hits >= 1 else 1)
	print("결과: %s" % ("PASS" if bad == 0 else "FAIL(%d)" % bad))
	quit(0 if bad == 0 else 1)

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
