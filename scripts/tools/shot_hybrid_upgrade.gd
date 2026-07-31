extends SceneTree
## 혼성젬 강화(원작 `AlchemyLayer`) 시각 + 흐름 검수 드라이버.
##
##   godot --path . --script res://scripts/tools/shot_hybrid_upgrade.gd -- <out_dir>
##
## 확인 흐름: 지하 → 혼성젬 강화 → [혼성젬 선택] → 가방 격자에서 고르기 → 용액 투입
## → 포인트/성공률이 **가방 키 메타**로 남는지(=화면 재빌드 후에도 유지) 확인.

var _out := "user://"
var _step := 0
var _shop: Node
var _udb: Node


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	process_frame.connect(_tick)


func _tick() -> void:
	_step += 1
	var gem := load("res://scripts/systems/gem.gd")
	if _step == 2:
		_udb = get_root().get_node_or_null("UserDB")
		# 혼성젬 + 용액을 넉넉히 넣는다.
		for row in [["체공젬", 4], ["공방젬", 7], ["방체젬", 2], ["샌즈의 젬", 5]]:
			_udb.add_item(gem.item_key(String((row as Array)[0]), int((row as Array)[1])), 3)
		for k in ["alchemy_moderation", "alchemy_wisdom", "alchemy_courage", "alchemy_justice"]:
			_udb.add_item(k, 20)
		var ps: PackedScene = load("res://scenes/magicshop.tscn")
		_shop = ps.instantiate()
		get_root().add_child(_shop)
		if _shop.has_method("enter"):
			_shop.enter({})
	elif _step == 8:
		_shop._set_floor(1)
	elif _step == 14:
		_shop._open_feature(0)                      # 지하 1번째 = 혼성젬 강화
	elif _step == 20:
		_save("hybrid_empty.png")                   # 투입 슬롯 비어 있는 상태(원작 혼성젬강화1)
		_shop._hybrid_key = gem.item_key("체공젬", 4)
		_shop._refresh_feature()
	elif _step == 26:
		_save("hybrid_picked.png")
		# 용액 2번 투입 → 포인트가 가방 키에 실려야 한다.
		var tbl: Dictionary = JSON.parse_string(FileAccess.open(
			"res://data/gems.json", FileAccess.READ).get_as_text())
		var potions: Array = (tbl["upgrade"] as Dictionary)["potions"]
		_shop._pour_potion(potions[0], "alchemy_moderation")
		_shop._pour_potion(potions[1], "alchemy_wisdom")
	elif _step == 32:
		var key: String = _shop._hybrid_key
		var inst: Dictionary = gem.item_key_to_slot(key)
		print("키=%s  포인트=%d  투입=%d  보유=%d"
			% [key, int(inst.get("points", 0)), int(inst.get("potions", 0)),
			   _udb.item_count(key)])
		var ok: bool = int(inst.get("points", 0)) > 0 and int(inst.get("potions", 0)) == 2 \
			and int(_udb.item_count(key)) == 1 and key.contains("@")
		print("RESULT: %s" % ("OK — 진행도가 가방 키에 남는다" if ok else "FAIL"))
		_save("hybrid_potion.png")
		if not ok:
			quit(1)
	elif _step == 36:
		quit(0)
	elif _step > 60:
		printerr("timeout")
		quit(1)


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var p := "%s/%s" % [_out.rstrip("/"), name]
	img.save_png(p)
	print("saved: ", p)
