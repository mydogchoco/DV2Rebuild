extends SceneTree

const SPINE := "res://scenes/worldmap_fx/magicshop_alchemist.tscn"
const WANT_ANIMS := ["normal", "resection", "wisdom", "brave", "justice", "glory", "legend"]

var _out := "user://"
var _step := 0
var _shop: Node
var _udb: Node
var _fails := 0

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
		if not ResourceLoader.exists(SPINE):
			_fail("스파인 씬 없음 %s — spine_export --scene 부터 돌릴 것" % SPINE)
			_finish(); return
		var inst := (load(SPINE) as PackedScene).instantiate()
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap == null:
			_fail("AnimationPlayer 없음")
		else:
			for an in WANT_ANIMS:
				if not ap.has_animation(an):
					_fail("애니 없음: %s" % an)
			print("애니 %d종: %s" % [ap.get_animation_list().size(),
				str(ap.get_animation_list())])
		var names := _node_names(inst)
		for want in ["magicshop_pot", "magicshop_sccop"]:
			if not names.any(func(n: String): return n.contains(want)):
				_fail("어태치먼트 노드 없음: %s" % want)
		inst.free()

		_udb.add_item(gem.item_key("체공젬", 4), 1)
		var ps: PackedScene = load("res://scenes/magicshop.tscn")
		_shop = ps.instantiate()
		get_root().add_child(_shop)
		if _shop.has_method("enter"):
			_shop.enter({})
	elif _step == 10:
		_shop._set_floor(1)
	elif _step == 16:
		_shop._open_feature(0)
		_shop._hybrid_key = gem.item_key("체공젬", 4)
		_shop._refresh_feature()
	elif _step == 22:
		var sp = _shop._alchemy_spine
		if sp == null or not is_instance_valid(sp):
			_fail("강화 화면에 스파인이 안 붙었다")
		else:
			var ap2 := sp.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap2 == null or not ap2.is_playing():
				_fail("스파인이 재생 중이 아니다")
			elif ap2.current_animation != "normal":
				_fail("대기 애니가 normal 이 아니다: %s" % ap2.current_animation)
			else:
				print("스파인 재생 중: %s (loop)" % ap2.current_animation)
		_save("alchemy_cauldron.png")
	elif _step == 24:
		var rp := "res://scenes/worldmap_fx/buildup_result_spine.tscn"
		if not ResourceLoader.exists(rp):
			_fail("결과 스파인 없음 %s" % rp)
		else:
			var ri := (load(rp) as PackedScene).instantiate()
			var rap := ri.get_node_or_null("AnimationPlayer") as AnimationPlayer
			for an in ["success_type", "failed_type"]:
				if rap == null or not rap.has_animation(an):
					_fail("결과 애니 없음: %s" % an)
			var rn := _node_names(ri)
			for want in ["enchant_success_s", "enchant_failed_f"]:
				if not rn.any(func(n: String): return n.contains(want)):
					_fail("글자 슬롯 없음: %s" % want)
			print("결과 스파인 애니: %s" % str(rap.get_animation_list() if rap else []))
			ri.free()
		var pots: Array = (JSON.parse_string(FileAccess.open(
			_data_file("gems.json"), FileAccess.READ).get_as_text())["upgrade"] as Dictionary)["potions"]
		_udb.add_item("alchemy_moderation", 5)
		var before_cnt := int(_udb.item_count("alchemy_moderation"))
		_shop._confirm_potion(pots[0], "alchemy_moderation")
		if int(_udb.item_count("alchemy_moderation")) != before_cnt:
			_fail("확인 팝업 없이 용액이 바로 소모됐다")
		else:
			print("용액 확인 팝업: 소모 보류 확인 (%d 유지)" % before_cnt)
	elif _step == 25:
		_save("potion_confirm.png")
	elif _step == 26:
		var bk: String = gem.item_key("체공젬", 4, {"broken": true})
		_udb.add_item(bk, 1)
		var before := int(_udb.item_count(bk))
		_shop._hybrid_key = bk
		_shop._destroy_broken_gem(bk)
		var after := int(_udb.item_count(bk))
		if not (before == 1 and after == 0):
			_fail("파손 젬이 안 사라졌다 (before=%d after=%d)" % [before, after])
		else:
			print("파손 젬 소멸 확인: %d → %d" % [before, after])
		if String(_shop._hybrid_key) != "":
			_fail("소멸 후에도 대상 키가 남아 있다: %s" % _shop._hybrid_key)
	elif _step == 28:
		for c in _shop.get_children():
			if c is CanvasLayer:
				c.queue_free()
	elif _step == 30:
		_shop._show_upgrade_result(true, "체공젬 +56  체력+56, 공격+7",
			"체공젬 +60  체력+60, 공격+7", {"name": "체공젬", "tier": 5}, "")
		create_timer(1.4).timeout.connect(func():
			_save("result_success.png")
			var lays := _shop.get_children().filter(func(c): return c is Control and c.z_index == 80)
			var vis_ok := false
			for l in lays:
				for c in l.get_children():
					if c is Node2D and c.visible:
						vis_ok = true
			if not vis_ok:
				_fail("결과 워드아트가 화면에 안 나온다(DelayTime 뒤에도 invisible)")
			else:
				print("결과 워드아트 표시 확인")
			_finish())
	elif _step > 600:
		_fail("timeout"); _finish()

func _node_names(n: Node, out: Array[String] = []) -> Array[String]:
	out.append(n.name)
	for c in n.get_children():
		_node_names(c, out)
	return out

func _fail(msg: String) -> void:
	_fails += 1
	printerr("  ✗ %s" % msg)

func _finish() -> void:
	print("[test_alchemy_spine] %s" % ("OK" if _fails == 0 else "FAIL %d" % _fails))
	quit(1 if _fails > 0 else 0)

func _save(name: String) -> void:
	var tex := get_root().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		print("skip(headless): %s" % name)
		return
	img.save_png("%s/%s" % [_out.rstrip("/"), name])
	print("saved: %s/%s" % [_out.rstrip("/"), name])

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
