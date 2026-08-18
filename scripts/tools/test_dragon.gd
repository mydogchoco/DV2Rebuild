extends SceneTree

func _init() -> void:
	var fails := 0
	var draw = _load(_data_file("dragons.json"))
	var dragons = draw.get("dragons", draw) if typeof(draw) == TYPE_DICTIONARY else draw
	if typeof(dragons) == TYPE_DICTIONARY:
		dragons = dragons.values()
	var stat_table = _load(_data_file("stat_table.json"))
	fails += _b("dragons 로드", typeof(dragons) == TYPE_ARRAY and dragons.size() >= 1)
	fails += _b("stat_table 로드", typeof(stat_table) == TYPE_DICTIONARY and stat_table.size() >= 1)

	var VALID_EL := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow"]
	var checked := 0
	var with_stages := 0
	var bad_stat := 0
	for d in dragons:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if not bool(d.get("name_from_player", false)):
			fails += _b("dragon.name", _s(d.get("name")).strip_edges() != "")
		fails += _b("dragon.element valid", _s(d.get("element")) in VALID_EL or _s(d.get("element")) in ["None",""])
		fails += _b("dragon.type(getAttackType)", _s(d.get("type")).strip_edges() != "")
		fails += _b("dragon.star>0(getDragonStarClass)", _num(d.get("star", 0)) > 0.0)
		var stats = Growth.compute_stats(d, stat_table, 30, {})
		if int(stats.get("hp", 0)) <= 0 or int(stats.get("att", 0)) <= 0:
			bad_stat += 1
			if bad_stat <= 5:
				printerr("FAIL stat pipeline: id=%s type=%s tier=%s hp=%s" % [d.get("id"), d.get("type"), d.get("stat_tier"), stats.get("hp")])
		if d.has("stages") and typeof(d["stages"]) in [TYPE_ARRAY, TYPE_DICTIONARY] and d["stages"].size() >= 1:
			with_stages += 1
		checked += 1

	fails += _b("전 드래곤 스탯 파이프라인 유효", bad_stat == 0)
	print("[test_dragon] %d 드래곤: 코어필드 완비, 스탯파이프라인 정상 %d, 진화stages 보유 %d" % [checked, checked - bad_stat, with_stages])

	if fails == 0:
		print("[test_dragon] ALL PASS")
	else:
		printerr("[test_dragon] %d FAIL (bad_stat=%d)" % [fails, bad_stat])
	quit(0 if fails == 0 else 1)

func _load(p: String):
	var f := FileAccess.open(p, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}

func _s(v) -> String:
	return "" if v == null else str(v)

func _num(v) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT: return float(v)
		TYPE_STRING: return float(v) if (v as String).is_valid_float() else 0.0
	return 0.0

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
