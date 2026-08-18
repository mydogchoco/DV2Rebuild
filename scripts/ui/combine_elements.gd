class_name CombineElements
extends CanvasLayer

const DURATION := 7.0
const TOTAL := 8.0
const SKIP_TIME_SCALE := 15.0

const ORBIT: Array[Vector2] = [Vector2(0, -250), Vector2(-215, 125), Vector2(215, 125)]
const POP_DELAY: Array[float] = [0.80, 1.05, 1.30]
const POP_HOLD: Array[float] = [1.70, 1.45, 1.20]
const SPIN_DPS := 12.0

const CO_SRC := 479.0
const COW_SRC := 437.0

const BATTLE_DIR := "battle_ui"
const FONT_PATH := "res://assets/converted/font_ui/font_combine.fnt"

static var _shown_run := ""
static var _font_cache: FontFile = null

var _pma: CanvasItemMaterial
var _res := ""
var _center := Vector2.ZERO
var _rate := 1.0
var _tweens: Array[Tween] = []
var _spinners: Array[Node2D] = []
var _buff: Dictionary = {}
var _table: Dictionary = {}
var _skipped := false

static func can_play(run_key: String, party_size: int, buff: Dictionary) -> bool:
	if run_key != "" and _shown_run == run_key:
		return false
	if party_size != 3:
		return false
	return String(buff.get("img", "")) != ""

static func mark_played(run_key: String) -> void:
	_shown_run = run_key

static func play(host: Node, elements: Array, buff: Dictionary, table: Dictionary) -> CombineElements:
	if elements.size() != 3 or String(buff.get("img", "")) == "":
		return null
	var l := CombineElements.new()
	l.layer = 100
	l._buff = buff
	l._table = table
	l._res = String(buff["img"])
	host.add_child(l)
	l._build(elements)
	return l

func _build(elements: Array) -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var vis := _vp_size()
	_center = vis * 0.5
	var S := Design.ASSET_SCALE

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.size = vis
	bg.z_index = -10
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_blocker_input)
	add_child(bg)
	var tb := _tween(bg)
	tb.tween_property(bg, "color:a", 1.0, 0.25)
	tb.tween_interval(TOTAL - 0.25 - 0.5)
	tb.tween_property(bg, "color:a", 0.0, 0.5)
	tb.tween_callback(queue_free)

	_build_center_mark()
	_build_center_ring()
	_build_orbit(elements)

	var tt := _tween(self)
	tt.tween_interval(3.85)
	tt.tween_callback(_text)

func _build_center_mark() -> void:
	var S := Design.ASSET_SCALE

	var cm := _spr_res("combine_mark", 0)
	if cm:
		cm.modulate.a = 0.0
		var t := _tween(cm)
		t.tween_interval(3.85)
		t.tween_callback(_set_alpha.bind(cm, 1.0))
		t.tween_interval(3.25)
		t.tween_property(cm, "scale", Vector2.ONE * 0.9 * S, 0.35)
		t.tween_property(cm, "scale", Vector2.ONE * 2.0 * S, 0.1)
		t.parallel().tween_property(cm, "modulate:a", 0.0, 0.1)
		t.tween_callback(cm.queue_free)

	var cmw1 := _spr_res("combine_mark_white", 2)
	if cmw1:
		cmw1.scale = Vector2.ZERO
		var t1 := _tween(cmw1)
		t1.tween_interval(3.75)
		t1.tween_property(cmw1, "scale", Vector2.ONE * S, 0.1)
		t1.tween_interval(0.4)
		t1.tween_property(cmw1, "modulate:a", 0.0, 0.5)
		t1.tween_callback(cmw1.queue_free)

	var cmw2 := _spr_res("combine_mark_white", 2)
	if cmw2:
		cmw2.scale = Vector2.ZERO
		cmw2.visible = false
		var t2 := _tween(cmw2)
		t2.tween_interval(3.75)
		t2.tween_property(cmw2, "scale", Vector2.ONE * S, 0.1)
		t2.tween_callback(_set_visible.bind(cmw2, true))
		t2.tween_property(cmw2, "scale", Vector2.ONE * 2.5 * S, 0.25)
		t2.parallel().tween_property(cmw2, "modulate:a", 0.0, 0.25)
		t2.tween_callback(cmw2.queue_free)

	var cmt := _spr_res("combine_mark_thick", 0)
	if cmt:
		cmt.modulate.a = 0.0
		var t3 := _tween(cmt)
		t3.tween_interval(3.85)
		t3.tween_callback(_set_alpha.bind(cmt, 1.0))
		t3.tween_interval(3.25)
		t3.tween_callback(cmt.queue_free)

func _build_center_ring() -> void:
	var S := Design.ASSET_SCALE

	var co := _spr_res("combine_outline", 0, true)
	if co:
		var spr: Sprite2D = co.get_child(0)
		spr.modulate.a = 0.0
		_spinners.append(spr)
		var t := _tween(co)
		t.tween_interval(3.85)
		t.tween_callback(_set_alpha.bind(spr, 1.0))
		t.tween_interval(3.25)
		t.tween_method(_ease_rot.bind(co, deg_to_rad(480.0), 1.0), 0.0, 1.0, 0.45)
		t.tween_callback(co.queue_free)
		var t2 := _tween(co)
		t2.tween_interval(3.85 + 3.25)
		t2.tween_property(spr, "scale", Vector2.ONE * 0.9 * S, 0.35)
		t2.tween_property(spr, "scale", Vector2.ONE * 2.0 * S, 0.1)
		t2.parallel().tween_property(spr, "modulate:a", 0.0, 0.1)

	var cow1 := _spr_bat("battle_combine_outline_white", 1, true)
	if cow1:
		var spr1: Sprite2D = cow1.get_child(0)
		spr1.modulate.a = 0.0
		_spinners.append(spr1)
		var t1 := _tween(cow1)
		t1.tween_interval(2.25)
		t1.tween_property(spr1, "modulate:a", 1.0, 1.5)
		t1.parallel().tween_method(_ease_rot.bind(cow1, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)
		t1.parallel().tween_method(_ease_scale.bind(spr1, 1.0, 0.9, 3.25), 0.0, 1.0, 1.5)
		t1.tween_property(spr1, "scale", Vector2.ONE * S, 0.1)
		t1.tween_interval(0.4)
		t1.tween_property(spr1, "modulate:a", 0.0, 0.5)
		t1.tween_callback(cow1.queue_free)

	var cow2 := _spr_bat("battle_combine_outline_white", 1, true)
	if cow2:
		var spr2: Sprite2D = cow2.get_child(0)
		spr2.visible = false
		_spinners.append(spr2)
		var t2 := _tween(cow2)
		t2.tween_interval(2.25)
		t2.tween_method(_ease_rot.bind(cow2, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)
		t2.tween_interval(0.1)
		t2.tween_callback(_set_visible.bind(spr2, true))
		t2.tween_property(spr2, "scale", Vector2.ONE * 2.5 * S, 0.25)
		t2.parallel().tween_property(spr2, "modulate:a", 0.0, 0.25)
		t2.tween_callback(cow2.queue_free)

	var cot := _spr_res("combine_outline_thick", 0)
	if cot:
		cot.modulate.a = 0.0
		_spinners.append(cot)
		var t3 := _tween(cot)
		t3.tween_interval(3.85)
		t3.tween_callback(_set_alpha.bind(cot, 1.0))
		t3.tween_interval(3.25)
		t3.tween_callback(cot.queue_free)

func _build_orbit(elements: Array) -> void:
	var S := Design.ASSET_SCALE
	var orbit_off := Vector2(1, -1) * ((CO_SRC - COW_SRC) * 0.5 * S)

	var orbit := Node2D.new()
	orbit.position = _center
	orbit.z_index = 2
	add_child(orbit)
	var t7 := _tween(orbit)
	t7.tween_interval(2.25)
	t7.tween_method(_ease_rot.bind(orbit, deg_to_rad(1440.0), 3.25), 0.0, 1.0, 1.5)

	for i in 3:
		var elem := String(elements[i])
		var mark := _spr_bat("battle_element_%s_mark" % elem, 0)
		if mark == null:
			continue
		mark.reparent(orbit, false)
		mark.position = orbit_off + ORBIT[i]
		mark.scale = Vector2.ZERO

		var outline := _spr_bat("battle_element_%s_outline" % elem, -1)
		if outline:
			_attach(outline, mark)
			outline.modulate.a = 0.0
			_spinners.append(outline)
			var t8 := _tween(outline)
			t8.tween_interval(1.75)
			t8.tween_property(outline, "modulate:a", 1.0, 1.0)
			t8.tween_interval(0.3)
			t8.tween_property(outline, "modulate:a", 0.0, 0.5)
			t8.tween_callback(outline.queue_free)

		var mwhite := _spr_bat("battle_element_%s_mark_white" % elem, 0)
		if mwhite:
			_attach(mwhite, mark)
			mwhite.modulate.a = 0.0
			var t9 := _tween(mwhite)
			t9.tween_interval(3.05)
			t9.tween_property(mwhite, "modulate:a", 1.0, 0.5)

			var owhite := _spr_bat("battle_element_outline_white", -1)
			if owhite:
				_attach(owhite, mwhite)
				owhite.modulate.a = 0.0
				_spinners.append(owhite)
				var ta := _tween(owhite)
				ta.tween_interval(3.05)
				ta.tween_property(owhite, "modulate:a", 1.0, 0.5)

		var tm := _tween(mark)
		tm.tween_interval(POP_DELAY[i] + 0.35)
		tm.tween_property(mark, "scale", Vector2.ONE * 1.25 * S, 0.1)
		tm.tween_property(mark, "scale", Vector2.ONE * S, 0.1)
		tm.tween_interval(POP_HOLD[i])
		tm.tween_property(mark, "modulate:a", 0.0, 0.5)
		tm.parallel().tween_property(mark, "position", orbit_off, 0.5)
		tm.tween_property(mark, "scale", Vector2.ZERO, 0.1)
		tm.tween_callback(mark.queue_free)

func _text() -> void:
	var S := Design.ASSET_SCALE
	var vis := _vp_size()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vis
	dim.z_index = 3
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var td := _tween(dim)
	td.tween_interval(0.5)
	td.tween_property(dim, "color:a", 100.0 / 255.0, 0.25)
	td.tween_interval(2.5)
	td.tween_property(dim, "color:a", 0.0, 0.5)
	td.tween_callback(dim.queue_free)

	var bend := _spr_bat("battle_text_bend", 3)
	if bend:
		bend.position = _center + Vector2(0, -150)
		bend.scale = Vector2(10.0, 0.0) * S
		var tb := _tween(bend)
		tb.tween_interval(0.5)
		tb.tween_property(bend, "scale", Vector2(10.0, 0.025) * S, 0.1)
		tb.tween_property(bend, "scale", Vector2(0.025, 0.125) * S, 0.25)
		tb.tween_callback(_set_visible.bind(bend, false))
		tb.tween_interval(2.2)
		tb.tween_callback(_show_at_scale.bind(bend, Vector2.ONE * 0.125 * S))
		tb.tween_property(bend, "scale", Vector2(10.0, 0.025) * S, 0.25)
		tb.tween_property(bend, "scale", Vector2(10.0, 0.0) * S, 0.1)
		tb.tween_callback(bend.queue_free)

	var nm := _bm_label(String(_buff.get("name", "")), 4)
	if nm:
		nm.position = _center + Vector2(0, -150)
		nm.scale = Vector2.ZERO
		var tn := _tween(nm)
		tn.tween_interval(0.85)
		tn.tween_property(nm, "scale", Vector2(2.0, 3.0) * S, 0.05)
		tn.tween_property(nm, "scale", Vector2(2.0, 2.0) * S, 0.05)
		tn.tween_interval(2.0)
		tn.tween_property(nm, "scale", Vector2(2.0, 3.0) * S, 0.05)
		tn.tween_property(nm, "scale", Vector2(1.0, 0.0) * S, 0.05)
		tn.tween_callback(nm.queue_free)

	_text_percentage()

func _text_percentage() -> void:
	var S := Design.ASSET_SCALE
	var lines := option_lines(_buff, _table)
	for i in lines.size():
		var lab := _bm_label(String(lines[i]), 4)
		if lab == null:
			continue
		var home := _center + Vector2(0, 25.0 + 50.0 * i)
		lab.position = home + Vector2(-50, 0)
		lab.scale = Vector2.ONE * S
		lab.modulate.a = 0.0
		var lead := i * 0.125
		var gap := i * 0.025

		var tp := _tween(lab)
		tp.tween_interval(lead + 1.25)
		tp.tween_property(lab, "position", home + Vector2(25, 0), 0.1)
		tp.tween_property(lab, "position", home, 0.1)
		tp.tween_interval(gap + 1.0)
		tp.tween_property(lab, "position", home + Vector2(-10, 0), 0.1)
		tp.tween_property(lab, "position", home + Vector2(65, 0), 0.1)
		tp.tween_callback(lab.queue_free)

		var tf := _tween(lab)
		tf.tween_interval(lead + 1.25)
		tf.tween_property(lab, "modulate:a", 1.0, 0.2)
		tf.tween_interval(gap + 1.0 + 0.1)
		tf.tween_property(lab, "modulate:a", 0.0, 0.1)

static func option_lines(buff: Dictionary, table: Dictionary) -> Array:
	var order: Array = table.get("stat_order", [])
	var labels: Dictionary = table.get("stat_labels", {})
	var eff: Dictionary = buff.get("effect", {})
	var out: Array = []
	for key in order:
		if not eff.has(key):
			continue
		var e = eff[key]
		var mode := "flat"
		var val := 0
		if typeof(e) == TYPE_DICTIONARY:
			mode = String((e as Dictionary).get("mode", "flat"))
			val = int(round(float((e as Dictionary).get("value", 0))))
		else:
			val = int(round(float(e)))
		if val == 0:
			continue
		var suffix := "" if mode == "flat" else "%"
		out.append("%s +%s%s" % [String(labels.get(key, key)), str(val).lpad(2, " "), suffix])
	return out

func _on_blocker_input(ev: InputEvent) -> void:
	if _skipped:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_skipped = true
		_rate = SKIP_TIME_SCALE
		for t in _tweens:
			if is_instance_valid(t):
				t.set_speed_scale(_rate)

func _process(delta: float) -> void:
	var d := deg_to_rad(SPIN_DPS) * delta * _rate
	for n in _spinners:
		if is_instance_valid(n):
			n.rotation += d

func _vp_size() -> Vector2:
	var v := get_viewport()
	if v == null:
		v = get_tree().root
	return v.get_visible_rect().size

func _tween(bound: Node) -> Tween:
	var t := bound.create_tween()
	t.set_speed_scale(_rate)
	_tweens.append(t)
	return t

func _set_alpha(node: CanvasItem, a: float) -> void:
	if is_instance_valid(node):
		node.modulate.a = a

func _set_visible(node: CanvasItem, v: bool) -> void:
	if is_instance_valid(node):
		node.visible = v

func _show_at_scale(node: Node2D, s: Vector2) -> void:
	if is_instance_valid(node):
		node.visible = true
		node.scale = s

func _ease_rot(t: float, node: Node2D, total: float, rate: float) -> void:
	if is_instance_valid(node):
		node.rotation = total * pow(t, rate)

func _ease_scale(t: float, node: Node2D, from_s: float, to_s: float, rate: float) -> void:
	if is_instance_valid(node):
		var s: float = from_s + (to_s - from_s) * pow(t, rate)
		node.scale = Vector2.ONE * s * Design.ASSET_SCALE

func _attach(child: Sprite2D, parent: Node2D) -> void:
	child.reparent(parent, false)
	child.position = Vector2.ZERO
	child.scale = Vector2.ONE

func _spr_res(frame: String, z: int, wrap := false) -> Node2D:
	return _spr("battle_combine_%s" % _res, "battle_%s_%s" % [_res, frame], z, wrap)

func _spr_bat(key: String, z: int, wrap := false) -> Node2D:
	return _spr(BATTLE_DIR, key, z, wrap)

func _spr(dir: String, key: String, z: int, wrap := false) -> Node2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		push_warning("[CombineElements] 프레임 없음: %s" % p)
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2.ONE * Design.ASSET_SCALE
	if not wrap:
		s.position = _center
		s.z_index = z
		add_child(s)
		return s
	var root := Node2D.new()
	root.position = _center
	root.z_index = z
	root.add_child(s)
	add_child(root)
	return root

static func _combine_font() -> FontFile:
	if _font_cache != null:
		return _font_cache
	if not ResourceLoader.exists(FONT_PATH):
		return null
	var f: FontFile = (load(FONT_PATH) as FontFile).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_font_cache = f
	return f

func _bm_label(text: String, z: int) -> Node2D:
	if text == "":
		return null
	var holder := Node2D.new()
	holder.z_index = z
	var l := Label.new()
	var f := _combine_font()
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	add_child(holder)
	l.reset_size()
	l.position = -l.size * 0.5
	return holder
