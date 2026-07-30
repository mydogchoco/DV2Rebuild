extends SceneTree
## 헤드리스 데이터 엔티티 검증 (§10 data층) — Monster / Item.
## 원작 근거:
##   docs/ref/orig_code/decomp/Monster.c — 필드 {no,name,level,hp,att,def,exp,race,attackType,groundType,
##     position,shadow*,getImagePath*(에셋키),getTalk*(대사)} (getter+setInfo).
##   docs/ref/orig_code/decomp/Item.c — 필드 {no,name,type,typeDetail,typeParam,comment,image,imageSmall,
##     price*,point*,count,saleType,...} (getter).
## 검증: monsters.json/items.json이 각 클래스의 **오프라인 코어 필드**를 완비하는지 + 에셋 연결.
##   ⚠️ 유실(서버소실): Monster.exp/Talk*, Item.price/comment/effect = ASSUMPTION/TODO(데이터트랙).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_data_entities.gd

func _init() -> void:
	var fails := 0

	# ── Monster (monsters.json) ──
	var mraw = _load("res://data/monsters.json")
	var monsters = mraw.get("monsters", mraw) if typeof(mraw) == TYPE_DICTIONARY else mraw
	if typeof(monsters) == TYPE_DICTIONARY:
		monsters = monsters.values()
	fails += _b("monsters 로드", typeof(monsters) == TYPE_ARRAY and monsters.size() >= 1)
	var m_ok := 0
	var m_scene := 0
	# monsters.json은 위키 출처라 element가 한글(gen_stages가 stages.json 생성 시 영어로 매핑).
	# 두 어휘 모두 유효로 인정.
	var VALID_EL := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow", "none",
		"무", "불", "물", "바람", "땅", "대지", "빛", "암흑", "어둠", "신성", "혼돈", "그림자"]
	for mo in monsters:
		if typeof(mo) != TYPE_DICTIONARY:
			continue
		# Monster.name/hp/att/def(getName/getHp/getAtt/getDef): 필수·유효
		fails += _b("monster.name", String(mo.get("name", "")).strip_edges() != "")
		fails += _b("monster.hp>0", _num(mo.get("hp", 0)) > 0.0)
		fails += _b("monster.att>=0", _num(mo.get("att", -1)) >= 0.0)
		fails += _b("monster.def>=0", _num(mo.get("def", -1)) >= 0.0)
		# Monster.race(getRace) ≈ 우리 element: 유효 속성
		fails += _b("monster.element valid", String(mo.get("element", "none")) in VALID_EL)
		# Monster.getImagePathSpineJson ≈ scenes/monsters/monster_{asset_id}.tscn 연결
		var aid := int(_num(mo.get("asset_id", 0)))
		if aid > 0 and ResourceLoader.exists("res://scenes/monsters/monster_%d.tscn" % aid):
			m_scene += 1
		m_ok += 1

	# ── Item (items.json) ──
	var iraw = _load("res://data/items.json")
	fails += _b("items 로드", typeof(iraw) == TYPE_DICTIONARY and iraw.size() >= 1)
	var i_ok := 0
	var i_icon := 0
	for key in iraw.keys():
		if String(key).begins_with("_"):
			continue
		var it = iraw[key]
		if typeof(it) != TYPE_DICTIONARY:
			continue
		# Item.name(getName)/type(getType→category): 필수
		fails += _b("item[%s].name" % key, String(it.get("name", "")).strip_edges() != "")
		fails += _b("item[%s].category" % key, String(it.get("category", "")).strip_edges() != "")
		# Item.image(getImage)→icon: 있으면 카운트(일부 유실 허용)
		if String(it.get("icon", "")).strip_edges() != "":
			i_icon += 1
		i_ok += 1

	print("[test_data_entities] Monster %d(코어필드 완비, spine씬연결 %d) · Item %d(코어필드 완비, icon %d)" % [m_ok, m_scene, i_ok, i_icon])
	# 에셋 연결 최소 보장(대부분 연결돼야 함)
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
