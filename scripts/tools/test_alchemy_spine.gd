extends SceneTree
## 혼성젬 강화 화면의 **가마솥 스파인** + **파손 젬 소멸 규칙** 스모크.
##
##   godot --path . --script res://scripts/tools/test_alchemy_spine.gd -- <out_dir>
##
## ① 원작 `magicshop_alchemist` 스파인이 변환돼 애니 7종이 다 들어왔는가
##    (`normal` + 용액 6종 `resection/wisdom/brave/justice/glory/legend` — 원작 서버 키와 동일)
## ② 냄비·국자 어태치먼트(`magicshop_pot` / `magicshop_sccop`)가 실제로 그려지는가
## ③ 강화 화면에 스파인이 붙고 `normal` 이 도는가
## ④ 🟦 파손 젬은 복구를 안 고르면 **가방에서 사라지는가**(사용자 확정 2026-07-31)

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
		# ① 애니 7종
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
		# ② 냄비·국자 슬롯
		var names := _node_names(inst)
		for want in ["magicshop_pot", "magicshop_sccop"]:
			if not names.any(func(n: String): return n.contains(want)):
				_fail("어태치먼트 노드 없음: %s" % want)
		inst.free()

		# 화면 띄우기
		_udb.add_item(gem.item_key("체공젬", 4), 1)
		var ps: PackedScene = load("res://scenes/magicshop.tscn")
		_shop = ps.instantiate()
		get_root().add_child(_shop)
		if _shop.has_method("enter"):
			_shop.enter({})
	elif _step == 10:
		_shop._set_floor(1)
	elif _step == 16:
		_shop._open_feature(0)                     # 혼성젬 강화
		_shop._hybrid_key = gem.item_key("체공젬", 4)
		_shop._refresh_feature()
	elif _step == 22:
		# ③ 스파인이 붙었고 normal 이 도는가
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
	elif _step == 26:
		# ④ 파손 젬 소멸 — 복구를 안 고른 경로(`_destroy_broken_gem`) 를 직접 친다.
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
		_finish()
	elif _step > 60:
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
	var img := get_root().get_texture().get_image()
	img.save_png("%s/%s" % [_out.rstrip("/"), name])
	print("saved: %s/%s" % [_out.rstrip("/"), name])
