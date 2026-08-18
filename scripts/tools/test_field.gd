extends SceneTree

func _init() -> void:
	var fails := 0
	var f := FileAccess.open(_data_file("stages.json"), FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text()) if f else {}
	var stages: Dictionary = {}
	if typeof(raw) == TYPE_DICTIONARY:
		stages = raw.get("stages", raw)
	fails += _b("stages 로드", stages.size() >= 1)

	var checked := 0
	var lost_present := 0
	for sid in stages.keys():
		if String(sid).begins_with("_"):
			continue
		var st = stages[sid]
		if typeof(st) != TYPE_DICTIONARY:
			continue
		fails += _b("st[%s].name" % sid, String(st.get("name", "")).strip_edges() != "")
		fails += _b("st[%s].level>0" % sid, _num(st.get("level", 0)) > 0.0)
		var enemies = st.get("enemies", [])
		fails += _b("st[%s].enemies>=1" % sid, typeof(enemies) == TYPE_ARRAY and enemies.size() >= 1)
		if typeof(enemies) == TYPE_ARRAY:
			for e in enemies:
				if typeof(e) != TYPE_DICTIONARY:
					fails += _b("st[%s] enemy dict" % sid, false)
					continue
				fails += _b("st[%s] enemy id>0" % sid, _num(e.get("id", 0)) > 0.0)
				fails += _b("st[%s] enemy hp>0" % sid, _num(e.get("hp_max", 0)) > 0.0)
		if st.has("soundPath") or st.has("dragonArr"):
			lost_present += 1
		checked += 1

	print("[test_field] Field 오프라인필드 검증: %d 던전(name/level/enemies 완비). 유실필드(soundPath/dragonArr) 보유 %d(0 정상)" % [checked, lost_present])

	if fails == 0:
		print("[test_field] ALL PASS")
	else:
		printerr("[test_field] %d FAIL" % fails)
	quit(0 if fails == 0 else 1)

func _num(v) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return float(v) if (v as String).is_valid_float() else 0.0
	return 0.0

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
