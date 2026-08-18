extends Control

const FLOOR := 692.0
var _pma: CanvasItemMaterial
var _result_box: Control
var _sel_egg: String = ""

var _params: Dictionary = {}

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	Bgm.play("bg_cave")
	for c in get_children(): c.queue_free()
	var vis := _vis()
	var bg := TextureRect.new()
	var bp := "res://assets/converted/cave_bg/cavebg1.jpg"
	if ResourceLoader.exists(bp): bg.texture = load(bp)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.35); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg); add_child(dim)
	var title := Label.new()
	title.text = "부화"
	title.add_theme_font_size_override("font_size", 34); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 44); title.position = Vector2(0, 40)
	add_child(title)
	var eggs := _egg_keys()
	var info := Label.new()
	info.text = "보유 알 %d개    (알 없으면 기본 부화 300골드)" % eggs.size()
	info.add_theme_font_size_override("font_size", 18); info.add_theme_color_override("font_color", Color(0.95, 0.95, 0.8))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; info.size = Vector2(vis.x, 26); info.position = Vector2(0, 96)
	add_child(info)
	if _sel_egg == "" or not eggs.has(_sel_egg):
		_sel_egg = eggs[0] if not eggs.is_empty() else ""
	if not eggs.is_empty():
		var row_w := float(eggs.size()) * 92.0
		var x0 := vis.x * 0.5 - row_w * 0.5 + 46.0
		for i in eggs.size():
			var ek: String = eggs[i]
			var slot := TextureRect.new(); slot.texture = load("res://assets/converted/colosseum_ui/scene_colosseum_tournament_box1.tres")
			slot.size = Vector2(84, 84); slot.position = Vector2(x0 + i * 92.0 - 42.0, vis.y * 0.24)
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; add_child(slot)
			if ek == _sel_egg:
				var frm := TextureRect.new(); frm.texture = load("res://assets/converted/colosseum_ui/scene_colosseum_tournament_box_frame.tres")
				frm.size = Vector2(88, 88); frm.position = slot.position - Vector2(2, 2)
				frm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; frm.modulate = Color(1, 0.9, 0.4); add_child(frm)
			var es := _egg_sprite(ek)
			if es: es.scale = Vector2(0.85, 0.85); es.position = Vector2(x0 + i * 92.0, vis.y * 0.24 + 40.0); add_child(es)
			var cnt := Label.new(); cnt.text = "×%d" % UserDB.item_count(ek)
			cnt.add_theme_font_size_override("font_size", 14); cnt.add_theme_color_override("font_color", Color.WHITE)
			cnt.position = Vector2(x0 + i * 92.0 - 34.0, vis.y * 0.24 + 56.0); add_child(cnt)
			var btn := Button.new(); btn.flat = true; btn.size = Vector2(84, 84)
			btn.position = slot.position; btn.pressed.connect(_on_pick_egg.bind(ek)); add_child(btn)
	var eggspr := _egg_sprite(_sel_egg)
	if eggspr: eggspr.position = Vector2(vis.x * 0.5, vis.y * 0.46); add_child(eggspr)
	var hatch := Button.new()
	hatch.text = "부화하기"
	hatch.size = Vector2(180, 52); hatch.position = Vector2(vis.x * 0.5 - 200, vis.y * 0.62)
	hatch.pressed.connect(_on_hatch)
	add_child(hatch)
	var combine := Button.new()
	combine.text = "조합 (알 2개)"
	combine.size = Vector2(180, 52); combine.position = Vector2(vis.x * 0.5 + 20, vis.y * 0.62)
	combine.pressed.connect(_on_combine)
	add_child(combine)
	var frag := Button.new()
	frag.text = "알조각 조합"
	frag.size = Vector2(180, 44); frag.position = Vector2(vis.x * 0.5 - 90, vis.y * 0.62 + 62)
	frag.pressed.connect(_open_fragments)
	add_child(frag)
	var hist := Button.new(); hist.text = "부화 이력"; hist.size = Vector2(140, 40)
	hist.position = Vector2(vis.x - 160, vis.y * 0.62 + 62)
	hist.pressed.connect(_open_egg_history); add_child(hist)
	_result_box = Control.new(); _result_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_result_box)
	var back := Button.new()
	var from := String(_params.get("from", "cave"))
	back.text = "← 월드맵" if from == "worldmap" else "← 둥지"
	back.position = Vector2(20, 18)
	back.pressed.connect(func():
		if from == "worldmap": Scenes.goto("worldmap", {"region": "yutakan"})
		else: Scenes.goto("cave"))
	add_child(back)

func _on_pick_egg(ek: String) -> void:
	_sel_egg = ek
	_rebuild()

func _open_fragments() -> void:
	var cfg: Dictionary = Data.egg_fragments
	var sets: Dictionary = cfg.get("sets", {})
	var need := int(cfg.get("count", 7))
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var pop := Control.new(); pop.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(pop)
	pop.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: pop.queue_free())
	pop.add_child(dim)
	var panel := NinePatchRect.new(); panel.size = Vector2(560, 480); panel.position = (vis - panel.size) * 0.5
	panel.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	panel.patch_margin_left = 130; panel.patch_margin_top = 190; panel.patch_margin_right = 55; panel.patch_margin_bottom = 81
	pop.add_child(panel)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(504, 54); tbar.position = Vector2(28, 14); panel.add_child(tbar)
	var title := Label.new(); title.text = "알조각 조합"
	title.add_theme_font_size_override("font_size", 23); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(560 - 50 - 18, 16); xb.pressed.connect(func(): pop.queue_free()); panel.add_child(xb)
	var y := 84.0
	for pfx in sets:
		var info: Dictionary = sets[pfx]
		var have := 0
		for i in range(1, need + 1):
			if UserDB.item_count("%s_egg_%d" % [pfx, i]) > 0: have += 1
		var full := have >= need
		var row := Label.new()
		row.text = "%s   [%d/%d]" % [String(info.get("name", pfx)), have, need]
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", Color(1, 0.9, 0.5) if full else Color(0.8, 0.8, 0.8))
		row.position = Vector2(30, y); row.size = Vector2(320, 30); panel.add_child(row)
		var b := Button.new()
		b.text = "조합 (%d G)" % int(info.get("cost", 5000))
		b.disabled = not full
		b.size = Vector2(150, 34); b.position = Vector2(380, y - 4)
		b.pressed.connect(_combine_fragments.bind(pfx, info, need, layer))
		panel.add_child(b)
		y += 52.0
	var hint := Label.new()
	hint.text = "던전/상점에서 알조각을 모아 7개를 채우면 조합 가능"
	hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(560, 20); hint.position = Vector2(0, y + 6)
	panel.add_child(hint)
	var close := Button.new(); close.text = "닫기"; close.size = Vector2(120, 40)
	close.position = Vector2(220, 418); close.pressed.connect(func(): pop.queue_free()); panel.add_child(close)

func _combine_fragments(pfx: String, info: Dictionary, need: int, layer: CanvasLayer) -> void:
	for i in range(1, need + 1):
		if UserDB.item_count("%s_egg_%d" % [pfx, i]) <= 0:
			return
	var cost := int(info.get("cost", 5000))
	if not UserDB.spend("gold", cost):
		_show_result(-1, "골드가 부족합니다 (%d G)" % cost); return
	for i in range(1, need + 1):
		UserDB.use_item("%s_egg_%d" % [pfx, i], 1)
	var did := int(info.get("dragon", 0))
	UserDB.add_dragon(did)
	if is_instance_valid(layer): layer.queue_free()
	_rebuild()
	if not _open_egg_reveal(did):
		_show_result(did, "%s 조합 성공!" % String(info.get("name", "특수 드래곤")))

const EGG_SCENE := "res://scenes/eggs/egg_%d.tscn"
func _open_egg_reveal(dragon_id: int) -> bool:
	var path := EGG_SCENE % dragon_id
	if not ResourceLoader.exists(path):
		return false
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var holder := Node2D.new()
	holder.position = Vector2(vis.x * 0.5, vis.y * 0.5)
	holder.scale = Vector2(1.6, 1.6)
	layer.add_child(holder)
	var inst = load(path).instantiate()
	holder.add_child(inst)
	var ap = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
		ap.play("animation")
	var cb := TextureButton.new()
	cb.texture_normal = load("res://assets/converted/common_ui/common_check_btn.tres")
	cb.scale = Vector2(1.5, 1.5)
	cb.position = Vector2(vis.x * 0.9 - 40, vis.y * 0.9 - 40)
	cb.modulate.a = 0.0
	cb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free())
	layer.add_child(cb)
	var tw := cb.create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(cb, "modulate:a", 1.0, 0.5)
	return true

func _egg_keys() -> Array:
	var out: Array = []
	for k in UserDB.inventory().keys():
		var it: Dictionary = EggGacha.item_def(String(k), Data.dragons)
		if it.is_empty():
			it = Data.get_item(String(k))
		if EggGacha.is_gacha_egg(it):
			continue
		if String(it.get("category", "")) == "egg" and UserDB.item_count(String(k)) > 0:
			out.append(String(k))
	return out

func _open_egg_history() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: layer.queue_free())
	layer.add_child(dim)
	var BW := 520.0
	var BH := clampf(vis.y - 80.0, 400.0, 620.0)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "부화 이력"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 84); scroll.size = Vector2(BW - 72, BH - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(BW - 90, 0); scroll.add_child(vb)
	var drs: Array = UserDB.dragons()
	for i in drs.size():
		var dd: Dictionary = drs[i]
		var cell := Control.new(); cell.custom_minimum_size = Vector2(BW - 100, 62)
		var cellbg := NinePatchRect.new()
		cellbg.texture = load("res://assets/converted/common_ui/common_item_bg.tres")
		cellbg.patch_margin_left = 18; cellbg.patch_margin_right = 18
		cellbg.patch_margin_top = 18; cellbg.patch_margin_bottom = 18
		cellbg.size = Vector2(BW - 100, 62)
		cellbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cellbg)
		var dp := "res://assets/converted/dex_ui/dragon_%d.tres" % int(dd["id"])
		if ResourceLoader.exists(dp):
			var ds := Sprite2D.new(); ds.texture = load(dp); ds.material = _pma; ds.scale = Vector2(0.7, 0.7)
			ds.position = Vector2(36, 31); cell.add_child(ds)
		var nm := Label.new()
		nm.text = "%s   Lv.%d   ✓ 부화 완료" % [Icons.species_name(int(dd["id"])), int(dd["level"])]
		nm.add_theme_font_size_override("font_size", 18); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
		nm.position = Vector2(76, 18); nm.size = Vector2(BW - 190, 26); cell.add_child(nm)
		vb.add_child(cell)

func _egg_sprite(key: String) -> Sprite2D:
	if key == "":
		return null
	var did := EggGacha.dragon_of(key)
	if did > 0:
		var t := Icons.dragon_egg_texture(did)
		if t != null:
			var es := Sprite2D.new(); es.texture = t; es.material = _pma
			es.scale = Vector2(1.4, 1.4); return es
		return null
	var p := Data.item_icon_path(key)
	if ResourceLoader.exists(p):
		var s := Sprite2D.new(); s.texture = load(p); s.material = _pma; s.scale = Vector2(1.4, 1.4); return s
	return null

func _on_hatch() -> void:
	Bgm.sfx("effect_box_peong")
	var eggs := _egg_keys()
	var egg_grade := 0
	if not eggs.is_empty():
		var use_egg: String = _sel_egg if (_sel_egg != "" and eggs.has(_sel_egg)) else eggs[0]
		egg_grade = EggItem.grade_of(use_egg)
		UserDB.add_item(use_egg, -1)
	elif not UserDB.spend("gold", 300):
		_show_result(-1, "골드가 부족합니다")
		return
	var ids: Array = Data.dragon_ids_random()
	if ids.is_empty(): return
	var r := RandomNumberGenerator.new(); r.randomize()
	var did := int(ids[r.randi() % ids.size()])
	var nest_blessed := bool(UserDB.get_pmeta("blessed_nest", false))
	var fixed := EggUpgrade.hatch_grade(egg_grade, Data.laboratory.get("egg_upgrade", {}))
	if fixed > 0.0:
		UserDB.add_dragon(did, 1, Hatchery.stat_bonus_for_grade(Hatchery.bless(fixed, nest_blessed)))
	elif nest_blessed:
		UserDB.add_dragon(did, 1, Hatchery.stat_bonus_for_grade(Hatchery.bless(Growth.BASE_GRADE, true)))
	else:
		UserDB.add_dragon(did, 1)
	UserDB.bump_quest("hatches")
	_show_result(did, "")

func _on_combine() -> void:
	Bgm.sfx("effect_combine")
	var eggs := _egg_keys()
	if eggs.size() >= 2:
		var recipe: Dictionary = Data.combine_egg_match([eggs[0], eggs[-1]])
		if not recipe.is_empty():
			var rcost := int(recipe.get("cost", 0))
			if rcost > 0 and not UserDB.spend("gold", rcost):
				_show_result(-1, "골드 부족 (%d)" % rcost)
				return
			UserDB.add_item(eggs[0], -1); UserDB.add_item(eggs[-1], -1)
			var target := String(recipe.get("target", ""))
			if target != "": UserDB.add_item(target, 1)
			UserDB.bump_quest("hatches")
			_show_result(-1, "조합 성공! %s 획득" % (Data.item_name(target) if target != "" else "알"))
			return
	if eggs.size() >= 2:
		UserDB.add_item(eggs[0], -1); UserDB.add_item(eggs[-1] if eggs.size() > 1 else eggs[0], -1)
	elif not UserDB.spend("gold", 600):
		_show_result(-1, "알 2개 또는 600골드 필요")
		return
	var ids: Array = Data.dragon_ids_random()
	if ids.is_empty(): return
	var r := RandomNumberGenerator.new(); r.randomize()
	var did := int(ids[r.randi() % ids.size()])
	var bonus := {"base": {"hp": r.randi_range(2, 6), "att": r.randi_range(1, 3), "def": r.randi_range(1, 3)},
		"growth": {"hp": r.randi_range(1, 3), "att": r.randi_range(0, 2), "def": r.randi_range(0, 2)}}
	UserDB.add_dragon(did, 1, bonus)
	UserDB.bump_quest("hatches")
	_show_result(did, "조합 성공! (고품질)")

func _show_result(did: int, msg: String) -> void:
	for c in _result_box.get_children(): c.queue_free()
	var vis := _vis()
	if did < 0:
		var l := Label.new(); l.text = msg; l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(1, 0.6, 0.5)); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(vis.x, 30); l.position = Vector2(0, vis.y * 0.78); _result_box.add_child(l)
		return
	_hatch_reveal(did, msg)

func _hatch_reveal(did: int, msg: String) -> void:
	var vis := _vis()
	var center := Vector2(vis.x * 0.5, vis.y * 0.4)
	var egg := _egg_sprite(_sel_egg)
	if egg == null and not _egg_keys().is_empty():
		egg = _egg_sprite(_egg_keys()[0])
	if egg:
		egg.position = center; _result_box.add_child(egg)
		var t := egg.create_tween()
		for i in 3:
			t.tween_property(egg, "rotation", 0.18, 0.09).set_trans(Tween.TRANS_SINE)
			t.tween_property(egg, "rotation", -0.18, 0.09).set_trans(Tween.TRANS_SINE)
		t.tween_property(egg, "rotation", 0.0, 0.06)
		t.tween_property(egg, "scale", egg.scale * 1.25, 0.12).set_trans(Tween.TRANS_BACK)
		t.tween_callback(func(): _hatch_burst(center, did, msg, egg))
	else:
		_hatch_burst(center, did, msg, null)

func _hatch_burst(center: Vector2, did: int, msg: String, egg: Sprite2D) -> void:
	if egg and is_instance_valid(egg): egg.queue_free()
	var vis := _vis()
	var flash := ColorRect.new(); flash.color = Color(1, 1, 0.9, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tf := flash.create_tween()
	tf.tween_property(flash, "color:a", 0.7, 0.1)
	tf.tween_property(flash, "color:a", 0.0, 0.4)
	tf.tween_callback(flash.queue_free)
	var dust := CPUParticles2D.new()
	dust.position = center; dust.emitting = true; dust.one_shot = true
	dust.amount = 24; dust.lifetime = 0.7; dust.explosiveness = 0.9
	dust.direction = Vector2(0, -1); dust.spread = 180.0
	dust.initial_velocity_min = 90.0; dust.initial_velocity_max = 220.0
	dust.gravity = Vector2(0, 220.0)
	dust.scale_amount_min = 2.0; dust.scale_amount_max = 5.0
	dust.color = Color(1, 0.95, 0.6)
	_result_box.add_child(dust)
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(dust): dust.queue_free())
	var por := _portrait(did, "baby", 1.1)
	if por:
		por.position = center; por.scale = Vector2(0.1, 0.1); _result_box.add_child(por)
		var tp := por.create_tween()
		tp.tween_property(por, "scale", Vector2(1.25, 1.25), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tp.tween_property(por, "scale", Vector2(1.1, 1.1), 0.12)
	var l := Label.new()
	l.text = "%s  %s" % [msg if msg != "" else "새로운 드래곤!", Icons.species_name(did)]
	l.add_theme_font_size_override("font_size", 26); l.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.size = Vector2(vis.x, 32); l.position = Vector2(0, vis.y * 0.52)
	l.modulate.a = 0.0; _result_box.add_child(l)
	l.create_tween().tween_property(l, "modulate:a", 1.0, 0.3).set_delay(0.2)

func _vis() -> Vector2:
	return get_viewport_rect().size

func _portrait(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	var p := "res://assets/converted/%s/dragon_dragon_%d_box_%s.tres" % [dir, id, stage]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new(); s.texture = load(p); s.material = _pma; s.scale = Vector2(scale, scale)
	return s
