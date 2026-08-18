extends SceneTree

func _init() -> void:
	var fails := 0

	var mraw = _load(_data_file("monsters.json"))
	var monsters = mraw.get("monsters", mraw) if typeof(mraw) == TYPE_DICTIONARY else mraw
	if typeof(monsters) == TYPE_DICTIONARY:
		monsters = monsters.values()
	fails += _b("monsters 로드", typeof(monsters) == TYPE_ARRAY and monsters.size() >= 1)
	var m_ok := 0
	var m_scene := 0
	var VALID_EL := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow", "none",
		"무", "불", "물", "바람", "땅", "대지", "빛", "암흑", "어둠", "신성", "혼돈", "그림자"]
	for mo in monsters:
		if typeof(mo) != TYPE_DICTIONARY:
			continue
		fails += _b("monster.name", String(mo.get("name", "")).strip_edges() != "")
		fails += _b("monster.hp>0", _num(mo.get("hp", 0)) > 0.0)
		fails += _b("monster.att>=0", _num(mo.get("att", -1)) >= 0.0)
		fails += _b("monster.def>=0", _num(mo.get("def", -1)) >= 0.0)
		fails += _b("monster.element valid", String(mo.get("element", "none")) in VALID_EL)
		var aid := int(_num(mo.get("asset_id", 0)))
		if aid > 0 and ResourceLoader.exists("res://scenes/monsters/monster_%d.tscn" % aid):
			m_scene += 1
		m_ok += 1

	var iraw = _load(_data_file("items.json"))
	fails += _b("items 로드", typeof(iraw) == TYPE_DICTIONARY and iraw.size() >= 1)
	var i_ok := 0
	var i_icon := 0
	for key in iraw.keys():
		if String(key).begins_with("_"):
			continue
		var it = iraw[key]
		if typeof(it) != TYPE_DICTIONARY:
			continue
		fails += _b("item[%s].name" % key, String(it.get("name", "")).strip_edges() != "")
		fails += _b("item[%s].category" % key, String(it.get("category", "")).strip_edges() != "")
		if String(it.get("icon", "")).strip_edges() != "":
			i_icon += 1
		i_ok += 1

	print("[test_data_entities] Monster %d(코어필드 완비, spine씬연결 %d) · Item %d(코어필드 완비, icon %d)" % [m_ok, m_scene, i_ok, i_icon])
	fails += _b("monster spine씬 대부분 연결", m_scene >= int(m_ok * 0.8))
	fails += _b("item icon 대부분 존재", i_icon >= int(i_ok * 0.8))

	if fails == 0:
		print("[test_data_entities] ALL PASS")
	else:
		printerr("[test_data_entities] %d FAIL" % fails)
	quit(0 if fails == 0 else 1)

func _load(p: String):
	var f := FileAccess.open(p, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}

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
