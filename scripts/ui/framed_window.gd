class_name FramedWindow
extends Control

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_SIZE := Vector2(800.0, 480.0)
const WIN_CENTER_Y := 380.0
const DIM_ALPHA := 127.0 / 255.0
const BTN_CAP := Rect2(20, 20, 4, 4)
const BTN_SIZE := Vector2(220.0, 56.0)

var body: Control
var content: Control
var win_size: Vector2
var close_btn: TextureButton

var _dim: ColorRect
var _body_top := 20.0

static func open(parent: Node, title: String, sz := WIN_SIZE) -> FramedWindow:
	var p := FramedWindow.new()
	p.win_size = sz
	parent.add_child(p)
	p._build(title)
	return p

func _build(title: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	create_tween().tween_property(_dim, "color:a", DIM_ALPHA, 0.2)

	var vis := get_viewport_rect().size
	body = Control.new()
	body.size = win_size
	body.position = Vector2(
		round((vis.x - win_size.x) * 0.5),
		round(Design.flip_y(WIN_CENTER_Y) - win_size.y * 0.5))
	body.pivot_offset = win_size * 0.5
	add_child(body)

	var frame := AtlasUI.nine("ninepatch_ui", "9patch_popup4", win_size, WIN_CAP)
	if frame != null:
		body.add_child(frame)
		body.move_child(frame, 0)

	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2(1.2, 1.2), 0.1)
	tw.tween_property(body, "scale", Vector2.ONE, 0.1)

	if title != "":
		var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
		var tw_pt := win_size.x * 0.5
		var tbar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw_pt, th))
		_body_top = 50.0 + th * 0.5 + 10.0
		if tbar != null:
			tbar.position = Vector2(win_size.x * 0.5 - tw_pt * 0.5, 50.0 - th * 0.5)
			body.add_child(tbar)
		var tl := Label.new()
		tl.text = title
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color.WHITE)
		tl.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
		tl.add_theme_constant_override("outline_size", 5)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.size = Vector2(tw_pt, th)
		tl.position = Vector2(win_size.x * 0.5 - tw_pt * 0.5, 50.0 - th * 0.5)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tl)

	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(win_size.x - 50.0, 50.0) - cs * 0.5
	x.pressed.connect(close)
	body.add_child(x)
	close_btn = x

	content = Control.new()
	content.size = win_size
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(content)

func add_body_label(text: String, font_size := 22,
		color := Color(0.16, 0.09, 0.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bottom := win_size.y - 60.0 - BTN_SIZE.y * 0.5 - 10.0
	l.position = Vector2(20.0, _body_top)
	l.size = Vector2(win_size.x - 40.0, maxf(40.0, bottom - _body_top))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(l)
	return l

func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()
		content.remove_child(c)

func add_action_button(text: String, cb: Callable, kind := 0, sz := BTN_SIZE,
		pos := Vector2.INF) -> Control:
	const FRAME := {0: "9patch_btn", 1: "9patch_btn2", 2: "9patch_btn3", 4: "9patch_btn6",
		5: "9patch_btn8", 7: "9patch_btn10", 8: "9patch_btn11"}
	var center := pos
	if center == Vector2.INF:
		center = Vector2(win_size.x * 0.5, win_size.y - 60.0)
	var root := Control.new()
	root.size = sz
	root.position = center - sz * 0.5
	content.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", String(FRAME.get(kind, "9patch_btn4")), sz, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(cb)
	root.add_child(b)
	return root

func add_info_button(cb: Callable) -> void:
	var sz := AtlasUI.size_pt("common_ui", "common_btn_info") * 1.05
	var root := Control.new()
	root.size = sz
	root.position = Vector2(win_size.x * 0.5 + win_size.x * 0.25 + 10.0, 50.0) - sz * 0.5
	content.add_child(root)
	var s := AtlasUI.spr("common_ui", "common_btn_info", Design.ASSET_SCALE * 1.05)
	if s != null:
		s.position = sz * 0.5
		root.add_child(s)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(cb)
	root.add_child(b)

func close() -> void:
	closed.emit()
	queue_free()
