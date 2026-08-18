class_name LevelUpScreen
extends Node

static func open(host: Node, uid: int, opts: Dictionary = {}) -> LevelUpScreen:
	var s := LevelUpScreen.new()
	s._uid = uid
	s._host_stage = opts.get("stage_node")
	s._opts = opts
	host.add_child(s)
	return s

static func open_queue(host: Node, entries: Array, on_all_closed := Callable(),
		opts: Dictionary = {}) -> void:
	if entries.is_empty():
		if on_all_closed.is_valid(): on_all_closed.call()
		return
	var rest := entries.slice(1)
	var o := opts.duplicate()
	o["on_close"] = func(): open_queue(host, rest, on_all_closed, opts)
	open(host, int((entries[0] as Dictionary).get("uid", 0)), o)

var _uid := 0
var _host_stage
var _opts: Dictionary = {}
var _pma: CanvasItemMaterial

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var sf := FileAccess.open("res://assets/converted/stand_ui/_manifest.json", FileAccess.READ)
	if sf: _stand_manifest = JSON.parse_string(sf.get_as_text())
	var isf := FileAccess.open("res://assets/converted/item_small_ui/_manifest.json", FileAccess.READ)
	if isf: _item_small_manifest = JSON.parse_string(isf.get_as_text())
	_build()

func _notify(key: String) -> void:
	var c = _opts.get(key)
	if c is Callable and (c as Callable).is_valid():
		(c as Callable).call()

func _close_self() -> void:
	_notify("on_close")
	queue_free()

func play_fx(fx: Dictionary) -> void:
	_lvup_redraw(fx)

func word_banner(text: String, secs := 1.6, col := Color(0.72, 0.94, 1.0),
		outline := Color(0, 0, 0, 0.9)) -> void:
	_lvup_word_banner(text, secs, col, outline)

const STAND_COUNT := 16
const S1080 := 692.0 / 1080.0

var _stand_manifest: Dictionary = {}
var _item_small_manifest: Dictionary = {}
var _portrait_manifests: Dictionary = {}

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

func _atlas_sprite(dir: String, name: String, _man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _portrait_sprite(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0:
		var sframe := "dragon_dragon_%d_box_%s_skin%d" % [id, stage, skin]
		if _portrait_manifests[dir].has(sframe): frame = sframe
	return _atlas_sprite(dir, frame, _portrait_manifests[dir], scale)

func _man_adventure() -> Dictionary:
	return AtlasUI.manifest("adventure_ui")

func _man_common() -> Dictionary:
	return AtlasUI.manifest("common_ui")

func _josa_c(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _grade_of(inst: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
		inst.get("gain_log", []), Data.level_curve.get("grade", {}))

func _skills_learned_since(uid: int, before_size: int) -> Array:
	var pool: Array = UserDB.dragon_skills(uid)
	var out: Array = []
	for i in range(before_size, pool.size()):
		var sid := int((pool[i] as Dictionary).get("id", 0))
		out.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	return out

const _LVUP_GUARANTEE := {
	"bless_of_dragon": "max1", "bless_of_maia": "max2",
	"bless_of_dersa": "triple", "bless_of_amor": "amor",
}
const _STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력"}
const _LVUP_ITEMS := ["level_up", "bless_of_dragon", "bless_of_maia", "bless_of_dersa",
	"bless_of_amor", "level_down"]
const _LVUP_MIN_SLOTS := 2
const _LVUP_UI_Z := 40

var _lvup_ctx: Dictionary = {}
var _lvup_dragon_holder: Node2D
var _lvup_fx_busy := false
var _lvup_auto_running := false

var _lvup_bmfonts := {}
func _lvup_bmfont(name: String) -> FontFile:
	if _lvup_bmfonts.has(name):
		return _lvup_bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_lvup_bmfonts[name] = f
	return f

func _lvup_bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _lvup_bmfont(font)
	if f:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build() -> void:
	var a := UserDB.get_dragon(_uid)
	if a.is_empty():
		_close_self(); return
	a = a.duplicate()
	a["uid"] = _uid
	var uid := _uid
	var ddef: Dictionary = Data.get_dragon(int(a.get("id", 0)))
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var uilay := CanvasLayer.new(); uilay.layer = 31; add_child(uilay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var win := Control.new()
	win.size = vis
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uilay.add_child(win)

	if is_instance_valid(_host_stage): _host_stage.visible = false
	overlay.tree_exited.connect(func():
		if is_instance_valid(_host_stage): _host_stage.visible = true)
	var dragon_ap := _lvup_build_dragon(overlay, a, vis)

	var lup := TextureRect.new()
	lup.texture = load("res://assets/converted/lvup_ui/level_up.png")
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(vis.x * 0.30, vis.y * 0.20)
	lup.position = _lvup_art_home(vis, lup.size)
	lup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lup.z_index = _LVUP_UI_Z
	win.add_child(lup)

	var tback := ColorRect.new()
	tback.color = Color(0.05, 0.04, 0.03, 1.0)
	tback.size = Vector2(vis.x, 120.0)
	tback.position = Vector2(0.0, vis.y - 120.0)
	tback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tback.z_index = _LVUP_UI_Z
	win.add_child(tback)
	var tbox := NinePatchRect.new()
	tbox.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	tbox.patch_margin_left = 10; tbox.patch_margin_right = 10
	tbox.patch_margin_top = 4; tbox.patch_margin_bottom = 4
	tbox.size = Vector2(vis.x - 10.0, 120.0)
	tbox.position = Vector2(5.0, vis.y - 120.0)
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tbox.z_index = _LVUP_UI_Z
	win.add_child(tbox)
	var tlabel := Label.new()
	tlabel.add_theme_font_size_override("font_size", 28)
	tlabel.add_theme_color_override("font_color", Color.WHITE)
	tlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tlabel.size = Vector2(tbox.size.x - 20.0, 112.0); tlabel.position = Vector2(10.0, 4.0)
	tbox.add_child(tlabel)

	var okb := TextureButton.new()
	var okt := "res://assets/converted/common_ui/common_check_btn.tres"
	if ResourceLoader.exists(okt):
		okb.texture_normal = load(okt)
		okb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		okb.position = Vector2(vis.x - 30.0 - 44.0 * Design.ASSET_SCALE, 20.0)
	else:
		okb.position = Vector2(vis.x - 60.0, 20.0)
	var do_close := func() -> void:
		Bgm.sfx("effect_button")
		_lvup_ctx = {}
		_lvup_dragon_holder = null
		if is_instance_valid(_host_stage): _host_stage.visible = true
		if is_instance_valid(overlay): overlay.queue_free()
		if is_instance_valid(uilay): uilay.queue_free()
		_close_self()
	okb.pressed.connect(do_close)
	uilay.add_child(okb)
	var ac := float(_opts.get("auto_close", 0.0))
	if ac > 0.0:
		get_tree().create_timer(ac).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_instance_valid(okb):
				do_close.call())

	var body := Control.new()
	body.size = vis
	body.position = Vector2.ZERO
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.z_index = _LVUP_UI_Z
	win.add_child(body)

	_lvup_ctx = {"uid": uid, "ddef": ddef, "vis": vis, "body": body, "tlabel": tlabel,
		"overlay": overlay, "reroll": 0, "art": lup, "win": win, "dragon_ap": dragon_ap}
	_lvup_redraw()

func _lvup_word_banner(text: String, secs := 1.6, col := Color(0.72, 0.94, 1.0),
		outline := Color(0.06, 0.24, 0.42, 1.0)) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	var art: TextureRect = _lvup_ctx.get("art")
	if not is_instance_valid(win) or not is_instance_valid(art): return
	if is_instance_valid(_lvup_ctx.get("word")):
		(_lvup_ctx["word"] as Node).queue_free()
	art.visible = false
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 52)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = art.size
	l.position = art.position
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.7, 0.7)
	l.z_index = _LVUP_UI_Z
	win.add_child(l)
	_lvup_ctx["word"] = l
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(secs)
	t.tween_callback(func():
		if is_instance_valid(art): art.visible = true
		if is_instance_valid(l): l.queue_free())

const DRAGON_CX := 0.22

func _lvup_art_home(vis: Vector2, art_size: Vector2) -> Vector2:
	return Vector2(vis.x * DRAGON_CX - art_size.x * 0.5, vis.y * 0.03)

func _lvup_build_dragon(parent: Node, a: Dictionary, vis: Vector2) -> AnimationPlayer:
	var holder := Node2D.new()
	_lvup_dragon_holder = holder
	holder.scale = Vector2(S1080, S1080)
	holder.position = Vector2(vis.x * DRAGON_CX, vis.y / 2.0 + 34.0)
	parent.add_child(holder)
	var bl := _atlas_sprite("common_ui", "common_backlight3", _man_common(), 1.35)
	if bl and bl.texture:
		bl.position = Vector2(0, 40)
		bl.modulate = Color(1, 1, 1, 0.5)
		holder.add_child(bl)
		bl.create_tween().set_loops().tween_property(bl, "rotation", TAU, 6.0).from(0.0)
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var pw: float = maxf(1.0, float(info.get("w", 305)))
	var ph: float = maxf(1.0, float(info.get("h", 120)))
	var psc := 620.0 / pw
	var ped := _atlas_sprite("stand_ui", "stand_stand%d" % (si + 1), _stand_manifest, psc)
	if ped:
		ped.position = Vector2(0, 357.0 - ph * psc / 2.0)
		holder.add_child(ped)
	var stage_name := Growth.stage_for_level(int(a["level"]))
	var art := Icons.art_id_of(a)
	var path := Icons.spine_scene(art, stage_name)
	if path != "":
		var d2 := Node2D.new()
		d2.scale = Vector2(1.9, 1.9)
		d2.position = Vector2(0, -7)
		holder.add_child(d2)
		var inst = load(path).instantiate()
		d2.add_child(inst)
		var dap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if dap:
			if dap.has_animation("love"):
				dap.animation_finished.connect(_lvup_loop_love.bind(dap))
				_lvup_play_love(dap)
			elif dap.has_animation("wait"):
				dap.play("wait")
			return dap
	else:
		var por := _portrait_sprite(art, stage_name, 2.6, int(a.get("skin", 0)))
		if por:
			por.position = Vector2(0, -30)
			holder.add_child(por)
	return null

func _lvup_refresh_dragon() -> void:
	if _lvup_ctx.is_empty(): return
	var overlay = _lvup_ctx.get("overlay")
	if not is_instance_valid(overlay): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	if d.is_empty(): return
	if is_instance_valid(_lvup_dragon_holder):
		var old := _lvup_dragon_holder
		if old.get_parent(): old.get_parent().remove_child(old)
		old.queue_free()
	_lvup_dragon_holder = null
	_lvup_ctx["dragon_ap"] = _lvup_build_dragon(overlay, d, _lvup_ctx["vis"])

func _lvup_play_love(dap: AnimationPlayer) -> void:
	if not is_instance_valid(dap): return
	dap.play("love")
	_lvup_dragon_voice()

func _lvup_loop_love(anim: StringName, dap: AnimationPlayer) -> void:
	if _lvup_ctx.is_empty() or not is_instance_valid(dap): return
	if anim != &"love": return
	_lvup_play_love(dap)

func _dragon_voice_no(dragon_id: int, level: int) -> int:
	var e: Dictionary = Icons.voice_row(dragon_id)
	if e.is_empty():
		return 0
	return int(e.get(Growth.stage_for_level(level), 0))

func _play_dragon_voice(dragon_id: int, level: int) -> void:
	var n := _dragon_voice_no(dragon_id, level)
	if n > 0:
		Bgm.sfx("voice%d" % n)

func _lvup_dragon_voice() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	_play_dragon_voice(int(ddef.get("id", 0)), int(d.get("level", 1)))

func _lvup_stretch(name: String, dir: String, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p): t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.material = _pma
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _lvup_reroll_cost() -> Dictionary:
	var rc: Dictionary = (Data.level_curve.get("roll", {}) as Dictionary).get("reroll_cost", {})
	return {"kind": String(rc.get("kind", "diamond")), "amount": int(rc.get("amount", 2))}

func _lvup_redraw(fx: Dictionary = {}) -> void:
	if _lvup_ctx.is_empty(): return
	var body: Control = _lvup_ctx.get("body")
	var tlabel: Label = _lvup_ctx.get("tlabel")
	if not is_instance_valid(body) or not is_instance_valid(tlabel):
		_lvup_ctx = {}
		return
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()

	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var vis: Vector2 = _lvup_ctx["vis"]
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var level := int(d.get("level", 1))
	var awakened := bool(d.get("awakened", false))
	var cap := Growth.level_cap(awakened)
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var gain_log: Array = d.get("gain_log", [])
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var COL_X := vis.x * 0.45

	var t := Label.new()
	t.text = Icons.name_of(d)
	_lvup_style(t, 26, Color.WHITE)
	t.position = Vector2(COL_X, vis.y * 0.13); body.add_child(t)
	var gr := Label.new()
	gr.text = "%.1f" % _grade_of(d, ddef)
	_lvup_bm_style(gr, 30, Color(1.0, 0.62, 0.12), "font_rating")
	gr.position = Vector2(COL_X + 250, vis.y * 0.13); body.add_child(gr)

	var ey := vis.y * 0.21
	var expw := _atlas_sprite("adventure_ui", "scene_adventure_bonus_exp_mini",
		_man_adventure(), 0.8 * Design.ASSET_SCALE)
	if expw: expw.position = Vector2(COL_X + 26, ey + 12); body.add_child(expw)
	var bar_size := Vector2(300.0, 18.0)
	var bar_pos := Vector2(COL_X + 60, ey + 3)
	var ebg := _lvup_stretch("common_bar_bg2", "common_ui", bar_size)
	ebg.position = bar_pos; body.add_child(ebg)
	var need := LevelSystem.exp_to_next(Data.level_curve, level)
	var cur := int(d.get("exp", 0))
	var pct := clampf(float(cur) / maxf(1.0, float(need)), 0.0, 1.0)
	var clip := Control.new()
	clip.position = bar_pos
	clip.size = Vector2(bar_size.x * pct, bar_size.y)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(clip)
	var efill := _lvup_stretch("common_bar_exp", "common_ui", bar_size)
	clip.add_child(efill)
	var ecov := _lvup_stretch("common_bar_cover", "common_ui", bar_size)
	ecov.position = bar_pos; body.add_child(ecov)
	var etx := Label.new()
	etx.text = "%d / %d" % [cur, need]
	_lvup_bm_style(etx, 18, Color.WHITE, "font_common")
	etx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etx.size = bar_size; etx.position = bar_pos
	body.add_child(etx)

	var sb2: Dictionary = d.get("stat_bonus", {})
	var base_bonus: Dictionary = sb2.get("base", {})
	var bn := clampi(int(fx.get("batch", 1)), 1, maxi(1, gain_log.size()))
	var now_st := Growth.main_stats(ddef, Data.stat_table, gain_log, base_bonus)
	var prev_log := gain_log.slice(0, maxi(0, gain_log.size() - bn))
	var prev_st := Growth.main_stats(ddef, Data.stat_table, prev_log, base_bonus)
	var prev_lv := maxi(1, level - bn)
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(prev_lv), str(level), "", false, false]]
	var maxed_n := 0
	for spec in [["hp", "생명력", Color(0.55, 1.0, 0.55)], ["att", "공격력", Color(1.0, 0.5, 0.45)],
			["def", "방어력", Color(0.5, 0.75, 1.0)]]:
		var k: String = spec[0]
		var mx := int(max_stats.get(k, 1)) * bn
		var gain := int(now_st[k]) - int(prev_st[k])
		var trans := gain > mx
		var maxed := gain >= mx
		if maxed: maxed_n += 1
		rows.append([String(spec[1]), spec[2], str(int(prev_st[k])), str(int(now_st[k])),
			"(+%d/%d)" % [gain, mx], maxed, trans])
	var yy := vis.y * 0.29
	var fx_on := not fx.is_empty()
	var fx_rows: Array = []
	var badge_no := 0
	for i in rows.size():
		var ry := yy + i * 44.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		_lvup_bm_style(nm2, 26, rows[i][1])
		nm2.position = Vector2(COL_X, ry); body.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		_lvup_bm_style(bv, 26, Color.WHITE)
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.size = Vector2(96, 32); bv.position = Vector2(COL_X + 100, ry); body.add_child(bv)
		var ar := _atlas_sprite("common_ui", "common_btn_arrow2", _man_common(), 0.75)
		if ar: ar.position = Vector2(COL_X + 224, ry + 16); body.add_child(ar)
		var av := Label.new(); av.text = String(rows[i][3])
		_lvup_bm_style(av, 26, Color.WHITE)
		av.position = Vector2(COL_X + 252, ry); body.add_child(av)
		av.pivot_offset = Vector2(0.0, 20.0)
		var dl: Label = null
		if String(rows[i][4]) != "":
			dl = Label.new(); dl.text = String(rows[i][4])
			_lvup_bm_style(dl, 20, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			dl.position = Vector2(COL_X + 340, ry + 5); body.add_child(dl)
			dl.pivot_offset = Vector2(0.0, 15.0)
		var bd: Node2D = null
		if bool(rows[i][5]):
			badge_no += 1
			bd = Node2D.new()
			bd.position = Vector2(COL_X + 470.0, ry + 16.0)
			body.add_child(bd)
			var gbg := _atlas_sprite("common_ui", "common_max_bg", _man_common(), Design.ASSET_SCALE * 0.8)
			if gbg: bd.add_child(gbg)
			var mb := Label.new()
			mb.text = "%dMAX%s" % [badge_no, "+" if bool(rows[i][6]) else ""]
			_lvup_bm_style(mb, 17, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mb.size = Vector2(110, 28); mb.position = Vector2(-55, -14)
			bd.add_child(mb)
		if fx_on:
			if ar: ar.modulate.a = 0.0
			av.modulate.a = 0.0
			if dl: dl.modulate.a = 0.0
			if bd: bd.visible = false
			fx_rows.append({"is_level": i == 0, "arrow": ar, "av": av,
				"final": String(rows[i][3]), "dl": dl, "maxed": bool(rows[i][5]),
				"trans": bool(rows[i][6]), "badge": bd,
				"badge_pos": Vector2(COL_X + 470.0, ry + 16.0), "ry": ry})

	var can_up := level < cap
	var slot_y := vis.y * 0.575
	var slots := 0
	for key in _LVUP_ITEMS:
		if UserDB.item_count(key) <= 0:
			continue
		_lvup_item_slot(body, key, Vector2(COL_X + 6 + slots * 86.0, slot_y), can_up, level)
		slots += 1
	for i in maxi(0, _LVUP_MIN_SLOTS - slots):
		_lvup_locked_slot(body, Vector2(COL_X + 6 + (slots + i) * 86.0, slot_y))

	if gain_log.is_empty():
		tlabel.text = "레벨업 이력이 없습니다.  레벨 아이템으로 레벨을 올리세요."
	else:
		var dn2 := Icons.species_name(int(d["id"]))
		tlabel.text = "%s%s 레벨 %d%s 되었습니다.  (MAX %d)" % [dn2,
			_josa_c(dn2, "은", "는"), level, _josa_c(str(level), "이", "가"), maxed_n]

	_lvup_build_reroll(body, vis, roll_cfg, gain_log.is_empty())

	if fx_on:
		fx["rows"] = fx_rows
		_lvup_fx_timeline(fx)

func _lvup_style(l: Label, size: int, col: Color, outline := Color(0, 0, 0, 0.9)) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _lvt(secs: float) -> void:
	await get_tree().create_timer(maxf(0.01, secs)).timeout

func _lvup_fx_timeline(fx: Dictionary) -> void:
	_lvup_fx_busy = true
	var sp := float(fx.get("sp", 1.0))
	var win: Control = _lvup_ctx.get("win")
	var vis: Vector2 = _lvup_ctx["vis"]
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.z_index = _LVUP_UI_Z + 20
	if is_instance_valid(win) and win.get_parent() != null:
		win.get_parent().add_child(blocker)
	fx["blocker"] = blocker
	if bool(_lvup_ctx.get("auto", false)):
		_lvup_add_auto_cancel_hit(blocker)
	fx["maxn"] = 0
	match String(fx.get("kind", "up")):
		"up":
			Bgm.sfx("effect_level_updown")
			await _lvup_wordart_flight(sp)
		"reset":
			Bgm.sfx("effect_level_updown")
			_lvup_word_banner("LEVEL RESET", 1.4)
			await _lvt(0.6 * sp)
		_:
			await _lvt(0.1 * sp)
	if _lvup_ctx.is_empty(): return
	if bool(fx.get("stage_changed", false)):
		CocosParticle.spawn(self, "pt_rev_up", Vector2(vis.x * 0.20, vis.y * 0.55), 135, 0.6)
		await _lvt(1.0 * sp)
		if _lvup_ctx.is_empty(): return
		_lvup_refresh_dragon()
		_notify("on_evolved")
		_notify("on_evolved")
		await _lvt(1.0 * sp)
	if _lvup_ctx.is_empty(): return
	var rows: Array = fx.get("rows", [])
	fx["pending"] = rows.size()
	for i in rows.size():
		if i > 0:
			await _lvt(0.4 * sp)
			if _lvup_ctx.is_empty(): return
		_lvup_fx_row(fx, i)
	while int(fx.get("pending", 0)) > 0:
		if _lvup_ctx.is_empty(): return
		await _lvt(0.1)
	await _lvt(2.0 * sp)
	if _lvup_ctx.is_empty():
		_lvup_fx_busy = false
		return
	_lvup_fx_slot_open(fx)
	await _lvt(0.3 * sp)
	_lvup_fx_busy = false
	var blk = fx.get("blocker")
	if is_instance_valid(blk): blk.queue_free()

func _lvup_wordart_flight(sp: float) -> void:
	var art: TextureRect = _lvup_ctx.get("art")
	var vis: Vector2 = _lvup_ctx["vis"]
	if not is_instance_valid(art):
		await _lvt(0.5 * sp)
		return
	if _lvup_ctx.get("art_tweens") is Array:
		for t in _lvup_ctx["art_tweens"]:
			if t is Tween and t.is_valid(): t.kill()
	var tws: Array = []
	_lvup_ctx["art_tweens"] = tws
	art.pivot_offset = art.size * 0.5
	var home: Vector2 = _lvup_art_home(vis, art.size)
	var K := 1.0 / 0.27
	art.position = Vector2(vis.x * 0.5 - art.size.x * 0.5, vis.y + 60.0)
	art.scale = Vector2.ONE * (0.5 * K)
	var y1 := art.position.y - (vis.y / 3.0 + 200.0)
	var y2 := y1 - vis.y / 3.0
	var tw := art.create_tween()
	tws.append(tw)
	tw.tween_property(art, "position:y", y1, 0.5 * sp)
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.45 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.4 * K), 0.5 * sp)
	tw.tween_callback(func():
		if not _lvup_ctx.is_empty() and is_instance_valid(art):
			_lvup_feather_burst(art.position + art.size * 0.5))
	tw.tween_property(art, "position:y", y2, 0.5 * sp)
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.85 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.7 * K), 0.25 * sp)
	tw.tween_interval(0.25 * sp)
	await tw.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	var from := art.position
	var jump := func(t: float):
		if is_instance_valid(art):
			var p := from.lerp(home, t)
			p.y -= 100.0 * sin(PI * t)
			art.position = p
	var jt := art.create_tween()
	tws.append(jt)
	jt.tween_method(jump, 0.0, 1.0, 0.5 * sp)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, 0.5 * sp)
	jt.tween_property(art, "position:y", home.y + 10.0, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE * 0.93, sp / 6.0)
	jt.tween_property(art, "position:y", home.y, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, sp / 6.0)
	await jt.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	var fl := art.create_tween().set_loops()
	tws.append(fl)
	fl.tween_property(art, "position:y", home.y - 20.0, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE * 1.03, 1.0)
	fl.tween_property(art, "position:y", home.y, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE, 1.0)

func _lvup_feather_burst(center: Vector2) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	CocosParticle.spawn(win, "pt_feature_c", center + Vector2(0, 30), _LVUP_UI_Z + 6, 0.8)
	var offs := [Vector2(-70, -30), Vector2(-100, 20), Vector2(-120, 50), Vector2(-20, 5),
		Vector2(70, 25), Vector2(50, 100), Vector2(90, 60), Vector2(100, 20),
		Vector2(60, -25), Vector2(-50, 80), Vector2(30, -60), Vector2(110, -45)]
	var cman := _man_common()
	for i in offs.size():
		var s := _atlas_sprite("common_ui", "common_feather%d" % (1 + (i % 3)), cman, Design.ASSET_SCALE)
		if s == null: continue
		s.position = center
		s.z_index = _LVUP_UI_Z + 6
		win.add_child(s)
		var d: Vector2 = offs[i] * Design.ASSET_SCALE
		d.y = -d.y
		var base: Vector2 = s.scale
		var tw := s.create_tween()
		tw.tween_property(s, "position", center + d, 0.25)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x, 0.25)
		tw.parallel().tween_property(s, "scale", base * 1.7, 0.25)
		tw.tween_property(s, "position", center + d * 3.0, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x * 2.0, 0.5)
		tw.parallel().tween_property(s, "scale", base * 1.5, 0.5)
		tw.tween_property(s, "modulate:a", 0.0, 0.5)
		tw.tween_callback(s.queue_free)

func _lvup_fx_row(fx: Dictionary, idx: int) -> void:
	var sp := float(fx.get("sp", 1.0))
	var rows: Array = fx["rows"]
	var row: Dictionary = rows[idx]
	var ar: Node2D = row.get("arrow")
	if is_instance_valid(ar):
		ar.create_tween().tween_property(ar, "modulate:a", 1.0, 0.15 * sp)
		var abase: Vector2 = ar.scale
		var al := ar.create_tween().set_loops()
		al.tween_property(ar, "scale", abase * 1.047, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
		al.tween_property(ar, "scale", abase * 0.953, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
	var av: Label = row.get("av")
	if not is_instance_valid(av):
		fx["pending"] = int(fx["pending"]) - 1
		return
	if bool(row.get("is_level", false)):
		av.scale = Vector2.ONE * 0.5
		var lt := av.create_tween()
		lt.tween_property(av, "modulate:a", 1.0, 0.1 * sp)
		lt.parallel().tween_property(av, "scale", Vector2.ONE * 2.0, 0.15 * sp)
		lt.tween_property(av, "scale", Vector2.ONE * 1.1, 0.1 * sp)
		fx["pending"] = int(fx["pending"]) - 1
		return
	await _lvup_digit_roll(av, String(row.get("final", "")), sp)
	if _lvup_ctx.is_empty(): return
	var dl: Label = row.get("dl")
	if is_instance_valid(dl):
		dl.modulate.a = 1.0
		dl.scale = Vector2.ONE * 0.8
		var dt := dl.create_tween()
		dt.tween_property(dl, "scale", Vector2.ONE * 1.1, 0.15 * sp)
		dt.tween_property(dl, "scale", Vector2.ONE, 0.1 * sp)
	var body: Control = _lvup_ctx.get("body")
	if is_instance_valid(body):
		CocosParticle.spawn(body, "pt_levelup_light", av.position + Vector2(50, 16), 8, 0.9, 60)
	await _lvt(0.3 * sp)
	if _lvup_ctx.is_empty(): return
	if bool(row.get("maxed", false)):
		await _lvup_fx_badge(fx, row)
	fx["pending"] = int(fx["pending"]) - 1

func _lvup_digit_roll(av: Label, final_text: String, sp: float) -> void:
	av.modulate.a = 1.0
	var n := final_text.length()
	if n == 0: return
	var counters: Array = []
	for i in n:
		counters.append((i * 3) % 10)
	var t := 0.0
	var lock_start := 0.8
	while true:
		if not is_instance_valid(av) or _lvup_ctx.is_empty(): return
		var locked := 0
		if t >= lock_start:
			locked = clampi(1 + int(floor((t - lock_start) / 0.2)), 0, n)
		if locked >= n: break
		var s := ""
		for i in n:
			s += final_text[i] if i < locked else str(counters[i])
			if i >= locked:
				counters[i] = (int(counters[i]) + 1) % 10
		av.text = s
		await _lvt(0.07 * sp)
		t += 0.07
	av.text = final_text
	var tw := av.create_tween()
	tw.tween_property(av, "scale", Vector2.ONE * 0.75, 0.1 * sp)
	tw.tween_property(av, "scale", Vector2.ONE * 1.25, 0.2 * sp)
	tw.tween_property(av, "scale", Vector2.ONE, 0.1 * sp)
	await tw.finished

func _lvup_fx_badge(fx: Dictionary, row: Dictionary) -> void:
	var sp := float(fx.get("sp", 1.0))
	var bd: Node2D = row.get("badge")
	if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var n := int(fx.get("maxn", 0)) + 1
	fx["maxn"] = n
	var target: Vector2 = row["badge_pos"]
	bd.visible = true
	bd.z_index = 10
	bd.position = vis * 0.5
	bd.modulate.a = 0.0
	if n < 3:
		bd.scale = Vector2.ONE * 20.0
		var tw := bd.create_tween()
		tw.set_parallel(true)
		tw.tween_property(bd, "modulate:a", 1.0, 0.2 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd): return
		Bgm.sfx("effect_max_fun")
		_lvup_shake()
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	else:
		bd.scale = Vector2.ONE * 2.0
		var tw := bd.create_tween()
		tw.tween_property(bd, "modulate:a", 1.0, 0.1 * sp)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 4.0, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 6.0, 0.2 * sp)
		tw.tween_interval(0.5 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
		Bgm.sfx("effect_max_fun")
		_lvup_fx_triple()
		_lvup_shake()
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	if not is_instance_valid(bd): return
	var ml := bd.create_tween().set_loops()
	ml.tween_property(bd, "scale", Vector2.ONE * 1.1, 0.2)
	ml.tween_property(bd, "scale", Vector2.ONE, 0.2)
	ml.tween_interval(0.3)

func _lvup_fx_triple() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	_lvup_dragon_voice()
	CritCutin.show(self, {
		"id": Icons.art_id_of(d) if not d.is_empty() else int(ddef.get("id", 0)),
		"element": Icons.element_of(d) if not d.is_empty() else String(ddef.get("element", "")),
		"awakened": bool(d.get("awakened", false)),
	}, 1.0 / 3.0, "트리플 맥스", 60)
	var vis: Vector2 = _lvup_ctx["vis"]
	var lay := CanvasLayer.new(); lay.layer = 61
	add_child(lay)
	for pname in ["pt_3max1", "pt_3max2"]:
		var p := CocosParticle.spawn(lay, pname, Vector2(-60.0, vis.y * 0.5), 1, 0.3)
		if p:
			var base_y := vis.y * 0.5
			var arc := func(t: float):
				if is_instance_valid(p):
					p.position = Vector2(-60.0 + (vis.x + 120.0) * t,
						base_y - vis.y * 0.4 * sin(PI * t))
			p.create_tween().tween_method(arc, 0.0, 1.0, 0.5 * 3.0)
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(lay): lay.queue_free())

func _lvup_shake() -> void:
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var orig: Vector2 = win.position
	var tw := win.create_tween()
	for off in [Vector2(6, 4), Vector2(-5, -3), Vector2(4, 2), Vector2(-2, -2)]:
		tw.tween_property(win, "position", orig + off, 0.04)
	tw.tween_property(win, "position", orig, 0.04)

func _lvup_fx_slot_open(fx: Dictionary) -> void:
	var slot := int(fx.get("slot_new", -1))
	if slot < 0 or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	var types: Array = d.get("skill_slots", [])
	var shape := String(types[slot]) if slot < types.size() else "star"
	var holder := Node2D.new()
	holder.position = Vector2(vis.x * 0.47, vis.y * 0.52)
	holder.z_index = _LVUP_UI_Z + 10
	win.add_child(holder)
	var bg := _atlas_sprite("common_ui", "common_skill_%s_bg" % shape, _man_common(), Design.ASSET_SCALE)
	if bg:
		bg.modulate.a = 0.0
		holder.add_child(bg)
		var bbase: Vector2 = bg.scale
		var tw := bg.create_tween()
		tw.tween_property(bg, "modulate:a", 1.0, 0.7)
		tw.parallel().tween_property(bg, "scale", bbase * 1.2, 1.0)
		tw.tween_property(bg, "scale", bbase, 0.3)
	var l := Label.new()
	l.text = Data.ui("#cd7178af")
	_lvup_bm_style(l, 24, Color.WHITE)
	l.position = Vector2(42, -16)
	l.modulate.a = 0.0
	holder.add_child(l)
	l.create_tween().tween_property(l, "modulate:a", 1.0, 0.5)
	CocosParticle.spawn(holder, "pt_take_skill", Vector2.ZERO, 1, 0.8, 80)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(holder): holder.queue_free())

func _lvup_item_slot(body: Control, key: String, pos: Vector2, can_up: bool, level: int) -> void:
	var cman := _man_common()
	var bx := _atlas_sprite("common_ui", "common_item_box", cman, Design.ASSET_SCALE)
	if bx: bx.position = pos + Vector2(38, 38); body.add_child(bx)
	var icon := _atlas_sprite("item_small_ui", "item_item_small_%s" % key, _item_small_manifest, 0.86)
	if icon: icon.position = pos + Vector2(38, 38); body.add_child(icon)
	var cnt := UserDB.item_count(key)
	var badge := Label.new()
	badge.text = "%d" % cnt
	_lvup_style(badge, 18, Color(1, 1, 1))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.size = Vector2(66, 22); badge.position = pos + Vector2(4, 52)
	body.add_child(badge)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(76, 76); b.position = pos
	b.tooltip_text = "%s%s" % [Data.item_name(key),
		{"": "", "max1": " (맥스 1 보장)", "max2": " (맥스 2 보장)",
		 "triple": " (트리플맥스)", "amor": " (전 스탯 초월맥스)"}.get(String(_LVUP_GUARANTEE.get(key, "")), "")]
	var usable := (key != "level_down" and can_up) or (key == "level_down" and level > 1)
	b.disabled = not usable
	b.pressed.connect(_lvup_use_item.bind(key))
	body.add_child(b)

func _lvup_locked_slot(body: Control, pos: Vector2) -> void:
	var bx := _atlas_sprite("common_ui", "common_item_box", _man_common(), Design.ASSET_SCALE)
	if bx:
		bx.position = pos + Vector2(38, 38); bx.modulate = Color(0.6, 0.6, 0.6, 1.0)
		body.add_child(bx)
	var lk := _atlas_sprite("common_ui", "common_lock", _man_common(), Design.ASSET_SCALE * 0.8)
	if lk: lk.position = pos + Vector2(38, 38); body.add_child(lk)

func _lvup_use_item(key: String) -> void:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	if UserDB.item_count(key) <= 0: return
	var d := UserDB.get_dragon(uid)
	var level := int(d.get("level", 1))
	var old_stage := Growth.stage_for_level(level)
	if key == "level_down":
		if level <= 1 or not UserDB.level_down(uid): return
		UserDB.add_item("level_down", -1)
		Bgm.sfx("effect_level_updown")
		_lvup_word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		_lvup_ctx["reroll"] = 0
		_notify("on_changed")
		_lvup_redraw()
		var down_stage := Growth.stage_for_level(int(UserDB.get_dragon(uid).get("level", 1)))
		if down_stage != old_stage:
			_lvup_refresh_dragon()
			_notify("on_evolved")
			_notify("on_evolved")
		return
	if level >= Growth.level_cap(bool(d.get("awakened", false))): return
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(Data.level_curve.get("roll", {}), max_stats, rng,
		0.0, String(_LVUP_GUARANTEE.get(key, "")))
	var sk_before := UserDB.dragon_skills(uid).size()
	UserDB.level_up_with(uid, roll)
	var sk_new := _skills_learned_since(uid, sk_before)
	if not sk_new.is_empty():
		Toast.show(self, "새 스킬 습득 — %s" % ", ".join(sk_new))
	UserDB.add_item(key, -1)
	_lvup_ctx["reroll"] = 0
	var new_level := int(UserDB.get_dragon(uid).get("level", 1))
	var slot_new := -1
	for si in Loadout.SLOT_UNLOCK_LEVEL.size():
		var lreq := int(Loadout.SLOT_UNLOCK_LEVEL[si])
		if level < lreq and new_level >= lreq:
			slot_new = si
	_notify("on_changed")
	_lvup_redraw({"kind": "up", "sp": 1.0,
		"stage_changed": Growth.stage_for_level(new_level) != old_stage,
		"slot_new": slot_new, "triple": bool(roll.get("triple", false))})

func _lvup_build_reroll(body: Control, vis: Vector2, roll_cfg: Dictionary, no_history: bool) -> void:
	var cman := _man_common()
	var cost := _lvup_reroll_cost()
	var have := UserDB.currency(String(cost["kind"]))
	var affordable := have >= int(cost["amount"])
	var bx := vis.x * 0.60
	var by := vis.y * 0.70

	var auto_on := bool(_lvup_ctx.get("auto", false))
	var ab := TextureButton.new()
	var ap := "res://assets/converted/common_ui/common_bt_levelupauto_%s.tres" % ("on" if auto_on else "off")
	if ResourceLoader.exists(ap):
		ab.texture_normal = load(ap)
		ab.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	ab.position = Vector2(bx, by + 6)
	ab.disabled = no_history
	ab.name = "AutoButton"
	ab.tooltip_text = "자동 다시뽑기 중단" if auto_on else Data.ui("#30082726")
	ab.pressed.connect(_lvup_toggle_auto)
	body.add_child(ab)
	_lvup_ctx["auto_btn"] = ab

	var ix := bx + 110.0
	var iy := by + 34.0
	var ric := _atlas_sprite("common_ui", "common_stat_reflash", cman, Design.ASSET_SCALE * 0.72)
	if ric:
		ric.position = Vector2(ix, iy)
		if not affordable or no_history: ric.modulate = Color(0.55, 0.55, 0.55)
		body.add_child(ric)

	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var mp := Label.new()
	mp.text = "(MAX 확률 %.1f%%" % (pity * 100.0)
	_lvup_style(mp, 17, Color(1, 0.78, 0.2))
	mp.position = Vector2(ix + 46, by - 2); body.add_child(mp)
	var mpa := _atlas_sprite("common_ui", "common_maxpercent_arrow", cman, Design.ASSET_SCALE)
	var mpw: float = ThemeDB.fallback_font.get_string_size(mp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	if mpa: mpa.position = Vector2(ix + 56 + mpw, by + 10); body.add_child(mpa)
	var mpc := Label.new()
	mpc.text = ")"
	_lvup_style(mpc, 17, Color(1, 0.78, 0.2))
	mpc.position = Vector2(ix + 66 + mpw, by - 2); body.add_child(mpc)

	var lb := Label.new()
	lb.text = Data.ui("#276d144b")
	_lvup_style(lb, 23, Color.WHITE if affordable else Color(0.65, 0.65, 0.65))
	lb.position = Vector2(ix + 46, by + 20); body.add_child(lb)

	var di := _atlas_sprite("common_ui", "common_diamond_small1", cman, Design.ASSET_SCALE * 0.9)
	if di: di.position = Vector2(ix + 62, by + 66); body.add_child(di)
	var cl := Label.new()
	cl.text = "x %d" % int(cost["amount"])
	_lvup_style(cl, 22, Color.WHITE if affordable else Color(1.0, 0.45, 0.45))
	cl.position = Vector2(ix + 84, by + 52); body.add_child(cl)

	var hit := Button.new()
	hit.flat = true
	hit.name = "RerollButton"
	hit.size = Vector2(240, 96); hit.position = Vector2(ix - 34, by - 6)
	hit.disabled = no_history or not affordable
	hit.tooltip_text = ("보유 %s %d" % [String(cost["kind"]), have]) if not affordable else ""
	hit.pressed.connect(_lvup_ask_reroll)
	body.add_child(hit)

func _lvup_ask_reroll() -> void:
	MessageWindow.open(self, Data.ui("#276d144b"), Data.ui("#0668a7b9"),
		func(): _lvup_do_reroll_once())

func _lvup_toggle_auto() -> void:
	if _lvup_ctx.is_empty(): return
	if bool(_lvup_ctx.get("auto", false)):
		_lvup_ctx["auto"] = false
		_lvup_drop_auto_cancel_hit()
		if _lvup_fx_busy:
			_lvup_set_auto_icon(false)
		else:
			_lvup_redraw()
		return
	if _lvup_auto_running: return
	MessageWindow.open(self, Data.ui("#30082726"), "다시뽑기를 자동으로 하시겠습니까?\n이 경우, 다이아가 많이 소모될 수 있습니다.",
		func():
			if _lvup_ctx.is_empty() or _lvup_auto_running: return
			_lvup_ctx["auto"] = true
			_lvup_redraw()
			_lvup_auto_loop())

func _lvup_set_auto_icon(on: bool) -> void:
	var ab = _lvup_ctx.get("auto_btn")
	if not (ab is TextureButton) or not is_instance_valid(ab): return
	var p := "res://assets/converted/common_ui/common_bt_levelupauto_%s.tres" % ("on" if on else "off")
	if ResourceLoader.exists(p):
		ab.texture_normal = load(p)

func _lvup_add_auto_cancel_hit(blocker: Control) -> void:
	var ab = _lvup_ctx.get("auto_btn")
	if not (ab is Control) or not is_instance_valid(ab) or not is_instance_valid(blocker): return
	_lvup_drop_auto_cancel_hit()
	var hit := Button.new()
	hit.flat = true
	hit.name = "AutoCancelHit"
	hit.size = (ab as Control).size * (ab as Control).scale
	hit.tooltip_text = "자동 다시뽑기 중단"
	hit.pressed.connect(_lvup_toggle_auto)
	blocker.add_child(hit)
	hit.global_position = (ab as Control).global_position
	_lvup_ctx["auto_cancel_hit"] = hit

func _lvup_drop_auto_cancel_hit() -> void:
	var h = _lvup_ctx.get("auto_cancel_hit")
	if is_instance_valid(h):
		h.get_parent().remove_child(h)
		h.queue_free()
	_lvup_ctx.erase("auto_cancel_hit")

func _lvup_auto_loop() -> void:
	if _lvup_auto_running: return
	_lvup_auto_running = true
	while not _lvup_ctx.is_empty() and bool(_lvup_ctx.get("auto", false)):
		if not _lvup_do_reroll_once():
			break
		while _lvup_fx_busy:
			await get_tree().create_timer(0.1).timeout
			if _lvup_ctx.is_empty():
				_lvup_auto_running = false
				return
		if not bool(_lvup_ctx.get("auto", false)): break
		var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
		var gl: Array = d.get("gain_log", [])
		var mx := Growth.tier_growth(_lvup_ctx["ddef"], Data.stat_table)
		if not gl.is_empty():
			var lastg: Dictionary = gl[gl.size() - 1]
			var all_max := true
			for k in ["hp", "att", "def"]:
				if int(lastg.get(k, 0)) < int(mx.get(k, 1)): all_max = false
			if all_max: break
		await get_tree().create_timer(0.3).timeout
	_lvup_auto_running = false
	if not _lvup_ctx.is_empty():
		_lvup_ctx["auto"] = false
		_lvup_drop_auto_cancel_hit()
		_lvup_redraw()

func _lvup_do_reroll_once() -> bool:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return false
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var cost := _lvup_reroll_cost()
	var kind := String(cost["kind"])
	var amount := int(cost["amount"])
	if UserDB.currency(kind) < amount: return false
	if (UserDB.get_dragon(uid).get("gain_log", []) as Array).is_empty(): return false
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(roll_cfg, max_stats, rng, pity, "")
	if not UserDB.spend(kind, amount): return false
	if not UserDB.replace_last_gain(uid, roll): return false
	_lvup_ctx["reroll"] = 0 if bool(roll.get("triple", false)) else int(_lvup_ctx.get("reroll", 0)) + 1
	_notify("on_changed")
	_lvup_redraw({"kind": "reset", "sp": 0.5 if bool(_lvup_ctx.get("auto", false)) else 1.0,
		"stage_changed": false, "slot_new": -1, "triple": bool(roll.get("triple", false))})
	return true
